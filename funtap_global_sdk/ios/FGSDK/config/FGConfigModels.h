//
//  FGConfigModels.h — mirror KA/config/FGConfigModels.kt (spec §3): schema fg_main_config.json.
//  Property = field JSON VERBATIM (kể cả hoa/thường: MediationType, base_api_domain, AdUnitID...).
//  Field vắng trong JSON giữ default (bảng §3) — mirror Gson no-arg constructor.
//  Enum lưu NSInteger verbatim; convert qua FGAdsNetworkTypeFrom(...) tại nơi dùng.
//  Parse: NSJSONSerialization → +fromDict: (Gson thay bằng map field tay, xem README).
//
#pragma once
#import <Foundation/Foundation.h>
#import "FGEnums.h"

#if !defined(__OBJC__)
#error "FGConfigModels.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@class FGPlatformConfig;
@class FGCustomAdsMediationConfig;
@class FGAdsAdUnitConfig;
@class FGPlatformAdUnit;
@class FGBackfillConfig;
@class FGBackfillRule;
@class FGFacebookConfig;
@class FGAppsflyerConfig;
@class FGPrivacyConfig;

/// §3.1 top-level.
@interface FGMainConfig : NSObject
@property (nonatomic, copy, nullable) NSArray<NSString *> *enabled_packages;
@property (nonatomic, copy, nullable) NSArray<NSString *> *maxOnlyCountries;
@property (nonatomic, strong, nullable) FGPlatformConfig *android;
@property (nonatomic, strong, nullable) FGPlatformConfig *ios;
@property (nonatomic, copy, nullable) NSArray<NSString *> *listDevice;
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

/// §3.2 android / ios.
@interface FGPlatformConfig : NSObject
@property (nonatomic, assign) NSInteger MediationType;                                  // default 0 (Max)
@property (nonatomic, copy, nullable) NSString *base_api_domain;
@property (nonatomic, copy, nullable) NSString *app_key;
@property (nonatomic, copy, nullable) NSString *game_code;
@property (nonatomic, copy, nullable) NSArray<NSString *> *enabled_packages;
@property (nonatomic, strong, nullable) FGCustomAdsMediationConfig *main_ads_config;
@property (nonatomic, strong, nullable) FGFacebookConfig *facebook_configs;
@property (nonatomic, strong, nullable) FGAppsflyerConfig *appsflyer_configs;
@property (nonatomic, strong, nullable) FGPrivacyConfig *privacy_configs;
@property (nonatomic, copy, nullable) NSString *package_name;
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

/// §3.3 main_ads_config.
@interface FGCustomAdsMediationConfig : NSObject
@property (nonatomic, assign) NSInteger primaryProvider;                                // default 0 (Max)
@property (nonatomic, copy, nullable) NSString *max_sdk_key;
@property (nonatomic, copy, nullable) NSString *google_admob_app_id;
@property (nonatomic, strong) FGAdsAdUnitConfig *primaryAdUnitConfig;                   // default new
@property (nonatomic, strong) FGBackfillConfig *backfillConfig;                         // default new
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

/// §3.4 primaryAdUnitConfig — 5 slot.
@interface FGAdsAdUnitConfig : NSObject
@property (nonatomic, strong) FGPlatformAdUnit *Interstitial;
@property (nonatomic, strong) FGPlatformAdUnit *Rewarded;
@property (nonatomic, strong) FGPlatformAdUnit *Banner;
@property (nonatomic, strong) FGPlatformAdUnit *AppOpen;
@property (nonatomic, strong) FGPlatformAdUnit *MRec;
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

@interface FGPlatformAdUnit : NSObject
@property (nonatomic, copy, nullable) NSString *AdUnitID;                               // default nil
@property (nonatomic, assign) BOOL IsAutoLoad;                                          // default YES
@property (nonatomic, assign) BOOL EnableAds;                                           // default YES
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

/// §3.5 backfillConfig — 5 slot.
@interface FGBackfillConfig : NSObject
@property (nonatomic, strong) FGBackfillRule *Interstitial;
@property (nonatomic, strong) FGBackfillRule *Rewarded;
@property (nonatomic, strong) FGBackfillRule *Banner;
@property (nonatomic, strong) FGBackfillRule *AppOpen;
@property (nonatomic, strong) FGBackfillRule *MRec;
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

@interface FGBackfillRule : NSObject
@property (nonatomic, assign) BOOL Enable;                                              // default NO
@property (nonatomic, copy) NSString *AdUnitID;                                         // default @""
@property (nonatomic, assign) BOOL IsAutoLoad;                                          // default YES
@property (nonatomic, assign) NSInteger AdType;                                         // ⚠️ đọc từ JSON, đừng dựa default
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

@interface FGFacebookConfig : NSObject
@property (nonatomic, copy, nullable) NSString *app_id;
@property (nonatomic, copy, nullable) NSString *client_token;
@property (nonatomic, copy, nullable) NSString *app_name;
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

@interface FGAppsflyerConfig : NSObject
@property (nonatomic, copy, nullable) NSString *DevKey;
@property (nonatomic, copy, nullable) NSString *AppId;
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

@interface FGPrivacyConfig : NSObject
@property (nonatomic, copy, nullable) NSString *privacy_policy_url;
@property (nonatomic, copy, nullable) NSString *terms_of_service_url;
@property (nonatomic, copy, nullable) NSString *users_tracking_usage_description;
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

NS_ASSUME_NONNULL_END
