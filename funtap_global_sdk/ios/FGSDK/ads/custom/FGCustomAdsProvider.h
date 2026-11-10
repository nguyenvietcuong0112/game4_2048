//
//  FGCustomAdsProvider.h — mirror KA/ads/custom/FGCustomAdsProvider.kt (spec §7.8/§16-8):
//  mediation Custom = MAX primary + AdMob backfill.
//
//   - Tạo `_maxProvider` + `_admobProvider = FGAdmobAdsProvider(buildBackfill, isBackfill=YES)`.
//   - `onInitialized` của Custom fire khi **MAX** ready (→ drive orchestrator). AdMob backfill IM LẶNG.
//   - `Primary` = MAX (primaryProvider=Max) — chỉ primary SetReady(Ads).
//   - `IsMaxOnlyCountry` = primary=Max && CountryCode!=nil && `maxOnlyCountries` chứa CountryCode (ignore-case).
//   - `HasAdmobBackfill` = primary=Max && !IsMaxOnlyCountry. NO → tắt sạch backfill (chạy MAX-only).
//   - Routing từng format: primary trước; fail → nếu `HasAdmobBackfill && IsBackfillReady(rule)` → backfill
//     theo `rule.AdType`. Inter fallback AdMob MRec/Banner (non-modal → invoke onInterstitialClosed NGAY).
//     AppOpen: max-only→MAX, else→AdMob.
//
//  ⚠️ CountryCode LẤY LIVE từ `_maxProvider.liveCountryCode` (AppLovin, Unity `MaxSdk.CountryCode`),
//     KHÔNG từ config JSON — gate mọi thứ dựa giá trị này (spec §16-8).
//
//  Constructor pin README: nhận main_ads_config trực tiếp (Kotlin nhận FGPlatformConfig rồi tự đọc
//  main_ads_config) — nullable, degenerate → AdMob backfill config default (mọi slot rỗng, không load gì).
//
#pragma once
#import <Foundation/Foundation.h>
#import "../IFGAdsProvider.h"
#import "../../config/FGConfigModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface FGCustomAdsProvider : NSObject <IFGAdsProvider>

- (instancetype)initWithConfig:(FGCustomAdsMediationConfig *_Nullable)config NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
