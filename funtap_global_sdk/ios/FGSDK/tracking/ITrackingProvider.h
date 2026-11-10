//
//  ITrackingProvider.h — mirror KA/tracking/ITrackingProvider.kt (spec §9).
//  `initialize` PHẢI fire FGEvent::Tracking::OnProviderReady dù init fail (quirk 20 —
//  không thì SDK treo, cờ Analystic không set).
//  Kotlin `providerType: ProviderType?` → NSNumber* nullable (@(ProviderType));
//  nil = provider "không xác định" (router luôn cho nhận, spec §9.2).
//
#pragma once
#import <Foundation/Foundation.h>
#import "../event/FGEventTypes.h"
#import "../util/FGSDKDefines.h"

#if !defined(__OBJC__)
#error "ITrackingProvider.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@protocol ITrackingProvider <NSObject>

/// @(ProviderType); nil = không xác định.
@property (nonatomic, readonly, nullable) NSNumber *providerType;

- (void)initialize:(BOOL)isConsent isATTAuthorized:(BOOL)isATTAuthorized;

- (void)logEvent:(NSString *)eventName params:(FGParams _Nullable)params;

- (void)setUserProperties:(FGParams)props;

- (void)setConsent:(BOOL)isConsent;

@end

NS_ASSUME_NONNULL_END
