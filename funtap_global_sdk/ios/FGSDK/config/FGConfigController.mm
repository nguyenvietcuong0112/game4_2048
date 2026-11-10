//
//  FGConfigController.mm — mirror KA/config/FGConfigController.kt (spec §3).
//  Android assets → iOS NSBundle mainBundle resource (README adaptation table).
//
#import "FGConfigController.h"

static NSString *const kFGConfigTag = @"FGConfig";
static NSString *const kFGConfigResourceName = @"fg_main_config"; // fg_main_config.json
static NSString *const kFGConfigResourceType = @"json";

// Kotlin @Volatile cached — static, đọc lười lần đầu (không lock: race chỉ gây load thừa, như Kotlin)
static FGMainConfig *sCached = nil;

@implementation FGConfigController

+ (FGMainConfig * _Nullable)mainConfig {
    if (sCached) return sCached;
    sCached = [self loadConfig];
    return sCached;
}

+ (FGPlatformConfig * _Nullable)mainPlatform {
    return [self mainConfig].ios;
}

+ (void)invalidateCache {
    sCached = nil;
}

// Kotlin private fun load() — đổi tên vì `+load` là hook đặc biệt của ObjC runtime (tự chạy lúc load image)
+ (FGMainConfig * _Nullable)loadConfig {
    NSString *path = [[NSBundle mainBundle] pathForResource:kFGConfigResourceName
                                                     ofType:kFGConfigResourceType];
    if (!path) {
        NSLog(@"[%@] %@.%@ không có trong bundle — thêm vào Copy Bundle Resources",
              kFGConfigTag, kFGConfigResourceName, kFGConfigResourceType);
        return nil;
    }
    NSError *err = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&err];
    if (!data) {
        NSLog(@"[%@] load %@.%@ fail: %@", kFGConfigTag, kFGConfigResourceName, kFGConfigResourceType, err);
        return nil;
    }
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (![json isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[%@] parse %@.%@ fail: %@", kFGConfigTag, kFGConfigResourceName, kFGConfigResourceType, err);
        return nil;
    }
    return [FGMainConfig fromDict:(NSDictionary *)json];
}

@end
