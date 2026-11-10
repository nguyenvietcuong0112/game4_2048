//
//  FGAdsController.h — mirror KA/ads/FGAdsController.kt (spec §7.1): bootstrap Ads.
//  Register 1 lần trong FGSDK init. Ads chỉ Initialize SAU khi tracking ready
//  (subscribe FGEvent::Tracking::OnAllProvidersReady).
//
#pragma once
#import <Foundation/Foundation.h>

#if !defined(__OBJC__)
#error "FGAdsController.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGAdsController : NSObject

+ (void)register;

@end

NS_ASSUME_NONNULL_END
