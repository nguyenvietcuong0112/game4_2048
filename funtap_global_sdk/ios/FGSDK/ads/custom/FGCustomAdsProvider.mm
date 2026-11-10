//
//  FGCustomAdsProvider.mm — mirror KA/ads/custom/FGCustomAdsProvider.kt (spec §7.8/§16-8).
//  Không marshal ở đây — callback đã được 2 provider con marshal FGMainThreadDispatcher (mirror Kotlin).
//
#import "FGCustomAdsProvider.h"
#import "../FGAdsOrchestrator.h"
#import "../admob/FGAdmobAdsProvider.h"
#import "../admob/FGAdmobConfig.h"
#import "../max/FGMaxAdsProvider.h"
#import "../../config/FGConfigController.h"
#import "../../config/FGEnums.h"

static NSString *const TAG = @"FGCustom";

@interface FGCustomAdsProvider ()
- (id<IFGAdsProvider>)primary;
- (FGBackfillConfig *_Nullable)backfill;
- (BOOL)isMaxOnlyCountry;
- (BOOL)hasAdmobBackfill;
- (BOOL)isBackfillReady:(FGBackfillRule *_Nullable)rule;
- (void)onMaxReady;
- (void)preloadAppOpenWhenReady;
- (void)loadBackfillFor:(FGBackfillRule *_Nullable)rule;
@end

@implementation FGCustomAdsProvider {
    FGSignal _onInitialized;
    FGSignal1<NSString *> _onInitializationFailed;

    FGCustomAdsMediationConfig *_adsConfig; // nullable (Kotlin adsConfig = platform.main_ads_config)
    BOOL _primaryIsMax;
    FGMaxAdsProvider *_maxProvider;
    FGAdmobAdsProvider *_admobProvider;
}

- (instancetype)initWithConfig:(FGCustomAdsMediationConfig *)config {
    if ((self = [super init])) {
        _adsConfig = config;
        // Kotlin: FGAdsMediationProvider.from(adsConfig?.primaryProvider ?: 0) == Max.
        _primaryIsMax = FGAdsMediationProviderFrom(config != nil ? config.primaryProvider : 0)
                        == FGAdsMediationProviderMax;
        _maxProvider = [[FGMaxAdsProvider alloc] initWithConfig:config];
        // adsConfig null (degenerate) → config default (mọi slot rỗng → không load gì).
        _admobProvider = [[FGAdmobAdsProvider alloc]
            initWithConfig:[FGAdmobConfigBuilder buildBackfill:(config ?: [[FGCustomAdsMediationConfig alloc] init])]
                isBackfill:YES];
    }
    return self;
}

- (FGSignal &)onInitialized { return _onInitialized; }
- (FGSignal1<NSString *> &)onInitializationFailed { return _onInitializationFailed; }

/** primaryProvider=Max → MAX là Primary; else AdMob. */
- (id<IFGAdsProvider>)primary { return _primaryIsMax ? (id<IFGAdsProvider>)_maxProvider : (id<IFGAdsProvider>)_admobProvider; }

/** Kotlin `backfill get() = adsConfig?.backfillConfig` — nil-safe qua nil messaging. */
- (FGBackfillConfig *)backfill { return _adsConfig.backfillConfig; }

// ── Gate (dựa CountryCode LIVE từ MAX) ───────────────────────────────────────

/** spec §7.8 — primary=Max && CountryCode!=nil && maxOnlyCountries chứa CountryCode (OrdinalIgnoreCase). */
- (BOOL)isMaxOnlyCountry {
    if (!_primaryIsMax) return NO;
    NSString *cc = _maxProvider.liveCountryCode;
    if (cc == nil) return NO;
    // maxOnlyCountries là field TOP-LEVEL (FGMainConfig), không thuộc platform — lấy qua FGConfigController.
    NSArray<NSString *> *list = [FGConfigController mainConfig].maxOnlyCountries;
    if (list == nil) return NO;
    for (NSString *item in list) {
        if ([item caseInsensitiveCompare:cc] == NSOrderedSame) return YES;
    }
    return NO;
}

/** spec §7.8 — primary=Max && !IsMaxOnlyCountry. NO → tắt sạch backfill (MAX-only). */
- (BOOL)hasAdmobBackfill { return _primaryIsMax && ![self isMaxOnlyCountry]; }

/** spec §7.8 — backfill sẵn sàng: rule.Enable && AdMob provider ready cho format = rule.AdType. */
- (BOOL)isBackfillReady:(FGBackfillRule *)rule {
    if (rule == nil || !rule.Enable) return NO;
    switch (FGBackfillAdTypeFrom(rule.AdType)) {
        case FGBackfillAdTypeInterstitial: return [_admobProvider isInterstitialReady];
        case FGBackfillAdTypeRewarded:     return [_admobProvider isRewardedReady];
        case FGBackfillAdTypeBanner:       return [_admobProvider isBannerReady];
        case FGBackfillAdTypeAppOpen:      return [_admobProvider isAppOpenReady];
        case FGBackfillAdTypeMRec:         return [_admobProvider isMRecReady];
    }
    return NO;
}

// ── Init ─────────────────────────────────────────────────────────────────────

- (void)initialize:(FGAdsOrchestrator *)orchestrator {
    // Custom onInitialized drive off MAX (spec §7.8). MAX primary tự SetReady(Ads); AdMob backfill im lặng.
    __weak FGCustomAdsProvider *weakSelf = self;
    [_maxProvider onInitialized].add([weakSelf] { [weakSelf onMaxReady]; });
    [_maxProvider onInitializationFailed].add([weakSelf](NSString *reason) {
        FGCustomAdsProvider *s = weakSelf; if (!s) return;
        s->_onInitializationFailed.invoke(reason);
    });
    [_maxProvider initialize:orchestrator];
    [_admobProvider initialize:orchestrator];
}

- (void)onMaxReady {
    NSLog(@"[%@] MAX ready → Custom onInitialized (country=%@, maxOnly=%d, backfill=%d)",
          TAG, _maxProvider.liveCountryCode, [self isMaxOnlyCountry], [self hasAdmobBackfill]);
    _onInitialized.invoke();
    [self preloadAppOpenWhenReady];
}

/** spec §7.8 — PreloadAppOpenWhenReady: AppOpen route theo country (max-only→MAX, else→AdMob). */
- (void)preloadAppOpenWhenReady {
    if ([self isMaxOnlyCountry]) [_maxProvider loadAppOpen];
    else if ([self hasAdmobBackfill]) [_admobProvider loadAppOpen];
    else [_maxProvider loadAppOpen];
}

// ── Load (delegate primary + backfill theo AdType) ───────────────────────────

- (void)loadInterstitial {
    [self.primary loadInterstitial];
    if ([self hasAdmobBackfill]) [self loadBackfillFor:self.backfill.Interstitial];
}

- (void)loadRewarded {
    [self.primary loadRewarded];
    if ([self hasAdmobBackfill]) [self loadBackfillFor:self.backfill.Rewarded];
}

- (void)loadBanner {
    [self.primary loadBanner];
    if ([self hasAdmobBackfill]) [self loadBackfillFor:self.backfill.Banner];
}

- (void)loadAppOpen {
    // AppOpen route theo country (spec §7.8): max-only→MAX; else→AdMob.
    if ([self isMaxOnlyCountry]) [_maxProvider loadAppOpen];
    else if ([self hasAdmobBackfill]) [_admobProvider loadAppOpen];
    else [self.primary loadAppOpen];
}

- (void)loadMRec {
    [self.primary loadMRec];
    if ([self hasAdmobBackfill]) [self loadBackfillFor:self.backfill.MRec];
}

/** Load AdMob slot theo AdType của rule (1 rule route vào slot AdMob khác tên — spec §3.5). */
- (void)loadBackfillFor:(FGBackfillRule *)rule {
    if (rule == nil || !rule.Enable) return;
    switch (FGBackfillAdTypeFrom(rule.AdType)) {
        case FGBackfillAdTypeInterstitial: [_admobProvider loadInterstitial]; break;
        case FGBackfillAdTypeRewarded:     [_admobProvider loadRewarded]; break;
        case FGBackfillAdTypeBanner:       [_admobProvider loadBanner]; break;
        case FGBackfillAdTypeAppOpen:      [_admobProvider loadAppOpen]; break;
        case FGBackfillAdTypeMRec:         [_admobProvider loadMRec]; break;
    }
}

// ── Interstitial (primary → backfill theo AdType; MRec/Banner non-modal invoke onClosed ngay) ──

- (void)showInterstitial:(NSString *)placement
                playMode:(NSString *)playMode
            currentLevel:(double)currentLevel
                  params:(FGParams)params
    onInterstitialClosed:(void (^)(void))onInterstitialClosed {
    if ([self.primary isInterstitialReady]) {
        [self.primary showInterstitial:placement playMode:playMode currentLevel:currentLevel
                                params:params onInterstitialClosed:onInterstitialClosed];
        return;
    }
    FGBackfillRule *rule = self.backfill.Interstitial;
    if ([self hasAdmobBackfill] && [self isBackfillReady:rule]) {
        switch (FGBackfillAdTypeFrom(rule.AdType)) {
            case FGBackfillAdTypeInterstitial:
                [_admobProvider showInterstitial:placement playMode:playMode currentLevel:currentLevel
                                          params:params onInterstitialClosed:onInterstitialClosed];
                break;
            case FGBackfillAdTypeMRec:
                [_admobProvider showMRec:placement playMode:playMode currentLevel:currentLevel params:params];
                if (onInterstitialClosed) onInterstitialClosed(); // non-modal → callback ngay
                break;
            case FGBackfillAdTypeBanner:
                [_admobProvider showBanner:placement playMode:playMode currentLevel:currentLevel params:params];
                if (onInterstitialClosed) onInterstitialClosed();
                break;
            default:
                if (onInterstitialClosed) onInterstitialClosed();
                break;
        }
        return;
    }
    // Không backfill → để primary xử lý not-ready path (invoke onClosed).
    [self.primary showInterstitial:placement playMode:playMode currentLevel:currentLevel
                            params:params onInterstitialClosed:onInterstitialClosed];
}

- (BOOL)isInterstitialReady {
    return [self.primary isInterstitialReady]
        || ([self hasAdmobBackfill] && [self isBackfillReady:self.backfill.Interstitial]);
}

// ── Rewarded ─────────────────────────────────────────────────────────────────

- (void)showRewarded:(NSString *)placement
            playMode:(NSString *)playMode
        currentLevel:(double)currentLevel
          onRewarded:(void (^)(void))onRewarded
              params:(FGParams)params {
    if ([self.primary isRewardedReady]) {
        [self.primary showRewarded:placement playMode:playMode currentLevel:currentLevel
                        onRewarded:onRewarded params:params];
        return;
    }
    FGBackfillRule *rule = self.backfill.Rewarded;
    if ([self hasAdmobBackfill] && [self isBackfillReady:rule]) {
        [_admobProvider showRewarded:placement playMode:playMode currentLevel:currentLevel
                          onRewarded:onRewarded params:params];
        return;
    }
    [self.primary showRewarded:placement playMode:playMode currentLevel:currentLevel
                    onRewarded:onRewarded params:params];
}

- (BOOL)isRewardedReady {
    return [self.primary isRewardedReady]
        || ([self hasAdmobBackfill] && [self isBackfillReady:self.backfill.Rewarded]);
}

// ── Banner (primary + backfill; hide cả hai) ─────────────────────────────────

- (void)showBanner:(NSString *)placement
          playMode:(NSString *)playMode
      currentLevel:(double)currentLevel
            params:(FGParams)params {
    [self.primary showBanner:placement playMode:playMode currentLevel:currentLevel params:params];
    if ([self hasAdmobBackfill] && [self isBackfillReady:self.backfill.Banner])
        [_admobProvider showBanner:placement playMode:playMode currentLevel:currentLevel params:params];
}

- (void)hideBanner {
    [self.primary hideBanner];
    if ([self hasAdmobBackfill]) [_admobProvider hideBanner];
}

// ── AppOpen (max-only→MAX, else→AdMob) ───────────────────────────────────────

- (void)showAppOpen:(NSString *)placement
           playMode:(NSString *)playMode
       currentLevel:(double)currentLevel
             params:(FGParams)params {
    if ([self isMaxOnlyCountry])
        [_maxProvider showAppOpen:placement playMode:playMode currentLevel:currentLevel params:params];
    else if ([self hasAdmobBackfill])
        [_admobProvider showAppOpen:placement playMode:playMode currentLevel:currentLevel params:params];
    else
        [self.primary showAppOpen:placement playMode:playMode currentLevel:currentLevel params:params];
}

- (BOOL)isAppOpenReady {
    if ([self isMaxOnlyCountry]) return [_maxProvider isAppOpenReady];
    if ([self hasAdmobBackfill]) return [_admobProvider isAppOpenReady];
    return [self.primary isAppOpenReady];
}

// ── MREC (primary → backfill AdMob MRec) ─────────────────────────────────────

- (void)showMRec:(NSString *)placement
        playMode:(NSString *)playMode
    currentLevel:(double)currentLevel
          params:(FGParams)params {
    if ([self.primary isMRecReady])
        [self.primary showMRec:placement playMode:playMode currentLevel:currentLevel params:params];
    else if ([self hasAdmobBackfill] && [self isBackfillReady:self.backfill.MRec])
        [_admobProvider showMRec:placement playMode:playMode currentLevel:currentLevel params:params];
    else
        [self.primary showMRec:placement playMode:playMode currentLevel:currentLevel params:params];
}

- (void)showMRecAt:(NSString *)placement
          playMode:(NSString *)playMode
      currentLevel:(double)currentLevel
         screenPos:(CGPoint)screenPos
            params:(FGParams)params {
    if ([self.primary isMRecReady])
        [self.primary showMRecAt:placement playMode:playMode currentLevel:currentLevel screenPos:screenPos params:params];
    else if ([self hasAdmobBackfill] && [self isBackfillReady:self.backfill.MRec])
        [_admobProvider showMRecAt:placement playMode:playMode currentLevel:currentLevel screenPos:screenPos params:params];
    else
        [self.primary showMRecAt:placement playMode:playMode currentLevel:currentLevel screenPos:screenPos params:params];
}

- (void)showMRecPreset:(NSString *)placement
              playMode:(NSString *)playMode
          currentLevel:(double)currentLevel
            adPosition:(NSInteger)adPosition
                params:(FGParams)params {
    if ([self.primary isMRecReady])
        [self.primary showMRecPreset:placement playMode:playMode currentLevel:currentLevel adPosition:adPosition params:params];
    else if ([self hasAdmobBackfill] && [self isBackfillReady:self.backfill.MRec])
        [_admobProvider showMRecPreset:placement playMode:playMode currentLevel:currentLevel adPosition:adPosition params:params];
    else
        [self.primary showMRecPreset:placement playMode:playMode currentLevel:currentLevel adPosition:adPosition params:params];
}

- (void)updateMRecPosition:(CGPoint)screenPos {
    [self.primary updateMRecPosition:screenPos];
    if ([self hasAdmobBackfill]) [_admobProvider updateMRecPosition:screenPos];
}

- (void)updateMRecPositionPreset:(NSInteger)adPosition {
    [self.primary updateMRecPositionPreset:adPosition];
    if ([self hasAdmobBackfill]) [_admobProvider updateMRecPositionPreset:adPosition];
}

- (void)hideMRec {
    [self.primary hideMRec];
    if ([self hasAdmobBackfill]) [_admobProvider hideMRec];
}

- (void)destroyMRec {
    [self.primary destroyMRec];
    if ([self hasAdmobBackfill]) [_admobProvider destroyMRec];
}

- (BOOL)isMRecReady {
    return [self.primary isMRecReady]
        || ([self hasAdmobBackfill] && [self isBackfillReady:self.backfill.MRec]);
}

@end
