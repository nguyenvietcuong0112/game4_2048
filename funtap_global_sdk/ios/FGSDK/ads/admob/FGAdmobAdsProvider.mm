//
//  FGAdmobAdsProvider.mm — mirror KA/ads/admob/FGAdmobAdsProvider.kt (spec §7.8/§8, §5.2/§5.3).
//
//  Adaptation iOS (README): Activity/Context → FGViewControllerTracker.topViewController (present);
//  root view Android (android.R.id.content) → keyWindow; translation px → frame origin point.
//  Callback anonymous Kotlin (FullScreenContentCallback/AdListener) → proxy block-based 1:1.
//
//  ⚠️ Revenue: Android AdValue.valueMicros/1_000_000; iOS GADAdValue.value là NSDecimalNumber
//     ĐƠN VỊ TIỀN (không phải micros) → dùng value.doubleValue TRỰC TIẾP.
//
#import "FGAdmobAdsProvider.h"
#import "FGAdmobConfig.h"
#import "../FGAds.h"
#import "../FGAdEventLogger.h"
#import "../FGAdsOrchestrator.h"
#import "../OpenAppAction.h"
#import "../max/FGMaxRetry.h"
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
#import <QuartzCore/QuartzCore.h> // CACurrentMediaTime (≈ System.nanoTime — monotonic)
#include <atomic>

#if GOOGLE_MOBILE_ADS_ENABLE
#import <GoogleMobileAds/GoogleMobileAds.h>
#endif

static NSString *const TAG = @"FGAdmob";

// spec §8 — AdMob ad_network luôn "google_admob" (mirror val adNetwork Kotlin).
static NSString *const kAdmobNetwork = @"google_admob";

// ── Show context + timing (spec §8) — mirror inner class Ctx Kotlin ──────────

struct FGAdmobShowCtx {
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
static double FGAdmobSecs(double start) {
    return start == 0.0 ? 0.0 : CACurrentMediaTime() - start;
}

/** XParams cho ad_revenue_sdk = play_mode/level + custom show params (mirror xParams Kotlin). */
static FGParams FGAdmobXParams(const FGAdmobShowCtx &c) {
    NSMutableDictionary<NSString *, id> *m = [NSMutableDictionary dictionary];
    m[@"play_mode"] = c.playMode;
    m[@"level"] = @(c.level);
    if (c.params != nil) [m addEntriesFromDictionary:c.params];
    return m;
}

// ── FGAdEventLogger shortcuts (mirror logRequest/logDisplay/logCompleted Kotlin) ─────────
// adPlatform = admob_sdk, adNetwork = "google_admob" (spec §8).

static void FGAdmobLogRequest(const FGAdmobShowCtx &c, NSString *format, BOOL success, NSString *reason,
                              double value, NSInteger requestCount, NSString *unitId) {
    [FGAdEventLogger adRequest:c.playMode level:c.level platform:FGConstValue.admob_sdk
                     adNetwork:kAdmobNetwork format:format location:c.location
                       success:success reason:reason value:value requestCount:requestCount unitId:unitId];
}

static void FGAdmobLogDisplay(const FGAdmobShowCtx &c, NSString *format, BOOL success, NSString *reason,
                              double value) {
    [FGAdEventLogger adDisplay:c.playMode level:c.level platform:FGConstValue.admob_sdk
                     adNetwork:kAdmobNetwork format:format location:c.location
                       success:success reason:reason value:value];
}

static void FGAdmobLogCompleted(const FGAdmobShowCtx &c, NSString *format, BOOL success, double value) {
    [FGAdEventLogger adCompleted:c.playMode level:c.level platform:FGConstValue.admob_sdk
                       adNetwork:kAdmobNetwork format:format location:c.location
                         success:success value:value];
}

// ── FGPublicEvent (spec §5.2) — FGAdsInfo AdMob TỐI GIẢN như Kotlin:
//    AdID/AdFormat/NetworkName("google_admob")/Placement/Revenue — field khác ""/0 (spec §5.3). ──

static FGAdsInfo *FGAdmobAdInfo(NSString *format, NSString *placement, NSString *adUnitId, double revenue = 0.0) {
    return [[FGAdsInfo alloc] initWithAdID:adUnitId
                                  AdFormat:format
                               NetworkName:kAdmobNetwork
                          NetworkPlacement:nil
                                 Placement:placement
                        CreativeIdentifier:nil
                                   Revenue:revenue
                          RevenuePrecision:nil
                             LatencyMillis:0
                                   DspName:nil];
}

/** Kotlin errInfo — chỉ AdID/AdFormat/Placement (NetworkName ""). */
static FGAdsInfo *FGAdmobErrInfo(NSString *unitId, NSString *format, NSString *placement) {
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

#if GOOGLE_MOBILE_ADS_ENABLE

// ── Proxy delegate — thay anonymous FullScreenContentCallback/AdListener Kotlin (block 1:1) ─────
// GAD fullScreenContentDelegate/GADBannerView.delegate là weak → provider giữ strong ref.

@interface FGAdmobFullScreenProxy : NSObject <GADFullScreenContentDelegate>
@property (nonatomic, copy, nullable) void (^onShown)(void);          // onAdShowedFullScreenContent
@property (nonatomic, copy, nullable) void (^onDismissed)(void);      // onAdDismissedFullScreenContent
@property (nonatomic, copy, nullable) void (^onFailedToShow)(NSError *error);
@property (nonatomic, copy, nullable) void (^onClicked)(void);        // onAdClicked
@end

@implementation FGAdmobFullScreenProxy
- (void)adWillPresentFullScreenContent:(id<GADFullScreenPresentingAd>)ad {
    if (self.onShown) self.onShown();
}
- (void)adDidDismissFullScreenContent:(id<GADFullScreenPresentingAd>)ad {
    if (self.onDismissed) self.onDismissed();
}
- (void)ad:(id<GADFullScreenPresentingAd>)ad didFailToPresentFullScreenContentWithError:(NSError *)error {
    if (self.onFailedToShow) self.onFailedToShow(error);
}
- (void)adDidRecordClick:(id<GADFullScreenPresentingAd>)ad {
    if (self.onClicked) self.onClicked();
}
// Kotlin không override onAdImpression — mirror no-op (không implement adDidRecordImpression).
@end

@interface FGAdmobBannerProxy : NSObject <GADBannerViewDelegate>
@property (nonatomic, copy, nullable) void (^onLoaded)(void);                 // onAdLoaded
@property (nonatomic, copy, nullable) void (^onLoadFailed)(NSError *error);   // onAdFailedToLoad
@property (nonatomic, copy, nullable) void (^onClicked)(void);                // onAdClicked
@end

@implementation FGAdmobBannerProxy
- (void)bannerViewDidReceiveAd:(GADBannerView *)bannerView {
    if (self.onLoaded) self.onLoaded();
}
- (void)bannerView:(GADBannerView *)bannerView didFailToReceiveAdWithError:(NSError *)error {
    if (self.onLoadFailed) self.onLoadFailed(error);
}
- (void)bannerViewDidRecordClick:(GADBannerView *)bannerView {
    if (self.onClicked) self.onClicked();
}
@end

// ── Provider ─────────────────────────────────────────────────────────────────

@interface FGAdmobAdsProvider ()
- (void)onSdkInitialized;
- (void)autoLoadAd;
- (void)onPaid:(GADAdValue *)adValue
        format:(NSString *)format
           ctx:(const FGAdmobShowCtx &)c
isInterstitial:(BOOL)isInterstitial
        unitId:(NSString *)unitId
        afSend:(void (^_Nullable)(void))afSend;
- (void)reloadMRec;
- (BOOL)prepareShowMRec;
- (void)positionCentered:(GADBannerView *)v;
- (void)positionAt:(GADBannerView *)v screenPos:(CGPoint)screenPos;
- (void)positionPreset:(GADBannerView *)v adPosition:(NSInteger)adPosition;
- (void)mrecShown:(NSString *)placement;
@end

@implementation FGAdmobAdsProvider {
    FGSignal _onInitialized;
    FGSignal1<NSString *> _onInitializationFailed;

    FGAdmobConfig *_config;
    BOOL _isBackfill;
    FGAdsOrchestrator *_orchestrator; // giữ mirror Kotlin (không dùng lại sau initialize)

    std::atomic<bool> _isInitialized; // Kotlin @Volatile

    // Retry counters (spec §7.6 — pattern giống MAX).
    NSInteger _interRetryCount;
    NSInteger _rewardRetryCount;
    NSInteger _bannerRetryCount;
    NSInteger _appOpenRetryCount;
    NSInteger _mrecRetryCount;

    // Last-load reason (spec §8 — _xLastLoadReason cho ad_display giả AdMob not-ready).
    NSString *_interLastLoadReason;
    NSString *_rewardLastLoadReason;
    NSString *_appOpenLastLoadReason;

    // Loaded ad refs (AdMob one-shot: ref != nil ⇒ ready). Set nil sau show/dismiss.
    GADInterstitialAd *_interstitialAd;
    FGAdmobFullScreenProxy *_interFsProxy;
    void (^_onInterstitialComplete)(void); // ⚠️ single-slot (đồng bộ quirk §16-2)

    GADRewardedAd *_rewardedAd;
    FGAdmobFullScreenProxy *_rewardFsProxy;
    void (^_onRewardComplete)(void);
    BOOL _rewardGranted;

    GADAppOpenAd *_appOpenAd;
    FGAdmobFullScreenProxy *_appOpenFsProxy;

    // Banner/MRec dùng GADBannerView (create-once trên show).
    GADBannerView *_bannerView;
    FGAdmobBannerProxy *_bannerProxy;
    BOOL _isBannerLoaded;
    BOOL _isBannerShowing;
    GADBannerView *_mrecView;
    FGAdmobBannerProxy *_mrecProxy;
    BOOL _mrecCreated;
    BOOL _mrecLoaded;

    // Request counters (spec §8 — Banner/MRec=0; AdMob primary có count cho inter/reward/appopen).
    NSInteger _interRequestCount;
    NSInteger _rewardRequestCount;
    NSInteger _appOpenRequestCount;

    // Show context + load timing (spec §8).
    FGAdmobShowCtx _interCtx;
    FGAdmobShowCtx _rewardCtx;
    FGAdmobShowCtx _bannerCtx;
    FGAdmobShowCtx _appOpenCtx;
    FGAdmobShowCtx _mrecCtx;
    double _interLoadStart;
    double _rewardLoadStart;
    double _bannerLoadStart;
    double _appOpenLoadStart;
    double _mrecLoadStart;
}

- (instancetype)initWithConfig:(FGAdmobConfig *)config isBackfill:(BOOL)isBackfill {
    if ((self = [super init])) {
        _config = config;
        _isBackfill = isBackfill;
        _isInitialized = false;
    }
    return self;
}

- (FGSignal &)onInitialized { return _onInitialized; }
- (FGSignal1<NSString *> &)onInitializationFailed { return _onInitializationFailed; }

/** spec §8 — impression + ad_revenue_sdk + logAdRevenue (+ af cho inter/reward) — mirror onPaid Kotlin. */
- (void)onPaid:(GADAdValue *)adValue
        format:(NSString *)format
           ctx:(const FGAdmobShowCtx &)c
isInterstitial:(BOOL)isInterstitial
        unitId:(NSString *)unitId
        afSend:(void (^)(void))afSend {
    // ⚠️ Android: valueMicros/1_000_000; iOS: GADAdValue.value đã là ĐƠN VỊ TIỀN → doubleValue trực tiếp.
    double revenue = adValue.value.doubleValue;
    NSString *currency = adValue.currencyCode ?: @"";
    NSMutableDictionary<NSString *, id> *dict =
        [FGAdEventLogger buildImpression:format
                                 isAdmob:YES
                          isInterstitial:isInterstitial
                               adNetwork:kAdmobNetwork
                                 revenue:revenue
                                currency:currency
                              // ad_unit_name CHỈ Interstitial (quirk §16-7 key ad_source cũng chỉ Inter).
                              adUnitName:(isInterstitial ? unitId : nil)];
    [FGAdEventLogger adImpression:dict];
    [FGAdEventLogger adRevenueSdk:dict location:c.location xParams:FGAdmobXParams(c)];
    if (afSend) afSend();
    [FGAdEventLogger logAdRevenue:kAdmobNetwork isAdmob:YES currency:currency revenue:revenue
                           format:format adUnit:unitId];
}

// ── Init ─────────────────────────────────────────────────────────────────────

- (void)initialize:(FGAdsOrchestrator *)orchestrator {
    _orchestrator = orchestrator;
    __weak FGAdmobAdsProvider *weakSelf = self;
    [FGMainThreadDispatcher enqueue:^{
        @try { // ≈ Kotlin catch Throwable
            // OnSDKReady fire khi cả Analystic+Ads ready (Custom → sau MAX primary ready) → autoload.
            FGEvent::InitEvent::OnSDKReady.add([weakSelf] { [weakSelf autoLoadAd]; });

#if GOOGLE_MOBILE_ADS_ENABLE
            NSArray<NSString *> *devices = [FGConfigController mainConfig].listDevice;
            if (devices.count > 0) {
                GADMobileAds.sharedInstance.requestConfiguration.testDeviceIdentifiers = devices;
                NSLog(@"[%@] Configured %lu test devices in GADMobileAds", TAG, (unsigned long)devices.count);
            }
            [GADMobileAds.sharedInstance startWithCompletionHandler:^(GADInitializationStatus *status) {
                [weakSelf onSdkInitialized];
            }];
#else
            [weakSelf onSdkInitialized];
#endif
        } @catch (NSException *e) {
            NSLog(@"[%@] AdMob init exception: %@", TAG, e);
            self->_onInitializationFailed.invoke(e.reason ?: @"init exception");
        }
    }];
}

- (void)onSdkInitialized {
    __weak FGAdmobAdsProvider *weakSelf = self;
    [FGMainThreadDispatcher enqueue:^{
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        s->_isInitialized = true;
        if (s->_isBackfill) {
            // ⚠️ spec §7.8/§16-8: backfill IM LẶNG — không fire init/ready. Custom provider drive orchestrator.
            NSLog(@"[%@] AdMob backfill initialized (silent)", TAG);
            return;
        }
        // primary: fire init + set ready (giống MAX onSdkInitialized).
        FGEvent::InitEvent::ApplovinInitComplete.invoke();
        s->_onInitialized.invoke();
        [FGInitStateMachine SetReady:FGInitStateAds];
        NSLog(@"[%@] AdMob primary initialized", TAG);
    }];
}

/** spec §7.4-6 (mirror MAX AutoLoadAd): Rewarded trước (cả khi RemoveAds), rồi format khác theo IsAutoLoad. */
- (void)autoLoadAd {
    if (!FGInternetChecker.isConnected) return;
    if (_config.rewarded.isAutoLoad) [self loadRewarded];
    if (FGInternalData.IsRemoveAds) return;
    if (_config.banner.isAutoLoad) [self loadBanner];
    if (_config.interstitial.isAutoLoad) [self loadInterstitial];
    if (_config.appOpen.isAutoLoad) [self loadAppOpen];
    if (_config.mrec.isAutoLoad) [self loadMRec];
}

// ── Interstitial ─────────────────────────────────────────────────────────────

- (void)loadInterstitial {
    FGAdmobAdUnit *u = _config.interstitial;
    if (FGInternalData.IsRemoveAds || !_isInitialized || !u.isUsable || [self isInterstitialReady]) return;
    // Kotlin guard activity()/appContext cho load — iOS không cần Context (adaptation README).
    NSString *unitId = u.adUnitId;
    _interRequestCount++;
    _interLoadStart = CACurrentMediaTime();
    __weak FGAdmobAdsProvider *weakSelf = self;
    [GADInterstitialAd loadWithAdUnitID:unitId
                                request:[GADRequest request]
                      completionHandler:^(GADInterstitialAd *ad, NSError *error) {
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        if (error != nil) {
            s->_interstitialAd = nil;
            s->_interLastLoadReason = [FGAdmobError mapToReason:error.code];
            FGAdmobLogRequest(s->_interCtx, FGConstValue.Interstitial, NO,
                              s->_interLastLoadReason ?: @"unknown",
                              FGAdmobSecs(s->_interLoadStart), s->_interRequestCount, unitId);
            FGPublicEvent::Interstitial.FailedToLoad.invoke(
                FGAdmobErrInfo(unitId, FGConstValue.Interstitial, s->_interCtx.location));
            [FGMaxRetry retryLoadAd:s->_interRetryCount format:@"admob_interstitial"
                         loadAction:^{ [weakSelf loadInterstitial]; }];
            s->_interRetryCount++; // ⚠️ retry TRƯỚC, count++ SAU (spec §7.6)
            return;
        }
        s->_interRetryCount = 0;
        s->_interstitialAd = ad;
        ad.paidEventHandler = ^(GADAdValue *av) {
            FGAdmobAdsProvider *p = weakSelf; if (!p) return;
            [p onPaid:av format:FGConstValue.Interstitial ctx:p->_interCtx isInterstitial:YES
               unitId:unitId afSend:^{ [FGAdEventLogger afIntersDisplayed]; }];
        };
        FGAdmobLogRequest(s->_interCtx, FGConstValue.Interstitial, YES, @"",
                          FGAdmobSecs(s->_interLoadStart), s->_interRequestCount, unitId);
        FGPublicEvent::Interstitial.Loaded.invoke(
            FGAdmobAdInfo(FGConstValue.Interstitial, s->_interCtx.location, unitId));
    }];
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
    _interCtx.set(playMode, currentLevel, placement, params);
    GADInterstitialAd *ad = _interstitialAd;
    if (ad == nil || ![self isInterstitialReady]) {
        // ⚠️ AdMob không reset retry khi show not-ready — chỉ Load lại (spec §7.6).
        [self loadInterstitial];
        // spec §8 — ad_display giả (success=false, reason=lastLoadReason ?? "not_ready", value=0).
        FGAdmobLogDisplay(_interCtx, FGConstValue.Interstitial, NO,
                          _interLastLoadReason ?: @"not_ready", 0.0);
        if (onInterstitialClosed) onInterstitialClosed();
        return;
    }
    UIViewController *vc = [FGViewControllerTracker topViewController];
    if (vc == nil) { // ≈ Kotlin activity() null
        if (onInterstitialClosed) onInterstitialClosed();
        return;
    }
    NSString *unitId = _config.interstitial.adUnitId ?: @"";
    FGAds.openAppAction = OpenAppActionAds;
    _onInterstitialComplete = [onInterstitialClosed copy]; // ⚠️ single-slot (quirk §16-2)
    __weak FGAdmobAdsProvider *weakSelf = self;
    FGAdmobFullScreenProxy *proxy = [FGAdmobFullScreenProxy new];
    proxy.onShown = ^{
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        FGAdmobLogDisplay(s->_interCtx, FGConstValue.Interstitial, YES, @"",
                          FGAdmobSecs(s->_interCtx.showStart));
        FGPublicEvent::Interstitial.Shown.invoke(
            FGAdmobAdInfo(FGConstValue.Interstitial, s->_interCtx.location, unitId));
    };
    proxy.onDismissed = ^{
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        s->_interstitialAd = nil;
        FGAdmobLogCompleted(s->_interCtx, FGConstValue.Interstitial, YES,
                            FGAdmobSecs(s->_interCtx.showStart));
        FGPublicEvent::Interstitial.Closed.invoke(
            FGAdmobAdInfo(FGConstValue.Interstitial, s->_interCtx.location, unitId));
        FGEvent::Ads::ResetAOAction.invoke();
        void (^cb)(void) = s->_onInterstitialComplete;
        s->_onInterstitialComplete = nil; // ⚠️ invoke + null (quirk §16-2)
        if (cb) cb();
        [s loadInterstitial];
    };
    proxy.onFailedToShow = ^(NSError *adError) {
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        s->_interstitialAd = nil;
        FGAdmobLogDisplay(s->_interCtx, FGConstValue.Interstitial, NO,
                          [FGAdmobError mapToReason:adError.code], FGAdmobSecs(s->_interCtx.showStart));
        FGPublicEvent::Interstitial.FailedToShow.invoke(
            FGAdmobErrInfo(unitId, FGConstValue.Interstitial, s->_interCtx.location));
        void (^cb)(void) = s->_onInterstitialComplete;
        s->_onInterstitialComplete = nil;
        if (cb) cb();
        [s loadInterstitial];
    };
    proxy.onClicked = ^{
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        [FGAdEventLogger adClick:FGConstValue.Interstitial platform:FGConstValue.admob_sdk adNetwork:kAdmobNetwork];
        FGPublicEvent::Interstitial.Clicked.invoke(
            FGAdmobAdInfo(FGConstValue.Interstitial, s->_interCtx.location, unitId));
    };
    ad.fullScreenContentDelegate = proxy;
    _interFsProxy = proxy; // giữ strong (GAD delegate là weak ref)
    [ad presentFromRootViewController:vc];
}

- (BOOL)isInterstitialReady { return _interstitialAd != nil; }

// ── Rewarded (không guard IsRemoveAds) ───────────────────────────────────────

- (void)loadRewarded {
    FGAdmobAdUnit *u = _config.rewarded;
    if (!_isInitialized || !u.isUsable || [self isRewardedReady]) return;
    NSString *unitId = u.adUnitId;
    _rewardRequestCount++;
    _rewardLoadStart = CACurrentMediaTime();
    __weak FGAdmobAdsProvider *weakSelf = self;
    [GADRewardedAd loadWithAdUnitID:unitId
                            request:[GADRequest request]
                  completionHandler:^(GADRewardedAd *ad, NSError *error) {
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        if (error != nil) {
            NSLog(@"[%@] AdMob Rewarded load error (unit=%@): %@", TAG, unitId, error);
            s->_rewardedAd = nil;
            s->_rewardLastLoadReason = [FGAdmobError mapToReason:error.code];
            FGAdmobLogRequest(s->_rewardCtx, FGConstValue.Reward, NO,
                              s->_rewardLastLoadReason ?: @"unknown",
                              FGAdmobSecs(s->_rewardLoadStart), s->_rewardRequestCount, unitId);
            FGPublicEvent::Rewarded.FailedToLoad.invoke(
                FGAdmobErrInfo(unitId, FGConstValue.Reward, s->_rewardCtx.location));
            [FGMaxRetry retryLoadAd:s->_rewardRetryCount format:@"admob_reward"
                         loadAction:^{ [weakSelf loadRewarded]; }];
            s->_rewardRetryCount++;
            return;
        }
        s->_rewardRetryCount = 0;
        s->_rewardedAd = ad;
        ad.paidEventHandler = ^(GADAdValue *av) {
            FGAdmobAdsProvider *p = weakSelf; if (!p) return;
            [p onPaid:av format:FGConstValue.Reward ctx:p->_rewardCtx isInterstitial:NO
               unitId:unitId afSend:^{ [FGAdEventLogger afRewardedDisplayed]; }];
        };
        FGAdmobLogRequest(s->_rewardCtx, FGConstValue.Reward, YES, @"",
                          FGAdmobSecs(s->_rewardLoadStart), s->_rewardRequestCount, unitId);
        FGPublicEvent::Rewarded.Loaded.invoke(
            FGAdmobAdInfo(FGConstValue.Reward, s->_rewardCtx.location, unitId));
    }];
}

- (void)showRewarded:(NSString *)placement
            playMode:(NSString *)playMode
        currentLevel:(double)currentLevel
          onRewarded:(void (^)(void))onRewarded
              params:(FGParams)params {
    FGPublicEvent::Rewarded.Request.invoke(placement);
    if (!_isInitialized) return;
    GADRewardedAd *ad = _rewardedAd;
    if (ad == nil || ![self isRewardedReady]) {
        // ⚠️ AdMob không reset retry — chỉ Load lại (spec §7.6).
        [self loadRewarded];
        // OnRewardFailed("Ad not ready") — không có trong §5.2, để future (mirror TODO Kotlin).
        return;
    }
    UIViewController *vc = [FGViewControllerTracker topViewController];
    if (vc == nil) return; // ≈ Kotlin activity() null
    NSString *unitId = _config.rewarded.adUnitId ?: @"";
    _rewardGranted = NO;
    _onRewardComplete = [onRewarded copy];
    _rewardCtx.set(playMode, currentLevel, placement, params);
    __weak FGAdmobAdsProvider *weakSelf = self;
    FGAdmobFullScreenProxy *proxy = [FGAdmobFullScreenProxy new];
    proxy.onShown = ^{
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        FGAdmobLogDisplay(s->_rewardCtx, FGConstValue.Reward, YES, @"",
                          FGAdmobSecs(s->_rewardCtx.showStart));
        FGPublicEvent::Rewarded.Shown.invoke(
            FGAdmobAdInfo(FGConstValue.Reward, s->_rewardCtx.location, unitId));
    };
    proxy.onDismissed = ^{
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        s->_rewardedAd = nil;
        // spec §8 — AdMob Reward success = onRewardComplete==nil (đã nhận reward).
        FGAdmobLogCompleted(s->_rewardCtx, FGConstValue.Reward, s->_onRewardComplete == nil,
                            FGAdmobSecs(s->_rewardCtx.showStart));
        FGPublicEvent::Rewarded.Closed.invoke(
            FGAdmobAdInfo(FGConstValue.Reward, s->_rewardCtx.location, unitId));
        if (s->_onRewardComplete != nil) {
            s->_onRewardComplete = nil;
            // OnRewardFailed("User closed ad before reward") — để future (mirror TODO Kotlin).
        }
        s->_rewardGranted = NO;
        [s loadRewarded];
    };
    proxy.onFailedToShow = ^(NSError *adError) {
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        s->_rewardedAd = nil;
        s->_onRewardComplete = nil;
        s->_rewardGranted = NO;
        FGAdmobLogDisplay(s->_rewardCtx, FGConstValue.Reward, NO,
                          [FGAdmobError mapToReason:adError.code], FGAdmobSecs(s->_rewardCtx.showStart));
        FGPublicEvent::Rewarded.FailedToShow.invoke(
            FGAdmobErrInfo(unitId, FGConstValue.Reward, s->_rewardCtx.location));
        [s loadRewarded];
    };
    proxy.onClicked = ^{
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        [FGAdEventLogger adClick:FGConstValue.Reward platform:FGConstValue.admob_sdk adNetwork:kAdmobNetwork];
        FGPublicEvent::Rewarded.Clicked.invoke(
            FGAdmobAdInfo(FGConstValue.Reward, s->_rewardCtx.location, unitId));
    };
    ad.fullScreenContentDelegate = proxy;
    _rewardFsProxy = proxy;
    [ad presentFromRootViewController:vc userDidEarnRewardHandler:^{
        // spec §8/quirk §16-5 nhánh AdMob — reward cấp trong handler của present (khác MAX ở didRewardUserForAd).
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        s->_rewardGranted = YES;
        FGPublicEvent::Rewarded.Completed.invoke(
            FGAdmobAdInfo(FGConstValue.Reward, s->_rewardCtx.location, unitId));
        void (^cb)(void) = s->_onRewardComplete;
        s->_onRewardComplete = nil;
        if (cb) cb();
    }];
}

- (BOOL)isRewardedReady { return _rewardedAd != nil; }

// ── Banner ───────────────────────────────────────────────────────────────────

- (void)loadBanner {
    FGAdmobAdUnit *u = _config.banner;
    if (FGInternalData.IsRemoveAds || !_isInitialized || !u.isUsable) return;
    __weak FGAdmobAdsProvider *weakSelf = self;
    [FGMainThreadDispatcher enqueue:^{
        UIWindow *win = [FGViewControllerTracker keyWindow];
        UIViewController *vc = [FGViewControllerTracker topViewController];
        if (win == nil || vc == nil) return; // ≈ Kotlin activity/root null → bỏ
        if (self->_bannerView != nil) [self->_bannerView removeFromSuperview]; // mirror removeView cũ
        GADBannerView *view = [[GADBannerView alloc] initWithAdSize:GADAdSizeBanner];
        NSString *unitId = u.adUnitId;
        view.adUnitID = unitId;
        view.rootViewController = vc;
        // Thay Gravity BOTTOM|CENTER_HORIZONTAL Android: 320x50 pt đáy giữa, bám đáy khi xoay.
        CGSize sz = CGSizeFromGADAdSize(GADAdSizeBanner);
        CGRect b = win.bounds;
        view.frame = CGRectMake((b.size.width - sz.width) / 2, b.size.height - sz.height,
                                sz.width, sz.height);
        view.autoresizingMask = UIViewAutoresizingFlexibleTopMargin
                              | UIViewAutoresizingFlexibleLeftMargin
                              | UIViewAutoresizingFlexibleRightMargin;
        view.hidden = YES; // ≈ View.GONE
        FGAdmobBannerProxy *proxy = [FGAdmobBannerProxy new];
        proxy.onLoaded = ^{
            FGAdmobAdsProvider *s = weakSelf; if (!s) return;
            s->_isBannerLoaded = YES;
            if (s->_isBannerShowing) {
                view.hidden = NO;
                UIWindow *curWin = [FGViewControllerTracker keyWindow];
                if (view.superview != curWin && curWin != nil) {
                    [view removeFromSuperview];
                    [curWin addSubview:view];
                }
                if (view.superview) [view.superview bringSubviewToFront:view];
            }
            // Banner request_count = 0 (spec §8).
            FGAdmobLogRequest(s->_bannerCtx, FGConstValue.Banner, YES, @"",
                              FGAdmobSecs(s->_bannerLoadStart), 0, unitId);
            FGPublicEvent::Banner.Loaded.invoke(
                FGAdmobAdInfo(FGConstValue.Banner, s->_bannerCtx.location, unitId));
        };
        proxy.onLoadFailed = ^(NSError *error) {
            FGAdmobAdsProvider *s = weakSelf; if (!s) return;
            s->_isBannerLoaded = NO;
            // Keep _isBannerShowing = YES so when retry/reload succeeds it unhides automatically
            FGAdmobLogRequest(s->_bannerCtx, FGConstValue.Banner, NO,
                              [FGAdmobError mapToReason:error.code],
                              FGAdmobSecs(s->_bannerLoadStart), 0, unitId);
            FGPublicEvent::Banner.FailedToLoad.invoke(
                FGAdmobErrInfo(unitId, FGConstValue.Banner, s->_bannerCtx.location));
            [FGMaxRetry retryLoadAd:s->_bannerRetryCount format:@"admob_banner"
                         loadAction:^{ [weakSelf loadBanner]; }];
            s->_bannerRetryCount++;
        };
        proxy.onClicked = ^{
            FGAdmobAdsProvider *s = weakSelf; if (!s) return;
            [FGAdEventLogger adClick:FGConstValue.Banner platform:FGConstValue.admob_sdk adNetwork:kAdmobNetwork];
            FGPublicEvent::Banner.Clicked.invoke(
                FGAdmobAdInfo(FGConstValue.Banner, s->_bannerCtx.location, unitId));
        };
        view.paidEventHandler = ^(GADAdValue *av) {
            FGAdmobAdsProvider *s = weakSelf; if (!s) return;
            [s onPaid:av format:FGConstValue.Banner ctx:s->_bannerCtx isInterstitial:NO
               unitId:unitId afSend:nil];
            // iOS: av.value đơn vị tiền (Android valueMicros/1e6).
            FGPublicEvent::Banner.RevenuePaid.invoke(
                FGAdmobAdInfo(FGConstValue.Banner, s->_bannerCtx.location, unitId, av.value.doubleValue));
        };
        view.delegate = proxy;
        [win addSubview:view];
        self->_bannerProxy = proxy; // giữ strong (GADBannerView.delegate là weak)
        self->_bannerView = view;
        self->_bannerLoadStart = CACurrentMediaTime();
        [view loadRequest:[GADRequest request]];
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

        GADBannerView *v = self->_bannerView;
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
        [v loadRequest:[GADRequest request]];

        FGPublicEvent::Banner.Shown.invoke(
            FGAdmobErrInfo(self->_config.banner.adUnitId ?: @"", FGConstValue.Banner, placement));
    }];
}

- (void)hideBanner {
    [FGMainThreadDispatcher enqueue:^{
        self->_isBannerShowing = NO;
        if (self->_bannerView != nil) self->_bannerView.hidden = YES;
        // Kotlin: Hidden invoke cả khi bannerView null — mirror.
        FGPublicEvent::Banner.Hidden.invoke(
            FGAdmobErrInfo(self->_config.banner.adUnitId ?: @"", FGConstValue.Banner,
                           self->_bannerCtx.location));
    }];
}

- (BOOL)isBannerReady { return _isBannerLoaded; }

// ── AppOpen (gate bởi openAppAction) ─────────────────────────────────────────

- (void)loadAppOpen {
    FGAdmobAdUnit *u = _config.appOpen;
    if (FGInternalData.IsRemoveAds || !_isInitialized || !u.isUsable || [self isAppOpenReady]) return;
    NSString *unitId = u.adUnitId;
    _appOpenRequestCount++;
    _appOpenLoadStart = CACurrentMediaTime();
    __weak FGAdmobAdsProvider *weakSelf = self;
    [GADAppOpenAd loadWithAdUnitID:unitId
                           request:[GADRequest request]
                 completionHandler:^(GADAppOpenAd *ad, NSError *error) {
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        if (error != nil) {
            s->_appOpenAd = nil;
            s->_appOpenLastLoadReason = [FGAdmobError mapToReason:error.code];
            FGAdmobLogRequest(s->_appOpenCtx, FGConstValue.AppOpen, NO,
                              s->_appOpenLastLoadReason ?: @"unknown",
                              FGAdmobSecs(s->_appOpenLoadStart), s->_appOpenRequestCount, unitId);
            FGPublicEvent::AppOpen.FailedToLoad.invoke(
                FGAdmobErrInfo(unitId, FGConstValue.AppOpen, s->_appOpenCtx.location));
            [FGMaxRetry retryLoadAd:s->_appOpenRetryCount format:@"admob_app_open"
                         loadAction:^{ [weakSelf loadAppOpen]; }];
            s->_appOpenRetryCount++;
            return;
        }
        s->_appOpenRetryCount = 0;
        s->_appOpenAd = ad;
        ad.paidEventHandler = ^(GADAdValue *av) {
            FGAdmobAdsProvider *p = weakSelf; if (!p) return;
            // AppOpen không có af_*_displayed + không có RevenuePaid public (FullscreenEvents §5.2).
            [p onPaid:av format:FGConstValue.AppOpen ctx:p->_appOpenCtx isInterstitial:NO
               unitId:unitId afSend:nil];
        };
        FGAdmobLogRequest(s->_appOpenCtx, FGConstValue.AppOpen, YES, @"",
                          FGAdmobSecs(s->_appOpenLoadStart), s->_appOpenRequestCount, unitId);
        FGPublicEvent::AppOpen.Loaded.invoke(
            FGAdmobAdInfo(FGConstValue.AppOpen, s->_appOpenCtx.location, unitId));
    }];
}

- (void)showAppOpen:(NSString *)placement
           playMode:(NSString *)playMode
       currentLevel:(double)currentLevel
             params:(FGParams)params {
    FGPublicEvent::AppOpen.Request.invoke(placement);
    if (FGInternalData.IsRemoveAds || !_isInitialized) return;
    OpenAppAction prev = FGAds.openAppAction;
    // ⚠️ quirk §16-6: AdMob check openAppAction != NONE TRƯỚC readiness — tránh double fake event khi AO đóng.
    if (prev != OpenAppActionNONE) return;
    GADAppOpenAd *ad = _appOpenAd;
    if (ad == nil || ![self isAppOpenReady]) {
        [self loadAppOpen];
        return;
    }
    UIViewController *vc = [FGViewControllerTracker topViewController];
    if (vc == nil) return; // ≈ Kotlin activity() null
    NSString *unitId = _config.appOpen.adUnitId ?: @"";
    FGAds.openAppAction = OpenAppActionAO;
    _appOpenCtx.set(playMode, currentLevel, placement, params);
    __weak FGAdmobAdsProvider *weakSelf = self;
    FGAdmobFullScreenProxy *proxy = [FGAdmobFullScreenProxy new];
    proxy.onShown = ^{
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        FGAdmobLogDisplay(s->_appOpenCtx, FGConstValue.AppOpen, YES, @"",
                          FGAdmobSecs(s->_appOpenCtx.showStart));
        FGPublicEvent::AppOpen.Shown.invoke(
            FGAdmobAdInfo(FGConstValue.AppOpen, s->_appOpenCtx.location, unitId));
    };
    proxy.onDismissed = ^{
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        s->_appOpenAd = nil;
        FGAdmobLogCompleted(s->_appOpenCtx, FGConstValue.AppOpen, YES,
                            FGAdmobSecs(s->_appOpenCtx.showStart));
        FGPublicEvent::AppOpen.Closed.invoke(
            FGAdmobAdInfo(FGConstValue.AppOpen, s->_appOpenCtx.location, unitId));
        FGEvent::Ads::ResetAOAction.invoke();
        [s loadAppOpen];
    };
    proxy.onFailedToShow = ^(NSError *adError) {
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        s->_appOpenAd = nil;
        FGAdmobLogDisplay(s->_appOpenCtx, FGConstValue.AppOpen, NO,
                          [FGAdmobError mapToReason:adError.code], FGAdmobSecs(s->_appOpenCtx.showStart));
        FGPublicEvent::AppOpen.FailedToShow.invoke(
            FGAdmobErrInfo(unitId, FGConstValue.AppOpen, s->_appOpenCtx.location));
        [s loadAppOpen];
    };
    proxy.onClicked = ^{
        // AppOpen CÓ Clicked (mirror Kotlin — soát đủ invoke).
        FGAdmobAdsProvider *s = weakSelf; if (!s) return;
        [FGAdEventLogger adClick:FGConstValue.AppOpen platform:FGConstValue.admob_sdk adNetwork:kAdmobNetwork];
        FGPublicEvent::AppOpen.Clicked.invoke(
            FGAdmobAdInfo(FGConstValue.AppOpen, s->_appOpenCtx.location, unitId));
    };
    ad.fullScreenContentDelegate = proxy;
    _appOpenFsProxy = proxy;
    [ad presentFromRootViewController:vc];
}

- (BOOL)isAppOpenReady { return _appOpenAd != nil; }

// ── MREC (spec §7.7 — ScreenToMRecPosAdmob KHÔNG safe-area) ──────────────────

- (void)loadMRec {
    if (_mrecCreated) return; // create-once
    FGAdmobAdUnit *u = _config.mrec;
    if (!_isInitialized || !u.isUsable) return;
    __weak FGAdmobAdsProvider *weakSelf = self;
    [FGMainThreadDispatcher enqueue:^{
        UIWindow *win = [FGViewControllerTracker keyWindow];
        UIViewController *vc = [FGViewControllerTracker topViewController];
        if (win == nil || vc == nil) return;
        GADBannerView *view = [[GADBannerView alloc] initWithAdSize:GADAdSizeMediumRectangle];
        NSString *unitId = u.adUnitId;
        view.adUnitID = unitId;
        view.rootViewController = vc;
        // Android: (300*density)x(250*density) px Gravity TOP|START — iOS frame point 300x250 top-left.
        view.frame = CGRectMake(0, 0, 300, 250);
        view.hidden = YES;
        FGAdmobBannerProxy *proxy = [FGAdmobBannerProxy new];
        proxy.onLoaded = ^{
            FGAdmobAdsProvider *s = weakSelf; if (!s) return;
            s->_mrecLoaded = YES;
            // MRec request_count = 0 (spec §8).
            FGAdmobLogRequest(s->_mrecCtx, FGConstValue.Mrec, YES, @"",
                              FGAdmobSecs(s->_mrecLoadStart), 0, unitId);
            FGPublicEvent::MRec.Loaded.invoke(
                FGAdmobAdInfo(FGConstValue.Mrec, s->_mrecCtx.location, unitId));
        };
        proxy.onLoadFailed = ^(NSError *error) {
            FGAdmobAdsProvider *s = weakSelf; if (!s) return;
            s->_mrecLoaded = NO;
            FGAdmobLogRequest(s->_mrecCtx, FGConstValue.Mrec, NO,
                              [FGAdmobError mapToReason:error.code],
                              FGAdmobSecs(s->_mrecLoadStart), 0, unitId);
            FGPublicEvent::MRec.FailedToLoad.invoke(
                FGAdmobErrInfo(unitId, FGConstValue.Mrec, s->_mrecCtx.location));
            // retry gọi reloadMRec (loadMRec bị gate create-once) — mirror Kotlin.
            [FGMaxRetry retryLoadAd:s->_mrecRetryCount format:@"admob_mrec"
                         loadAction:^{ [weakSelf reloadMRec]; }];
            s->_mrecRetryCount++;
        };
        proxy.onClicked = ^{
            FGAdmobAdsProvider *s = weakSelf; if (!s) return;
            [FGAdEventLogger adClick:FGConstValue.Mrec platform:FGConstValue.admob_sdk adNetwork:kAdmobNetwork];
            FGPublicEvent::MRec.Clicked.invoke(
                FGAdmobAdInfo(FGConstValue.Mrec, s->_mrecCtx.location, unitId));
        };
        view.paidEventHandler = ^(GADAdValue *av) {
            FGAdmobAdsProvider *s = weakSelf; if (!s) return;
            [s onPaid:av format:FGConstValue.Mrec ctx:s->_mrecCtx isInterstitial:NO
               unitId:unitId afSend:nil];
            FGPublicEvent::MRec.RevenuePaid.invoke(
                FGAdmobAdInfo(FGConstValue.Mrec, s->_mrecCtx.location, unitId, av.value.doubleValue));
        };
        view.delegate = proxy;
        [win addSubview:view];
        self->_mrecProxy = proxy;
        self->_mrecView = view;
        self->_mrecCreated = YES;
        self->_mrecLoadStart = CACurrentMediaTime();
        [view loadRequest:[GADRequest request]];
    }];
}

/** reload khi retry (view đã tạo) — mirror reloadMRec Kotlin. */
- (void)reloadMRec {
    [FGMainThreadDispatcher enqueue:^{
        self->_mrecLoadStart = CACurrentMediaTime();
        [self->_mrecView loadRequest:[GADRequest request]];
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
        GADBannerView *v = self->_mrecView;
        if (v == nil) return;
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
        GADBannerView *v = self->_mrecView;
        if (v == nil) return;
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
        GADBannerView *v = self->_mrecView;
        if (v == nil) return;
        [self positionPreset:v adPosition:adPosition];
        v.hidden = NO;
        [self mrecShown:placement];
    }];
}

- (void)mrecShown:(NSString *)placement {
    FGPublicEvent::MRec.Shown.invoke(
        FGAdmobErrInfo(_config.mrec.adUnitId ?: @"", FGConstValue.Mrec, placement));
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
        if (self->_mrecView != nil) self->_mrecView.hidden = YES;
        // Kotlin: Hidden invoke cả khi mrecView null — mirror.
        FGPublicEvent::MRec.Hidden.invoke(
            FGAdmobErrInfo(self->_config.mrec.adUnitId ?: @"", FGConstValue.Mrec,
                           self->_mrecCtx.location));
    }];
}

- (void)destroyMRec {
    [FGMainThreadDispatcher enqueue:^{
        if (self->_mrecView != nil) [self->_mrecView removeFromSuperview];
        // Android AdView.destroy() — iOS không có API tương đương, ARC giải phóng khi nil.
        self->_mrecView = nil;
        self->_mrecCreated = NO;
        self->_mrecLoaded = NO;
    }];
}

- (BOOL)isMRecReady { return _mrecView != nil && _mrecCreated; }

// ── MREC positioning (spec §7.7) — Kotlin translation px = dp*density; iOS frame origin = point ──

- (void)positionCentered:(GADBannerView *)v {
    CGSize s = UIScreen.mainScreen.bounds.size;
    CGRect f = v.frame;
    f.origin.x = (s.width - 300) / 2;
    f.origin.y = (s.height - 250) / 2;
    v.frame = f;
}

/**
 * spec §7.7 — ScreenToMRecPosAdmob (KHÔNG safe-area, khác MAX). screenPos = px gốc dưới-trái (Unity).
 * FGUtils trả point góc trên-trái MREC (Kotlin: translation px = resultDp * density).
 */
- (void)positionAt:(GADBannerView *)v screenPos:(CGPoint)screenPos {
    CGPoint pt = [FGUtils ScreenToMRecPosAdmob:screenPos];
    CGRect f = v.frame;
    f.origin = pt;
    v.frame = f;
}

/** Preset AdViewPosition (Unity enum order): 0=TopLeft..8=BottomRight, 4=Centered (mirror map Kotlin). */
- (void)positionPreset:(GADBannerView *)v adPosition:(NSInteger)adPosition {
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

#else // !GOOGLE_MOBILE_ADS_ENABLE

// Stub khi tắt Google Mobile Ads (README guard third-party): provider không bao giờ initialized —
// hành vi mirror nhánh !isInitialized của Kotlin (Inter show → invoke closed; còn lại drop; ready=NO).

@implementation FGAdmobAdsProvider {
    FGSignal _onInitialized;
    FGSignal1<NSString *> _onInitializationFailed;
    FGAdmobConfig *_config;
    BOOL _isBackfill;
}

- (instancetype)initWithConfig:(FGAdmobConfig *)config isBackfill:(BOOL)isBackfill {
    if ((self = [super init])) { _config = config; _isBackfill = isBackfill; }
    return self;
}

- (FGSignal &)onInitialized { return _onInitialized; }
- (FGSignal1<NSString *> &)onInitializationFailed { return _onInitializationFailed; }

- (void)initialize:(FGAdsOrchestrator *)orchestrator {
    NSLog(@"[%@] GOOGLE_MOBILE_ADS_ENABLE=0 → AdMob provider disabled", TAG);
    _onInitializationFailed.invoke(@"GOOGLE_MOBILE_ADS_ENABLE=0");
}

- (void)loadInterstitial {}
- (void)showInterstitial:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
                  params:(FGParams)params onInterstitialClosed:(void (^)(void))onInterstitialClosed {
    FGPublicEvent::Interstitial.Request.invoke(placement);
    if (onInterstitialClosed) onInterstitialClosed(); // mirror nhánh !isInitialized
}
- (BOOL)isInterstitialReady { return NO; }

- (void)loadRewarded {}
- (void)showRewarded:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
          onRewarded:(void (^)(void))onRewarded params:(FGParams)params {
    FGPublicEvent::Rewarded.Request.invoke(placement);
}
- (BOOL)isRewardedReady { return NO; }

- (void)loadBanner {}
- (void)showBanner:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
            params:(FGParams)params {
    FGPublicEvent::Banner.Request.invoke(placement);
}
- (void)hideBanner {}
- (BOOL)isBannerReady { return NO; }

- (void)loadAppOpen {}
- (void)showAppOpen:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
             params:(FGParams)params {
    FGPublicEvent::AppOpen.Request.invoke(placement);
}
- (BOOL)isAppOpenReady { return NO; }

- (void)loadMRec {}
- (void)showMRec:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
          params:(FGParams)params {
    FGPublicEvent::MRec.Request.invoke(placement);
}
- (void)showMRecAt:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
         screenPos:(CGPoint)screenPos params:(FGParams)params {
    FGPublicEvent::MRec.Request.invoke(placement);
}
- (void)showMRecPreset:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
            adPosition:(NSInteger)adPosition params:(FGParams)params {
    FGPublicEvent::MRec.Request.invoke(placement);
}
- (void)updateMRecPosition:(CGPoint)screenPos {}
- (void)updateMRecPositionPreset:(NSInteger)adPosition {}
- (void)destroyMRec {}
- (void)hideMRec {}
- (BOOL)isMRecReady { return NO; }

@end

#endif // GOOGLE_MOBILE_ADS_ENABLE
