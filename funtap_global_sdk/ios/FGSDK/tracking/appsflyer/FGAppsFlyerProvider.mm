//
//  FGAppsFlyerProvider.mm — mirror KA/tracking/appsflyer/FGAppsFlyerProvider.kt (spec §9.4).
//
#import "FGAppsFlyerProvider.h"
#import "../../config/FGConfigController.h"
#import "../../event/FGEvent.h"
#import "../../util/FGConstValue.h"
#import "../../util/FGMainThreadDispatcher.h"

#if APPSFLYER_SDK_ENABLE
#import <AppsFlyerLib/AppsFlyerLib.h>
#import <PurchaseConnector/PurchaseConnector.h>
#endif

static NSString *const kFGAppsFlyerTag = @"FGAppsFlyer";

#if APPSFLYER_SDK_ENABLE
@interface FGAppsFlyerProvider () <AppsFlyerLibDelegate, AppsFlyerDeepLinkDelegate, AppsFlyerPurchaseRevenueDelegate>
- (void)logAdRevenue:(NSString *)network
             isAdmob:(BOOL)isAdmob
            currency:(NSString *)currency
             revenue:(double)revenue
              format:(NSString *)format
              adUnit:(NSString *)adUnit;
- (void)startPurchaseConnector;
@end
#endif

@implementation FGAppsFlyerProvider {
    BOOL _isATT;
}

- (instancetype)init {
    self = [super init];
    if (self) { _isATT = YES; }
    return self;
}

- (NSNumber *)providerType { return @(ProviderTypeAppsFlyer); }

- (void)initialize:(BOOL)isConsent isATTAuthorized:(BOOL)isATTAuthorized {
    _isATT = isATTAuthorized;
    // provider sống suốt app (mirror Kotlin) → strong capture; AppsFlyerLib.delegate là weak
    FGAppsFlyerProvider *sf = self;
    [FGMainThreadDispatcher enqueue:^{
        @try {
#if APPSFLYER_SDK_ENABLE
            FGAppsflyerConfig *cfg = [FGConfigController mainPlatform].appsflyer_configs;
            NSString *devKey = cfg.DevKey;
            if (devKey.length == 0) {
                NSLog(@"[%@] thiếu DevKey → init fail, vẫn signal ready", kFGAppsFlyerTag);
                return; // @finally vẫn chạy
            }
            AppsFlyerLib *af = [AppsFlyerLib shared];
            // mirror af.init(devKey, conversionListener, ctx) — iOS: devKey + appleAppID + delegate
            af.appsFlyerDevKey = devKey;
            if (cfg.AppId.length > 0) af.appleAppID = cfg.AppId;
            af.delegate = sf;
            af.deepLinkDelegate = sf; // §12 — deferred deeplink → FGEvent::Deeplink
            // spec §9.4 nhánh iOS — chờ ATT tối đa 60s trước khi start
            [af waitForATTUserAuthorizationWithTimeoutInterval:60];
            [sf setConsent:isConsent];
            af.customerUserID = FGConstValue.UserDeviceId;
            [af start];

            // spec §8 — đăng ký hook logAdRevenue (chỉ set khi provider init = guard APPSFLYER_SDK_ENABLE tự nhiên)
            FGEvent::Tracking::LogAdRevenue =
                [sf](NSString *network, BOOL isAdmob, NSString *currency, double revenue,
                     NSString *format, NSString *adUnit) {
                    [sf logAdRevenue:network isAdmob:isAdmob currency:currency
                              revenue:revenue format:format adUnit:adUnit];
                };

            // KHÔNG có FCM uninstall token — đường Android-only (spec §9.4); iOS đo uninstall qua APNs (ngoài scope)

            // spec §11 — PurchaseConnector ROI360: af_purchase Connector TỰ bắn (IAP không gọi thủ công)
            [sf startPurchaseConnector];
            NSLog(@"[%@] AppsFlyer init OK", kFGAppsFlyerTag);
#else
            NSLog(@"[%@] APPSFLYER_SDK_ENABLE=0 → skip init, vẫn signal ready", kFGAppsFlyerTag);
#endif
        } @catch (id e) {
            NSLog(@"[%@] init fail: %@", kFGAppsFlyerTag, e);
        } @finally {
            FGEvent::Tracking::OnProviderReady.invoke(); // LUÔN signal ready (quirk 20)
            FGEvent::InitEvent::AppsFlyerInitComplete.invoke();
        }
    }];
}

- (void)logEvent:(NSString *)eventName params:(FGParams)params {
#if APPSFLYER_SDK_ENABLE
    // ⚠️ quirk 11: af_revenue → KHÔNG logEvent (tránh double count Connector). Ad revenue thật đi qua
    // hook LogAdRevenue (logAdRevenue) với đủ AFAdRevenueData; event generic không mang đủ field nên skip.
    if ([eventName isEqualToString:FGConstValue.AF_Revenue]) {
        NSLog(@"[%@] af_revenue skip logEvent (dùng hook logAdRevenue)", kFGAppsFlyerTag);
        return;
    }
    NSMutableDictionary<NSString *, id> *values = nil;
    if (params != nil) {
        values = [NSMutableDictionary dictionaryWithCapacity:params.count];
        [params enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) {
            if (![v isKindOfClass:[NSNull class]]) values[k] = v; // mirror filterValues { it != null }
        }];
    }
    [[AppsFlyerLib shared] logEvent:eventName withValues:values];
#endif
}

/** ⚠️ spec §9.4 — SetUserProperties = no-op (body comment out ở Unity, quirk 10). */
- (void)setUserProperties:(FGParams)props { /* no-op */ }

/**
 * spec §9.4 verbatim — AppsFlyerConsent(isUserSubjectToGDPR=true, hasConsentForDataUsage=consent,
 * hasConsentForAdsPersonalization=consent&&ATT, hasConsentForAdStorage=consent).
 */
- (void)setConsent:(BOOL)isConsent {
#if APPSFLYER_SDK_ENABLE
    @try {
        AppsFlyerConsent *consent =
            [[AppsFlyerConsent alloc] initWithIsUserSubjectToGDPR:@YES
                                           hasConsentForDataUsage:@(isConsent)
                                  hasConsentForAdsPersonalization:@(isConsent && _isATT)
                                           hasConsentForAdStorage:@(isConsent)];
        [[AppsFlyerLib shared] setConsentData:consent];
    } @catch (id e) {
        NSLog(@"[%@] setConsent fail: %@", kFGAppsFlyerTag, e);
    }
#endif
}

#if APPSFLYER_SDK_ENABLE

/**
 * spec §8 — logAdRevenue(AFAdRevenueData(network, ApplovinMax|GoogleAdMob, currency, revenue),
 * { "ad_type": format, "ad_unit": adUnit }). AdMob revenue đã quy đổi /1e6 ở phía ads provider.
 */
- (void)logAdRevenue:(NSString *)network
             isAdmob:(BOOL)isAdmob
            currency:(NSString *)currency
             revenue:(double)revenue
              format:(NSString *)format
              adUnit:(NSString *)adUnit {
    @try {
        AppsFlyerAdRevenueMediationNetworkType mediation = isAdmob
            ? AppsFlyerAdRevenueMediationNetworkTypeGoogleAdMob
            : AppsFlyerAdRevenueMediationNetworkTypeApplovinMax;
        AFAdRevenueData *data = [[AFAdRevenueData alloc] initWithMonetizationNetwork:network
                                                                    mediationNetwork:mediation
                                                                 currencyIso4217Code:currency
                                                                        eventRevenue:@(revenue)];
        [[AppsFlyerLib shared] logAdRevenue:data
                       additionalParameters:@{ @"ad_type": format, @"ad_unit": adUnit }];
    } @catch (id e) {
        NSLog(@"[%@] logAdRevenue fail: %@", kFGAppsFlyerTag, e);
    }
}

/**
 * spec §11 — ROI360 PurchaseConnector: tự observe StoreKit → bắn af_purchase (không gọi thủ công).
 * autoLogPurchaseRevenue subs+in-app = mirror logSubscriptions(true)+autoLogInApps(true) Android.
 * SK1 default — KHÔNG setStoreKitVersion SK2 (README: SK2 ở spec §9.4 là artifact Unity IAP 5).
 */
- (void)startPurchaseConnector {
    @try {
        PurchaseConnector *pc = [PurchaseConnector shared];
        pc.purchaseRevenueDelegate = self;
        pc.autoLogPurchaseRevenue = AFSDKAutoLogPurchaseRevenueOptionsAutoRenewableSubscriptions
                                  | AFSDKAutoLogPurchaseRevenueOptionsInAppPurchases;
#if APPSFLYER_CONNECTOR_SANDBOX
        pc.isSandbox = YES; // spec §9.4 — sandbox connector
#endif
        [pc startObservingTransactions];
    } @catch (id e) {
        NSLog(@"[%@] PurchaseConnector fail: %@", kFGAppsFlyerTag, e);
    }
}

#pragma mark - AppsFlyerPurchaseRevenueDelegate

- (void)didReceivePurchaseRevenueValidationInfo:(NSDictionary * _Nullable)validationInfo
                                          error:(NSError * _Nullable)error {
    // Connector tự log af_purchase — mirror Kotlin (không đặt validation listener xử lý thêm)
}

#pragma mark - AppsFlyerDeepLinkDelegate

/**
 * spec §12 — deferred deeplink. FOUND && isDeferred → đọc deep_link_value → OnDeferredDeepLinkReceived(value, 0).
 * ⚠️ quirk 16.1: deep_link_sub1 KHÔNG parse → luôn truyền 0 (mirror Android).
 */
- (void)didResolveDeepLink:(AppsFlyerDeepLinkResult *)result {
    if (result.status != AFSDKDeepLinkResultStatusFound) return;
    AppsFlyerDeepLink *dl = result.deepLink;
    if (dl == nil || !dl.isDeferred) return;
    NSString *value = @"";
    @try { value = dl.deeplinkValue ?: @""; } @catch (id e) { value = @""; } // mirror runCatching
    if (value.length > 0) FGEvent::Deeplink::OnDeferredDeepLinkReceived.invoke(value, 0);
}

#pragma mark - AppsFlyerLibDelegate

- (void)onConversionDataSuccess:(NSDictionary *)conversionInfo {
    if (conversionInfo == nil) return;
    // spec §9.4 — map attribution → user props (⚠️ quirk 12 lệch tên). Cuối cùng ghi Firebase
    // (AppsFlyer SetUserProperties no-op).
    NSMutableDictionary<NSString *, id> *props = [NSMutableDictionary dictionary];
    id v;
    if ((v = conversionInfo[@"media_source"]) != nil) props[@"media_source"] = v;
    if ((v = conversionInfo[@"campaign"]) != nil)     props[@"campaign"] = v;
    if ((v = conversionInfo[@"adgroup"]) != nil)      props[@"ad_group"] = v; // ⚠️ adgroup → ad_group
    if ((v = conversionInfo[@"adset_id"]) != nil)     props[@"adset_id"] = v; // giữ nguyên
    if ((v = conversionInfo[@"adset"]) != nil)        props[@"ad_set"] = v;   // ⚠️ adset → ad_set
    if (props.count > 0 && FGEvent::Tracking::SetUserProperties) {
        FGEvent::Tracking::SetUserProperties(props);
    }
}

- (void)onConversionDataFail:(NSError *)error {
    NSLog(@"[%@] conversion fail: %@", kFGAppsFlyerTag, error.localizedDescription);
}

- (void)onAppOpenAttribution:(NSDictionary *)attributionData { /* deeplink §12 */ }

- (void)onAppOpenAttributionFailure:(NSError *)error {
    NSLog(@"[%@] attribution fail: %@", kFGAppsFlyerTag, error.localizedDescription);
}

#endif // APPSFLYER_SDK_ENABLE

@end
