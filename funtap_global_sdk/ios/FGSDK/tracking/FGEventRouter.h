//
//  FGEventRouter.h — mirror KA/tracking/FGEventRouter.kt (spec §9.2):
//  provider không xác định → LUÔN nhận event; else chỉ nhận khi event.providers chứa type của nó.
//
#pragma once
#import <Foundation/Foundation.h>
#import "ITrackingProvider.h"
#import "FGTrackingEvent.h"

#if !defined(__OBJC__)
#error "FGEventRouter.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGEventRouter : NSObject

+ (BOOL)isProviderEnabled:(id<ITrackingProvider>)provider event:(FGTrackingEvent *)event;

@end

NS_ASSUME_NONNULL_END
