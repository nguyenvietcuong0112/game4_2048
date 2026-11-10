//
//  FGEventTypes.h — mirror KA/event/FGEventTypes.kt.
//  `Params` (typealias Kotlin) đã typedef `FGParams` ở util/FGSDKDefines.h — KHÔNG lặp ở đây.
//
#pragma once
#import <Foundation/Foundation.h>

#if !defined(__OBJC__)
#error "FGEventTypes.h là ObjC++ — chỉ include từ file .mm"
#endif

/// spec §3.6 — FGEvent.ProviderType. Tên VERBATIM theo Kotlin (không thêm prefix FG).
typedef NS_ENUM(NSInteger, ProviderType) {
    ProviderTypeFirebase  = 0,
    ProviderTypeAppsFlyer = 1,
    ProviderTypeFacebook  = 2,
    ProviderTypeAppLovin  = 3, // MỞ RỘNG ngoài Unity — AppLovin EventService (xem FGAppLovinEventProvider)
};

/// Kotlin `ProviderType.from(v)` — ngoài range fallback Firebase.
static inline ProviderType ProviderTypeFrom(NSInteger v) {
    switch (v) {
        case 1:  return ProviderTypeAppsFlyer;
        case 2:  return ProviderTypeFacebook;
        case 3:  return ProviderTypeAppLovin;
        default: return ProviderTypeFirebase;
    }
}

/**
 * spec §3.6 — FGEvent.FGInitState [Flags]. Bitmask.
 * ⚠️ Giữ nguyên chính tả gốc `Analystic` (thiếu chữ).
 */
typedef NS_OPTIONS(NSInteger, FGInitState) {
    FGInitStateNone      = 0,
    FGInitStateAnalystic = 1 << 0,
    FGInitStateAds       = 1 << 1,
    FGInitStateConsent   = 1 << 2, // tồn tại nhưng KHÔNG dùng trong state machine
};
