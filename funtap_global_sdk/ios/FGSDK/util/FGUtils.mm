//
//  FGUtils.mm — mirror FGUtils (Unity, spec §7.7). Công thức VERBATIM.
//  UIKit tính bằng point → px = point * scale (Screen.height px = bounds.height * scale, README).
//
#import "FGUtils.h"
#import "FGViewControllerTracker.h"

@implementation FGUtils

+ (CGFloat)MRecHalfWidthDp { return 150.0; }

+ (CGFloat)MRecHalfHeightDp { return 125.0; }

+ (CGFloat)GetScreenDensity {
    return UIScreen.mainScreen.scale;
}

+ (CGSize)GetMRecSize {
    CGFloat density = [self GetScreenDensity];
    return CGSizeMake(300.0 * density, 250.0 * density); // px
}

+ (CGPoint)ScreenToMRecPosMax:(CGPoint)p {
    CGFloat density = [self GetScreenDensity];
    CGFloat screenHeightPx = UIScreen.mainScreen.bounds.size.height * density;
    // safeAreaInsets là point → đổi sang px trước khi trừ (input p là px)
    UIEdgeInsets insets = FGViewControllerTracker.keyWindow.safeAreaInsets; // window nil → insets = 0
    CGFloat x1 = p.x - insets.left * density;               // px
    CGFloat topOffsetPx = insets.top * density;             // = Screen.height - safeArea.height - safeArea.y
    CGFloat y1 = screenHeightPx - p.y - topOffsetPx;        // px, lật gốc dưới-trái → trên-trái
    return CGPointMake(x1 / density - FGUtils.MRecHalfWidthDp,
                       y1 / density - FGUtils.MRecHalfHeightDp); // dp/point
}

+ (CGPoint)ScreenToMRecPosAdmob:(CGPoint)p {
    CGFloat density = [self GetScreenDensity];
    CGFloat screenHeightPx = UIScreen.mainScreen.bounds.size.height * density;
    CGFloat x1 = p.x;                                       // px, KHÔNG safe-area
    CGFloat y1 = screenHeightPx - p.y;                      // px
    return CGPointMake(x1 / density - FGUtils.MRecHalfWidthDp,
                       y1 / density - FGUtils.MRecHalfHeightDp); // dp/point
}

@end
