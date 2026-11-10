//
//  FGAdsInfo.mm — impl FGAdsInfo.h (mirror KA/event/FGAdsInfo.kt, spec §5.3).
//
#import "FGAdsInfo.h"

@implementation FGAdsInfo

- (instancetype)initWithAdID:(NSString *)AdID
                    AdFormat:(NSString *)AdFormat
                 NetworkName:(NSString *)NetworkName
            NetworkPlacement:(NSString *)NetworkPlacement
                   Placement:(NSString *)Placement
          CreativeIdentifier:(NSString *)CreativeIdentifier
                     Revenue:(double)Revenue
            RevenuePrecision:(NSString *)RevenuePrecision
               LatencyMillis:(long long)LatencyMillis
                     DspName:(NSString *)DspName {
    self = [super init];
    if (self) {
        _AdID = [AdID copy] ?: @"";
        _AdFormat = [AdFormat copy] ?: @"";
        _NetworkName = [NetworkName copy] ?: @"";
        _NetworkPlacement = [NetworkPlacement copy] ?: @"";
        _Placement = [Placement copy] ?: @"";
        _CreativeIdentifier = [CreativeIdentifier copy] ?: @"";
        _Revenue = Revenue;
        _RevenuePrecision = [RevenuePrecision copy] ?: @"";
        _LatencyMillis = LatencyMillis;
        _DspName = [DspName copy] ?: @"";
    }
    return self;
}

- (instancetype)init {
    return [self initWithAdID:@"" AdFormat:@"" NetworkName:@"" NetworkPlacement:@"" Placement:@""
           CreativeIdentifier:@"" Revenue:0.0 RevenuePrecision:@"" LatencyMillis:0 DspName:@""];
}

@end
