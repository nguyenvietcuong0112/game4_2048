//
//  FGFirebaseProvider.mm — mirror KA/tracking/firebase/FGFirebaseProvider.kt (spec §9.3).
//
#import "FGFirebaseProvider.h"
#import "../../consent/FGConsentManager.h"
#import "../../event/FGEvent.h"
#import "../../util/FGInternetChecker.h"
#import "../../util/FGMainThreadDispatcher.h"
#import <FirebaseCore/FirebaseCore.h>
#import <FirebaseAnalytics/FirebaseAnalytics.h>

static NSString *const kFGFirebaseTag = @"FGFirebase";
static const NSUInteger kMaxKey = 24;   // ⚠️ Firebase user-property key ≤ 24 (quirk 18)
static const NSUInteger kMaxValue = 36; // ⚠️ value ≤ 36 (quirk 18)

@interface FGFirebaseProvider ()
- (void)setUserProperty:(NSString *)key value:(NSString *)value;
@end

@implementation FGFirebaseProvider {
    volatile BOOL _isInitialized; // Kotlin @Volatile
    BOOL _isATT;
}

- (instancetype)init {
    self = [super init];
    if (self) { _isATT = YES; }
    return self;
}

- (NSNumber *)providerType { return @(ProviderTypeFirebase); }

- (void)initialize:(BOOL)isConsent isATTAuthorized:(BOOL)isATTAuthorized {
    _isATT = isATTAuthorized;
    // provider sống suốt app (mirror Kotlin) → strong capture
    FGFirebaseProvider *sf = self;
    [FGMainThreadDispatcher enqueue:^{
        @try {
            // mirror FirebaseApp.initializeApp(ctx): thiếu GoogleService-Info.plist → configure throw → catch
            if ([FIRApp defaultApp] == nil) [FIRApp configure];
            if ([FIRApp defaultApp] != nil) {
                sf->_isInitialized = YES;
                [sf setConsent:isConsent];
                FGEvent::Network::OnNetworkRestored.add([sf] {
                    [sf setUserProperty:@"connection" value:@"online"];
                });
                FGEvent::Network::OnNetworkLost.add([sf] {
                    [sf setUserProperty:@"connection" value:@"offline"];
                });
                [sf setUserProperty:@"connection"
                               value:(FGInternetChecker.isConnected ? @"online" : @"offline")];
                FGEvent::InitEvent::FirebaseInitComplete.invoke();
                NSLog(@"[%@] Firebase init OK", kFGFirebaseTag);
            } else {
                NSLog(@"[%@] no FIRApp (thiếu GoogleService-Info.plist?) → init fail, vẫn signal ready", kFGFirebaseTag);
            }
        } @catch (id e) {
            NSLog(@"[%@] init fail: %@", kFGFirebaseTag, e);
        } @finally {
            FGEvent::Tracking::OnProviderReady.invoke(); // LUÔN signal ready (quirk 20)
        }
    }];
}

- (void)logEvent:(NSString *)eventName params:(FGParams)params {
    if (!_isInitialized) return; // mirror `analytics ?: return`
    NSMutableDictionary<NSString *, id> *converted = [NSMutableDictionary dictionaryWithCapacity:params.count];
    [params enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) {
        if ([v isKindOfClass:[NSString class]] || [v isKindOfClass:[NSNumber class]]) {
            converted[k] = v; // mirror String/Int/Long/Double/Float giữ nguyên
        } else if ([v isKindOfClass:[NSNull class]]) {
            // mirror Kotlin putString(k, null) → param bị bỏ
        } else {
            converted[k] = [v description]; // mirror else → toString()
        }
    }];
    [FIRAnalytics logEventWithName:eventName parameters:converted];
}

- (void)setUserProperties:(FGParams)props {
    [props enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) {
        [self setUserProperty:k value:([v isKindOfClass:[NSNull class]] ? @"" : [v description])];
    }];
}

- (void)setUserProperty:(NSString *)key value:(NSString *)value {
    if (!_isInitialized) return;
    NSString *k = key.length > kMaxKey ? [key substringToIndex:kMaxKey] : key;
    NSString *v = value.length > kMaxValue ? [value substringToIndex:kMaxValue] : value;
    [FIRAnalytics setUserPropertyString:v forName:k]; // ⚠️ truncate 24/36 (quirk 18)
}

/** spec §9.3 — map theo CanRequestAds/HasConsentForAds × isATTAuthorized. */
- (void)setConsent:(BOOL)isConsent {
    if (!_isInitialized) return;
    BOOL adsAllowed = [FGConsentManager HasConsentForAds];
    BOOL adsAndAtt = adsAllowed && _isATT;
    FIRConsentStatus G = FIRConsentStatusGranted;
    FIRConsentStatus D = FIRConsentStatusDenied;
    [FIRAnalytics setConsent:@{
        FIRConsentTypeAdStorage:         adsAllowed ? G : D,
        FIRConsentTypeAdUserData:        adsAndAtt ? G : D,
        FIRConsentTypeAdPersonalization: adsAndAtt ? G : D,
        FIRConsentTypeAnalyticsStorage:  G,
    }];
}

@end
