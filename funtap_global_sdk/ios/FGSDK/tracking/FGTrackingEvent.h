//
//  FGTrackingEvent.h — mirror KA/tracking/FGTrackingEvent.kt (spec §9.1-9.2).
//
#pragma once
#import <Foundation/Foundation.h>
#import "../event/FGEventTypes.h"
#import "../util/FGSDKDefines.h"
#include <vector>

#if !defined(__OBJC__)
#error "FGTrackingEvent.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

/// spec §9.1 — trạng thái orchestrator (Disabled/Failed khai báo nhưng không dùng).
typedef NS_ENUM(NSInteger, FGTrackingState) {
    FGTrackingStateNotInitialized = 0,
    FGTrackingStateInitializing   = 1,
    FGTrackingStateReady          = 2,
    FGTrackingStateDisabled       = 3,
    FGTrackingStateFailed         = 4,
};

/// spec §9.2 — event kèm danh sách provider đích.
@interface FGTrackingEvent : NSObject

@property (nonatomic, copy, readonly) NSString *eventName;
@property (nonatomic, copy, readonly, nullable) FGParams params;
@property (nonatomic, readonly) std::vector<ProviderType> providers;

- (instancetype)initWithEventName:(NSString *)eventName
                           params:(FGParams _Nullable)params
                        providers:(std::vector<ProviderType>)providers;

@end

NS_ASSUME_NONNULL_END
