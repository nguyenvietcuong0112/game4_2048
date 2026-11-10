//
//  FGAdsOrchestrator.mm — mirror KA/ads/FGAdsOrchestrator.kt (spec §7.2).
//
#import "FGAdsOrchestrator.h"
#import "../event/FGEvent.h"

static NSString *const TAG = @"FGAdsOrch";

@interface FGAdsOrchestrator ()
@property (atomic, readwrite) FGAdsState state;
- (void)onProviderInitialized;
- (void)onProviderInitFailed:(NSString *)reason;
- (void)onNetworkRestored;
- (BOOL)canProcessRequest;
@end

@implementation FGAdsOrchestrator {
    id<IFGAdsProvider> _provider;
    FGPlatformConfig *_platform; // unused — giữ mirror Kotlin (@Suppress("unused"))
}

- (instancetype)initWithProvider:(id<IFGAdsProvider>)provider platform:(FGPlatformConfig *)platform {
    if ((self = [super init])) {
        _provider = provider;
        _platform = platform;
        _state = FGAdsStateNotInitialized;
    }
    return self;
}

- (void)initialize {
    self.state = FGAdsStateInitializing;
    // Signal giữ handler lâu dài → __weak tránh retain cycle provider↔orchestrator (README).
    __weak FGAdsOrchestrator *weakSelf = self;
    [_provider onInitialized].add([weakSelf] { [weakSelf onProviderInitialized]; });
    [_provider onInitializationFailed].add([weakSelf](NSString *reason) { [weakSelf onProviderInitFailed:reason]; });
    [_provider initialize:self];
}

- (void)onProviderInitialized {
    self.state = FGAdsStateReady;
    // _queue.Flush() — no-op (quirk §16-1: queue luôn rỗng).
    __weak FGAdsOrchestrator *weakSelf = self;
    FGEvent::Network::OnNetworkRestored.add([weakSelf] { [weakSelf onNetworkRestored]; });
    NSLog(@"[%@] provider initialized → Ready", TAG);
}

- (void)onProviderInitFailed:(NSString *)reason {
    self.state = FGAdsStateDisabled;
    NSLog(@"[%@] provider init failed → Disabled: %@", TAG, reason);
}

/** spec §7.2 — Ready thì reload format nào chưa ready (thứ tự Inter, Reward, AppOpen, MRec) rồi LUÔN LoadBanner. */
- (void)onNetworkRestored {
    if (self.state != FGAdsStateReady) return;
    if (![_provider isInterstitialReady]) [_provider loadInterstitial];
    if (![_provider isRewardedReady]) [_provider loadRewarded];
    if (![_provider isAppOpenReady]) [_provider loadAppOpen];
    if (![_provider isMRecReady]) [_provider loadMRec];
    [_provider loadBanner]; // luôn load banner
}

/** spec §7.2 — Disabled/Initializing/!=Ready → NO; Ready → YES. Initializing log "Queued" nhưng KHÔNG enqueue. */
- (BOOL)canProcessRequest {
    switch (self.state) {
        case FGAdsStateDisabled: return NO;
        case FGAdsStateInitializing: NSLog(@"[%@] Queued", TAG); return NO; // ⚠️ chỉ log, KHÔNG enqueue (quirk §16-1)
        case FGAdsStateReady: return YES;
        default: return NO;
    }
}

// ── Route (spec §7.2 guard) ───────────────────────────────────────────────

- (void)showInterstitial:(NSString *)placement
                playMode:(NSString *)playMode
            currentLevel:(double)currentLevel
                  params:(FGParams _Nullable)params
                onClosed:(void (^_Nullable)(void))onClosed {
    if (![self canProcessRequest]) { if (onClosed) onClosed(); return; }
    [_provider showInterstitial:placement playMode:playMode currentLevel:currentLevel
                         params:params onInterstitialClosed:onClosed];
}

- (void)showRewarded:(NSString *)placement
            playMode:(NSString *)playMode
        currentLevel:(double)currentLevel
          onRewarded:(void (^_Nullable)(void))onRewarded
              params:(FGParams _Nullable)params {
    if (![self canProcessRequest]) return;
    if (![_provider isRewardedReady]) return;
    [_provider showRewarded:placement playMode:playMode currentLevel:currentLevel
                 onRewarded:onRewarded params:params];
}

- (void)loadRewarded {
    if ([self canProcessRequest]) [_provider loadRewarded];
}

- (BOOL)isRewardedReady {
    return self.state == FGAdsStateReady ? [_provider isRewardedReady] : NO;
}

- (void)showBanner:(NSString *)placement
          playMode:(NSString *)playMode
      currentLevel:(double)currentLevel
            params:(FGParams _Nullable)params {
    if ([self canProcessRequest]) [_provider showBanner:placement playMode:playMode currentLevel:currentLevel params:params];
}

- (void)hideBanner {
    if ([self canProcessRequest]) [_provider hideBanner];
}

- (void)showAppOpen:(NSString *)placement
           playMode:(NSString *)playMode
       currentLevel:(double)currentLevel
             params:(FGParams _Nullable)params {
    if ([self canProcessRequest]) [_provider showAppOpen:placement playMode:playMode currentLevel:currentLevel params:params];
}

- (void)loadMRec {
    if ([self canProcessRequest]) [_provider loadMRec];
}

- (void)showMRec:(NSString *)placement
        playMode:(NSString *)playMode
    currentLevel:(double)currentLevel
          params:(FGParams _Nullable)params {
    if ([self canProcessRequest]) [_provider showMRec:placement playMode:playMode currentLevel:currentLevel params:params];
}

- (void)showMRecAt:(NSString *)placement
          playMode:(NSString *)playMode
      currentLevel:(double)currentLevel
         screenPos:(CGPoint)screenPos
            params:(FGParams _Nullable)params {
    if ([self canProcessRequest]) [_provider showMRecAt:placement playMode:playMode currentLevel:currentLevel screenPos:screenPos params:params];
}

- (void)showMRecPreset:(NSString *)placement
              playMode:(NSString *)playMode
          currentLevel:(double)currentLevel
            adPosition:(NSInteger)adPosition
                params:(FGParams _Nullable)params {
    if ([self canProcessRequest]) [_provider showMRecPreset:placement playMode:playMode currentLevel:currentLevel adPosition:adPosition params:params];
}

- (void)updateMRecPosition:(CGPoint)screenPos {
    if ([self canProcessRequest]) [_provider updateMRecPosition:screenPos];
}

- (void)updateMRecPositionPreset:(NSInteger)adPosition {
    if ([self canProcessRequest]) [_provider updateMRecPositionPreset:adPosition];
}

- (void)hideMRec {
    if ([self canProcessRequest]) [_provider hideMRec];
}

- (void)destroyMRec {
    if ([self canProcessRequest]) [_provider destroyMRec];
}

- (BOOL)isMRecReady {
    return self.state == FGAdsStateReady ? [_provider isMRecReady] : NO;
}

@end
