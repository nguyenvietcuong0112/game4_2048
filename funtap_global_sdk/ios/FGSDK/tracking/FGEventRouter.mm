//
//  FGEventRouter.mm — mirror KA/tracking/FGEventRouter.kt (spec §9.2).
//
#import "FGEventRouter.h"
#include <algorithm>

@implementation FGEventRouter

/**
 * spec §9.2 verbatim (Unity IsProviderEnabled): map TÊN CLASS chứa "Firebase"/"AppsFlyer"/"Facebook"
 * → ProviderType; không match = provider "không xác định" → LUÔN nhận event.
 * (Kotlin route qua providerType — tương đương cho 3 provider thật vì tên class chứa đúng chuỗi.)
 */
+ (BOOL)isProviderEnabled:(id<ITrackingProvider>)provider event:(FGTrackingEvent *)event {
    NSString *cls = NSStringFromClass([(NSObject *)provider class]);
    ProviderType type;
    if ([cls containsString:@"Firebase"])       type = ProviderTypeFirebase;
    else if ([cls containsString:@"AppsFlyer"]) type = ProviderTypeAppsFlyer;
    else if ([cls containsString:@"Facebook"])  type = ProviderTypeFacebook;
    else if ([cls containsString:@"AppLovin"])  type = ProviderTypeAppLovin;
    else return YES;

    const std::vector<ProviderType> provs = event.providers;
    return std::find(provs.begin(), provs.end(), type) != provs.end();
}

@end
