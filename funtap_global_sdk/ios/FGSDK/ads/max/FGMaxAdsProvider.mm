//
//  FGMaxAdsProvider.mm — mirror KA/ads/max/FGMaxAdsProvider.kt (spec §7.4-§7.7, §8, §5.2/§5.3).
//
//  Adaptation iOS (README): Activity/Context → không cần (MAInterstitialAd/MAAppOpenAd tự lấy top VC);
//  view root Android (android.R.id.content) → keyWindow; Gravity/translation → frame (point ≈ dp).
//  Delegate anonymous Kotlin → FGMaxDelegateProxy (block-based) giữ 1:1 từng callback.
//
#import "FGMaxAdsProvider.h"
#import "FGMaxError.h"
#import "FGMaxRetry.h"
#import "../FGAds.h"
#import "../FGAdEventLogger.h"
#import "../FGAdsOrchestrator.h"
#import "../OpenAppAction.h"
#import "../../consent/FGConsentManager.h"
#import "../../event/FGEvent.h"
#import "../../event/FGPublicEvent.h"
#import "../../event/FGAdsInfo.h"
#import "../../init/FGInitStateMachine.h"
#import "../../util/FGConstValue.h"
#import "../../util/FGInternalData.h"
#import "../../util/FGInternetChecker.h"
#import "../../util/FGMainThreadDispatcher.h"
#import "../../util/FGUtils.h"
#import "../../util/FGViewControllerTracker.h"
#import "../../config/FGConfigController.h"
#import <AppLovinSDK/AppLovinSDK.h>
#import <QuartzCore/QuartzCore.h> // CACurrentMediaTime (≈ System.nanoTime — monotonic)
#include <atomic>
#include <cmath>

static NSString *const TAG = @"FGMax";

// ── Show context + timing (spec §8) — mirror inner class Ctx Kotlin ──────────

struct FGMaxShowCtx {
    NSString *playMode = @"";
    double level = 0.0;
    NSString *location = @"";
    FGParams params = nil;
    double showStart = 0.0; // giây monotonic (Kotlin: nanos)

    void set(NSString *pm, double lv, NSString *loc, FGParams p) {
        playMode = pm; level = lv; location = loc; params = p;
        showStart = CACurrentMediaTime();
    }
};

/** Kotlin secs(startNanos) — start==0 → 0 (chưa đo). */
static double FGMaxSecs(double start) {
    return start == 0.0 ? 0.0 : CACurrentMediaTime() - start;
}

/** XParams cho ad_revenue_sdk = play_mode/level + custom show params (mirror xParams Kotlin). */
static FGParams FGMaxXParams(const FGMaxShowCtx &c) {
    NSMutableDictionary<NSString *, id> *m = [NSMutableDictionary dictionary];
    m[@"play_mode"] = c.playMode;
    m[@"level"] = @(c.level);
    if (c.params != nil) [m addEntriesFromDictionary:c.params];
    return m;
}

// ── FGPublicEvent (spec §5.2) — build FGAdsInfo từ MAAd; errInfo cho load/display fail ──

static FGAdsInfo *FGMaxToInfo(MAAd *ad, NSString *format, NSString *placement) {
    return [[FGAdsInfo alloc] initWithAdID:ad.adUnitIdentifier
                                  AdFormat:format
                               NetworkName:ad.networkName
                          NetworkPlacement:ad.networkPlacement
                                 Placement:placement
                        CreativeIdentifier:ad.creativeIdentifier
                                   Revenue:ad.revenue
                          RevenuePrecision:ad.revenuePrecision
                             // iOS: MAAd.requestLatency = GIÂY (NSTimeInterval) → millis (Kotlin requestLatencyMillis)
                             LatencyMillis:(long long)llround(ad.requestLatency * 1000.0)
                                   DspName:ad.DSPName];
}

static FGAdsInfo *FGMaxErrInfo(NSString *unitId, NSString *format, NSString *placement) {
    return [[FGAdsInfo alloc] initWithAdID:unitId
                                  AdFormat:format
                               NetworkName:nil
                          NetworkPlacement:nil
                                 Placement:placement
                        CreativeIdentifier:nil
                                   Revenue:0
                          RevenuePrecision:nil
                             LatencyMillis:0
                                   DspName:nil];
}

// ── FGAdEventLogger shortcuts (mirror logRequest/logDisplay/logCompleted Kotlin) ─────────
// adPlatform = applovin_max_sdk (spec §8).

static void FGMaxLogRequest(const FGMaxShowCtx &c, NSString *format, BOOL success, NSString *reason,
                            double value, NSInteger requestCount, NSString *adNetwork, NSString *unitId) {
    [FGAdEventLogger adRequest:c.playMode level:c.level platform:FGConstValue.applovin_max_sdk
                     adNetwork:adNetwork format:format location:c.location
                       success:success reason:reason value:value requestCount:requestCount unitId:unitId];
}

static void FGMaxLogDisplay(const FGMaxShowCtx &c, NSString *format, BOOL success, NSString *reason,
                            double value, NSString *adNetwork) {
    [FGAdEventLogger adDisplay:c.playMode level:c.level platform:FGConstValue.applovin_max_sdk
                     adNetwork:adNetwork format:format location:c.location
                       success:success reason:reason value:value];
}

static void FGMaxLogCompleted(const FGMaxShowCtx &c, NSString *format, BOOL success, double value,
                              NSString *adNetwork) {
    [FGAdEventLogger adCompleted:c.playMode level:c.level platform:FGConstValue.applovin_max_sdk
                       adNetwork:adNetwork format:format location:c.location
                         success:success value:value];
}

/** spec §8 — impression + ad_revenue_sdk + logAdRevenue (+ af_*_displayed cho inter/reward) — mirror onRevenue Kotlin. */
static void FGMaxOnRevenue(MAAd *ad, NSString *format, const FGMaxShowCtx &c, BOOL isInterstitial,
                           void (^_Nullable afSend)(void)) {
    NSString *network = ad.networkName ?: @"unknown";
    double revenue = ad.revenue;
    NSString *unit = ad.adUnitIdentifier ?: @"";
    NSMutableDictionary<NSString *, id> *dict =
        [FGAdEventLogger buildImpression:format
                                 isAdmob:NO
                          isInterstitial:isInterstitial
                               adNetwork:network
                                 revenue:revenue
                                currency:@"USD"
                              adUnitName:(isInterstitial ? unit : nil)];
    [FGAdEventLogger adImpression:dict];
    [FGAdEventLogger adRevenueSdk:dict location:c.location xParams:FGMaxXParams(c)];
    if (afSend) afSend();
    [FGAdEventLogger logAdRevenue:network isAdmob:NO currency:@"USD" revenue:revenue format:format adUnit:unit];
}

// ── FGMaxDelegateProxy — thay anonymous listener Kotlin (block per-callback, 1:1) ─────────
// MAAdViewAdDelegate/MARewardedAdDelegate đều extend MAAdDelegate → 1 proxy dùng cho mọi format.

@interface FGMaxDelegateProxy : NSObject <MAAdViewAdDelegate, MARewardedAdDelegate, MAAdRevenueDelegate>
@property (nonatomic, copy, nullable) void (^onLoaded)(MAAd *ad);
@property (nonatomic, copy, nullable) void (^onLoadFailed)(NSString *adUnitIdentifier, MAError *error);
@property (nonatomic, copy, nullable) void (^onDisplayed)(MAAd *ad);
@property (nonatomic, copy, nullable) void (^onHidden)(MAAd *ad);
@property (nonatomic, copy, nullable) void (^onClicked)(MAAd *ad);
@property (nonatomic, copy, nullable) void (^onDisplayFailed)(MAAd *ad, MAError *error);
@property (nonatomic, copy, nullable) void (^onRevenuePaid)(MAAd *ad);
@property (nonatomic, copy, nullable) void (^onUserRewarded)(MAAd *ad, MAReward *reward);
@end

@implementation FGMaxDelegateProxy
- (void)didLoadAd:(MAAd *)ad { if (self.onLoaded) self.onLoaded(ad); }
- (void)didFailToLoadAdForAdUnitIdentifier:(NSString *)adUnitIdentifier withError:(MAError *)error {
    if (self.onLoadFailed) self.onLoadFailed(adUnitIdentifier, error);
}
- (void)didDisplayAd:(MAAd *)ad { if (self.onDisplayed) self.onDisplayed(ad); }
- (void)didHideAd:(MAAd *)ad { if (self.onHidden) self.onHidden(ad); }
- (void)didClickAd:(MAAd *)ad { if (self.onClicked) self.onClicked(ad); }
- (void)didFailToDisplayAd:(MAAd *)ad withError:(MAError *)error {
    if (self.onDisplayFailed) self.onDisplayFailed(ad, error);
}
// Kotlin onAdExpanded/onAdCollapsed rỗng — mirror no-op.
- (void)didExpandAd:(MAAd *)ad {}
- (void)didCollapseAd:(MAAd *)ad {}
- (void)didPayRevenueForAd:(MAAd *)ad { if (self.onRevenuePaid) self.onRevenuePaid(ad); }
- (void)didRewardUserForAd:(MAAd *)ad withReward:(MAReward *)reward {
    if (self.onUserRewarded) self.onUserRewarded(ad, reward);
}
@end

// ── Provider ─────────────────────────────────────────────────────────────────

@interface FGMaxAdsProvider ()
- (FGAdsAdUnitConfig *_Nullable)adUnits;
- (void)onSdkInitialized:(NSString *_Nullable)country;
- (void)registerCallbacks;
- (void)autoLoadAd;
- (void)createInterstitial;
- (void)createRewarded;
- (void)createAppOpen;
- (void)reloadMRec;
- (BOOL)prepareShowMRec;
- (void)positionCentered:(MAAdView *)v;
- (void)positionAt:(MAAdView *)v screenPos:(CGPoint)screenPos;
- (void)positionPreset:(MAAdView *)v adPosition:(NSInteger)adPosition;
- (void)mrecShown:(NSString *)placement;
@end

@implementation FGMaxAdsProvider {
    FGSignal _onInitialized;
    FGSignal1<NSString *> _onInitializationFailed;

    FGCustomAdsMediationConfig *_config;
    FGAdsOrchestrator *_orchestrator; // giữ mirror Kotlin lateinit (không dùng lại sau initialize)

    std::atomic<bool> _isInitialized; // Kotlin @Volatile

    NSString *_countryCode; // spec §7.4 — bất biến sau init, AppOpen routing (Custom)

    BOOL _isBannerAutoShow; // remote IsBannerAutoShow (default false)
    BOOL _showAOAfterAds;   // remote showAOAfterAds (default false)

    // Retry counters (spec §7.6)
    NSInteger _interRetryCount;
    NSInteger _rewardRetryCount;
    NSInteger _bannerRetryCount;
    NSInteger _appOpenRetryCount;
    NSInteger _mrecRetryCount;

    // Request counters (spec §7.5 — Banner/MRec = 0)
    NSInteger _interRequestCount;
    NSInteger _rewardRequestCount;
    NSInteger _appOpenRequestCount;

    // Interstitial
    MAInterstitialAd *_interstitialAd;
    FGMaxDelegateProxy *_interDelegate;
    void (^_onInterstitialComplete)(void); // ⚠️ single-slot (quirk §16-2)

    // Rewarded
    MARewardedAd *_rewardedAd;
    FGMaxDelegateProxy *_rewardDelegate;
    void (^_onRewardComplete)(void);
    BOOL _rewardGranted;

    // Banner
    MAAdView *_bannerView;
    FGMaxDelegateProxy *_bannerDelegate;
    BOOL _isBannerCreated;
    BOOL _isBannerLoaded;
    BOOL _isBannerShowing;

    // AppOpen
    MAAppOpenAd *_appOpenAd;
    FGMaxDelegateProxy *_appOpenDelegate;

    // MREC
    MAAdView *_mrecView;
    FGMaxDelegateProxy *_mrecDelegate;
    BOOL _mrecCreated;

    // Show context + load timing (spec §8)
    FGMaxShowCtx _interCtx;
    FGMaxShowCtx _rewardCtx;
    FGMaxShowCtx _bannerCtx;
    FGMaxShowCtx _appOpenCtx;
    FGMaxShowCtx _mrecCtx;
    double _interLoadStart;
    double _rewardLoadStart;
    double _bannerLoadStart;
    double _appOpenLoadStart;
    double _mrecLoadStart;
}

- (instancetype)initWithConfig:(FGCustomAdsMediationConfig *)config {
    if ((self = [super init])) {
        _config = config;
        _isInitialized = false;
    }
    return self;
}

- (FGSignal &)onInitialized { return _onInitialized; }
- (FGSignal1<NSString *> &)onInitializationFailed { return _onInitializationFailed; }

- (NSString *)liveCountryCode { return _countryCode; }

// Kotlin `adsConfig`/`adUnits` computed props.
- (FGAdsAdUnitConfig *)adUnits { return _config.primaryAdUnitConfig; }

// ── Init (spec §7.4) ───────────────────────────────────────────────────────

- (void)initialize:(FGAdsOrchestrator *)orchestrator {
    _orchestrator = orchestrator;
    __weak FGMaxAdsProvider *weakSelf = self;
    [FGMainThreadDispatcher enqueue:^{
        @try { // ≈ Kotlin catch Throwable
            // 1. OnSDKReady += AutoLoadAd (OnSdkInitializedEvent thay bằng completion bên dưới).
            FGEvent::InitEvent::OnSDKReady.add([weakSelf] { [weakSelf autoLoadAd]; });

            // Kotlin guard appContext null — iOS không cần Context (adaptation README).
            NSString *key = self->_config.max_sdk_key;
            if (key.length == 0) {
                self->_onInitializationFailed.invoke(@"max_sdk_key null/empty");
                return;
            }

            // 2. ApplyPrivacyConsent TRƯỚC init.
            [self applyPrivacyConsent];

            // 3. InitializeSdk.
            ALSdkInitializationConfiguration *cfg = [ALSdkInitializationConfiguration
                configurationWithSdkKey:key
                            builderBlock:^(ALSdkInitializationConfigurationBuilder *builder) {
                                builder.mediationProvider = ALMediationProviderMAX;
                                NSArray<NSString *> *devices = [FGConfigController mainConfig].listDevice;
                                if (devices.count > 0) {
                                    NSPredicate *uuidPredicate = [NSPredicate predicateWithFormat:@"SELF MATCHES[c] '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'"];
                                    NSArray<NSString *> *validUuids = [devices filteredArrayUsingPredicate:uuidPredicate];
                                    builder.testDeviceAdvertisingIdentifiers = validUuids;
                                    NSLog(@"[%@] Configured %lu test devices in ALSdk (out of %lu)", TAG, (unsigned long)validUuids.count, (unsigned long)devices.count);
                                }
                            }];
            [[ALSdk shared] initializeWithConfiguration:cfg
                                      completionHandler:^(ALSdkConfiguration *sdkConfig) {
                [FGMainThreadDispatcher enqueue:^{ [weakSelf onSdkInitialized:sdkConfig.countryCode]; }];
            }];
        } @catch (NSException *e) {
            NSLog(@"[%@] MAX init exception: %@", TAG, e);
            self->_onInitializationFailed.invoke(e.reason ?: @"init exception");
        }
    }];
}

/** spec §7.4 step 2 — ApplyPrivacyConsent (iOS ALPrivacySettings không nhận Context). */
- (void)applyPrivacyConsent {
    @try {
        [ALPrivacySettings setHasUserConsent:[FGConsentManager HasConsentForAds]];
        [ALPrivacySettings setDoNotSell:NO];
    } @catch (NSException *e) {
        NSLog(@"[%@] applyPrivacyConsent fail: %@", TAG, e);
    }
}

/** spec §7.4 step 4 — OnSdkInitialized. */
- (void)onSdkInitialized:(NSString *)country {
    _isInitialized = true;
    _countryCode = [country copy];
    if (FGEvent::RemoteConfig::IsRemoteConfigReady && FGEvent::RemoteConfig::IsRemoteConfigReady()) {
        _isBannerAutoShow = FGEvent::RemoteConfig::GetBool ? FGEvent::RemoteConfig::GetBool(@"IsBannerAutoShow", NO) : NO;
        _showAOAfterAds = FGEvent::RemoteConfig::GetBool ? FGEvent::RemoteConfig::GetBool(@"showAOAfterAds", NO) : NO;
    }
    FGEvent::InitEvent::ApplovinInitComplete.invoke();
    @try {
        [self registerCallbacks];
    } @catch (NSException *e) {
        NSLog(@"[%@] registerCallbacks error: %@", TAG, e);
    }
    _onInitialized.invoke();
    // MAX không có isBackfill (chỉ AdMob) → SetReady vô điều kiện như Kotlin.
    [FGInitStateMachine SetReady:FGInitStateAds];
    NSLog(@"[%@] MAX initialized (country=%@, bannerAutoShow=%d, aoAfterAds=%d)",
          TAG, country, _isBannerAutoShow, _showAOAfterAds);
}

/** spec §7.4 step 5 — luôn đăng ký Rewarded; IsRemoveAds → dừng (không đăng ký Inter/Banner/AppOpen/MRec). */
- (void)registerCallbacks {
    [self createRewarded];
    if (FGInternalData.IsRemoveAds) return;
    [self createInterstitial];
    [self createAppOpen];
    // Banner/MRec view tạo lúc load (create-once).
}

/** spec §7.4 step 6 — AutoLoadAd (khi OnSDKReady). */
- (void)autoLoadAd {
    if (!FGInternetChecker.isConnected) return;
    [self loadRewarded]; // rewarded autoload trước (chạy cả khi RemoveAds)
    if (FGInternalData.IsRemoveAds) return;
    FGAdsAdUnitConfig *u = [self adUnits];
    if (u == nil) return;
    if (u.Banner.IsAutoLoad) [self loadBanner];
    if (u.Interstitial.IsAutoLoad) [self loadInterstitial];
    if (u.AppOpen.IsAutoLoad) [self loadAppOpen];
    if (u.MRec.IsAutoLoad) [self loadMRec];
}

// ── Interstitial (spec §7.5) ────────────────────────────────────────────────

- (void)createInterstitial {
    if (![self adUnits].Interstitial.EnableAds) return;
    NSString *unitId = [self adUnits].Interstitial.AdUnitID;
    if (unitId == nil || unitId.length == 0) return;
    // Kotlin guard activity() — iOS MAInterstitialAd không cần Activity (tự lấy top VC khi show).
    MAInterstitialAd *ad = [[MAInterstitialAd alloc] initWithAdUnitIdentifier:unitId];
    __weak FGMaxAdsProvider *weakSelf = self;
    FGMaxDelegateProxy *proxy = [FGMaxDelegateProxy new];
    proxy.onLoaded = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        s->_interRetryCount = 0;
        FGMaxLogRequest(s->_interCtx, FGConstValue.Interstitial, YES, @"", FGMaxSecs(s->_interLoadStart),
                        s->_interRequestCount, a.networkName ?: @"unknown", a.adUnitIdentifier ?: unitId);
        FGPublicEvent::Interstitial.Loaded.invoke(FGMaxToInfo(a, FGConstValue.Interstitial, s->_interCtx.location));
    };
    proxy.onLoadFailed = ^(NSString *adUnitIdentifier, MAError *error) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        NSLog(@"[%@] Interstitial onLoadFailed: unitId=%@, code=%ld, message=%@", TAG, adUnitIdentifier, (long)error.code, error.message);
        FGMaxLogRequest(s->_interCtx, FGConstValue.Interstitial, NO, [FGMaxError classifyLoad:error.code],
                        FGMaxSecs(s->_interLoadStart), s->_interRequestCount, @"unknown", unitId);
        FGPublicEvent::Interstitial.FailedToLoad.invoke(FGMaxErrInfo(unitId, FGConstValue.Interstitial, s->_interCtx.location));
        [FGMaxRetry retryLoadAd:s->_interRetryCount format:@"interstitial" loadAction:^{ [weakSelf loadInterstitial]; }];
        s->_interRetryCount++; // ⚠️ retry TRƯỚC, count++ SAU (spec §7.6)
    };
    proxy.onDisplayed = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxLogDisplay(s->_interCtx, FGConstValue.Interstitial, YES, @"", FGMaxSecs(s->_interCtx.showStart),
                        a.networkName ?: @"unknown");
        FGPublicEvent::Interstitial.Shown.invoke(FGMaxToInfo(a, FGConstValue.Interstitial, s->_interCtx.location));
    };
    proxy.onHidden = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxLogCompleted(s->_interCtx, FGConstValue.Interstitial, YES, FGMaxSecs(s->_interCtx.showStart),
                          a.networkName ?: @"unknown");
        FGPublicEvent::Interstitial.Closed.invoke(FGMaxToInfo(a, FGConstValue.Interstitial, s->_interCtx.location));
        FGEvent::Ads::ResetAOAction.invoke();
        void (^cb)(void) = s->_onInterstitialComplete;
        s->_onInterstitialComplete = nil; // ⚠️ invoke + null (quirk §16-2)
        if (cb) cb();
        [s loadInterstitial]; // preload
    };
    proxy.onClicked = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        [FGAdEventLogger adClick:FGConstValue.Interstitial platform:FGConstValue.applovin_max_sdk adNetwork:a.networkName ?: @"unknown"];
        FGPublicEvent::Interstitial.Clicked.invoke(FGMaxToInfo(a, FGConstValue.Interstitial, s->_interCtx.location));
    };
    proxy.onDisplayFailed = ^(MAAd *a, MAError *error) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxLogDisplay(s->_interCtx, FGConstValue.Interstitial, NO, [FGMaxError classifyDisplay:error.code],
                        FGMaxSecs(s->_interCtx.showStart), a.networkName ?: @"unknown");
        FGPublicEvent::Interstitial.FailedToShow.invoke(FGMaxToInfo(a, FGConstValue.Interstitial, s->_interCtx.location));
        void (^cb)(void) = s->_onInterstitialComplete;
        s->_onInterstitialComplete = nil;
        if (cb) cb();
        [s loadInterstitial];
    };
    proxy.onRevenuePaid = ^(MAAd *revAd) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxOnRevenue(revAd, FGConstValue.Interstitial, s->_interCtx, YES, ^{ [FGAdEventLogger afIntersDisplayed]; });
    };
    ad.delegate = proxy;
    ad.revenueDelegate = proxy;
    _interDelegate = proxy; // giữ strong (MAX delegate là weak ref)
    _interstitialAd = ad;
}

- (void)loadInterstitial {
    FGPlatformAdUnit *u = [self adUnits].Interstitial;
    if (u == nil) return;
    if (FGInternalData.IsRemoveAds || !_isInitialized || !u.EnableAds || [self isInterstitialReady]) return;
    if (_interstitialAd == nil) [self createInterstitial];
    _interRequestCount++;
    _interLoadStart = CACurrentMediaTime();
    [_interstitialAd loadAd];
}

- (void)showInterstitial:(NSString *)placement
                playMode:(NSString *)playMode
            currentLevel:(double)currentLevel
                  params:(FGParams)params
    onInterstitialClosed:(void (^)(void))onInterstitialClosed {
    FGPublicEvent::Interstitial.Request.invoke(placement);
    if (FGInternalData.IsRemoveAds || !_isInitialized) {
        if (onInterstitialClosed) onInterstitialClosed();
        return;
    }
    if (![self isInterstitialReady]) {
        if (_interRetryCount >= FGMaxRetry.MaxRetryAttempts) { _interRetryCount = 0; [self loadInterstitial]; }
        if (onInterstitialClosed) onInterstitialClosed();
        return;
    }
    FGAds.openAppAction = OpenAppActionAds;
    _onInterstitialComplete = [onInterstitialClosed copy]; // ⚠️ single-slot (quirk §16-2)
    _interCtx.set(playMode, currentLevel, placement, params);
    [_interstitialAd showAd];
}

- (BOOL)isInterstitialReady {
    return _interstitialAd != nil && [_interstitialAd isReady];
}

// ── Rewarded (spec §7.5 — không guard IsRemoveAds) ──────────────────────────

- (void)createRewarded {
    if (![self adUnits].Rewarded.EnableAds) return;
    NSString *unitId = [self adUnits].Rewarded.AdUnitID;
    if (unitId == nil || unitId.length == 0) return;
    MARewardedAd *ad = [MARewardedAd sharedWithAdUnitIdentifier:unitId];
    __weak FGMaxAdsProvider *weakSelf = self;
    FGMaxDelegateProxy *proxy = [FGMaxDelegateProxy new];
    proxy.onLoaded = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        s->_rewardRetryCount = 0;
        FGMaxLogRequest(s->_rewardCtx, FGConstValue.Reward, YES, @"", FGMaxSecs(s->_rewardLoadStart),
                        s->_rewardRequestCount, a.networkName ?: @"unknown", a.adUnitIdentifier ?: unitId);
        FGPublicEvent::Rewarded.Loaded.invoke(FGMaxToInfo(a, FGConstValue.Reward, s->_rewardCtx.location));
    };
    proxy.onLoadFailed = ^(NSString *adUnitIdentifier, MAError *error) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        NSLog(@"[%@] Rewarded onLoadFailed: unitId=%@, code=%ld, message=%@", TAG, adUnitIdentifier, (long)error.code, error.message);
        FGMaxLogRequest(s->_rewardCtx, FGConstValue.Reward, NO, [FGMaxError classifyLoad:error.code],
                        FGMaxSecs(s->_rewardLoadStart), s->_rewardRequestCount, @"unknown", unitId);
        FGPublicEvent::Rewarded.FailedToLoad.invoke(FGMaxErrInfo(unitId, FGConstValue.Reward, s->_rewardCtx.location));
        [FGMaxRetry retryLoadAd:s->_rewardRetryCount format:@"reward" loadAction:^{ [weakSelf loadRewarded]; }];
        s->_rewardRetryCount++;
    };
    proxy.onDisplayed = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxLogDisplay(s->_rewardCtx, FGConstValue.Reward, YES, @"", FGMaxSecs(s->_rewardCtx.showStart),
                        a.networkName ?: @"unknown");
        FGPublicEvent::Rewarded.Shown.invoke(FGMaxToInfo(a, FGConstValue.Reward, s->_rewardCtx.location));
    };
    proxy.onHidden = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        // spec §8 — Reward MAX success = _rewardGranted.
        FGMaxLogCompleted(s->_rewardCtx, FGConstValue.Reward, s->_rewardGranted, FGMaxSecs(s->_rewardCtx.showStart),
                          a.networkName ?: @"unknown");
        FGPublicEvent::Rewarded.Closed.invoke(FGMaxToInfo(a, FGConstValue.Reward, s->_rewardCtx.location));
        if (s->_onRewardComplete != nil) {
            // chưa nhận reward → user đóng sớm.
            s->_onRewardComplete = nil;
            // OnRewardFailed("User closed ad before reward") — reward-failed game callback để future (không có trong §5.2).
        }
        s->_rewardGranted = NO;
        [s loadRewarded];
    };
    proxy.onClicked = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        [FGAdEventLogger adClick:FGConstValue.Reward platform:FGConstValue.applovin_max_sdk adNetwork:a.networkName ?: @"unknown"];
        FGPublicEvent::Rewarded.Clicked.invoke(FGMaxToInfo(a, FGConstValue.Reward, s->_rewardCtx.location));
    };
    proxy.onDisplayFailed = ^(MAAd *a, MAError *error) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxLogDisplay(s->_rewardCtx, FGConstValue.Reward, NO, [FGMaxError classifyDisplay:error.code],
                        FGMaxSecs(s->_rewardCtx.showStart), a.networkName ?: @"unknown");
        FGPublicEvent::Rewarded.FailedToShow.invoke(FGMaxToInfo(a, FGConstValue.Reward, s->_rewardCtx.location));
        s->_onRewardComplete = nil;
        s->_rewardGranted = NO;
        [s loadRewarded];
    };
    proxy.onUserRewarded = ^(MAAd *a, MAReward *reward) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        // spec §7.5 — reward cấp ở đây, TRƯỚC Hidden (quirk §16-5).
        s->_rewardGranted = YES;
        FGPublicEvent::Rewarded.Completed.invoke(FGMaxToInfo(a, FGConstValue.Reward, s->_rewardCtx.location));
        void (^cb)(void) = s->_onRewardComplete;
        s->_onRewardComplete = nil;
        if (cb) cb();
    };
    proxy.onRevenuePaid = ^(MAAd *revAd) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxOnRevenue(revAd, FGConstValue.Reward, s->_rewardCtx, NO, ^{ [FGAdEventLogger afRewardedDisplayed]; });
    };
    ad.delegate = proxy;
    ad.revenueDelegate = proxy;
    _rewardDelegate = proxy;
    _rewardedAd = ad;
}

- (void)loadRewarded {
    FGPlatformAdUnit *u = [self adUnits].Rewarded;
    if (u == nil) return;
    if (!_isInitialized || !u.EnableAds || [self isRewardedReady]) return;
    if (_rewardedAd == nil) [self createRewarded];
    _rewardRequestCount++;
    _rewardLoadStart = CACurrentMediaTime();
    [_rewardedAd loadAd];
}

- (void)showRewarded:(NSString *)placement
            playMode:(NSString *)playMode
        currentLevel:(double)currentLevel
          onRewarded:(void (^)(void))onRewarded
              params:(FGParams)params {
    FGPublicEvent::Rewarded.Request.invoke(placement);
    if (!_isInitialized) return;
    if (![self isRewardedReady]) {
        if (_rewardRetryCount >= FGMaxRetry.MaxRetryAttempts) { _rewardRetryCount = 0; [self loadRewarded]; }
        // OnRewardFailed("Ad not ready") — không có trong §5.2, để future.
        return;
    }
    _rewardGranted = NO;
    _onRewardComplete = [onRewarded copy];
    _rewardCtx.set(playMode, currentLevel, placement, params);
    [_rewardedAd showAd];
}

- (BOOL)isRewardedReady {
    return _rewardedAd != nil && [_rewardedAd isReady];
}

// ── Banner (spec §7.5) ───────────────────────────────────────────────────────

- (void)loadBanner {
    FGPlatformAdUnit *u = [self adUnits].Banner;
    if (u == nil) return;
    if (FGInternalData.IsRemoveAds || !_isInitialized || !u.EnableAds) return;
    NSString *unitId = u.AdUnitID;
    if (unitId == nil) return;
    __weak FGMaxAdsProvider *weakSelf = self;
    [FGMainThreadDispatcher enqueue:^{
        UIWindow *win = [FGViewControllerTracker keyWindow];
        if (win == nil) return; // ≈ Kotlin activity/root null → bỏ
        // ⚠️ create-once flag set nhưng KHÔNG gate re-create (quirk §16-3) → mỗi LoadBanner tạo mới.
        if (self->_bannerView != nil) [self->_bannerView removeFromSuperview];
        MAAdView *view = [[MAAdView alloc] initWithAdUnitIdentifier:unitId adFormat:MAAdFormat.banner];
        // Mirror Unity CreateBanner BottomCenter: full-width, cao 50pt (chuẩn banner phone;
        // KHÔNG dùng adaptive — Kotlin cũng fix 50dp; đổi sang MAAdFormat.banner.adaptiveSize nếu cần sau).
        CGRect b = win.bounds;
        CGFloat h = 50;
        view.frame = CGRectMake(0, b.size.height - h, b.size.width, h);
        // Thay Gravity.BOTTOM Android: giữ đáy + full-width khi xoay màn hình.
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
        view.hidden = YES; // ≈ View.GONE
        FGMaxDelegateProxy *proxy = [FGMaxDelegateProxy new];
        proxy.onLoaded = ^(MAAd *a) {
            FGMaxAdsProvider *s = weakSelf; if (!s) return;
            s->_isBannerLoaded = YES;
            if (s->_isBannerAutoShow || s->_isBannerShowing) {
                view.hidden = NO;
                s->_isBannerShowing = YES;
                UIWindow *curWin = [FGViewControllerTracker keyWindow];
                if (view.superview != curWin && curWin != nil) {
                    [view removeFromSuperview];
                    [curWin addSubview:view];
                }
                if (view.superview) [view.superview bringSubviewToFront:view];
            }
            // Banner request_count = 0 (spec §8).
            FGMaxLogRequest(s->_bannerCtx, FGConstValue.Banner, YES, @"", FGMaxSecs(s->_bannerLoadStart),
                            0, a.networkName ?: @"unknown", unitId);
            FGPublicEvent::Banner.Loaded.invoke(FGMaxToInfo(a, FGConstValue.Banner, s->_bannerCtx.location));
        };
        proxy.onLoadFailed = ^(NSString *adUnitIdentifier, MAError *error) {
            FGMaxAdsProvider *s = weakSelf; if (!s) return;
            s->_isBannerLoaded = NO;
            // Keep _isBannerShowing = YES so when retry/reload succeeds it unhides automatically
            FGMaxLogRequest(s->_bannerCtx, FGConstValue.Banner, NO, [FGMaxError classifyLoad:error.code],
                            FGMaxSecs(s->_bannerLoadStart), 0, @"unknown", unitId);
            FGPublicEvent::Banner.FailedToLoad.invoke(FGMaxErrInfo(unitId, FGConstValue.Banner, s->_bannerCtx.location));
            [FGMaxRetry retryLoadAd:s->_bannerRetryCount format:@"banner" loadAction:^{ [weakSelf loadBanner]; }];
            s->_bannerRetryCount++;
        };
        // onDisplayed/onHidden/onDisplayFailed: Kotlin rỗng cho banner — mirror (không set block).
        proxy.onClicked = ^(MAAd *a) {
            FGMaxAdsProvider *s = weakSelf; if (!s) return;
            [FGAdEventLogger adClick:FGConstValue.Banner platform:FGConstValue.applovin_max_sdk adNetwork:a.networkName ?: @"unknown"];
            FGPublicEvent::Banner.Clicked.invoke(FGMaxToInfo(a, FGConstValue.Banner, s->_bannerCtx.location));
        };
        proxy.onRevenuePaid = ^(MAAd *revAd) {
            FGMaxAdsProvider *s = weakSelf; if (!s) return;
            FGMaxOnRevenue(revAd, FGConstValue.Banner, s->_bannerCtx, NO, nil);
            FGPublicEvent::Banner.RevenuePaid.invoke(FGMaxToInfo(revAd, FGConstValue.Banner, s->_bannerCtx.location));
        };
        view.delegate = proxy;
        view.revenueDelegate = proxy;
        [win addSubview:view];
        self->_bannerDelegate = proxy;
        self->_bannerView = view;
        self->_isBannerCreated = YES;
        self->_bannerLoadStart = CACurrentMediaTime();
        [view loadAd];
    }];
}

- (void)showBanner:(NSString *)placement
          playMode:(NSString *)playMode
      currentLevel:(double)currentLevel
            params:(FGParams)params {
    FGPublicEvent::Banner.Request.invoke(placement);
    if (FGInternalData.IsRemoveAds || !_isInitialized) return;
    _bannerCtx.set(playMode, currentLevel, placement, params);
    [FGMainThreadDispatcher enqueue:^{
        self->_isBannerShowing = YES;
        UIWindow *win = [FGViewControllerTracker keyWindow];
        if (win == nil) return;

        MAAdView *v = self->_bannerView;
        if (v == nil) { [self loadBanner]; return; }

        if (v.superview != win) {
            [v removeFromSuperview];
            [win addSubview:v];
        }

        CGRect b = win.bounds;
        CGFloat h = 50;
        v.frame = CGRectMake(0, b.size.height - h, b.size.width, h);

        v.hidden = NO;
        [win bringSubviewToFront:v];
        [v startAutoRefresh];
        [v loadAd];

        FGPublicEvent::Banner.Shown.invoke(
            FGMaxErrInfo([self adUnits].Banner.AdUnitID ?: @"", FGConstValue.Banner, placement));
    }];
}

- (void)hideBanner {
    [FGMainThreadDispatcher enqueue:^{
        MAAdView *v = self->_bannerView;
        if (v == nil) return;
        [v stopAutoRefresh];
        v.hidden = YES;
        self->_isBannerShowing = NO;
        FGPublicEvent::Banner.Hidden.invoke(
            FGMaxErrInfo([self adUnits].Banner.AdUnitID ?: @"", FGConstValue.Banner, self->_bannerCtx.location));
    }];
}

// ── AppOpen (spec §7.5 — gate bởi openAppAction) ────────────────────────────

- (void)createAppOpen {
    if (![self adUnits].AppOpen.EnableAds) return;
    NSString *unitId = [self adUnits].AppOpen.AdUnitID;
    if (unitId == nil || unitId.length == 0) return;
    // Kotlin fallback activity()/appContext — iOS MAAppOpenAd không cần Context.
    MAAppOpenAd *ad = [[MAAppOpenAd alloc] initWithAdUnitIdentifier:unitId];
    __weak FGMaxAdsProvider *weakSelf = self;
    FGMaxDelegateProxy *proxy = [FGMaxDelegateProxy new];
    proxy.onLoaded = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        s->_appOpenRetryCount = 0;
        FGMaxLogRequest(s->_appOpenCtx, FGConstValue.AppOpen, YES, @"", FGMaxSecs(s->_appOpenLoadStart),
                        s->_appOpenRequestCount, a.networkName ?: @"unknown", a.adUnitIdentifier ?: unitId);
        FGPublicEvent::AppOpen.Loaded.invoke(FGMaxToInfo(a, FGConstValue.AppOpen, s->_appOpenCtx.location));
    };
    proxy.onLoadFailed = ^(NSString *adUnitIdentifier, MAError *error) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxLogRequest(s->_appOpenCtx, FGConstValue.AppOpen, NO, [FGMaxError classifyLoad:error.code],
                        FGMaxSecs(s->_appOpenLoadStart), s->_appOpenRequestCount, @"unknown", unitId);
        FGPublicEvent::AppOpen.FailedToLoad.invoke(FGMaxErrInfo(unitId, FGConstValue.AppOpen, s->_appOpenCtx.location));
        [FGMaxRetry retryLoadAd:s->_appOpenRetryCount format:@"app_open" loadAction:^{ [weakSelf loadAppOpen]; }];
        s->_appOpenRetryCount++;
    };
    proxy.onDisplayed = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxLogDisplay(s->_appOpenCtx, FGConstValue.AppOpen, YES, @"", FGMaxSecs(s->_appOpenCtx.showStart),
                        a.networkName ?: @"unknown");
        FGPublicEvent::AppOpen.Shown.invoke(FGMaxToInfo(a, FGConstValue.AppOpen, s->_appOpenCtx.location));
    };
    proxy.onHidden = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxLogCompleted(s->_appOpenCtx, FGConstValue.AppOpen, YES, FGMaxSecs(s->_appOpenCtx.showStart),
                          a.networkName ?: @"unknown");
        FGPublicEvent::AppOpen.Closed.invoke(FGMaxToInfo(a, FGConstValue.AppOpen, s->_appOpenCtx.location));
        FGEvent::Ads::ResetAOAction.invoke();
        [s loadAppOpen];
    };
    proxy.onClicked = ^(MAAd *a) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        [FGAdEventLogger adClick:FGConstValue.AppOpen platform:FGConstValue.applovin_max_sdk adNetwork:a.networkName ?: @"unknown"];
        FGPublicEvent::AppOpen.Clicked.invoke(FGMaxToInfo(a, FGConstValue.AppOpen, s->_appOpenCtx.location));
    };
    proxy.onDisplayFailed = ^(MAAd *a, MAError *error) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        FGMaxLogDisplay(s->_appOpenCtx, FGConstValue.AppOpen, NO, [FGMaxError classifyDisplay:error.code],
                        FGMaxSecs(s->_appOpenCtx.showStart), a.networkName ?: @"unknown");
        FGPublicEvent::AppOpen.FailedToShow.invoke(FGMaxToInfo(a, FGConstValue.AppOpen, s->_appOpenCtx.location));
        [s loadAppOpen];
    };
    proxy.onRevenuePaid = ^(MAAd *revAd) {
        FGMaxAdsProvider *s = weakSelf; if (!s) return;
        // AppOpen không có af_*_displayed + không có RevenuePaid public (FullscreenEvents §5.2).
        FGMaxOnRevenue(revAd, FGConstValue.AppOpen, s->_appOpenCtx, NO, nil);
    };
    ad.delegate = proxy;
    ad.revenueDelegate = proxy;
    _appOpenDelegate = proxy;
    _appOpenAd = ad;
}

- (void)loadAppOpen {
    FGPlatformAdUnit *u = [self adUnits].AppOpen;
    if (u == nil) return;
    if (FGInternalData.IsRemoveAds || !_isInitialized || !u.EnableAds || [self isAppOpenReady]) return;
    if (_appOpenAd == nil) [self createAppOpen];
    _appOpenRequestCount++;
    _appOpenLoadStart = CACurrentMediaTime();
    [_appOpenAd loadAd];
}

- (void)showAppOpen:(NSString *)placement
           playMode:(NSString *)playMode
       currentLevel:(double)currentLevel
             params:(FGParams)params {
    FGPublicEvent::AppOpen.Request.invoke(placement);
    if (FGInternalData.IsRemoveAds || !_isInitialized) return;
    _appOpenCtx.set(playMode, currentLevel, placement, params);
    OpenAppAction prev = FGAds.openAppAction;
    if (prev != OpenAppActionNONE) {
        // chỉ show khi prev==Ads && showAOAfterAds (AO sau inter/reward), else bỏ qua (quirk §16-6).
        if (prev == OpenAppActionAds && _showAOAfterAds) {
            if (![self isAppOpenReady]) return;
            FGAds.openAppAction = OpenAppActionAO;
            [_appOpenAd showAd];
        }
        return;
    }
    // openAppAction == NONE
    if (![self isAppOpenReady]) {
        if (_appOpenRetryCount >= FGMaxRetry.MaxRetryAttempts) { _appOpenRetryCount = 0; [self loadAppOpen]; }
        return;
    }
    FGAds.openAppAction = OpenAppActionAO;
    [_appOpenAd showAd];
}

- (BOOL)isAppOpenReady {
    return _appOpenAd != nil && [_appOpenAd isReady];
}

// ── MREC (spec §7.5/§7.7) ────────────────────────────────────────────────────

- (void)loadMRec {
    if (_mrecCreated) return; // create-once
    FGPlatformAdUnit *u = [self adUnits].MRec;
    if (u == nil) return;
    if (!_isInitialized || !u.EnableAds) return;
    NSString *unitId = u.AdUnitID;
    if (unitId == nil) return;
    __weak FGMaxAdsProvider *weakSelf = self;
    [FGMainThreadDispatcher enqueue:^{
        UIWindow *win = [FGViewControllerTracker keyWindow];
        if (win == nil) return;
        MAAdView *view = [[MAAdView alloc] initWithAdUnitIdentifier:unitId adFormat:MAAdFormat.mrec];
        // 300x250 pt (≈ dp Android — Kotlin nhân density vì layout px; iOS frame đã là point).
        view.frame = CGRectMake(0, 0, 300, 250); // gốc top-left ≈ Gravity.TOP|START
        view.hidden = YES;
        FGMaxDelegateProxy *proxy = [FGMaxDelegateProxy new];
        proxy.onLoaded = ^(MAAd *a) {
            FGMaxAdsProvider *s = weakSelf; if (!s) return;
            // MRec request_count = 0 (spec §8).
            FGMaxLogRequest(s->_mrecCtx, FGConstValue.Mrec, YES, @"", FGMaxSecs(s->_mrecLoadStart),
                            0, a.networkName ?: @"unknown", unitId);
            FGPublicEvent::MRec.Loaded.invoke(FGMaxToInfo(a, FGConstValue.Mrec, s->_mrecCtx.location));
        };
        proxy.onLoadFailed = ^(NSString *adUnitIdentifier, MAError *error) {
            FGMaxAdsProvider *s = weakSelf; if (!s) return;
            FGMaxLogRequest(s->_mrecCtx, FGConstValue.Mrec, NO, [FGMaxError classifyLoad:error.code],
                            FGMaxSecs(s->_mrecLoadStart), 0, @"unknown", unitId);
            FGPublicEvent::MRec.FailedToLoad.invoke(FGMaxErrInfo(unitId, FGConstValue.Mrec, s->_mrecCtx.location));
            // retry gọi reloadMRec (loadMRec bị gate create-once).
            [FGMaxRetry retryLoadAd:s->_mrecRetryCount format:@"mrec" loadAction:^{ [weakSelf reloadMRec]; }];
            s->_mrecRetryCount++;
        };
        proxy.onClicked = ^(MAAd *a) {
            FGMaxAdsProvider *s = weakSelf; if (!s) return;
            [FGAdEventLogger adClick:FGConstValue.Mrec platform:FGConstValue.applovin_max_sdk adNetwork:a.networkName ?: @"unknown"];
            FGPublicEvent::MRec.Clicked.invoke(FGMaxToInfo(a, FGConstValue.Mrec, s->_mrecCtx.location));
        };
        proxy.onRevenuePaid = ^(MAAd *revAd) {
            FGMaxAdsProvider *s = weakSelf; if (!s) return;
            FGMaxOnRevenue(revAd, FGConstValue.Mrec, s->_mrecCtx, NO, nil);
            FGPublicEvent::MRec.RevenuePaid.invoke(FGMaxToInfo(revAd, FGConstValue.Mrec, s->_mrecCtx.location));
        };
        view.delegate = proxy;
        view.revenueDelegate = proxy;
        [win addSubview:view];
        self->_mrecDelegate = proxy;
        self->_mrecView = view;
        self->_mrecCreated = YES;
        // spec §7.5: CreateMRec + HideMRec + StopMRecAutoRefresh (không sinh revenue trước Show).
        [view stopAutoRefresh];
        self->_mrecLoadStart = CACurrentMediaTime();
        [view loadAd];
    }];
}

/** reload khi retry (view đã tạo). */
- (void)reloadMRec {
    [FGMainThreadDispatcher enqueue:^{
        self->_mrecLoadStart = CACurrentMediaTime();
        [self->_mrecView loadAd];
    }];
}

/** spec §7.5 — PrepareShowMRec: !ready → LoadMRec + return NO. */
- (BOOL)prepareShowMRec {
    if (![self isMRecReady]) { [self loadMRec]; return NO; }
    return YES;
}

- (void)showMRec:(NSString *)placement
        playMode:(NSString *)playMode
    currentLevel:(double)currentLevel
          params:(FGParams)params {
    FGPublicEvent::MRec.Request.invoke(placement);
    if (!_isInitialized) return;
    _mrecCtx.set(playMode, currentLevel, placement, params);
    [FGMainThreadDispatcher enqueue:^{
        if (![self prepareShowMRec]) return;
        MAAdView *v = self->_mrecView;
        if (v == nil) return;
        [v startAutoRefresh];
        [self positionCentered:v];
        v.hidden = NO;
        [self mrecShown:placement];
    }];
}

- (void)showMRecAt:(NSString *)placement
          playMode:(NSString *)playMode
      currentLevel:(double)currentLevel
         screenPos:(CGPoint)screenPos
            params:(FGParams)params {
    FGPublicEvent::MRec.Request.invoke(placement);
    if (!_isInitialized) return;
    _mrecCtx.set(playMode, currentLevel, placement, params);
    [FGMainThreadDispatcher enqueue:^{
        if (![self prepareShowMRec]) return;
        MAAdView *v = self->_mrecView;
        if (v == nil) return;
        [v startAutoRefresh];
        [self positionAt:v screenPos:screenPos];
        v.hidden = NO;
        [self mrecShown:placement];
    }];
}

- (void)showMRecPreset:(NSString *)placement
              playMode:(NSString *)playMode
          currentLevel:(double)currentLevel
            adPosition:(NSInteger)adPosition
                params:(FGParams)params {
    FGPublicEvent::MRec.Request.invoke(placement);
    if (!_isInitialized) return;
    _mrecCtx.set(playMode, currentLevel, placement, params);
    [FGMainThreadDispatcher enqueue:^{
        if (![self prepareShowMRec]) return;
        MAAdView *v = self->_mrecView;
        if (v == nil) return;
        [v startAutoRefresh];
        [self positionPreset:v adPosition:adPosition];
        v.hidden = NO;
        [self mrecShown:placement];
    }];
}

- (void)mrecShown:(NSString *)placement {
    FGPublicEvent::MRec.Shown.invoke(
        FGMaxErrInfo([self adUnits].MRec.AdUnitID ?: @"", FGConstValue.Mrec, placement));
}

- (void)updateMRecPosition:(CGPoint)screenPos {
    [FGMainThreadDispatcher enqueue:^{
        if (self->_mrecView != nil) [self positionAt:self->_mrecView screenPos:screenPos];
    }];
}

- (void)updateMRecPositionPreset:(NSInteger)adPosition {
    [FGMainThreadDispatcher enqueue:^{
        if (self->_mrecView != nil) [self positionPreset:self->_mrecView adPosition:adPosition];
    }];
}

- (void)hideMRec {
    [FGMainThreadDispatcher enqueue:^{
        MAAdView *v = self->_mrecView;
        if (v == nil) return;
        v.hidden = YES;
        [v stopAutoRefresh];
        FGPublicEvent::MRec.Hidden.invoke(
            FGMaxErrInfo([self adUnits].MRec.AdUnitID ?: @"", FGConstValue.Mrec, self->_mrecCtx.location));
    }];
}

- (void)destroyMRec {
    [FGMainThreadDispatcher enqueue:^{
        MAAdView *v = self->_mrecView;
        if (v != nil) {
            [v stopAutoRefresh];
            [v removeFromSuperview];
            // Android MaxAdView.destroy() — iOS không có API tương đương, ARC giải phóng khi nil.
        }
        self->_mrecView = nil;
        self->_mrecCreated = NO;
    }];
}

- (BOOL)isMRecReady {
    return _mrecView != nil && _mrecCreated;
}

// ── MREC positioning (spec §7.7) — Kotlin translation px = dp*density; iOS frame origin = point ──

- (void)positionCentered:(MAAdView *)v {
    // Kotlin: (widthPixels - 300*density)/2 px → point: (widthPt - 300)/2 (cùng công thức, đơn vị point).
    CGSize s = UIScreen.mainScreen.bounds.size;
    CGRect f = v.frame;
    f.origin.x = (s.width - 300) / 2;
    f.origin.y = (s.height - 250) / 2;
    v.frame = f;
}

/**
 * spec §7.7 — ScreenToMRecPosMax (CÓ safe-area). screenPos = px gốc dưới-trái (Unity convention).
 * FGUtils trả point góc trên-trái MREC (Kotlin: translation px = resultDp * density).
 */
- (void)positionAt:(MAAdView *)v screenPos:(CGPoint)screenPos {
    CGPoint pt = [FGUtils ScreenToMRecPosMax:screenPos];
    CGRect f = v.frame;
    f.origin = pt;
    v.frame = f;
}

/** Preset AdViewPosition (Unity enum order): 0=TopLeft..8=BottomRight, 4=Centered (mirror map Kotlin). */
- (void)positionPreset:(MAAdView *)v adPosition:(NSInteger)adPosition {
    CGSize s = UIScreen.mainScreen.bounds.size;
    CGFloat maxX = s.width - 300;
    CGFloat maxY = s.height - 250;
    CGFloat tx, ty;
    switch (adPosition) {
        case 0: tx = 0;        ty = 0;        break;
        case 1: tx = maxX / 2; ty = 0;        break;
        case 2: tx = maxX;     ty = 0;        break;
        case 3: tx = 0;        ty = maxY / 2; break;
        case 4: tx = maxX / 2; ty = maxY / 2; break;
        case 5: tx = maxX;     ty = maxY / 2; break;
        case 6: tx = 0;        ty = maxY;     break;
        case 7: tx = maxX / 2; ty = maxY;     break;
        case 8: tx = maxX;     ty = maxY;     break;
        default: tx = maxX / 2; ty = maxY / 2; break;
    }
    CGRect f = v.frame;
    f.origin.x = tx;
    f.origin.y = ty;
    v.frame = f;
}

@end
