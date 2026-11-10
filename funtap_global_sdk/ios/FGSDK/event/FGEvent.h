//
//  FGEvent.h — mirror KA/event/FGEvent.kt (spec §5.1): event bus tĩnh, header-only C++ namespace.
//  Module KHÔNG tham chiếu trực tiếp nhau, giao tiếp qua đây.
//  Quy ước native (như Kotlin):
//   - Lifecycle event (multicast, nhiều subscriber) → FGSignal/FGSignal1/FGSignal2.
//   - Facade command + Func (có return / single-target) → inline std::function nullable,
//     check `if (FGEvent::X::Y)` rồi gọi (≈ Kotlin `?.invoke(...)`).
//  Kotlin FGVector2 → CGPoint (như IFGAdsProvider.h); List → std::vector; Pair<String,Int>? →
//  std::optional<std::pair<NSString *, NSInteger>>.
//
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "FGSignal.h"
#import "FGEventTypes.h"
#import "../util/FGSDKDefines.h"
#include <functional>
#include <optional>
#include <utility>
#include <vector>

#if !defined(__OBJC__)
#error "FGEvent.h là ObjC++ — chỉ include từ file .mm"
#endif

namespace FGEvent {

namespace Ads {
    inline FGSignal RemoveAds;
    inline FGSignal OnInitAds;
    // (placement, playMode, currentLevel, params, onInterstitialClosed)
    inline std::function<void(NSString *, NSString *, double, FGParams, std::function<void()>)> ShowInterstitial;
    // ⚠️ Rewarded: Action callback TRƯỚC dict — (placement, playMode, currentLevel, onRewarded, params)
    inline std::function<void(NSString *, NSString *, double, std::function<void()>, FGParams)> ShowRewarded;
    inline std::function<BOOL()> IsRewardedReady;
    inline FGSignal LoadRewarded;
    inline std::function<void(NSString *, NSString *, double, FGParams)> ShowBanner;
    inline FGSignal HideBanner;
    inline std::function<void(NSString *, NSString *, double, FGParams)> ShowAppOpen;
    inline FGSignal ResetAOAction;
    inline std::function<void(NSString *, NSString *, double, FGParams)> ShowMRec;
    inline std::function<void(NSString *, NSString *, double, CGPoint, FGParams)> ShowMRecAt;
    inline std::function<void(NSString *, NSString *, double, NSInteger, FGParams)> ShowMRecPreset;
    inline std::function<void(CGPoint)> UpdateMRecPosition;
    inline std::function<void(NSInteger)> UpdateMRecPositionPreset;
    inline FGSignal HideMRec;
    inline FGSignal DestroyMRec;
    inline FGSignal LoadMRec;
    inline std::function<BOOL()> IsMRecReady;
}

namespace Tracking {
    inline FGSignal2<BOOL, BOOL> OnInitTracking; // (isConsent, isATTAuthorized)
    inline FGSignal OnProviderReady;
    inline FGSignal OnAllProvidersReady;
    inline std::function<void(NSString *, FGParams)> LogEventWithParams;
    inline std::function<void(NSString *, FGParams, ProviderType)> LogEventWithProvider;
    inline std::function<void(NSString *, FGParams, std::vector<ProviderType>)> LogEventWithProviders;
    inline std::function<void(NSString *)> LogEvent;
    inline std::function<void(NSString *, ProviderType)> LogEventProvider;
    inline std::function<void(NSString *, std::vector<ProviderType>)> LogEventProviders;
    inline std::function<void(FGParams)> SetUserProperties;
    inline std::function<void(BOOL)> SetConsent;
    // spec §8 — ad revenue → AppsFlyer logAdRevenue. Hook set bởi AppsFlyer provider lúc init
    // (null = AppsFlyer tắt/chưa init → no-op, tự nhiên thành guard APPSFLYER_SDK_ENABLE).
    // (network, isAdmob, currency, revenue, format, adUnit)
    inline std::function<void(NSString *, BOOL, NSString *, double, NSString *, NSString *)> LogAdRevenue;
}

namespace IAP {
    // (productId, location, playMode, level, callback(success, transactionId/reason)) — mirror Kotlin
    inline std::function<void(NSString *, NSString *, NSString *, NSInteger, std::function<void(BOOL, NSString *)>)> BuyProduct;
    inline std::function<NSString *(NSString *)> GetProductTitle;
    inline std::function<NSString *(NSString *)> GetProductPrice;
    inline std::function<void(std::function<void(BOOL)>)> RestorePurchase;
    inline std::function<BOOL(NSString *)> IsPurchased;
    inline std::function<NSInteger(NSString *)> GetPurchaseCount;
    // spec §11 — callback game subscribe (Action). Manager fire, game nghe qua FGSDKIAP facade.
    inline FGSignal1<BOOL> OnIAPInitialized;
    inline FGSignal1<NSString *> OnPurchaseProcessing;
    inline FGSignal2<NSString *, NSString *> OnPurchaseCompleted;   // (productId, transactionId)
    inline FGSignal2<NSString *, NSString *> OnPurchaseFailed;      // (productId, reason)
    inline FGSignal1<BOOL> OnRestorePurchasesCompleted;
}

namespace RemoteConfig {
    inline std::function<NSInteger(NSString *, NSInteger)> GetInt;
    inline std::function<BOOL(NSString *, BOOL)> GetBool;
    inline std::function<NSString *(NSString *, NSString *)> GetString;
    inline std::function<NSString *(NSString *)> GetJson; // trả nil = null; deserialize T ở tầng wrapper (spec §10, quirk 17)
    inline std::function<BOOL()> IsRemoteConfigReady;
    inline FGSignal OnRemoteConfigFetched;
}

namespace InitEvent {
    inline FGSignal OnSDKReady;
    inline FGSignal FirebaseInitComplete;
    inline FGSignal AppsFlyerInitComplete;
    inline FGSignal FacebookInitComplete;
    inline FGSignal ApplovinInitComplete;
    inline FGSignal1<BOOL> ConsentInitComplete;
    inline FGSignal1<BOOL> OnInterInitComplete;
    inline FGSignal1<BOOL> OnBannerInitComplete;
    inline FGSignal1<BOOL> OnRewardInitComplete;
    inline FGSignal1<BOOL> OnAppOpenInitComplete;
}

namespace Network {
    inline FGSignal OnNetworkRestored;
    inline FGSignal OnNetworkLost;
}

namespace Consent {
    inline FGSignal OnConsentSuccess;
    inline FGSignal OnConsentFailed;
}

namespace Deeplink {
    // Kotlin `(() -> Pair<String, Int>?)?` — nullopt = chưa có deeplink
    inline std::function<std::optional<std::pair<NSString *, NSInteger>>()> OnRequestDeepLink;
    inline FGSignal2<NSString *, NSInteger> OnDeferredDeepLinkReceived;
}

} // namespace FGEvent
