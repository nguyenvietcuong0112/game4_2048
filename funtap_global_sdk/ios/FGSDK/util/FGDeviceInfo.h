//
//  FGDeviceInfo.h — mirror KA/util/FGDeviceInfo.kt (spec §13/§14):
//  thông tin device cho Auth header/body, verify-iap body, DebugReporter. os luôn "ios" (nhánh iOS).
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGDeviceInfo : NSObject

@property (class, nonatomic, readonly) NSString *OS; // "ios"

/** mirror "Build.MANUFACTURER Build.MODEL" → UIDevice model + name. */
@property (class, nonatomic, readonly) NSString *deviceName;

/** device_os = phiên bản OS ("iOS X" ~ "Android X" bên Kotlin). */
@property (class, nonatomic, readonly) NSString *deviceOs;

/** package_name = bundleIdentifier (mirror Context.packageName). */
@property (class, nonatomic, readonly) NSString *packageName;

/** app_version = CFBundleShortVersionString (mirror versionName). */
@property (class, nonatomic, readonly) NSString *appVersion;

/** bundle_number = CFBundleVersion dạng long (mirror longVersionCode). */
@property (class, nonatomic, readonly) long long bundleNumber;

/** network = wifi/cellular/none (qua NWPathMonitor của FGInternetChecker). */
@property (class, nonatomic, readonly) NSString *network;

@end

NS_ASSUME_NONNULL_END
