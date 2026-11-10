//
//  FGAnalyticsController.h — mirror KA/tracking/FGAnalyticsController.kt (spec §9.1):
//  bootstrap tracking — tạo orchestrator, wire facade FGEvent::Tracking::* → orchestrator,
//  subscribe OnInitTracking để init providers sau consent. Register 1 lần trong FGSDK init.
//  ⚠️ Overload không provider → CHỈ Firebase (spec §4.1/§9.2).
//
#pragma once
#import <Foundation/Foundation.h>

#if !defined(__OBJC__)
#error "FGAnalyticsController.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGAnalyticsController : NSObject

+ (void)register;

@end

NS_ASSUME_NONNULL_END
