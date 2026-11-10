//
//  FGTrackingEvent.mm — mirror KA/tracking/FGTrackingEvent.kt.
//
#import "FGTrackingEvent.h"
#include <utility>

@implementation FGTrackingEvent

- (instancetype)initWithEventName:(NSString *)eventName
                           params:(FGParams)params
                        providers:(std::vector<ProviderType>)providers {
    self = [super init];
    if (self) {
        _eventName = [eventName copy];
        _params = [params copy];
        _providers = std::move(providers);
    }
    return self;
}

@end
