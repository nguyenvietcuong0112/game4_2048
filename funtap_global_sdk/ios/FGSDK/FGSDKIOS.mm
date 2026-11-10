//
//  FGSDKIOS.mm — impl entry point + facade. Mirror KA/FGSDK.kt + FGSDK*.kt.
//  Route mọi API qua FGEvent::* bus (bus null = chưa init/guard tắt → no-op / giá trị an toàn,
//  mirror Kotlin `?.invoke(...)`). Init flow spec §2 (Awake gộp Start — iOS không có 2 pha).
//
#import "FGSDKIOS.h"

#import <QuartzCore/QuartzCore.h>   // CACurrentMediaTime (stopwatch int_time)
#import <UIKit/UIKit.h>             // UIScreen (GetMRecSize)

#import "config/FGConfigController.h"
#import "config/FGConfigModels.h"
#import "init/FGInitStateMachine.h"
#import "consent/FGConsentManager.h"
#import "ads/FGAds.h"
#import <AppLovinSDK/AppLovinSDK.h>   // showMediationDebugger (QA)
#import "util/FGConstValue.h"
#import "util/FGMainThreadDispatcher.h"
#import "util/FGInternetChecker.h"
#import "tracking/FGAnalyticsController.h"
#import "remoteconfig/FGRemoteConfigFirebase.h"
#import "ads/FGAdsController.h"
#import "iap/FGIAPManager.h"
#import "deeplink/FGDeeplinkManager.h"
#import "auth/FGAuthManager.h"
#import "event/FGEvent.h"

static NSString *const TAG = @"FGSDK";
static const int64_t SDK_READY_TIMEOUT_MS = 15000;

// State tĩnh (Kotlin object field). Toàn bộ chạm ở main thread (init flow + OnSDKReady).
static BOOL sSubscribed = NO;
static BOOL sIsInit = NO;
static CFTimeInterval sInitStartTime = 0;

@interface FGSDKIOS ()
// Private — gọi từ lambda subscribe / timeout.
+ (void)onSDKReady;
+ (void)resetAOAction;
+ (void)doInit;
@end

// Convenience logs — build param cố định rồi → Firebase (mirror Kotlin `log()`).
static void fgLog(NSString *name, NSMutableDictionary *base, FGParams extra) {
    if (extra) [base addEntriesFromDictionary:extra];
    if (FGEvent::Tracking::LogEventWithParams) FGEvent::Tracking::LogEventWithParams(name, base);
}

@implementation FGSDKIOS

// ── core getters / openAppAction ─────────────────────────────────────────────
+ (BOOL)isInit { return sIsInit; }

+ (NSString *)sdkVersion { return [FGConstValue SdkVersion]; }

+ (OpenAppAction)openAppAction { return [FGAds openAppAction]; }
+ (void)setOpenAppAction:(OpenAppAction)value { [FGAds setOpenAppAction:value]; }

// ── §2 init flow ─────────────────────────────────────────────────────────────
+ (void)initSDK {
    // Đăng ký module đúng THỨ TỰ Android FGSDK.kt (FGActivityTracker → iOS FGViewControllerTracker
    // lấy top VC on-demand nên KHÔNG cần register — README adaptation).
    [FGAnalyticsController register];     // §9.1 — wire tracking bus TRƯỚC consent → OnInitTracking
    [FGRemoteConfigFirebase register];   // §10
    [FGAdsController register];           // §7 — Ads init SAU tracking ready (OnAllProvidersReady)
    [FGIAPManager register];             // §11
    [FGDeeplinkManager register];        // §12
    [FGAuthManager register];            // §13

    // Awake: subscribe TRƯỚC khi check (tránh miss). Guard tránh double-subscribe khi init 2 lần.
    if (!sSubscribed) {
        sSubscribed = YES;
        FGEvent::InitEvent::OnSDKReady.add([]{ [FGSDKIOS onSDKReady]; });
        FGEvent::Ads::ResetAOAction.add([]{ [FGSDKIOS resetAOAction]; });
    }
    if ([FGInitStateMachine IsReady]) [FGSDKIOS onSDKReady];

    // Start → InitSDK
    FGMainConfig *config = [FGConfigController mainConfig];
    if (config == nil) {
        NSLog(@"[%@] MainConfig null → KHÔNG init (thiếu/parse lỗi fg_main_config.json)", TAG);
        return;
    }
    sInitStartTime = CACurrentMediaTime();
    NSLog(@"[%@] InitSDK v%@ — MediationType=%ld", TAG, [self sdkVersion],
          (long)[FGConfigController mainPlatform].MediationType);

    [FGInternetChecker start];
    [FGSDKIOS doInit];

    // Fallback: 15s chưa ready → force OnSDKReady (tránh treo game).
    [FGMainThreadDispatcher postDelayed:SDK_READY_TIMEOUT_MS action:^{
        if (!sIsInit) {
            NSLog(@"[%@] SDK ready timeout %lldms → force OnSDKReady", TAG, SDK_READY_TIMEOUT_MS);
            FGEvent::InitEvent::OnSDKReady.invoke();
        }
    }];
}

+ (void)doInit {
    // Consent (UMP → ATT) rồi khởi động Tracking (spec §6.1). Callback fail-open (quirk 19).
    [FGConsentManager RequestConsent:^(BOOL isConsent, BOOL isATTAuthorized) {
        FGEvent::Tracking::OnInitTracking.invoke(isConsent, isATTAuthorized);
        FGEvent::InitEvent::ConsentInitComplete.invoke(isConsent);
    }];
}

/// spec §2 — bắn init_sdk ĐÚNG 1 lần với 4 param.
+ (void)onSDKReady {
    if (sIsInit) return; // OnSDKReady xử lý đúng 1 lần
    BOOL success = [FGInitStateMachine IsReady];
    NSString *reason;
    if (success) {
        reason = @"none";
    } else if (![FGInitStateMachine IsMaxReady] && ![FGInitStateMachine IsAnalysticReady]) {
        reason = @"mediation_fail,analytic_fail";
    } else if (![FGInitStateMachine IsMaxReady]) {
        reason = @"mediation_fail";
    } else if (![FGInitStateMachine IsAnalysticReady]) {
        reason = @"analytic_fail";
    } else {
        reason = @"none";
    }
    double intTime = CACurrentMediaTime() - sInitStartTime; // giây (float)

    // Param key VERBATIM (spec §2). success → chuỗi "true"/"false" (Kotlin Boolean.toString()).
    NSDictionary *params = @{
        @"success":     success ? @"true" : @"false",
        @"int_time":    @(intTime),
        @"reason":      reason,
        @"sdk_version": [self sdkVersion],
    };
    // → CHỈ Firebase (spec §9.7). LogEventWithParams = overload không provider = Firebase (quirk 9).
    if (FGEvent::Tracking::LogEventWithParams) {
        FGEvent::Tracking::LogEventWithParams([FGConstValue InitSDK], params);
    }
    NSLog(@"[%@] OnSDKReady → init_sdk %@", TAG, params);

    sIsInit = YES;
}

/// spec §7.5 — chờ 4s (ignoreFullScreenAdsTime) rồi set openAppAction=NONE.
+ (void)resetAOAction {
    int64_t delayMs = (int64_t)([FGConstValue ignoreFullScreenAdsTime] * 1000); // 4000ms
    [FGMainThreadDispatcher postDelayed:delayMs action:^{ [FGAds setOpenAppAction:OpenAppActionNONE]; }];
}

// ── §4.1 Tracking ────────────────────────────────────────────────────────────
+ (void)LogEvent:(NSString *)eventName {
    if (FGEvent::Tracking::LogEvent) FGEvent::Tracking::LogEvent(eventName);
}
+ (void)LogEvent:(NSString *)eventName parameters:(FGParams)parameters {
    if (FGEvent::Tracking::LogEventWithParams) FGEvent::Tracking::LogEventWithParams(eventName, parameters);
}
+ (void)LogEvent:(NSString *)eventName provider:(ProviderType)provider {
    if (FGEvent::Tracking::LogEventProvider) FGEvent::Tracking::LogEventProvider(eventName, provider);
}
+ (void)LogEvent:(NSString *)eventName providers:(std::vector<ProviderType>)providers {
    if (FGEvent::Tracking::LogEventProviders) FGEvent::Tracking::LogEventProviders(eventName, providers);
}
+ (void)LogEvent:(NSString *)eventName parameters:(FGParams)parameters provider:(ProviderType)provider {
    if (FGEvent::Tracking::LogEventWithProvider) FGEvent::Tracking::LogEventWithProvider(eventName, parameters, provider);
}
+ (void)LogEvent:(NSString *)eventName parameters:(FGParams)parameters providers:(std::vector<ProviderType>)providers {
    if (FGEvent::Tracking::LogEventWithProviders) FGEvent::Tracking::LogEventWithProviders(eventName, parameters, providers);
}

+ (void)SetUserProperties:(FGParams)userProperties {
    if (FGEvent::Tracking::SetUserProperties) FGEvent::Tracking::SetUserProperties(userProperties);
}

+ (void)LogLevelStart:(NSInteger)level playCount:(NSInteger)playCount loseCount:(NSInteger)loseCount
             playMode:(NSString *)playMode additionalParams:(FGParams)additionalParams {
    fgLog(@"level_start", [@{
        @"level": @(level), @"play_count": @(playCount), @"lose_count": @(loseCount), @"play_mode": playMode,
    } mutableCopy], additionalParams);
}

+ (void)LogLevelEnd:(NSInteger)level playCount:(NSInteger)playCount loseCount:(NSInteger)loseCount
           playMode:(NSString *)playMode playDuration:(double)playDuration success:(BOOL)success
             reason:(NSString *)reason additionalParams:(FGParams)additionalParams {
    fgLog(@"level_end", [@{
        @"level": @(level), @"play_mode": playMode, @"play_count": @(playCount), @"lose_count": @(loseCount),
        @"play_duration": @(playDuration), @"success": success ? @"true" : @"false", @"reason": reason,
    } mutableCopy], additionalParams);
}

+ (void)LogEarnResource:(NSString *)playMode level:(NSInteger)level itemType:(NSString *)itemType
                   name:(NSString *)name amount:(double)amount earnPlacement:(NSString *)earnPlacement
                   item:(NSString *)item booster:(NSString *)booster balance:(double)balance
       additionalParams:(FGParams)additionalParams {
    fgLog(@"resource_source", [@{
        @"play_mode": playMode, @"level": @(level), @"item_type": itemType, @"name": name, @"amount": @(amount),
        @"earn_placement": earnPlacement, @"item": item, @"booster": booster, @"balance": @(balance),
    } mutableCopy], additionalParams);
}

+ (void)LogSpendResource:(NSString *)playMode level:(NSInteger)level itemType:(NSString *)itemType
                    name:(NSString *)name amount:(double)amount spendPlacement:(NSString *)spendPlacement
             spendReason:(NSString *)spendReason item:(NSString *)item booster:(NSString *)booster
                 balance:(double)balance additionalParams:(FGParams)additionalParams {
    fgLog(@"resource_sink", [@{
        @"play_mode": playMode, @"level": @(level), @"item_type": itemType, @"name": name, @"amount": @(amount),
        @"spend_placement": spendPlacement, @"spend_reason": spendReason, @"item": item, @"booster": booster, @"balance": @(balance),
    } mutableCopy], additionalParams);
}

+ (void)LogTutorial:(NSString *)actionName actionValue:(NSString *)actionValue
   additionalParams:(FGParams)additionalParams {
    fgLog(@"tut_action", [@{ @"name": actionName, @"value": actionValue } mutableCopy], additionalParams);
}

+ (void)LogLoadingStart:(NSString *)placement additionalParams:(FGParams)additionalParams {
    fgLog(@"loading_start", [@{ @"placement": placement } mutableCopy], additionalParams);
}

+ (void)LogLoadingEnd:(NSString *)placement isLoad:(BOOL)isLoad loadTime:(double)loadTime
     additionalParams:(FGParams)additionalParams {
    fgLog(@"loading_finish", [@{
        @"placement": placement, @"is_load": @(isLoad ? 1 : 0), @"value": @(loadTime),
    } mutableCopy], additionalParams);
}

+ (void)LogIAPShow:(NSString *)playMode level:(NSInteger)level location:(NSString *)location
              type:(NSString *)type productId:(NSString *)productId additionalParams:(FGParams)additionalParams {
    fgLog(@"iap_show", [@{
        @"play_mode": playMode, @"level": @(level), @"location": location, @"type": type, @"product_id": productId,
    } mutableCopy], additionalParams);
}

+ (void)LogIAPClick:(NSString *)playMode level:(NSInteger)level location:(NSString *)location
               type:(NSString *)type productId:(NSString *)productId additionalParams:(FGParams)additionalParams {
    fgLog(@"iap_click", [@{
        @"play_mode": playMode, @"level": @(level), @"location": location, @"type": type, @"product_id": productId,
    } mutableCopy], additionalParams);
}

// ── §4.2 Ads ─────────────────────────────────────────────────────────────────
+ (void)ShowInterstitial:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
              parameters:(FGParams)parameters onInterstitialComplete:(void (^)(void))onInterstitialComplete {
    if (!FGEvent::Ads::ShowInterstitial) return;
    std::function<void()> cb = nullptr; // nil block → empty (mirror Kotlin null)
    if (onInterstitialComplete) cb = [onInterstitialComplete]{ onInterstitialComplete(); };
    FGEvent::Ads::ShowInterstitial(placement, playMode, currentLevel, parameters, cb);
}

+ (void)ShowRewarded:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
          onRewarded:(void (^)(void))onRewarded parameters:(FGParams)parameters {
    if (!FGEvent::Ads::ShowRewarded) return;
    std::function<void()> cb = nullptr;
    if (onRewarded) cb = [onRewarded]{ onRewarded(); };
    FGEvent::Ads::ShowRewarded(placement, playMode, currentLevel, cb, parameters);
}

+ (BOOL)IsRewardedReady {
    return FGEvent::Ads::IsRewardedReady ? FGEvent::Ads::IsRewardedReady() : NO;
}

+ (void)LoadRewarded { FGEvent::Ads::LoadRewarded.invoke(); }

+ (void)ShowBanner:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
        parameters:(FGParams)parameters {
    if (FGEvent::Ads::ShowBanner) FGEvent::Ads::ShowBanner(placement, playMode, currentLevel, parameters);
}

+ (void)HideBanner { FGEvent::Ads::HideBanner.invoke(); }

+ (void)ShowAppOpen:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
         parameters:(FGParams)parameters {
    if (FGEvent::Ads::ShowAppOpen) FGEvent::Ads::ShowAppOpen(placement, playMode, currentLevel, parameters);
}

// ── §4.3 MREC ────────────────────────────────────────────────────────────────
+ (void)LoadMRec { FGEvent::Ads::LoadMRec.invoke(); }

+ (void)ShowMRec:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
      parameters:(FGParams)parameters {
    if (FGEvent::Ads::ShowMRec) FGEvent::Ads::ShowMRec(placement, playMode, currentLevel, parameters);
}

+ (void)ShowMRec:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
      adPosition:(NSInteger)adPosition parameters:(FGParams)parameters {
    if (FGEvent::Ads::ShowMRecPreset) FGEvent::Ads::ShowMRecPreset(placement, playMode, currentLevel, adPosition, parameters);
}

+ (void)ShowMRec:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
       screenPos:(CGPoint)screenPos parameters:(FGParams)parameters {
    if (FGEvent::Ads::ShowMRecAt) FGEvent::Ads::ShowMRecAt(placement, playMode, currentLevel, screenPos, parameters);
}

+ (void)UpdateMRecPosition:(CGPoint)screenPos {
    if (FGEvent::Ads::UpdateMRecPosition) FGEvent::Ads::UpdateMRecPosition(screenPos);
}

+ (void)UpdateMRecPositionPreset:(NSInteger)adPosition {
    if (FGEvent::Ads::UpdateMRecPositionPreset) FGEvent::Ads::UpdateMRecPositionPreset(adPosition);
}

+ (void)HideMRec { FGEvent::Ads::HideMRec.invoke(); }
+ (void)DestroyMRec { FGEvent::Ads::DestroyMRec.invoke(); }

+ (BOOL)IsMRecReady {
    return FGEvent::Ads::IsMRecReady ? FGEvent::Ads::IsMRecReady() : NO;
}

+ (CGPoint)GetMRecSize {
    CGFloat scale = UIScreen.mainScreen.scale; // ≈ DisplayMetrics.density Android (§7.7)
    return CGPointMake(300 * scale, 250 * scale);
}

+ (void)RemoveAds { FGEvent::Ads::RemoveAds.invoke(); }

// ── §4.4 RemoteConfig ────────────────────────────────────────────────────────
+ (NSInteger)GetRemoteConfigInt:(NSString *)key defaultValue:(NSInteger)defaultValue {
    return FGEvent::RemoteConfig::GetInt ? FGEvent::RemoteConfig::GetInt(key, defaultValue) : defaultValue;
}
+ (BOOL)GetRemoteConfigBool:(NSString *)key defaultValue:(BOOL)defaultValue {
    return FGEvent::RemoteConfig::GetBool ? FGEvent::RemoteConfig::GetBool(key, defaultValue) : defaultValue;
}
+ (NSString *)GetRemoteConfigString:(NSString *)key defaultValue:(NSString *)defaultValue {
    return FGEvent::RemoteConfig::GetString ? FGEvent::RemoteConfig::GetString(key, defaultValue) : defaultValue;
}
+ (BOOL)IsRemoteConfigReady {
    return FGEvent::RemoteConfig::IsRemoteConfigReady ? FGEvent::RemoteConfig::IsRemoteConfigReady() : NO;
}

// ── §4.5 IAP ─────────────────────────────────────────────────────────────────
+ (void)ActivateRemoveAds { FGEvent::Ads::RemoveAds.invoke(); } // dùng chung handler RemoveAds

+ (void)BuyProduct:(NSString *)productId location:(NSString *)location playMode:(NSString *)playMode
             level:(NSInteger)level result:(void (^)(BOOL, NSString *))result {
    if (FGEvent::IAP::BuyProduct) {
        FGEvent::IAP::BuyProduct(productId, location, playMode, level,
                                 [result](BOOL success, NSString *tx){ result(success, tx); });
    } else {
        result(NO, @"iap_disabled"); // bus null (IAP tắt/chưa init)
    }
}

+ (void)RestorePurchases:(void (^)(BOOL))callback {
    if (FGEvent::IAP::RestorePurchase) {
        FGEvent::IAP::RestorePurchase([callback](BOOL success){ if (callback) callback(success); });
    } else if (callback) {
        callback(NO);
    }
}

+ (BOOL)ProductIsPurchased:(NSString *)productId {
    return FGEvent::IAP::IsPurchased ? FGEvent::IAP::IsPurchased(productId) : NO;
}
+ (NSInteger)GetProductPurchaseCount:(NSString *)productId {
    return FGEvent::IAP::GetPurchaseCount ? FGEvent::IAP::GetPurchaseCount(productId) : 0;
}
+ (NSString *)GetProductTitle:(NSString *)productId {
    return FGEvent::IAP::GetProductTitle ? FGEvent::IAP::GetProductTitle(productId) : @"";
}
+ (NSString *)GetProductPrice:(NSString *)productId {
    return FGEvent::IAP::GetProductPrice ? FGEvent::IAP::GetProductPrice(productId) : @"";
}

// ── §4.6 Deeplink ────────────────────────────────────────────────────────────
+ (NSArray *)GetDeeplinkResult {
    if (!FGEvent::Deeplink::OnRequestDeepLink) return nil;
    auto r = FGEvent::Deeplink::OnRequestDeepLink();
    if (!r.has_value()) return nil;                 // quirk 2 guard đã áp ở manager
    return @[r->first, @(r->second)];               // Pair<String,Int> → @[NSString, NSNumber]
}

+ (void)handleOpenURL:(NSURL *)url { [FGDeeplinkManager handleURL:url]; }

#pragma mark - QA

+ (void)showMediationDebugger {
    [FGMainThreadDispatcher enqueue:^{
        @try {
            [[ALSdk shared] showMediationDebugger];
            NSLog(@"[FGSDK] showMediationDebugger: opened");
        } @catch (NSException *e) {
            // MAX chưa init / chưa nhúng AppLovin → không được để crash game.
            NSLog(@"[FGSDK] showMediationDebugger lỗi: %@", e.reason);
        }
    }];
}

@end
