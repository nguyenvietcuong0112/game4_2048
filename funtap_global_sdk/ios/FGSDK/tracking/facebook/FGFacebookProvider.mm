//
//  FGFacebookProvider.mm — mirror KA/tracking/facebook/FGFacebookProvider.kt (spec §9.5).
//  iOS trả nợ ATT của Kotlin: SetAdvertiserTrackingEnabled(isATT) là API iOS-only.
//
#import "FGFacebookProvider.h"
#import "../../config/FGConfigController.h"
#import "../../event/FGEvent.h"
#import "../../util/FGMainThreadDispatcher.h"

#if FACEBOOK_SDK_ENABLE
#import <SafariServices/SafariServices.h>
#import <AuthenticationServices/AuthenticationServices.h>
#import <FBSDKCoreKit/FBSDKCoreKit.h>
#import <FBSDKCoreKit/FBSDKCoreKit-Swift.h>
#endif

static NSString *const kFGFacebookTag = @"FGFacebook";

@implementation FGFacebookProvider {
    volatile BOOL _isReady; // Kotlin @Volatile
    BOOL _isATT;
}

- (instancetype)init {
    self = [super init];
    if (self) { _isATT = YES; }
    return self;
}

- (NSNumber *)providerType { return @(ProviderTypeFacebook); }

- (void)initialize:(BOOL)isConsent isATTAuthorized:(BOOL)isATTAuthorized {
    _isATT = isATTAuthorized;
    // provider sống suốt app (mirror Kotlin) → strong capture
    FGFacebookProvider *sf = self;
    [FGMainThreadDispatcher enqueue:^{
        @try {
#if FACEBOOK_SDK_ENABLE
            FGFacebookConfig *cfg = [FGConfigController mainPlatform].facebook_configs;
            if (cfg.app_id.length == 0) {
                NSLog(@"[%@] thiếu app_id → init fail, vẫn signal ready", kFGFacebookTag);
                return; // @finally vẫn chạy
            }
            FBSDKSettings.sharedSettings.appID = cfg.app_id;
            if (cfg.client_token != nil) FBSDKSettings.sharedSettings.clientToken = cfg.client_token;
            // ⚠️ Kotlin CHỈ set appId + clientToken (KHÔNG displayName) → giữ verbatim, không set app_name
            [[FBSDKApplicationDelegate sharedInstance] initializeSDK]; // mirror FB.Init/fullyInitialize
            [FBSDKAppEvents.shared activateApp];
            // spec §9.5 — SetAdvertiserTrackingEnabled(isATT): API iOS-only, Kotlin để nợ Phase 11 → trả ở đây
            FBSDKSettings.sharedSettings.advertiserTrackingEnabled = sf->_isATT;
            NSLog(@"[%@] Facebook init OK (isATT=%d)", kFGFacebookTag, isATTAuthorized);
#else
            NSLog(@"[%@] FACEBOOK_SDK_ENABLE=0 → skip init, vẫn signal ready", kFGFacebookTag);
#endif
        } @catch (id e) {
            NSLog(@"[%@] init fail: %@", kFGFacebookTag, e);
        } @finally {
            if (!sf->_isReady) {
                sf->_isReady = YES;
                FGEvent::Tracking::OnProviderReady.invoke(); // LUÔN signal ready đúng 1 lần (quirk 20)
                FGEvent::InitEvent::FacebookInitComplete.invoke();
            }
        }
    }];
}

/** ⚠️ no-op (spec §9.5, quirk 10). */
- (void)logEvent:(NSString *)eventName params:(FGParams)params { /* no-op */ }

/** ⚠️ no-op (spec §9.5, quirk 10). */
- (void)setUserProperties:(FGParams)props { /* no-op */ }

/** spec §9.5 — SetConsent = SetAdvertiserTrackingEnabled(isATTAuthorized) — dùng isATT đã lưu, KHÔNG dùng isConsent (mirror Unity). */
- (void)setConsent:(BOOL)isConsent {
#if FACEBOOK_SDK_ENABLE
    @try {
        FBSDKSettings.sharedSettings.advertiserTrackingEnabled = _isATT;
    } @catch (id e) {
        NSLog(@"[%@] setConsent fail: %@", kFGFacebookTag, e);
    }
#endif
}

@end
