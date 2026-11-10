//
//  FGSDKIOS.h — entry point + facade công khai. Mirror 1:1:
//    KA/FGSDK.kt (init flow spec §2) + FGSDK{Ads,Tracking,RemoteConfig,IAP,Deeplink}.kt (spec §4).
//  Kotlin `object FGSDK` + extension fun → ObjC class chỉ có class methods (+). Tên method GIỮ
//  VERBATIM theo Kotlin (LogEvent, ShowInterstitial, GetRemoteConfigInt...) để mirror rõ ràng.
//  ⚠️ Header ObjC++ (chứa std::vector, FGParams, CGPoint) — chỉ include từ file .mm.
//
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "ads/OpenAppAction.h"
#import "event/FGEventTypes.h"     // ProviderType
#import "util/FGSDKDefines.h"      // FGParams
#include <vector>

#if !defined(__OBJC__)
#error "FGSDKIOS.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGSDKIOS : NSObject

// ── Vòng đời / core (spec §2) ────────────────────────────────────────────────
/// = FGSDK.init(context) bên Android. iOS không cần Context (README adaptation).
/// Gọi 1 lần lúc app khởi động (AppDelegate / FGBridge.install).
+ (void)initSDK;

/// spec §2 — FGSDK.isInit (bắn init_sdk xong = YES).
@property (class, nonatomic, readonly) BOOL isInit;

/// FGSDK.SDK_VERSION = FGConstValue.SdkVersion ("3.2.6").
@property (class, nonatomic, readonly) NSString *sdkVersion;

/// Mở **Mediation Debugger** của AppLovin MAX (mirror `MaxSdk.ShowMediationDebugger()` bên Unity,
/// và `FGSDK.showMediationDebugger()` bên Android). QA soi adapter/ad unit/waterfall trên máy thật.
/// KHÔNG phải API phát hành. MAX chưa init thì bỏ qua (chỉ log), không crash.
+ (void)showMediationDebugger;

/// spec §4/§7.5 — FGSDK.openAppAction. Nguồn chân lý ở FGAds; đây chỉ delegate.
@property (class, nonatomic) OpenAppAction openAppAction;

// ── §4.1 Tracking / Analytics ────────────────────────────────────────────────
/// ⚠️ Overload KHÔNG chỉ định provider = CHỈ Firebase (quirk 9 / spec §4.1).
+ (void)LogEvent:(NSString *)eventName;
+ (void)LogEvent:(NSString *)eventName parameters:(FGParams)parameters;
+ (void)LogEvent:(NSString *)eventName provider:(ProviderType)provider;
+ (void)LogEvent:(NSString *)eventName providers:(std::vector<ProviderType>)providers;
+ (void)LogEvent:(NSString *)eventName parameters:(FGParams)parameters provider:(ProviderType)provider;
+ (void)LogEvent:(NSString *)eventName parameters:(FGParams)parameters providers:(std::vector<ProviderType>)providers;

+ (void)SetUserProperties:(FGParams)userProperties;

// Convenience logs — event/param key VERBATIM §4.1. additionalParams merge cuối.
+ (void)LogLevelStart:(NSInteger)level playCount:(NSInteger)playCount loseCount:(NSInteger)loseCount
             playMode:(NSString *)playMode additionalParams:(FGParams _Nullable)additionalParams;
+ (void)LogLevelEnd:(NSInteger)level playCount:(NSInteger)playCount loseCount:(NSInteger)loseCount
           playMode:(NSString *)playMode playDuration:(double)playDuration success:(BOOL)success
             reason:(NSString *)reason additionalParams:(FGParams _Nullable)additionalParams;
+ (void)LogEarnResource:(NSString *)playMode level:(NSInteger)level itemType:(NSString *)itemType
                   name:(NSString *)name amount:(double)amount earnPlacement:(NSString *)earnPlacement
                   item:(NSString *)item booster:(NSString *)booster balance:(double)balance
       additionalParams:(FGParams _Nullable)additionalParams;
+ (void)LogSpendResource:(NSString *)playMode level:(NSInteger)level itemType:(NSString *)itemType
                    name:(NSString *)name amount:(double)amount spendPlacement:(NSString *)spendPlacement
             spendReason:(NSString *)spendReason item:(NSString *)item booster:(NSString *)booster
                 balance:(double)balance additionalParams:(FGParams _Nullable)additionalParams;
+ (void)LogTutorial:(NSString *)actionName actionValue:(NSString *)actionValue
   additionalParams:(FGParams _Nullable)additionalParams;
+ (void)LogLoadingStart:(NSString *)placement additionalParams:(FGParams _Nullable)additionalParams;
+ (void)LogLoadingEnd:(NSString *)placement isLoad:(BOOL)isLoad loadTime:(double)loadTime
     additionalParams:(FGParams _Nullable)additionalParams;
+ (void)LogIAPShow:(NSString *)playMode level:(NSInteger)level location:(NSString *)location
              type:(NSString *)type productId:(NSString *)productId
  additionalParams:(FGParams _Nullable)additionalParams;
+ (void)LogIAPClick:(NSString *)playMode level:(NSInteger)level location:(NSString *)location
               type:(NSString *)type productId:(NSString *)productId
   additionalParams:(FGParams _Nullable)additionalParams;

// ── §4.2 Ads ─────────────────────────────────────────────────────────────────
+ (void)ShowInterstitial:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
              parameters:(FGParams _Nullable)parameters
  onInterstitialComplete:(void (^_Nullable)(void))onInterstitialComplete;
/// ⚠️ onRewarded TRƯỚC parameters (spec §4.2/§5.1).
+ (void)ShowRewarded:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
          onRewarded:(void (^_Nullable)(void))onRewarded parameters:(FGParams _Nullable)parameters;
+ (BOOL)IsRewardedReady;
+ (void)LoadRewarded;
+ (void)ShowBanner:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
        parameters:(FGParams _Nullable)parameters;
+ (void)HideBanner;
+ (void)ShowAppOpen:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
         parameters:(FGParams _Nullable)parameters;

// ── §4.3 MREC ────────────────────────────────────────────────────────────────
+ (void)LoadMRec;
/// vị trí mặc định Centered.
+ (void)ShowMRec:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
      parameters:(FGParams _Nullable)parameters;
/// preset AdViewPosition (0=TopLeft..8=BottomRight, 4=Centered).
+ (void)ShowMRec:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
      adPosition:(NSInteger)adPosition parameters:(FGParams _Nullable)parameters;
/// bám toạ độ màn hình (FGVector2 → CGPoint).
+ (void)ShowMRec:(NSString *)placement playMode:(NSString *)playMode currentLevel:(double)currentLevel
       screenPos:(CGPoint)screenPos parameters:(FGParams _Nullable)parameters;
+ (void)UpdateMRecPosition:(CGPoint)screenPos;
+ (void)UpdateMRecPositionPreset:(NSInteger)adPosition;
+ (void)HideMRec;
+ (void)DestroyMRec;
+ (BOOL)IsMRecReady;
/// (300*scale, 250*scale) px — spec §4.3/§7.7.
+ (CGPoint)GetMRecSize;
/// spec §4.5 — set IsRemoveAds=true + hide banner.
+ (void)RemoveAds;

// ── §4.4 RemoteConfig ────────────────────────────────────────────────────────
+ (NSInteger)GetRemoteConfigInt:(NSString *)key defaultValue:(NSInteger)defaultValue;
+ (BOOL)GetRemoteConfigBool:(NSString *)key defaultValue:(BOOL)defaultValue;
+ (NSString *)GetRemoteConfigString:(NSString *)key defaultValue:(NSString *)defaultValue;
+ (BOOL)IsRemoteConfigReady;

// ── §4.5 IAP ─────────────────────────────────────────────────────────────────
/// = FGEvent.Ads.RemoveAds (dùng chung handler với RemoveAds).
+ (void)ActivateRemoveAds;
+ (void)BuyProduct:(NSString *)productId location:(NSString *)location playMode:(NSString *)playMode
             level:(NSInteger)level result:(void (^)(BOOL success, NSString *transactionId))result;
+ (void)RestorePurchases:(void (^_Nullable)(BOOL success))callback;
+ (BOOL)ProductIsPurchased:(NSString *)productId;
+ (NSInteger)GetProductPurchaseCount:(NSString *)productId;
+ (NSString *)GetProductTitle:(NSString *)productId;
/// ⚠️ localizedPriceString đã format kèm ký hiệu tiền tệ, KHÔNG phải số.
+ (NSString *)GetProductPrice:(NSString *)productId;

// ── §4.6 Deeplink ────────────────────────────────────────────────────────────
/// ProcessCallbackToGame (one-shot). nil khi chưa có / guard action==""||value==0 (quirk 2).
/// Trả @[action(NSString), @(value)(NSNumber)] hoặc nil (mirror Pair<String,Int>?).
+ (NSArray * _Nullable)GetDeeplinkResult;

/// Host app / FGBridge forward URL (openURL) — mirror HandleDeepLinkIntent bên Android.
+ (void)handleOpenURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
