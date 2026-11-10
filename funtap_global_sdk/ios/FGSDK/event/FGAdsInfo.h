//
//  FGAdsInfo.h — mirror KA/event/FGAdsInfo.kt (spec §5.3): model impression truyền cho FGPublicEvent
//  (mọi prop get private ở Unity → readonly). Constructor arg đầu `adUnitIdentifier` → prop `AdID`.
//  Round revenue làm ở provider khi tạo, KHÔNG ở model.
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGAdsInfo : NSObject

@property (nonatomic, copy, readonly) NSString *AdID;
@property (nonatomic, copy, readonly) NSString *AdFormat;
@property (nonatomic, copy, readonly) NSString *NetworkName;
@property (nonatomic, copy, readonly) NSString *NetworkPlacement;
@property (nonatomic, copy, readonly) NSString *Placement;
@property (nonatomic, copy, readonly) NSString *CreativeIdentifier;
@property (nonatomic, readonly) double Revenue;
@property (nonatomic, copy, readonly) NSString *RevenuePrecision;
@property (nonatomic, readonly) long long LatencyMillis;
@property (nonatomic, copy, readonly) NSString *DspName;

/// Constructor đầy đủ tham số mirror Kotlin (nil string → default "").
- (instancetype)initWithAdID:(NSString *_Nullable)AdID
                    AdFormat:(NSString *_Nullable)AdFormat
                 NetworkName:(NSString *_Nullable)NetworkName
            NetworkPlacement:(NSString *_Nullable)NetworkPlacement
                   Placement:(NSString *_Nullable)Placement
          CreativeIdentifier:(NSString *_Nullable)CreativeIdentifier
                     Revenue:(double)Revenue
            RevenuePrecision:(NSString *_Nullable)RevenuePrecision
               LatencyMillis:(long long)LatencyMillis
                     DspName:(NSString *_Nullable)DspName NS_DESIGNATED_INITIALIZER;

/// Kotlin default args: toàn bộ rỗng/0.
- (instancetype)init;

@end

NS_ASSUME_NONNULL_END
