//
//  FGAdmobAdsProvider.h — mirror KA/ads/admob/FGAdmobAdsProvider.kt (spec §7.8/§8):
//  provider AdMob (Google Mobile Ads iOS SDK). Dùng 2 mode:
//   - primary (MediationType=AdMob): fire ApplovinInitComplete + onInitialized + SetReady(Ads).
//   - backfill (Custom, MAX primary): `isBackfill=YES` → IM LẶNG (KHÔNG fire ApplovinInitComplete,
//     KHÔNG onInitialized, KHÔNG SetReady(Ads)) — chỉ primary set ready (spec §16-8).
//
//  Quirk dùng chung MAX: retry FGMaxRetry (=8, 2·2^count, §16-4); error→reason FGAdmobError.mapToReason (§8).
//  ⚠️ AdMob KHÔNG reset retry count khi show not-ready — chỉ Load lại (spec §7.6, khác MAX).
//
#pragma once
#import <Foundation/Foundation.h>
#import "../IFGAdsProvider.h"
#import "FGAdmobConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface FGAdmobAdsProvider : NSObject <IFGAdsProvider>

- (instancetype)initWithConfig:(FGAdmobConfig *)config
                    isBackfill:(BOOL)isBackfill NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Kotlin `fun isBannerReady()` — NGOÀI IFGAdsProvider; Custom provider dùng cho IsBackfillReady (spec §7.8).
- (BOOL)isBannerReady;

@end

NS_ASSUME_NONNULL_END
