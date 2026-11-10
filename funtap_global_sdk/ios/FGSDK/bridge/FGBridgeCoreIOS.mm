//
//  FGBridgeCoreIOS.mm — mirror KA/bridge/FGBridgeCore.kt 100% (engine-agnostic).
//
//  Toàn bộ dispatch ~45 method + wiring event nằm ở đây; glue theo engine chỉ nối
//  kênh vào `emit` / `handle:` (xem header).
//
#import "FGBridgeCoreIOS.h"
#import "../FGSDKIOS.h"
#import "../event/FGEvent.h"
#import "../event/FGPublicEvent.h"
#import "../event/FGAdsInfo.h"
#import "../event/FGEventTypes.h"
#import "../util/FGMainThreadDispatcher.h"

#include <vector>

static NSString *const TAG = @"FGBridgeCore";

static void (^gEmit)(NSString *) = nil;

// ── JSON serialize ────────────────────────────────────────────────────────────
static NSString *jsonString(id obj) {
    NSError *e = nil;
    NSData *d = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&e];
    if (e || !d) { NSLog(@"[%@] serialize fail: %@", TAG, e); return nil; }
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
}

static void emitJson(NSString *_Nullable json) {
    if (json == nil) return;
    void (^blk)(NSString *) = gEmit;
    if (blk) blk(json);
}

// ── Outbound (mirror FGBridgeCore ret/push/pushInfo/pushArgs) ──────────────────
static void emitRet(id cb, id value) {
    if (![cb isKindOfClass:NSString.class]) return;               // cb null → bỏ (mirror `cb ?: return`)
    emitJson(jsonString(@{ @"e": @"ret", @"cb": cb, @"v": value ?: NSNull.null }));
}

static void push(NSString *event) {
    emitJson([NSString stringWithFormat:@"{\"e\":\"%@\"}", event]);
}

static NSDictionary *adsInfoToDict(FGAdsInfo *i) {
    // 10 field tên VERBATIM (spec §5.3).
    return @{
        @"AdID":               i.AdID ?: @"",
        @"AdFormat":           i.AdFormat ?: @"",
        @"NetworkName":        i.NetworkName ?: @"",
        @"NetworkPlacement":   i.NetworkPlacement ?: @"",
        @"Placement":          i.Placement ?: @"",
        @"CreativeIdentifier": i.CreativeIdentifier ?: @"",
        @"Revenue":            @(i.Revenue),
        @"RevenuePrecision":   i.RevenuePrecision ?: @"",
        @"LatencyMillis":      @(i.LatencyMillis),
        @"DspName":            i.DspName ?: @"",
    };
}

static void pushInfo(NSString *event, FGAdsInfo *info) {
    emitJson(jsonString(@{ @"e": event, @"info": adsInfoToDict(info) }));
}

static void pushArgs(NSString *event, NSArray *args) {
    emitJson(jsonString(@{ @"e": event, @"args": args }));
}

// ── Inbound arg helpers (mirror JsonObject.str/int/dbl/flt/bool/params/providers) ──
static NSString *argStr(NSDictionary *a, NSString *k) {
    id v = a[k]; return [v isKindOfClass:NSString.class] ? v : @"";
}
static NSInteger argInt(NSDictionary *a, NSString *k) {
    id v = a[k]; return [v isKindOfClass:NSNumber.class] ? [v integerValue] : 0;
}
static double argDbl(NSDictionary *a, NSString *k) {
    id v = a[k]; return [v isKindOfClass:NSNumber.class] ? [v doubleValue] : 0.0;
}
static float argFlt(NSDictionary *a, NSString *k) {
    id v = a[k]; return [v isKindOfClass:NSNumber.class] ? [v floatValue] : 0.0f;
}
static BOOL argBool(NSDictionary *a, NSString *k) {
    id v = a[k]; return [v isKindOfClass:NSNumber.class] ? [v boolValue] : NO;
}
/// null value → nil (bỏ). NSJSONSerialization đã cho NSString/NSNumber/NSNull nên KHÔNG rebuild.
static FGParams argParams(NSDictionary *a, NSString *k) {
    id v = a[k]; return [v isKindOfClass:NSDictionary.class] ? (FGParams)v : nil;
}
/// key có mặt & khác null (mirror JsonObject.has cho showMRec/updateMRecPosition).
static BOOL argHas(NSDictionary *a, NSString *k) {
    id v = a[k]; return v != nil && ![v isKindOfClass:NSNull.class];
}
static ProviderType providerFromString(NSString *s) {
    if ([s isEqualToString:@"AppsFlyer"]) return ProviderTypeAppsFlyer;
    if ([s isEqualToString:@"Facebook"])  return ProviderTypeFacebook;
    if ([s isEqualToString:@"AppLovin"])  return ProviderTypeAppLovin;
    return ProviderTypeFirebase; // "Firebase" / fallback
}

@interface FGBridgeCoreIOS ()
+ (void)dispatchMethod:(NSString *)m args:(NSDictionary *)a cb:(id)cb;
@end

@implementation FGBridgeCoreIOS

+ (void (^)(NSString *))emit { return gEmit; }
+ (void)setEmit:(void (^)(NSString *))emit { gEmit = [emit copy]; }

// ── Inbound dispatch ───────────────────────────────────────────────────────────
+ (void)handle:(NSString *)json {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    NSError *err = nil;
    id cmd = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![cmd isKindOfClass:NSDictionary.class]) return;

    NSString *m = cmd[@"m"];
    if (![m isKindOfClass:NSString.class]) return;
    NSDictionary *args = [cmd[@"args"] isKindOfClass:NSDictionary.class] ? cmd[@"args"] : @{};
    id cb = cmd[@"cb"]; // NSString hoặc nil/NSNull

    // Marshal về main thread trước khi chạm state/gọi game (spec §14) — kênh script có thể
    // callback trên thread khác. Nuốt + log exception (mirror runCatching FGBridgeCore).
    [FGMainThreadDispatcher enqueue:^{
        @try {
            [FGBridgeCoreIOS dispatchMethod:m args:args cb:cb];
        } @catch (id ex) {
            NSLog(@"[%@] dispatch %@ fail: %@", TAG, m, ex);
        }
    }];
}

+ (void)dispatchMethod:(NSString *)m args:(NSDictionary *)a cb:(id)cb {
    // ── Core ──
    if ([m isEqualToString:@"getSdkVersion"]) {
        emitRet(cb, [FGSDKIOS sdkVersion]);
    } else if ([m isEqualToString:@"isInit"]) {
        emitRet(cb, @([FGSDKIOS isInit]));
    } else if ([m isEqualToString:@"showMediationDebugger"]) {
        // QA only — mirror bản Android/Unity.
        [FGSDKIOS showMediationDebugger];

    // ── Tracking ──
    } else if ([m isEqualToString:@"logEvent"]) {
        NSString *name = argStr(a, @"name");
        FGParams params = argParams(a, @"params");
        BOOL hasProviders = [a[@"providers"] isKindOfClass:NSArray.class];
        std::vector<ProviderType> providers;
        if (hasProviders) {
            for (id v in (NSArray *)a[@"providers"]) {
                if ([v isKindOfClass:NSString.class]) providers.push_back(providerFromString(v));
            }
        }
        if (params && hasProviders)      [FGSDKIOS LogEvent:name parameters:params providers:providers];
        else if (params)                 [FGSDKIOS LogEvent:name parameters:params];
        else if (hasProviders)           [FGSDKIOS LogEvent:name providers:providers];
        else                             [FGSDKIOS LogEvent:name];
    } else if ([m isEqualToString:@"setUserProperties"]) {
        FGParams props = argParams(a, @"props");
        if (props) [FGSDKIOS SetUserProperties:props];
    } else if ([m isEqualToString:@"logLevelStart"]) {
        [FGSDKIOS LogLevelStart:argInt(a, @"level") playCount:argInt(a, @"playCount") loseCount:argInt(a, @"loseCount")
                       playMode:argStr(a, @"playMode") additionalParams:argParams(a, @"extra")];
    } else if ([m isEqualToString:@"logLevelEnd"]) {
        [FGSDKIOS LogLevelEnd:argInt(a, @"level") playCount:argInt(a, @"playCount") loseCount:argInt(a, @"loseCount")
                     playMode:argStr(a, @"playMode") playDuration:argDbl(a, @"playDuration") success:argBool(a, @"success")
                       reason:argStr(a, @"reason") additionalParams:argParams(a, @"extra")];
    } else if ([m isEqualToString:@"logEarnResource"]) {
        [FGSDKIOS LogEarnResource:argStr(a, @"playMode") level:argInt(a, @"level") itemType:argStr(a, @"itemType")
                             name:argStr(a, @"name") amount:argDbl(a, @"amount") earnPlacement:argStr(a, @"earnPlacement")
                             item:argStr(a, @"item") booster:argStr(a, @"booster") balance:argDbl(a, @"balance")
                 additionalParams:argParams(a, @"extra")];
    } else if ([m isEqualToString:@"logSpendResource"]) {
        [FGSDKIOS LogSpendResource:argStr(a, @"playMode") level:argInt(a, @"level") itemType:argStr(a, @"itemType")
                              name:argStr(a, @"name") amount:argDbl(a, @"amount") spendPlacement:argStr(a, @"spendPlacement")
                       spendReason:argStr(a, @"spendReason") item:argStr(a, @"item") booster:argStr(a, @"booster")
                           balance:argDbl(a, @"balance") additionalParams:argParams(a, @"extra")];
    } else if ([m isEqualToString:@"logTutorial"]) {
        [FGSDKIOS LogTutorial:argStr(a, @"actionName") actionValue:argStr(a, @"actionValue")
             additionalParams:argParams(a, @"extra")];
    } else if ([m isEqualToString:@"logLoadingStart"]) {
        [FGSDKIOS LogLoadingStart:argStr(a, @"placement") additionalParams:argParams(a, @"extra")];
    } else if ([m isEqualToString:@"logLoadingEnd"]) {
        [FGSDKIOS LogLoadingEnd:argStr(a, @"placement") isLoad:argBool(a, @"isLoad") loadTime:argDbl(a, @"loadTime")
               additionalParams:argParams(a, @"extra")];
    } else if ([m isEqualToString:@"logIAPShow"]) {
        [FGSDKIOS LogIAPShow:argStr(a, @"playMode") level:argInt(a, @"level") location:argStr(a, @"location")
                        type:argStr(a, @"type") productId:argStr(a, @"productId") additionalParams:argParams(a, @"extra")];
    } else if ([m isEqualToString:@"logIAPClick"]) {
        [FGSDKIOS LogIAPClick:argStr(a, @"playMode") level:argInt(a, @"level") location:argStr(a, @"location")
                         type:argStr(a, @"type") productId:argStr(a, @"productId") additionalParams:argParams(a, @"extra")];

    // ── Ads ──
    } else if ([m isEqualToString:@"showInterstitial"]) {
        [FGSDKIOS ShowInterstitial:argStr(a, @"placement") playMode:argStr(a, @"playMode") currentLevel:argDbl(a, @"level")
                       parameters:argParams(a, @"params") onInterstitialComplete:^{ emitRet(cb, @YES); }];
    } else if ([m isEqualToString:@"showRewarded"]) {
        [FGSDKIOS ShowRewarded:argStr(a, @"placement") playMode:argStr(a, @"playMode") currentLevel:argDbl(a, @"level")
                    onRewarded:^{ emitRet(cb, @YES); } parameters:argParams(a, @"params")];
    } else if ([m isEqualToString:@"isRewardedReady"]) {
        emitRet(cb, @([FGSDKIOS IsRewardedReady]));
    } else if ([m isEqualToString:@"loadRewarded"]) {
        [FGSDKIOS LoadRewarded];
    } else if ([m isEqualToString:@"showBanner"]) {
        [FGSDKIOS ShowBanner:argStr(a, @"placement") playMode:argStr(a, @"playMode") currentLevel:argDbl(a, @"level")
                  parameters:argParams(a, @"params")];
    } else if ([m isEqualToString:@"hideBanner"]) {
        [FGSDKIOS HideBanner];
    } else if ([m isEqualToString:@"showAppOpen"]) {
        [FGSDKIOS ShowAppOpen:argStr(a, @"placement") playMode:argStr(a, @"playMode") currentLevel:argDbl(a, @"level")
                   parameters:argParams(a, @"params")];
    } else if ([m isEqualToString:@"loadMRec"]) {
        [FGSDKIOS LoadMRec];
    } else if ([m isEqualToString:@"showMRec"]) {
        NSString *p = argStr(a, @"placement"); NSString *pm = argStr(a, @"playMode");
        double lv = argDbl(a, @"level"); FGParams params = argParams(a, @"params");
        if (argHas(a, @"adPosition"))
            [FGSDKIOS ShowMRec:p playMode:pm currentLevel:lv adPosition:argInt(a, @"adPosition") parameters:params];
        else if (argHas(a, @"x"))
            [FGSDKIOS ShowMRec:p playMode:pm currentLevel:lv screenPos:CGPointMake(argFlt(a, @"x"), argFlt(a, @"y")) parameters:params];
        else
            [FGSDKIOS ShowMRec:p playMode:pm currentLevel:lv parameters:params];
    } else if ([m isEqualToString:@"updateMRecPosition"]) {
        if (argHas(a, @"adPosition")) [FGSDKIOS UpdateMRecPositionPreset:argInt(a, @"adPosition")];
        else                          [FGSDKIOS UpdateMRecPosition:CGPointMake(argFlt(a, @"x"), argFlt(a, @"y"))];
    } else if ([m isEqualToString:@"hideMRec"]) {
        [FGSDKIOS HideMRec];
    } else if ([m isEqualToString:@"destroyMRec"]) {
        [FGSDKIOS DestroyMRec];
    } else if ([m isEqualToString:@"isMRecReady"]) {
        emitRet(cb, @([FGSDKIOS IsMRecReady]));
    } else if ([m isEqualToString:@"removeAds"]) {
        [FGSDKIOS RemoveAds];

    // ── RemoteConfig ──
    } else if ([m isEqualToString:@"getRemoteConfigInt"]) {
        emitRet(cb, @([FGSDKIOS GetRemoteConfigInt:argStr(a, @"key") defaultValue:argInt(a, @"default")]));
    } else if ([m isEqualToString:@"getRemoteConfigBool"]) {
        emitRet(cb, @([FGSDKIOS GetRemoteConfigBool:argStr(a, @"key") defaultValue:argBool(a, @"default")]));
    } else if ([m isEqualToString:@"getRemoteConfigString"]) {
        emitRet(cb, [FGSDKIOS GetRemoteConfigString:argStr(a, @"key") defaultValue:argStr(a, @"default")]);
    } else if ([m isEqualToString:@"isRemoteConfigReady"]) {
        emitRet(cb, @([FGSDKIOS IsRemoteConfigReady]));

    // ── IAP ──
    } else if ([m isEqualToString:@"activateRemoveAds"]) {
        [FGSDKIOS ActivateRemoveAds];
    } else if ([m isEqualToString:@"buyProduct"]) {
        [FGSDKIOS BuyProduct:argStr(a, @"productId") location:argStr(a, @"location") playMode:argStr(a, @"playMode")
                       level:argInt(a, @"level") result:^(BOOL ok, NSString *tx) {
                           emitRet(cb, @[@(ok), tx ?: @""]);
                       }];
    } else if ([m isEqualToString:@"restorePurchases"]) {
        [FGSDKIOS RestorePurchases:^(BOOL ok) { emitRet(cb, @(ok)); }];
    } else if ([m isEqualToString:@"productIsPurchased"]) {
        emitRet(cb, @([FGSDKIOS ProductIsPurchased:argStr(a, @"productId")]));
    } else if ([m isEqualToString:@"getProductPurchaseCount"]) {
        emitRet(cb, @([FGSDKIOS GetProductPurchaseCount:argStr(a, @"productId")]));
    } else if ([m isEqualToString:@"getProductTitle"]) {
        emitRet(cb, [FGSDKIOS GetProductTitle:argStr(a, @"productId")]);
    } else if ([m isEqualToString:@"getProductPrice"]) {
        emitRet(cb, [FGSDKIOS GetProductPrice:argStr(a, @"productId")]);

    // ── Deeplink ──
    } else if ([m isEqualToString:@"getDeeplinkResult"]) {
        emitRet(cb, [FGSDKIOS GetDeeplinkResult]); // nil → NSNull → script null

    } else {
        NSLog(@"[%@] unknown method: %@", TAG, m);
    }
}

// ── Outbound wiring (mirror FGBridgeCore.start / wireAdEvents / wireIapEvents) ──
+ (void)start {
    static BOOL started = NO;
    if (started) return;
    started = YES;

    // Fullscreen (Interstitial / AppOpen): request, loaded, failed_to_load, shown, failed_to_show, clicked, closed.
    auto wireFull = [](NSString *prefix, FGPublicEvent::FullscreenEvents &e) {
        e.Request.add     ([prefix](NSString *p) { pushArgs([prefix stringByAppendingString:@".request"], @[p ?: @""]); });
        e.Loaded.add      ([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".loaded"], i); });
        e.FailedToLoad.add([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".failed_to_load"], i); });
        e.Shown.add       ([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".shown"], i); });
        e.FailedToShow.add([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".failed_to_show"], i); });
        e.Clicked.add     ([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".clicked"], i); });
        e.Closed.add      ([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".closed"], i); });
    };
    // Banner / MRec: request, loaded, failed_to_load, shown, hidden, clicked, revenue_paid.
    auto wireBanner = [](NSString *prefix, FGPublicEvent::BannerEvents &e) {
        e.Request.add     ([prefix](NSString *p) { pushArgs([prefix stringByAppendingString:@".request"], @[p ?: @""]); });
        e.Loaded.add      ([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".loaded"], i); });
        e.FailedToLoad.add([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".failed_to_load"], i); });
        e.Shown.add       ([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".shown"], i); });
        e.Hidden.add      ([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".hidden"], i); });
        e.Clicked.add     ([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".clicked"], i); });
        e.RevenuePaid.add ([prefix](FGAdsInfo *i){ pushInfo([prefix stringByAppendingString:@".revenue_paid"], i); });
    };

    wireFull(@"ad.interstitial", FGPublicEvent::Interstitial);
    wireFull(@"ad.app_open", FGPublicEvent::AppOpen);

    // ⚠️ format = "reward" (KHÔNG phải "rewarded"); có Completed.
    {
        FGPublicEvent::RewardedEvents &e = FGPublicEvent::Rewarded;
        e.Request.add     ([](NSString *p) { pushArgs(@"ad.reward.request", @[p ?: @""]); });
        e.Loaded.add      ([](FGAdsInfo *i){ pushInfo(@"ad.reward.loaded", i); });
        e.FailedToLoad.add([](FGAdsInfo *i){ pushInfo(@"ad.reward.failed_to_load", i); });
        e.Shown.add       ([](FGAdsInfo *i){ pushInfo(@"ad.reward.shown", i); });
        e.FailedToShow.add([](FGAdsInfo *i){ pushInfo(@"ad.reward.failed_to_show", i); });
        e.Clicked.add     ([](FGAdsInfo *i){ pushInfo(@"ad.reward.clicked", i); });
        e.Closed.add      ([](FGAdsInfo *i){ pushInfo(@"ad.reward.closed", i); });
        e.Completed.add   ([](FGAdsInfo *i){ pushInfo(@"ad.reward.completed", i); });
    }

    wireBanner(@"ad.banner", FGPublicEvent::Banner);
    wireBanner(@"ad.mrec", FGPublicEvent::MRec);

    // IAP callbacks.
    FGEvent::IAP::OnIAPInitialized.add         ([](BOOL ok)                 { pushArgs(@"iap.initialized", @[@(ok)]); });
    FGEvent::IAP::OnPurchaseProcessing.add     ([](NSString *p)             { pushArgs(@"iap.processing", @[p ?: @""]); });
    FGEvent::IAP::OnPurchaseCompleted.add      ([](NSString *a, NSString *b){ pushArgs(@"iap.completed", @[a ?: @"", b ?: @""]); });
    FGEvent::IAP::OnPurchaseFailed.add         ([](NSString *a, NSString *b){ pushArgs(@"iap.failed", @[a ?: @"", b ?: @""]); });
    FGEvent::IAP::OnRestorePurchasesCompleted.add([](BOOL ok)               { pushArgs(@"iap.restored", @[@(ok)]); });

    // RemoteConfig fetched.
    FGEvent::RemoteConfig::OnRemoteConfigFetched.add([]{ push(@"remoteconfig.fetched"); });
}

@end
