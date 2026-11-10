//
//  FGAdmobConfig.mm — mirror KA/ads/admob/FGAdmobConfig.kt (spec §7.1/§7.8/§8).
//
#import "FGAdmobConfig.h"
#import "../../config/FGEnums.h"

// ── FGAdmobAdUnit ────────────────────────────────────────────────────────────

@implementation FGAdmobAdUnit

- (instancetype)initWithAdUnitId:(NSString *)adUnitId
                      isAutoLoad:(BOOL)isAutoLoad
                       enableAds:(BOOL)enableAds {
    if ((self = [super init])) {
        _adUnitId = [adUnitId copy];
        _isAutoLoad = isAutoLoad;
        _enableAds = enableAds;
    }
    return self;
}

// Kotlin `isUsable` = enableAds && !adUnitId.isNullOrEmpty().
- (BOOL)isUsable {
    return _enableAds && _adUnitId.length > 0;
}

@end

// ── FGAdmobConfig ────────────────────────────────────────────────────────────

@implementation FGAdmobConfig

- (instancetype)initWithAppId:(NSString *)appId
                 interstitial:(FGAdmobAdUnit *)interstitial
                     rewarded:(FGAdmobAdUnit *)rewarded
                       banner:(FGAdmobAdUnit *)banner
                      appOpen:(FGAdmobAdUnit *)appOpen
                         mrec:(FGAdmobAdUnit *)mrec {
    if ((self = [super init])) {
        _appId = [appId copy];
        _interstitial = interstitial;
        _rewarded = rewarded;
        _banner = banner;
        _appOpen = appOpen;
        _mrec = mrec;
    }
    return self;
}

@end

// ── FGAdmobConfigBuilder ─────────────────────────────────────────────────────

// Kotlin FGPlatformAdUnit.toAdmob() / FGBackfillRule.toAdmob() (extension fun → static C).
static FGAdmobAdUnit *FGAdmobFromPrimary(FGPlatformAdUnit *u) {
    return [[FGAdmobAdUnit alloc] initWithAdUnitId:u.AdUnitID isAutoLoad:u.IsAutoLoad enableAds:u.EnableAds];
}

static FGAdmobAdUnit *FGAdmobFromRule(FGBackfillRule *r) {
    // enableAds = rule.Enable (spec §3.5).
    return [[FGAdmobAdUnit alloc] initWithAdUnitId:r.AdUnitID isAutoLoad:r.IsAutoLoad enableAds:r.Enable];
}

// Kotlin EMPTY — slot không có rule route vào → disabled.
static FGAdmobAdUnit *FGAdmobEmptyUnit(void) {
    return [[FGAdmobAdUnit alloc] initWithAdUnitId:@"" isAutoLoad:NO enableAds:NO];
}

@implementation FGAdmobConfigBuilder

+ (FGAdmobConfig *)buildPrimary:(FGCustomAdsMediationConfig *)mediation {
    FGAdsAdUnitConfig *u = mediation.primaryAdUnitConfig;
    return [[FGAdmobConfig alloc] initWithAppId:mediation.google_admob_app_id
                                   interstitial:FGAdmobFromPrimary(u.Interstitial)
                                       rewarded:FGAdmobFromPrimary(u.Rewarded)
                                         banner:FGAdmobFromPrimary(u.Banner)
                                        appOpen:FGAdmobFromPrimary(u.AppOpen)
                                           mrec:FGAdmobFromPrimary(u.MRec)];
}

+ (FGAdmobConfig *)buildBackfill:(FGCustomAdsMediationConfig *)mediation {
    FGBackfillConfig *bf = mediation.backfillConfig;
    // ⚠️ Slot AdMob keyed theo rule.AdType — 1 rule route vào slot AdMob KHÁC tên (spec §3.5).
    // Duyệt theo thứ tự Kotlin listOf(...): rule sau ghi đè rule trước nếu trùng AdType.
    NSMutableDictionary<NSNumber *, FGAdmobAdUnit *> *slots = [NSMutableDictionary dictionary];
    for (FGBackfillRule *rule in @[ bf.Interstitial, bf.Rewarded, bf.Banner, bf.AppOpen, bf.MRec ]) {
        slots[@(FGBackfillAdTypeFrom(rule.AdType))] = FGAdmobFromRule(rule);
    }
    return [[FGAdmobConfig alloc] initWithAppId:mediation.google_admob_app_id
                                   interstitial:(slots[@(FGBackfillAdTypeInterstitial)] ?: FGAdmobEmptyUnit())
                                       rewarded:(slots[@(FGBackfillAdTypeRewarded)] ?: FGAdmobEmptyUnit())
                                         banner:(slots[@(FGBackfillAdTypeBanner)] ?: FGAdmobEmptyUnit())
                                        appOpen:(slots[@(FGBackfillAdTypeAppOpen)] ?: FGAdmobEmptyUnit())
                                           mrec:(slots[@(FGBackfillAdTypeMRec)] ?: FGAdmobEmptyUnit())];
}

@end

// ── FGAdmobError ─────────────────────────────────────────────────────────────

@implementation FGAdmobError

// spec §8 — mapping VERBATIM theo mã Android/Unity (GADErrorCode iOS đánh số khác — GIỮ, quirk đã pin ở header).
+ (NSString *)mapToReason:(NSInteger)code {
    switch (code) {
        case 3:  return @"no_fill";
        case 2:  return @"network";
        case 1:  return @"config";
        default: return @"unknown";
    }
}

@end
