//
//  FGAdsController.mm — mirror KA/ads/FGAdsController.kt (spec §7.1).
//
#import "FGAdsController.h"
#import "FGAds.h"
#import "FGAdsOrchestrator.h"
#import "IFGAdsProvider.h"
#import "max/FGMaxAdsProvider.h"
#import "admob/FGAdmobAdsProvider.h"
#import "admob/FGAdmobConfig.h"
#import "custom/FGCustomAdsProvider.h"
#import "../config/FGConfigController.h"
#import "../config/FGEnums.h"
#import "../event/FGEvent.h"

static NSString *const TAG = @"FGAdsCtrl";

// Kotlin object state → static nội bộ .mm
static BOOL sRegistered = NO;

/**
 * Kotlin private `initialize()` — spec §7.1: chọn provider theo MediationType,
 * tạo orchestrator, FGAds.Initialize. Static C function (KHÔNG dùng ObjC `+initialize`
 * vì runtime tự gọi selector đó lần message đầu → init ads sai thời điểm).
 */
static void FGAdsCtrlInitialize(void) {
    FGPlatformConfig *platform = [FGConfigController mainPlatform];
    if (platform == nil) {
        NSLog(@"[%@] MainPlatform null → không init ads", TAG);
        return;
    }
    FGAdsNetworkType mediation = FGAdsNetworkTypeFrom(platform.MediationType);
    id<IFGAdsProvider> provider;
    switch (mediation) {
        case FGAdsNetworkTypeMax:
            // Pin README: provider nhận main_ads_config trực tiếp (Kotlin nhận platform rồi tự đọc).
            provider = [[FGMaxAdsProvider alloc] initWithConfig:platform.main_ads_config];
            break;
        case FGAdsNetworkTypeAdMob: {
            FGCustomAdsMediationConfig *cfg = platform.main_ads_config;
            if (cfg == nil) {
                NSLog(@"[%@] AdMob: main_ads_config null → fallback MAX", TAG);
                // ≈ Kotlin FGMaxAdsProvider(platform) với main_ads_config null — provider tự guard.
                provider = [[FGMaxAdsProvider alloc] initWithConfig:cfg];
            } else {
                provider = [[FGAdmobAdsProvider alloc] initWithConfig:[FGAdmobConfigBuilder buildPrimary:cfg]
                                                           isBackfill:NO];
            }
            break;
        }
        case FGAdsNetworkTypeCustom:
            // MAX primary + AdMob backfill (spec §7.8).
            provider = [[FGCustomAdsProvider alloc] initWithConfig:platform.main_ads_config];
            break;
    }
    FGAdsOrchestrator *orchestrator = [[FGAdsOrchestrator alloc] initWithProvider:provider platform:platform];
    [orchestrator initialize];
    [FGAds Initialize:orchestrator];
    NSLog(@"[%@] ads initialize: mediation=%ld", TAG, (long)mediation);
}

@implementation FGAdsController

+ (void)register {
    if (sRegistered) return;
    sRegistered = YES;
    FGEvent::Tracking::OnAllProvidersReady.add([] { FGAdsCtrlInitialize(); });
}

@end
