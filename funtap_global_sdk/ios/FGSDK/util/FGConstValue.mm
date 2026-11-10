//
//  FGConstValue.mm — mirror KA/util/FGConstValue.kt (spec §15). Mọi giá trị VERBATIM.
//
#import "FGConstValue.h"
#import <UIKit/UIKit.h>

@implementation FGConstValue

+ (NSString *)SdkVersion { return @"3.2.6"; }

+ (float)ignoreFullScreenAdsTime { return 4.0f; }

// Provider names
+ (NSString *)Firebase { return @"firebase"; }
+ (NSString *)Facebook { return @"facebook"; }
+ (NSString *)AppsFlyer { return @"appsflyer"; }
+ (NSString *)Applovin { return @"applovin"; }
+ (NSString *)RemoteConfig { return @"remote_config"; }
+ (NSString *)applovin_max_sdk { return @"applovin_max_sdk"; }
+ (NSString *)admob_sdk { return @"admob_sdk"; }

// Ad formats
+ (NSString *)Interstitial { return @"interstitial"; }
+ (NSString *)Reward { return @"reward"; }
+ (NSString *)Banner { return @"banner"; }
+ (NSString *)AppOpen { return @"app_open"; }
+ (NSString *)Mrec { return @"mrec"; }

// Revenue / AppsFlyer
+ (NSString *)AdImpression { return @"ad_impression"; }
+ (NSString *)AdRevenue { return @"ad_revenue_sdk"; } // ⚠️ không phải "ad_revenue"
+ (NSString *)AFAdRevenue { return @"af_ad_revenue"; }
+ (NSString *)AF_Revenue { return @"af_revenue"; }
+ (NSString *)AF_Currency { return @"af_currency"; }
+ (NSString *)AF_Quantity { return @"af_quantity"; }
+ (NSString *)AF_OrderID { return @"af_order_id"; }
+ (NSString *)AF_Purchase { return @"af_purchase"; }

// Event names
+ (NSString *)InitSDK { return @"init_sdk"; }
+ (NSString *)AdLoaded { return @"ad_loaded"; }
+ (NSString *)AdRequest { return @"ad_request"; }
+ (NSString *)AdDisplay { return @"ad_display"; }
+ (NSString *)AdCompleted { return @"ad_completed"; }
+ (NSString *)AdFormat { return @"ad_format"; }
+ (NSString *)AdLoadFailed { return @"ad_load_fail"; } // ⚠️ không phải "ad_load_failed"

// Param keys
+ (NSString *)ProductId { return @"product_id"; }
+ (NSString *)DeviceId { return @"device_id"; }
+ (NSString *)DeviceName { return @"device_name"; }
+ (NSString *)PackageName { return @"package_name"; }
+ (NSString *)Platform { return @"platform"; }
+ (NSString *)Provider { return @"provider"; }
+ (NSString *)EventParam { return @"event_param"; }
+ (NSString *)EventTag { return @"event_tag"; }
+ (NSString *)EventName { return @"event_name"; }
+ (NSString *)Event { return @"event"; }
+ (NSString *)Status { return @"status"; }

+ (NSString *)UserDeviceId {
    // mirror SystemInfo.deviceUniqueIdentifier — iOS = identifierForVendor (nil sau reinstall sớm → "")
    NSString *uuid = UIDevice.currentDevice.identifierForVendor.UUIDString;
    return uuid ?: @"";
}

@end
