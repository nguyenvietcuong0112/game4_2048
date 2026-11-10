//
//  FGConfigModels.mm — mirror KA/config/FGConfigModels.kt (spec §3).
//  Gson → NSJSONSerialization + map field tay (README): field vắng / sai kiểu / NSNull → giữ default.
//
#import "FGConfigModels.h"

// ---- helper đọc dict null-safe (mirror "field vắng giữ default" của Gson) ----

static NSString * _Nullable FGStr(NSDictionary *d, NSString *k) {
    id v = d[k];
    return [v isKindOfClass:[NSString class]] ? (NSString *)v : nil;
}

static NSInteger FGInt(NSDictionary *d, NSString *k, NSInteger def) {
    id v = d[k];
    return [v isKindOfClass:[NSNumber class]] ? ((NSNumber *)v).integerValue : def;
}

static BOOL FGBool(NSDictionary *d, NSString *k, BOOL def) {
    id v = d[k];
    return [v isKindOfClass:[NSNumber class]] ? ((NSNumber *)v).boolValue : def;
}

static NSArray<NSString *> * _Nullable FGStrArray(NSDictionary *d, NSString *k) {
    id v = d[k];
    if (![v isKindOfClass:[NSArray class]]) return nil;
    // lọc phần tử không phải string (Gson sẽ fail cả file — ở đây khoan dung hơn nhưng cùng kết quả với JSON hợp lệ)
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id e in (NSArray *)v) {
        if ([e isKindOfClass:[NSString class]]) [out addObject:(NSString *)e];
    }
    return out;
}

static NSDictionary * _Nullable FGDict(NSDictionary *d, NSString *k) {
    id v = d[k];
    return [v isKindOfClass:[NSDictionary class]] ? (NSDictionary *)v : nil;
}

// ---- §3.1 ----

@implementation FGMainConfig

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGMainConfig *c = [[FGMainConfig alloc] init];
    c.enabled_packages = FGStrArray(dict, @"enabled_packages");
    c.maxOnlyCountries = FGStrArray(dict, @"maxOnlyCountries");
    NSDictionary *androidDict = FGDict(dict, @"android");
    if (androidDict) c.android = [FGPlatformConfig fromDict:androidDict];
    NSDictionary *iosDict = FGDict(dict, @"ios");
    if (iosDict) c.ios = [FGPlatformConfig fromDict:iosDict];
    c.listDevice = FGStrArray(dict, @"listDevice");
    return c;
}

@end

// ---- §3.2 ----

@implementation FGPlatformConfig

- (instancetype)init {
    if (self = [super init]) {
        _MediationType = 0;
    }
    return self;
}

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGPlatformConfig *c = [[FGPlatformConfig alloc] init];
    c.MediationType = FGInt(dict, @"MediationType", 0);
    c.base_api_domain = FGStr(dict, @"base_api_domain");
    c.app_key = FGStr(dict, @"app_key");
    c.game_code = FGStr(dict, @"game_code");
    c.enabled_packages = FGStrArray(dict, @"enabled_packages");
    NSDictionary *adsDict = FGDict(dict, @"main_ads_config");
    if (adsDict) c.main_ads_config = [FGCustomAdsMediationConfig fromDict:adsDict];
    NSDictionary *fbDict = FGDict(dict, @"facebook_configs");
    if (fbDict) c.facebook_configs = [FGFacebookConfig fromDict:fbDict];
    NSDictionary *afDict = FGDict(dict, @"appsflyer_configs");
    if (afDict) c.appsflyer_configs = [FGAppsflyerConfig fromDict:afDict];
    NSDictionary *pvDict = FGDict(dict, @"privacy_configs");
    if (pvDict) c.privacy_configs = [FGPrivacyConfig fromDict:pvDict];
    c.package_name = FGStr(dict, @"package_name");
    return c;
}

@end

// ---- §3.3 ----

@implementation FGCustomAdsMediationConfig

- (instancetype)init {
    if (self = [super init]) {
        _primaryProvider = 0;
        _primaryAdUnitConfig = [[FGAdsAdUnitConfig alloc] init]; // default new (§3.3)
        _backfillConfig = [[FGBackfillConfig alloc] init];       // default new (§3.3)
    }
    return self;
}

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGCustomAdsMediationConfig *c = [[FGCustomAdsMediationConfig alloc] init];
    c.primaryProvider = FGInt(dict, @"primaryProvider", 0);
    c.max_sdk_key = FGStr(dict, @"max_sdk_key");
    c.google_admob_app_id = FGStr(dict, @"google_admob_app_id");
    NSDictionary *primaryDict = FGDict(dict, @"primaryAdUnitConfig");
    if (primaryDict) c.primaryAdUnitConfig = [FGAdsAdUnitConfig fromDict:primaryDict];
    NSDictionary *backfillDict = FGDict(dict, @"backfillConfig");
    if (backfillDict) c.backfillConfig = [FGBackfillConfig fromDict:backfillDict];
    return c;
}

@end

// ---- §3.4 ----

@implementation FGAdsAdUnitConfig

- (instancetype)init {
    if (self = [super init]) {
        _Interstitial = [[FGPlatformAdUnit alloc] init];
        _Rewarded = [[FGPlatformAdUnit alloc] init];
        _Banner = [[FGPlatformAdUnit alloc] init];
        _AppOpen = [[FGPlatformAdUnit alloc] init];
        _MRec = [[FGPlatformAdUnit alloc] init];
    }
    return self;
}

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGAdsAdUnitConfig *c = [[FGAdsAdUnitConfig alloc] init];
    NSDictionary *d;
    if ((d = FGDict(dict, @"Interstitial"))) c.Interstitial = [FGPlatformAdUnit fromDict:d];
    if ((d = FGDict(dict, @"Rewarded")))     c.Rewarded = [FGPlatformAdUnit fromDict:d];
    if ((d = FGDict(dict, @"Banner")))       c.Banner = [FGPlatformAdUnit fromDict:d];
    if ((d = FGDict(dict, @"AppOpen")))      c.AppOpen = [FGPlatformAdUnit fromDict:d];
    if ((d = FGDict(dict, @"MRec")))         c.MRec = [FGPlatformAdUnit fromDict:d];
    return c;
}

@end

@implementation FGPlatformAdUnit

- (instancetype)init {
    if (self = [super init]) {
        _IsAutoLoad = YES; // default §3.4
        _EnableAds = YES;  // default §3.4
    }
    return self;
}

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGPlatformAdUnit *u = [[FGPlatformAdUnit alloc] init];
    u.AdUnitID = FGStr(dict, @"AdUnitID");
    u.IsAutoLoad = FGBool(dict, @"IsAutoLoad", YES);
    u.EnableAds = FGBool(dict, @"EnableAds", YES);
    return u;
}

@end

// ---- §3.5 ----

@implementation FGBackfillConfig

- (instancetype)init {
    if (self = [super init]) {
        _Interstitial = [[FGBackfillRule alloc] init];
        _Rewarded = [[FGBackfillRule alloc] init];
        _Banner = [[FGBackfillRule alloc] init];
        _AppOpen = [[FGBackfillRule alloc] init];
        _MRec = [[FGBackfillRule alloc] init];
    }
    return self;
}

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGBackfillConfig *c = [[FGBackfillConfig alloc] init];
    NSDictionary *d;
    if ((d = FGDict(dict, @"Interstitial"))) c.Interstitial = [FGBackfillRule fromDict:d];
    if ((d = FGDict(dict, @"Rewarded")))     c.Rewarded = [FGBackfillRule fromDict:d];
    if ((d = FGDict(dict, @"Banner")))       c.Banner = [FGBackfillRule fromDict:d];
    if ((d = FGDict(dict, @"AppOpen")))      c.AppOpen = [FGBackfillRule fromDict:d];
    if ((d = FGDict(dict, @"MRec")))         c.MRec = [FGBackfillRule fromDict:d];
    return c;
}

@end

@implementation FGBackfillRule

- (instancetype)init {
    if (self = [super init]) {
        _Enable = NO;      // default §3.5
        _AdUnitID = @"";   // default §3.5
        _IsAutoLoad = YES; // default §3.5
        _AdType = 0;       // ⚠️ đọc từ JSON, đừng dựa default
    }
    return self;
}

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGBackfillRule *r = [[FGBackfillRule alloc] init];
    r.Enable = FGBool(dict, @"Enable", NO);
    NSString *adUnit = FGStr(dict, @"AdUnitID");
    if (adUnit) r.AdUnitID = adUnit;
    r.IsAutoLoad = FGBool(dict, @"IsAutoLoad", YES);
    r.AdType = FGInt(dict, @"AdType", 0);
    return r;
}

@end

// ---- §3.2 nested ----

@implementation FGFacebookConfig

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGFacebookConfig *c = [[FGFacebookConfig alloc] init];
    c.app_id = FGStr(dict, @"app_id");
    c.client_token = FGStr(dict, @"client_token");
    c.app_name = FGStr(dict, @"app_name");
    return c;
}

@end

@implementation FGAppsflyerConfig

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGAppsflyerConfig *c = [[FGAppsflyerConfig alloc] init];
    c.DevKey = FGStr(dict, @"DevKey");
    c.AppId = FGStr(dict, @"AppId");
    return c;
}

@end

@implementation FGPrivacyConfig

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGPrivacyConfig *c = [[FGPrivacyConfig alloc] init];
    c.privacy_policy_url = FGStr(dict, @"privacy_policy_url");
    c.terms_of_service_url = FGStr(dict, @"terms_of_service_url");
    c.users_tracking_usage_description = FGStr(dict, @"users_tracking_usage_description");
    return c;
}

@end
