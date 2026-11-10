//
//  FGMaxAdsProvider.h — mirror KA/ads/max/FGMaxAdsProvider.kt (spec §7.4/§7.5/§7.6/§7.7):
//  provider AppLovin MAX (iOS SDK).
//
//  Constructor pin README: nhận main_ads_config trực tiếp (Kotlin nhận FGPlatformConfig rồi tự đọc
//  main_ads_config) — nullable vì FGAdsController fallback MAX với config null (provider tự guard).
//
//  Quirk giữ verbatim:
//   - §16-2: `onInterstitialComplete` single-slot (double-show mất callback lần 1).
//   - §16-3: banner reload sau fail KHÔNG set lại `_isBannerShowing` → cờ lệch.
//   - §16-4: MaxRetryAttempts=8.
//   - §16-5: reward cấp ở didRewardUserForAd (TRƯỚC Hidden).
//   - §16-6: openAppAction + ResetAOAction gate AppOpen.
//
#pragma once
#import <Foundation/Foundation.h>
#import "../IFGAdsProvider.h"
#import "../../config/FGConfigModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface FGMaxAdsProvider : NSObject <IFGAdsProvider>

/**
 * spec §7.8/§16-8 — CountryCode LIVE từ `ALSdkConfiguration.countryCode` trong completion init
 * (Unity = `MaxSdk.CountryCode`). Custom provider đọc để tính IsMaxOnlyCountry. nil tới khi MAX init xong.
 */
@property (nonatomic, copy, readonly, nullable) NSString *liveCountryCode;

- (instancetype)initWithConfig:(FGCustomAdsMediationConfig *_Nullable)config NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
