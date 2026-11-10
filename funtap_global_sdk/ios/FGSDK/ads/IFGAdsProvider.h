//
//  IFGAdsProvider.h — mirror KA/ads/IFGAdsProvider.kt (spec §7.3).
//  `event Action OnInitialized` → FGSignal (trả C++ reference — hợp lệ trong ObjC++, mọi consumer là .mm).
//  Kotlin FGVector2 → CGPoint.
//
#pragma once
#import <UIKit/UIKit.h>
#import "../event/FGSignal.h"
#import "../util/FGSDKDefines.h"

NS_ASSUME_NONNULL_BEGIN

@class FGAdsOrchestrator;

@protocol IFGAdsProvider <NSObject>

- (FGSignal &)onInitialized;
- (FGSignal1<NSString *> &)onInitializationFailed;

- (void)initialize:(FGAdsOrchestrator *)orchestrator;

// Interstitial
- (void)loadInterstitial;
- (void)showInterstitial:(NSString *)placement
                playMode:(NSString *)playMode
            currentLevel:(double)currentLevel
                  params:(FGParams _Nullable)params
    onInterstitialClosed:(void (^_Nullable)(void))onInterstitialClosed;
- (BOOL)isInterstitialReady;

// Rewarded
- (void)showRewarded:(NSString *)placement
            playMode:(NSString *)playMode
        currentLevel:(double)currentLevel
          onRewarded:(void (^_Nullable)(void))onRewarded
              params:(FGParams _Nullable)params;
- (void)loadRewarded;
- (BOOL)isRewardedReady;

// Banner
- (void)showBanner:(NSString *)placement
          playMode:(NSString *)playMode
      currentLevel:(double)currentLevel
            params:(FGParams _Nullable)params;
- (void)hideBanner;
- (void)loadBanner;

// AppOpen
- (void)loadAppOpen;
- (void)showAppOpen:(NSString *)placement
           playMode:(NSString *)playMode
       currentLevel:(double)currentLevel
             params:(FGParams _Nullable)params;
- (BOOL)isAppOpenReady;

// MREC
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
- (void)destroyMRec;
- (void)hideMRec;
- (BOOL)isMRecReady;

@end

NS_ASSUME_NONNULL_END
