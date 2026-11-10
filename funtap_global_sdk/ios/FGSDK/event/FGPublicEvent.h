//
//  FGPublicEvent.h — mirror KA/event/FGPublicEvent.kt (spec §5.2): event game subscribe, header-only.
//  Callback = Action<FGAdsInfo>, riêng Request = Action<String> (placement).
//  Mỗi format có BỘ event khác nhau (giữ đúng — KHÔNG thêm event thừa cho format không có):
//   - Interstitial / AppOpen: Request, Loaded, FailedToLoad, Shown, FailedToShow, Clicked, Closed
//   - Rewarded: như trên + Completed
//   - Banner / MRec: Request, Loaded, FailedToLoad, Shown, Hidden, Clicked, RevenuePaid
//  RemoteConfig.OnRemoteConfigFetched đã ở FGEvent::RemoteConfig (không lặp ở đây).
//
#pragma once
#import <Foundation/Foundation.h>
#import "FGSignal.h"
#import "FGAdsInfo.h"

#if !defined(__OBJC__)
#error "FGPublicEvent.h là ObjC++ — chỉ include từ file .mm"
#endif

namespace FGPublicEvent {

/** Interstitial / AppOpen: KHÔNG có Hidden/RevenuePaid/Completed. */
struct FullscreenEvents {
    FGSignal1<NSString *> Request;      // placement
    FGSignal1<FGAdsInfo *> Loaded;
    FGSignal1<FGAdsInfo *> FailedToLoad;
    FGSignal1<FGAdsInfo *> Shown;
    FGSignal1<FGAdsInfo *> FailedToShow;
    FGSignal1<FGAdsInfo *> Clicked;
    FGSignal1<FGAdsInfo *> Closed;
};

/** Rewarded: Fullscreen + Completed. */
struct RewardedEvents {
    FGSignal1<NSString *> Request;
    FGSignal1<FGAdsInfo *> Loaded;
    FGSignal1<FGAdsInfo *> FailedToLoad;
    FGSignal1<FGAdsInfo *> Shown;
    FGSignal1<FGAdsInfo *> FailedToShow;
    FGSignal1<FGAdsInfo *> Clicked;
    FGSignal1<FGAdsInfo *> Closed;
    FGSignal1<FGAdsInfo *> Completed;
};

/** Banner / MRec: KHÔNG có FailedToShow/Closed/Completed; CÓ Hidden + RevenuePaid. */
struct BannerEvents {
    FGSignal1<NSString *> Request;
    FGSignal1<FGAdsInfo *> Loaded;
    FGSignal1<FGAdsInfo *> FailedToLoad;
    FGSignal1<FGAdsInfo *> Shown;
    FGSignal1<FGAdsInfo *> Hidden;
    FGSignal1<FGAdsInfo *> Clicked;
    FGSignal1<FGAdsInfo *> RevenuePaid;
};

inline FullscreenEvents Interstitial;
inline FullscreenEvents AppOpen;
inline RewardedEvents Rewarded;
inline BannerEvents Banner;
inline BannerEvents MRec;

} // namespace FGPublicEvent
