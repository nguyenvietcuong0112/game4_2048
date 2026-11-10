//
//  FGUtils.h — mirror FGUtils (Unity, spec §7.7): MREC coordinate conversion.
//  Quy ước đơn vị: input p là toạ độ MÀN HÌNH bằng PIXEL, gốc góc dưới-trái (Unity Screen convention);
//  output là toạ độ dp/point góc TRÊN-TRÁI của MREC (nhân lại density khi set frame px nếu cần).
//
#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGUtils : NSObject

/** MREC 300×250 dp → nửa chiều rộng/cao (spec §7.7). */
@property (class, nonatomic, readonly) CGFloat MRecHalfWidthDp;  // 150
@property (class, nonatomic, readonly) CGFloat MRecHalfHeightDp; // 125

/** density: iOS = UIScreen.mainScreen.scale (≈ DisplayMetrics.density Android). */
+ (CGFloat)GetScreenDensity;

/** (300*density, 250*density) — PIXEL (spec §4.3/§7.7). */
+ (CGSize)GetMRecSize;

/**
 * spec §7.7 — ScreenToMRecPosMax (CÓ safe-area). p = px gốc dưới-trái.
 *   x1 = p.x - safeArea.x;  topOffset = Screen.height - safeArea.height - safeArea.y (= top inset px)
 *   y1 = Screen.height - p.y - topOffset
 *   return (x1/density - 150, y1/density - 125)   [dp/point góc trên-trái MREC]
 */
+ (CGPoint)ScreenToMRecPosMax:(CGPoint)p;

/**
 * spec §7.7 — ScreenToMRecPosAdmob (KHÔNG safe-area). p = px gốc dưới-trái.
 *   x1 = p.x;  y1 = Screen.height - p.y
 *   return (x1/density - 150, y1/density - 125)   [dp/point góc trên-trái MREC]
 */
+ (CGPoint)ScreenToMRecPosAdmob:(CGPoint)p;

@end

NS_ASSUME_NONNULL_END
