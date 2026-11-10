//
//  FGTrackingOrchestrator.mm — mirror KA/tracking/FGTrackingOrchestrator.kt (spec §9.1-9.2).
//
#import "FGTrackingOrchestrator.h"
#import "FGEventRouter.h"
#import "ITrackingProvider.h"
#import "firebase/FGFirebaseProvider.h"
#import "appsflyer/FGAppsFlyerProvider.h"
#import "facebook/FGFacebookProvider.h"
#import "applovin/FGAppLovinEventProvider.h"
#import "applovin/FGAppLovinEventMapper.h"
#import "../config/FGConfigController.h"
#import "../event/FGEvent.h"
#import "../init/FGInitStateMachine.h"
#include <atomic>

static NSString *const kFGTrackingTag = @"FGTracking";

@interface FGTrackingOrchestrator ()
- (void)createProviders;
- (void)onProviderReady;
- (void)onAllProvidersReady;
- (void)flushBuffer;
- (void)enqueue:(FGTrackingEvent *)event;
- (void)dispatchLog:(FGTrackingEvent *)event;
- (void)dispatchProps:(FGParams)props;
@end

@implementation FGTrackingOrchestrator {
    std::atomic<FGTrackingState> _state; // Kotlin @Volatile
    NSMutableArray<id<ITrackingProvider>> *_providers;
    NSInteger _readyCount;
    NSMutableArray<dispatch_block_t> *_buffer;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = FGTrackingStateNotInitialized;
        _providers = [NSMutableArray array];
        _readyCount = 0;
        _buffer = [NSMutableArray array];
    }
    return self;
}

- (void)initialize:(BOOL)isConsent isATTAuthorized:(BOOL)isATTAuthorized {
    if (_state.load() != FGTrackingStateNotInitialized) return;
    _state.store(FGTrackingStateInitializing);

    // orchestrator sống suốt app (mirror Kotlin `+= ::onProviderReady`) → strong capture
    FGTrackingOrchestrator *sf = self;
    FGEvent::Tracking::OnProviderReady.add([sf] { [sf onProviderReady]; });
    [self createProviders];

    if (_providers.count == 0) { [self onAllProvidersReady]; return; }
    for (id<ITrackingProvider> p in [_providers copy]) {
        [p initialize:isConsent isATTAuthorized:isATTAuthorized];
    }
}

/** Gate theo enabled_packages nếu có (spec §3.2); rỗng/nil → bật cả 3 (giống hành vi Unity khi để trống). */
- (void)createProviders {
    NSArray<NSString *> *enabled = [FGConfigController mainPlatform].enabled_packages
        ?: [FGConfigController mainConfig].enabled_packages;
    BOOL (^on)(NSString *) = ^BOOL(NSString *packageId) {
        return enabled.count == 0 || [enabled containsObject:packageId];
    };

    if (on(@"firebase_analytic")) [_providers addObject:[[FGFirebaseProvider alloc] init]];
    if (on(@"appsflyer"))         [_providers addObject:[[FGAppsFlyerProvider alloc] init]];
    if (on(@"facebook"))          [_providers addObject:[[FGFacebookProvider alloc] init]];
    // AppLovin EventService (mở rộng ngoài Unity): LUÔN thêm (bám MAX SDK, không gate theo
    // enabled_packages analytics). Idle tới khi có event chỉ định providers=[AppLovin].
    [_providers addObject:[[FGAppLovinEventProvider alloc] init]];

    NSMutableArray *types = [NSMutableArray arrayWithCapacity:_providers.count];
    for (id<ITrackingProvider> p in _providers) [types addObject:p.providerType ?: [NSNull null]];
    NSLog(@"[%@] createProviders: %@", kFGTrackingTag, types);
}

- (void)onProviderReady {
    _readyCount++;
    if (_readyCount >= (NSInteger)_providers.count) [self onAllProvidersReady];
}

- (void)onAllProvidersReady {
    if (_state.load() == FGTrackingStateReady) return;
    _state.store(FGTrackingStateReady);
    [self flushBuffer];
    [FGInitStateMachine SetReady:FGInitStateAnalystic];
    FGEvent::Tracking::OnAllProvidersReady.invoke();
    NSLog(@"[%@] OnAllProvidersReady → Analystic ready", kFGTrackingTag);
}

- (void)flushBuffer {
    NSArray<dispatch_block_t> *pending = [_buffer copy];
    [_buffer removeAllObjects];
    for (dispatch_block_t b in pending) {
        @try { b(); } @catch (id e) { NSLog(@"[%@] flush fail: %@", kFGTrackingTag, e); }
    }
}

- (void)logEvent:(FGTrackingEvent *)event {
    [self enqueue:event];
    // AppLovin auto-log (mở rộng): 1 FG event có thể phái sinh event AppLovin (providers=[AppLovin]),
    // dùng CHUNG cơ chế buffer/dispatch. Map chỉ ở đây → event phái sinh KHÔNG map lại (không đệ quy).
    for (FGTrackingEvent *mapped in [FGAppLovinEventMapper map:event]) [self enqueue:mapped];
}

- (void)enqueue:(FGTrackingEvent *)event {
    if (_state.load() != FGTrackingStateReady) {
        FGTrackingOrchestrator *sf = self;
        [_buffer addObject:[^{ [sf dispatchLog:event]; } copy]];
        return;
    }
    [self dispatchLog:event];
}

- (void)dispatchLog:(FGTrackingEvent *)event {
    for (id<ITrackingProvider> p in _providers) {
        if (![FGEventRouter isProviderEnabled:p event:event]) continue;
        @try {
            [p logEvent:event.eventName params:event.params];
        } @catch (id e) {
            NSLog(@"[%@] logEvent %@ fail: %@", kFGTrackingTag, p.providerType, e);
        }
    }
}

- (void)setUserProperties:(FGParams)props {
    if (_state.load() != FGTrackingStateReady) {
        FGTrackingOrchestrator *sf = self;
        [_buffer addObject:[^{ [sf dispatchProps:props]; } copy]];
        return;
    }
    [self dispatchProps:props];
}

- (void)dispatchProps:(FGParams)props {
    for (id<ITrackingProvider> p in _providers) {
        @try { [p setUserProperties:props]; } @catch (id e) { /* mirror runCatching nuốt lỗi */ }
    }
}

/** spec §9.2 — SetConsent KHÔNG check state. */
- (void)setConsent:(BOOL)isConsent {
    for (id<ITrackingProvider> p in _providers) {
        @try { [p setConsent:isConsent]; } @catch (id e) { /* mirror runCatching nuốt lỗi */ }
    }
}

@end
