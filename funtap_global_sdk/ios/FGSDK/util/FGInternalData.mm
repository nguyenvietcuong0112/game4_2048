//
//  FGInternalData.mm — mirror KA/util/FGInternalData.kt (spec §6.4).
//
#import "FGInternalData.h"

static NSString *const kFGRemoveAdsKey = @"FGRemoveAds"; // key VERBATIM (Unity PlayerPrefs)

@implementation FGInternalData

+ (BOOL)IsRemoveAds {
    return [NSUserDefaults.standardUserDefaults boolForKey:kFGRemoveAdsKey]; // default NO như Kotlin
}

+ (void)setIsRemoveAds:(BOOL)value {
    [NSUserDefaults.standardUserDefaults setBool:value forKey:kFGRemoveAdsKey];
}

@end
