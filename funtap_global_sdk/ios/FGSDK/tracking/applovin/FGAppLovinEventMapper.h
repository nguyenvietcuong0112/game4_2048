//
//  FGAppLovinEventMapper.h — mirror KA/tracking/applovin/FGAppLovinEventMapper.kt.
//  Map "SDK tự động log" → AppLovin EventService (theo sheet tracking user cấp).
//
#pragma once
#import <Foundation/Foundation.h>
#import "../FGTrackingEvent.h"

#if !defined(__OBJC__)
#error "FGAppLovinEventMapper.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGAppLovinEventMapper : NSObject

/// Trả về 0..n event AppLovin (providers=[AppLovin]) phái sinh từ 1 FG event.
+ (NSArray<FGTrackingEvent *> *)map:(FGTrackingEvent *)event;

@end

NS_ASSUME_NONNULL_END
