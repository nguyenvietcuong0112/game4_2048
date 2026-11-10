//
//  FGAdsOrchestrator.h — mirror KA/ads/FGAdsOrchestrator.kt (spec §7.2):
//  state machine + guard + route xuống provider.
//
//  ⚠️ Quirk (spec §16-1): dù Unity có `FGAdsQueue` và log "Queued", orchestrator KHÔNG BAO GIỜ enqueue.
//     Request lúc đang Initializing bị DROP, không defer. `_queue` luôn rỗng — ở đây ta không dựng queue.
//
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "IFGAdsProvider.h"
#import "FGAdsState.h"
#import "../config/FGConfigModels.h"
#import "../util/FGSDKDefines.h"

NS_ASSUME_NONNULL_BEGIN

@interface FGAdsOrchestrator : NSObject

/// Kotlin `@Volatile var state private set` → atomic readonly.
@property (atomic, readonly) FGAdsState state;

- (instancetype)initWithProvider:(id<IFGAdsProvider>)provider
                        platform:(FGPlatformConfig *)platform NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)initialize;

// ── Route (spec §7.2 guard) ───────────────────────────────────────────────

/// ⚠️ !CanProcess → invoke callback complete rồi return (guard riêng Interstitial).
- (void)showInterstitial:(NSString *)placement
                playMode:(NSString *)playMode
            currentLevel:(double)currentLevel
                  params:(FGParams _Nullable)params
                onClosed:(void (^_Nullable)(void))onClosed;

/// ⚠️ !CanProcess → return (KHÔNG callback); !IsRewardedReady → return (guard riêng Rewarded).
- (void)showRewarded:(NSString *)placement
            playMode:(NSString *)playMode
        currentLevel:(double)currentLevel
          onRewarded:(void (^_Nullable)(void))onRewarded
              params:(FGParams _Nullable)params;

- (void)loadRewarded;
- (BOOL)isRewardedReady;

- (void)showBanner:(NSString *)placement
          playMode:(NSString *)playMode
      currentLevel:(double)currentLevel
            params:(FGParams _Nullable)params;
- (void)hideBanner;

- (void)showAppOpen:(NSString *)placement
           playMode:(NSString *)playMode
       currentLevel:(double)currentLevel
             params:(FGParams _Nullable)params;

- (void)loadMRec;
- (void)showMRec:(NSString *)placement
        playMode:(NSString *)playMode
    currentLevel:(double)currentLevel
          params:(FGParams _Nullable)params;
- (void)showMRecAt:(NSString *)placement
          playMode:(NSString *)playMode
      currentLevel:(double)currentLevel
         screenPos:(CGPoint)screenPos
            params:(FGParams _Nullable)params;
- (void)showMRecPreset:(NSString *)placement
              playMode:(NSString *)playMode
          currentLevel:(double)currentLevel
            adPosition:(NSInteger)adPosition
                params:(FGParams _Nullable)params;
- (void)updateMRecPosition:(CGPoint)screenPos;
- (void)updateMRecPositionPreset:(NSInteger)adPosition;
- (void)hideMRec;
- (void)destroyMRec;
- (BOOL)isMRecReady;

@end

NS_ASSUME_NONNULL_END
