//
//  FGEnums.h — mirror KA/config/FGEnums.kt (spec §3.6). Giá trị int verbatim trong JSON.
//  Config lưu NSInteger verbatim; enum có hàm *From() để map (Kotlin from(), ngoài range → fallback).
//  FGInitState (NS_OPTIONS, ⚠️ giữ typo `Analystic`) sống ở event/FGEventTypes.h (mirror vị trí
//  Kotlin KA/event/FGEventTypes.kt) — re-export qua import, KHÔNG định nghĩa lại.
//
#pragma once
#import <Foundation/Foundation.h>
#import "../event/FGEventTypes.h"

#if !defined(__OBJC__)
#error "FGEnums.h là ObjC++ — chỉ include từ file .mm"
#endif

/// MediationType.
typedef NS_ENUM(NSInteger, FGAdsNetworkType) {
    FGAdsNetworkTypeMax    = 0,
    FGAdsNetworkTypeAdMob  = 1,
    FGAdsNetworkTypeCustom = 2,
};

/// Kotlin `FGAdsNetworkType.from(v)` — ngoài range fallback Max.
static inline FGAdsNetworkType FGAdsNetworkTypeFrom(NSInteger v) {
    switch (v) {
        case 1:  return FGAdsNetworkTypeAdMob;
        case 2:  return FGAdsNetworkTypeCustom;
        default: return FGAdsNetworkTypeMax;
    }
}

/// primaryProvider.
typedef NS_ENUM(NSInteger, FGAdsMediationProvider) {
    FGAdsMediationProviderMax   = 0,
    FGAdsMediationProviderAdMob = 1,
};

/// Kotlin `FGAdsMediationProvider.from(v)` — ngoài range fallback Max.
static inline FGAdsMediationProvider FGAdsMediationProviderFrom(NSInteger v) {
    switch (v) {
        case 1:  return FGAdsMediationProviderAdMob;
        default: return FGAdsMediationProviderMax;
    }
}

/// backfill AdType.
typedef NS_ENUM(NSInteger, FGBackfillAdType) {
    FGBackfillAdTypeInterstitial = 0,
    FGBackfillAdTypeMRec         = 1,
    FGBackfillAdTypeBanner       = 2,
    FGBackfillAdTypeRewarded     = 3,
    FGBackfillAdTypeAppOpen      = 4,
};

/// Kotlin `FGBackfillAdType.from(v)` — ngoài range fallback Interstitial.
static inline FGBackfillAdType FGBackfillAdTypeFrom(NSInteger v) {
    switch (v) {
        case 1:  return FGBackfillAdTypeMRec;
        case 2:  return FGBackfillAdTypeBanner;
        case 3:  return FGBackfillAdTypeRewarded;
        case 4:  return FGBackfillAdTypeAppOpen;
        default: return FGBackfillAdTypeInterstitial;
    }
}

/// FGAdFormat (tầng API) — ⚠️ thứ tự KHÁC FGBackfillAdType.
typedef NS_ENUM(NSInteger, FGAdFormat) {
    FGAdFormatInterstitial = 0,
    FGAdFormatRewarded     = 1,
    FGAdFormatBanner       = 2,
    FGAdFormatAppOpen      = 3,
    FGAdFormatMRec         = 4,
};

/// Kotlin `FGAdFormat.from(v)` — ngoài range fallback Interstitial.
static inline FGAdFormat FGAdFormatFrom(NSInteger v) {
    switch (v) {
        case 1:  return FGAdFormatRewarded;
        case 2:  return FGAdFormatBanner;
        case 3:  return FGAdFormatAppOpen;
        case 4:  return FGAdFormatMRec;
        default: return FGAdFormatInterstitial;
    }
}
