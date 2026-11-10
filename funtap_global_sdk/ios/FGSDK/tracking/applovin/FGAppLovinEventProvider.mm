//
//  FGAppLovinEventProvider.mm — mirror KA/tracking/applovin/FGAppLovinEventProvider.kt.
//  AppLovin EventService: [ALSdk shared].eventService trackEvent:parameters: — dùng chung ALSdk instance
//  với FGMaxAdsProvider. event name PHẢI thuộc catalog AppLovin, value LUÔN String.
//
#import "FGAppLovinEventProvider.h"
#import "../../event/FGEvent.h"
#import <AppLovinSDK/AppLovinSDK.h>

@implementation FGAppLovinEventProvider

- (NSNumber *)providerType { return @(ProviderTypeAppLovin); }

- (void)initialize:(BOOL)isConsent isATTAuthorized:(BOOL)isATTAuthorized {
    // Không có bước init riêng (EventService bám [ALSdk shared]) → signal ready ngay
    // (hợp đồng ITrackingProvider: PHẢI fire, không thì cờ Analystic không set → treo, quirk 20).
    FGEvent::Tracking::OnProviderReady.invoke();
}

- (void)logEvent:(NSString *)eventName params:(FGParams)params {
    ALEventService *svc = [ALSdk shared].eventService;
    if (svc == nil) return;
    if (params.count == 0) {
        [svc trackEvent:eventName];
    } else {
        // AppLovin yêu cầu NSDictionary<NSString*,NSString*> — ép value về string, bỏ null.
        NSMutableDictionary<NSString *, NSString *> *data = [NSMutableDictionary dictionaryWithCapacity:params.count];
        [params enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) {
            if (v != nil && v != (id)[NSNull null]) data[k] = [NSString stringWithFormat:@"%@", v];
        }];
        [svc trackEvent:eventName parameters:data];
    }
}

- (void)setUserProperties:(FGParams)props { /* no-op: EventService không có user property */ }

- (void)setConsent:(BOOL)isConsent { /* no-op: consent xử ở MAX SDK init/privacy */ }

@end
