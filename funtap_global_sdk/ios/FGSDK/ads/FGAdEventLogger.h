//
//  FGAdEventLogger.h — mirror KA/ads/FGAdEventLogger.kt (spec §8): build + route ad analytics
//  events (Firebase) + AppsFlyer sends. Provider isolation: route qua FGEvent::Tracking bus,
//  KHÔNG import Firebase/AppsFlyer. Impl: FGAdEventLogger.mm (ads-core).
//
//  Quy ước §8: `success` = string "true"/"false"; `value` = giây (double) cho request/display/completed,
//  = revenue cho impression/revenue_sdk; `reason` = lowercase. ad_* events → CHỈ Firebase.
//
#pragma once
#import <Foundation/Foundation.h>
#import "../util/FGSDKDefines.h"

NS_ASSUME_NONNULL_BEGIN

@interface FGAdEventLogger : NSObject

/// spec §8 — ad_request (load done/fail). request_count: Banner/MRec = 0.
+ (void)adRequest:(NSString *)playMode
            level:(double)level
         platform:(NSString *)platform
        adNetwork:(NSString *)adNetwork
           format:(NSString *)format
         location:(NSString *)location
          success:(BOOL)success
           reason:(NSString *)reason
            value:(double)value
     requestCount:(NSInteger)requestCount
           unitId:(NSString *)unitId;

/// spec §8 — ad_display (show done/fail). AdMob not-ready show bắn giả (success=false, value=0).
+ (void)adDisplay:(NSString *)playMode
            level:(double)level
         platform:(NSString *)platform
        adNetwork:(NSString *)adNetwork
           format:(NSString *)format
         location:(NSString *)location
          success:(BOOL)success
           reason:(NSString *)reason
            value:(double)value;

/// spec §8 — ad_completed (ad closed). KHÔNG có reason.
+ (void)adCompleted:(NSString *)playMode
              level:(double)level
           platform:(NSString *)platform
          adNetwork:(NSString *)adNetwork
             format:(NSString *)format
           location:(NSString *)location
            success:(BOOL)success
              value:(double)value;

/// spec §8 — dict impression (dùng chung ad_impression + ad_revenue_sdk).
/// MAX: network key = `ad_network`. AdMob Interstitial: `ad_source`; format khác: `ad_network`.
/// `ad_unit_name` CHỈ có với Interstitial (cả MAX & AdMob).
+ (NSMutableDictionary<NSString *, id> *)buildImpression:(NSString *)format
                                                 isAdmob:(BOOL)isAdmob
                                          isInterstitial:(BOOL)isInterstitial
                                               adNetwork:(NSString *)adNetwork
                                                 revenue:(double)revenue
                                                currency:(NSString *)currency
                                              adUnitName:(NSString *_Nullable)adUnitName;

/// spec §8 — ad_impression (revenue paid).
+ (void)adImpression:(NSDictionary<NSString *, id> *)dict;

/// ad_click (user click ad). Params VERBATIM sheet: ad_format, ad_platform, ad_network (chỉ 3).
+ (void)adClick:(NSString *)format platform:(NSString *)platform adNetwork:(NSString *)adNetwork;

/// spec §8 — ad_revenue_sdk = dict impression + location + merge XParams (play_mode/level + custom).
+ (void)adRevenueSdk:(NSDictionary<NSString *, id> *)impressionDict
            location:(NSString *)location
             xParams:(FGParams _Nullable)xParams;

/// spec §8 — af_inters_displayed / af_rewarded_displayed (trong callback revenue). Route AppsFlyer.
+ (void)afIntersDisplayed;
+ (void)afRewardedDisplayed;

/// spec §8 — logAdRevenue mọi format (qua hook FGEvent::Tracking::LogAdRevenue; null → no-op).
+ (void)logAdRevenue:(NSString *)network
             isAdmob:(BOOL)isAdmob
            currency:(NSString *)currency
             revenue:(double)revenue
              format:(NSString *)format
              adUnit:(NSString *)adUnit;

@end

NS_ASSUME_NONNULL_END
