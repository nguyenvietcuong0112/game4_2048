//
//  FGAds.mm — mirror KA/ads/FGAds.kt (spec §7.1).
//
#import "FGAds.h"
#import "FGAdsOrchestrator.h"
#import "../event/FGEvent.h"
#import "../util/FGInternalData.h"

#include <functional>
#include <utility>

static NSString *const TAG = @"FGAds";

// Kotlin @Volatile — đọc/ghi qua bus đều trên main thread (spec §14), static thường là đủ.
static FGAdsOrchestrator *_orchestrator = nil;
static OpenAppAction _openAppAction = OpenAppActionNONE;

/** spec §7.1 — đã IsRemoveAds → return; else set true + HideBanner. */
static void FGAdsRemoveAds(void) {
    if (FGInternalData.IsRemoveAds) return;
    FGInternalData.IsRemoveAds = YES;
    FGEvent::Ads::HideBanner.invoke();
}

// Mirror đúng danh sách wire của Kotlin wireBus() — KHÔNG wire OnInitAds / ResetAOAction / ShowAppOpen thừa.
// Message-to-nil khi _orchestrator chưa set ≈ Kotlin `orchestrator?.` (null-safe).
static void FGAdsWireBus(void) {
    using namespace FGEvent::Ads;

    RemoveAds.add([] { FGAdsRemoveAds(); });

    ShowInterstitial = [](NSString *p, NSString *m, double l, FGParams params, std::function<void()> cb) {
        void (^onClosed)(void) = nil;
        if (cb) {
            std::function<void()> fn = std::move(cb);
            onClosed = ^{ fn(); };
        }
        [_orchestrator showInterstitial:p playMode:m currentLevel:l params:params onClosed:onClosed];
    };
    // ⚠️ Rewarded: callback TRƯỚC dict (spec §5.1).
    ShowRewarded = [](NSString *p, NSString *m, double l, std::function<void()> cb, FGParams params) {
        void (^onRewarded)(void) = nil;
        if (cb) {
            std::function<void()> fn = std::move(cb);
            onRewarded = ^{ fn(); };
        }
        [_orchestrator showRewarded:p playMode:m currentLevel:l onRewarded:onRewarded params:params];
    };
    IsRewardedReady = []() -> BOOL { return _orchestrator ? [_orchestrator isRewardedReady] : NO; };
    LoadRewarded.add([] { [_orchestrator loadRewarded]; });

    ShowBanner = [](NSString *p, NSString *m, double l, FGParams params) {
        [_orchestrator showBanner:p playMode:m currentLevel:l params:params];
    };
    HideBanner.add([] { [_orchestrator hideBanner]; });

    ShowAppOpen = [](NSString *p, NSString *m, double l, FGParams params) {
        [_orchestrator showAppOpen:p playMode:m currentLevel:l params:params];
    };

    ShowMRec = [](NSString *p, NSString *m, double l, FGParams params) {
        [_orchestrator showMRec:p playMode:m currentLevel:l params:params];
    };
    ShowMRecAt = [](NSString *p, NSString *m, double l, CGPoint pos, FGParams params) {
        [_orchestrator showMRecAt:p playMode:m currentLevel:l screenPos:pos params:params];
    };
    ShowMRecPreset = [](NSString *p, NSString *m, double l, NSInteger ap, FGParams params) {
        [_orchestrator showMRecPreset:p playMode:m currentLevel:l adPosition:ap params:params];
    };
    UpdateMRecPosition = [](CGPoint pos) { [_orchestrator updateMRecPosition:pos]; };
    UpdateMRecPositionPreset = [](NSInteger ap) { [_orchestrator updateMRecPositionPreset:ap]; };
    HideMRec.add([] { [_orchestrator hideMRec]; });
    DestroyMRec.add([] { [_orchestrator destroyMRec]; });
    LoadMRec.add([] { [_orchestrator loadMRec]; });
    IsMRecReady = []() -> BOOL { return _orchestrator ? [_orchestrator isMRecReady] : NO; };
}

@implementation FGAds

+ (OpenAppAction)openAppAction { return _openAppAction; }
+ (void)setOpenAppAction:(OpenAppAction)openAppAction { _openAppAction = openAppAction; }

+ (void)Initialize:(FGAdsOrchestrator *)orch {
    _orchestrator = orch;
    FGAdsWireBus();
    NSLog(@"[%@] FGAds initialized, bus wired", TAG);
}

@end
