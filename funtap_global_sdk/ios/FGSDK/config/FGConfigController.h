//
//  FGConfigController.h — mirror KA/config/FGConfigController.kt (spec §3):
//  load fg_main_config.json từ bundle resource, cache singleton, invalidateCache.
//  MainPlatform luôn = nhánh `ios` (spec §3.1: iOS → ios).
//
#pragma once
#import <Foundation/Foundation.h>
#import "FGConfigModels.h"

#if !defined(__OBJC__)
#error "FGConfigController.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGConfigController : NSObject

/// Kotlin `MainConfig` — nil nếu resource thiếu / JSON hỏng (null-safe, đã log).
+ (FGMainConfig * _Nullable)mainConfig;

/// Kotlin `MainPlatform` — = mainConfig.ios.
+ (FGPlatformConfig * _Nullable)mainPlatform;

+ (void)invalidateCache;

@end

NS_ASSUME_NONNULL_END
