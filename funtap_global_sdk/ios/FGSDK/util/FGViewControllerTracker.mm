//
//  FGViewControllerTracker.mm — thay FGActivityTracker (Android). Duyệt on-demand, không giữ ref.
//
#import "FGViewControllerTracker.h"

@implementation FGViewControllerTracker

+ (UIWindow *)keyWindow {
    UIApplication *app = UIApplication.sharedApplication;
    // iOS 13+: tìm key window trong window scene foreground
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) return w;
            }
        }
    }
    // fallback: app chưa có scene foreground (lúc init sớm) → window đầu tiên
    for (UIWindow *w in app.windows) {
        if (w.isKeyWindow) return w;
    }
    // window là @optional trong UIApplicationDelegate → phải check trước khi gọi
    id<UIApplicationDelegate> delegate = app.delegate;
    if (delegate && [delegate respondsToSelector:@selector(window)]) {
        UIWindow *w = delegate.window;
        if (w) return w;
    }
    return app.windows.firstObject;
}

+ (UIViewController *)topViewController {
    UIViewController *vc = [self keyWindow].rootViewController;
    while (vc != nil) {
        if (vc.presentedViewController != nil) {
            vc = vc.presentedViewController;
        } else if ([vc isKindOfClass:UINavigationController.class]) {
            UIViewController *top = ((UINavigationController *)vc).topViewController;
            if (top == nil) break;
            vc = top;
        } else if ([vc isKindOfClass:UITabBarController.class]) {
            UIViewController *selected = ((UITabBarController *)vc).selectedViewController;
            if (selected == nil) break;
            vc = selected;
        } else {
            break;
        }
    }
    return vc;
}

@end
