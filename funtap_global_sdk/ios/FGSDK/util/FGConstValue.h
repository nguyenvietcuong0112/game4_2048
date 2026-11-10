//
//  FGConstValue.h — mirror KA/util/FGConstValue.kt (spec §15): bảng hằng VERBATIM từ FGConstValue (Unity).
//  Kotlin object → class methods (class property để gọi được FGConstValue.X như Kotlin).
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGConstValue : NSObject

@property (class, nonatomic, readonly) NSString *SdkVersion; // "3.2.6"

/** spec §7.5/§16-6: coroutine ResetAOAction chờ 4s. */
@property (class, nonatomic, readonly) float ignoreFullScreenAdsTime;

// Provider names
@property (class, nonatomic, readonly) NSString *Firebase;
@property (class, nonatomic, readonly) NSString *Facebook;
@property (class, nonatomic, readonly) NSString *AppsFlyer;
@property (class, nonatomic, readonly) NSString *Applovin;
@property (class, nonatomic, readonly) NSString *RemoteConfig;
@property (class, nonatomic, readonly) NSString *applovin_max_sdk;
@property (class, nonatomic, readonly) NSString *admob_sdk;

// Ad formats
@property (class, nonatomic, readonly) NSString *Interstitial;
@property (class, nonatomic, readonly) NSString *Reward;
@property (class, nonatomic, readonly) NSString *Banner;
@property (class, nonatomic, readonly) NSString *AppOpen;
@property (class, nonatomic, readonly) NSString *Mrec;

// Revenue / AppsFlyer
@property (class, nonatomic, readonly) NSString *AdImpression;
@property (class, nonatomic, readonly) NSString *AdRevenue; // ⚠️ "ad_revenue_sdk", không phải "ad_revenue"
@property (class, nonatomic, readonly) NSString *AFAdRevenue;
@property (class, nonatomic, readonly) NSString *AF_Revenue;
@property (class, nonatomic, readonly) NSString *AF_Currency;
@property (class, nonatomic, readonly) NSString *AF_Quantity;
@property (class, nonatomic, readonly) NSString *AF_OrderID;
@property (class, nonatomic, readonly) NSString *AF_Purchase;

// Event names
@property (class, nonatomic, readonly) NSString *InitSDK;
@property (class, nonatomic, readonly) NSString *AdLoaded;
@property (class, nonatomic, readonly) NSString *AdRequest;
@property (class, nonatomic, readonly) NSString *AdDisplay;
@property (class, nonatomic, readonly) NSString *AdCompleted;
@property (class, nonatomic, readonly) NSString *AdFormat;
@property (class, nonatomic, readonly) NSString *AdLoadFailed; // ⚠️ "ad_load_fail", không phải "ad_load_failed"

// Param keys
@property (class, nonatomic, readonly) NSString *ProductId;
@property (class, nonatomic, readonly) NSString *DeviceId;
@property (class, nonatomic, readonly) NSString *DeviceName;
@property (class, nonatomic, readonly) NSString *PackageName;
@property (class, nonatomic, readonly) NSString *Platform;
@property (class, nonatomic, readonly) NSString *Provider;
@property (class, nonatomic, readonly) NSString *EventParam;
@property (class, nonatomic, readonly) NSString *EventTag;
@property (class, nonatomic, readonly) NSString *EventName;
@property (class, nonatomic, readonly) NSString *Event;
@property (class, nonatomic, readonly) NSString *Status;

/**
 * spec: UserDeviceId = SystemInfo.deviceUniqueIdentifier (runtime).
 * iOS native ~ identifierForVendor (mirror vai trò ANDROID_ID bên Kotlin); nil → "".
 */
@property (class, nonatomic, readonly) NSString *UserDeviceId;

@end

NS_ASSUME_NONNULL_END
