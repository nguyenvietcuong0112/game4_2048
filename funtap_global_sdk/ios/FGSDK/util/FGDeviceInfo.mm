//
//  FGDeviceInfo.mm — mirror KA/util/FGDeviceInfo.kt, nhánh iOS.
//
#import "FGDeviceInfo.h"
#import "FGInternetChecker.h"
#import <UIKit/UIKit.h>

@implementation FGDeviceInfo

+ (NSString *)OS { return @"ios"; }

+ (NSString *)deviceName {
    UIDevice *d = UIDevice.currentDevice;
    NSString *name = [NSString stringWithFormat:@"%@ %@", d.model ?: @"", d.name ?: @""];
    return [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

+ (NSString *)deviceOs {
    UIDevice *d = UIDevice.currentDevice;
    // systemName = "iOS" → "iOS 17.5" (mirror "Android ${RELEASE}")
    return [NSString stringWithFormat:@"%@ %@", d.systemName, d.systemVersion];
}

+ (NSString *)packageName {
    return NSBundle.mainBundle.bundleIdentifier ?: @"";
}

+ (NSString *)appVersion {
    NSString *v = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    return v ?: @"";
}

+ (long long)bundleNumber {
    NSString *v = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    return v ? (long long)v.longLongValue : 0LL; // parse fail → 0 (mirror getOrDefault(0L))
}

+ (NSString *)network {
    // iOS không query sync như ConnectivityManager → đọc state monitor (chưa start → "none")
    return FGInternetChecker.networkType;
}

@end
