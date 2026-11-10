//
//  FGAdmobConfig.h — mirror KA/ads/admob/FGAdmobConfig.kt (spec §7.8/§8):
//  config phẳng cho AdMob provider, keyed theo **format AdMob** (không phải slot backfill gốc).
//  Dùng chung 2 mode: primary (MediationType=AdMob) và backfill (Custom, MAX primary).
//
#pragma once
#import <Foundation/Foundation.h>
#import "../../config/FGConfigModels.h"

#if !defined(__OBJC__)
#error "FGAdmobConfig.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

/// Kotlin data class FGAdmobAdUnit(adUnitId, isAutoLoad, enableAds).
@interface FGAdmobAdUnit : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *adUnitId;
@property (nonatomic, readonly) BOOL isAutoLoad;
@property (nonatomic, readonly) BOOL enableAds;

/// Kotlin `isUsable` = enableAds && !adUnitId.isNullOrEmpty().
@property (nonatomic, readonly) BOOL isUsable;

- (instancetype)initWithAdUnitId:(NSString *_Nullable)adUnitId
                      isAutoLoad:(BOOL)isAutoLoad
                       enableAds:(BOOL)enableAds NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

/// Kotlin data class FGAdmobConfig(appId + 5 slot format AdMob).
@interface FGAdmobConfig : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *appId;
@property (nonatomic, strong, readonly) FGAdmobAdUnit *interstitial;
@property (nonatomic, strong, readonly) FGAdmobAdUnit *rewarded;
@property (nonatomic, strong, readonly) FGAdmobAdUnit *banner;
@property (nonatomic, strong, readonly) FGAdmobAdUnit *appOpen;
@property (nonatomic, strong, readonly) FGAdmobAdUnit *mrec;

- (instancetype)initWithAppId:(NSString *_Nullable)appId
                 interstitial:(FGAdmobAdUnit *)interstitial
                     rewarded:(FGAdmobAdUnit *)rewarded
                       banner:(FGAdmobAdUnit *)banner
                      appOpen:(FGAdmobAdUnit *)appOpen
                         mrec:(FGAdmobAdUnit *)mrec NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

/**
 * spec §7.1/§7.8 — builder cho AdMob config (mirror object FGAdmobConfigBuilder).
 *  - `buildPrimary`: map trực tiếp `primaryAdUnitConfig` (5 slot cùng tên) → slot AdMob cùng tên.
 *  - `buildBackfill`: ⚠️ map theo `rule.AdType` — 1 backfill rule route vào slot AdMob KHÁC tên (spec §3.5).
 *    vd Interstitial rule có AdType=MRec(1) → unit id nằm ở slot `mrec`. enableAds = `rule.Enable`.
 */
@interface FGAdmobConfigBuilder : NSObject

+ (FGAdmobConfig *)buildPrimary:(FGCustomAdsMediationConfig *)mediation;
+ (FGAdmobConfig *)buildBackfill:(FGCustomAdsMediationConfig *)mediation;

@end

/**
 * spec §8 — `MapAdMobErrorToReason(code)` (dùng cho load & display). Giá trị verbatim:
 *  3→no_fill, 2→network, 1→config, default(gồm 0/-1)→unknown. reason luôn lowercase.
 *  ⚠️ Mapping theo mã Android/Unity — GIỮ verbatim theo spec dù GADErrorCode iOS đánh số khác.
 */
@interface FGAdmobError : NSObject

+ (NSString *)mapToReason:(NSInteger)code;

@end

NS_ASSUME_NONNULL_END
