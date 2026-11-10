//
//  FGAdEventLogger.mm — mirror KA/ads/FGAdEventLogger.kt (spec §8).
//  Param key VERBATIM. Route qua FGEvent::Tracking bus — KHÔNG import Firebase/AppsFlyer
//  (provider isolation). LogEventWithParams = overload không provider → CHỈ Firebase (spec §9.2).
//
//  ⚠️ Điểm diễn giải (như Kotlin): NSDictionary không giữ thứ tự key như LinkedHashMap —
//  Firebase params không phụ thuộc thứ tự nên chấp nhận.
//
#import "FGAdEventLogger.h"
#import "../event/FGEvent.h"
#import "../event/FGEventTypes.h"

// Kotlin `fb(name, params)` — null-safe invoke (≈ `?.invoke`).
static void FGAdLogFb(NSString *name, NSDictionary<NSString *, id> *params) {
    if (FGEvent::Tracking::LogEventWithParams) FGEvent::Tracking::LogEventWithParams(name, params);
}

// ── Param builders (VERBATIM §8 — mirror buildRequest/buildDisplay/buildCompleted Kotlin) ──

static NSMutableDictionary<NSString *, id> *FGBuildRequest(
    NSString *playMode, double level, NSString *platform, NSString *adNetwork, NSString *format,
    NSString *location, BOOL success, NSString *reason, double value, NSInteger requestCount, NSString *unitId) {
    NSMutableDictionary<NSString *, id> *d = [NSMutableDictionary dictionary];
    d[@"play_mode"] = playMode;
    d[@"level"] = @(level);
    d[@"ad_platform"] = platform;
    d[@"ad_network"] = adNetwork;
    d[@"ad_format"] = format;
    d[@"location"] = location;
    d[@"success"] = success ? @"true" : @"false"; // ⚠️ string, không phải bool (spec §8)
    d[@"reason"] = reason;
    d[@"value"] = @(value);
    d[@"request_count"] = @(requestCount);
    d[@"unit_id"] = unitId;
    return d;
}

static NSMutableDictionary<NSString *, id> *FGBuildDisplay(
    NSString *playMode, double level, NSString *platform, NSString *adNetwork, NSString *format,
    NSString *location, BOOL success, NSString *reason, double value) {
    NSMutableDictionary<NSString *, id> *d = [NSMutableDictionary dictionary];
    d[@"play_mode"] = playMode;
    d[@"level"] = @(level);
    d[@"ad_platform"] = platform;
    d[@"ad_network"] = adNetwork;
    d[@"ad_format"] = format;
    d[@"location"] = location;
    d[@"success"] = success ? @"true" : @"false";
    d[@"reason"] = reason;
    d[@"value"] = @(value);
    return d;
}

static NSMutableDictionary<NSString *, id> *FGBuildCompleted(
    NSString *playMode, double level, NSString *platform, NSString *adNetwork, NSString *format,
    NSString *location, BOOL success, double value) {
    NSMutableDictionary<NSString *, id> *d = [NSMutableDictionary dictionary];
    d[@"play_mode"] = playMode;
    d[@"level"] = @(level);
    d[@"ad_platform"] = platform;
    d[@"ad_network"] = adNetwork;
    d[@"ad_format"] = format;
    d[@"location"] = location;
    d[@"success"] = success ? @"true" : @"false";
    d[@"value"] = @(value); // KHÔNG có reason (spec §8)
    return d;
}

@implementation FGAdEventLogger

+ (void)adRequest:(NSString *)playMode
            level:(double)level
         platform:(NSString *)platform
        adNetwork:(NSString *)adNetwork
           format:(NSString *)format
         location:(NSString *)location
          success:(BOOL)success
           reason:(NSString *)reason
            value:(double)value
     requestCount:(NSInteger)requestCount
           unitId:(NSString *)unitId {
    FGAdLogFb(@"ad_request", FGBuildRequest(playMode, level, platform, adNetwork, format,
                                            location, success, reason, value, requestCount, unitId));
}

+ (void)adDisplay:(NSString *)playMode
            level:(double)level
         platform:(NSString *)platform
        adNetwork:(NSString *)adNetwork
           format:(NSString *)format
         location:(NSString *)location
          success:(BOOL)success
           reason:(NSString *)reason
            value:(double)value {
    FGAdLogFb(@"ad_display", FGBuildDisplay(playMode, level, platform, adNetwork, format,
                                            location, success, reason, value));
}

+ (void)adCompleted:(NSString *)playMode
              level:(double)level
           platform:(NSString *)platform
          adNetwork:(NSString *)adNetwork
             format:(NSString *)format
           location:(NSString *)location
            success:(BOOL)success
              value:(double)value {
    FGAdLogFb(@"ad_completed", FGBuildCompleted(playMode, level, platform, adNetwork, format,
                                                location, success, value));
}

/**
 * spec §8 — dict impression (dùng chung ad_impression + ad_revenue_sdk).
 * MAX: network key = `ad_network`. AdMob Interstitial: `ad_source`; format khác: `ad_network`.
 * `ad_unit_name` CHỈ có với Interstitial.
 */
+ (NSMutableDictionary<NSString *, id> *)buildImpression:(NSString *)format
                                                 isAdmob:(BOOL)isAdmob
                                          isInterstitial:(BOOL)isInterstitial
                                               adNetwork:(NSString *)adNetwork
                                                 revenue:(double)revenue
                                                currency:(NSString *)currency
                                              adUnitName:(NSString *_Nullable)adUnitName {
    NSMutableDictionary<NSString *, id> *d = [NSMutableDictionary dictionary];
    d[@"ad_format"] = format;
    d[@"ad_platform"] = isAdmob ? @"admob_sdk" : @"applovin_max_sdk";
    NSString *networkKey = (isAdmob && isInterstitial) ? @"ad_source" : @"ad_network";
    d[networkKey] = adNetwork;
    d[@"value"] = @(revenue);
    d[@"currency"] = currency;
    if (isInterstitial && adUnitName != nil) d[@"ad_unit_name"] = adUnitName;
    return d;
}

+ (void)adImpression:(NSDictionary<NSString *, id> *)dict {
    FGAdLogFb(@"ad_impression", dict);
}

+ (void)adClick:(NSString *)format platform:(NSString *)platform adNetwork:(NSString *)adNetwork {
    FGAdLogFb(@"ad_click", @{ @"ad_format": format, @"ad_platform": platform, @"ad_network": adNetwork });
}

+ (void)adRevenueSdk:(NSDictionary<NSString *, id> *)impressionDict
            location:(NSString *)location
             xParams:(FGParams _Nullable)xParams {
    NSMutableDictionary<NSString *, id> *d = [impressionDict mutableCopy];
    d[@"location"] = location;
    if (xParams != nil) [d addEntriesFromDictionary:xParams]; // merge XParams (play_mode/level + custom)
    FGAdLogFb(@"ad_revenue_sdk", d);
}

+ (void)afIntersDisplayed {
    if (FGEvent::Tracking::LogEventProvider)
        FGEvent::Tracking::LogEventProvider(@"af_inters_displayed", ProviderTypeAppsFlyer);
}

+ (void)afRewardedDisplayed {
    if (FGEvent::Tracking::LogEventProvider)
        FGEvent::Tracking::LogEventProvider(@"af_rewarded_displayed", ProviderTypeAppsFlyer);
}

+ (void)logAdRevenue:(NSString *)network
             isAdmob:(BOOL)isAdmob
            currency:(NSString *)currency
             revenue:(double)revenue
              format:(NSString *)format
              adUnit:(NSString *)adUnit {
    // Hook set bởi AppsFlyer provider; null → no-op (≈ guard APPSFLYER_SDK_ENABLE).
    if (FGEvent::Tracking::LogAdRevenue)
        FGEvent::Tracking::LogAdRevenue(network, isAdmob, currency, revenue, format, adUnit);
}

@end
