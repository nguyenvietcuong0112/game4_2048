//
//  FGViewControllerTracker.h — thay KA/util/FGActivityTracker.kt (adaptation README):
//  iOS không cần lifecycle callback — lấy top VC on-demand từ keyWindow (UMP/Ads/IAP cần VC để present).
//
#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGViewControllerTracker : NSObject

/** ≈ FGActivityTracker.currentActivity — rootVC → duyệt presented/UINavigationController/UITabBarController chain. */
+ (UIViewController * _Nullable)topViewController;

/** Key window hiện tại (FGUtils cần safeAreaInsets, provider cần addSubview). */
+ (UIWindow * _Nullable)keyWindow;

@end

NS_ASSUME_NONNULL_END
