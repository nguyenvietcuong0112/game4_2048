//
//  FGMaxError.h — mirror KA/ads/max/FGMaxError.kt (spec §8): MAX error code → reason (lowercase).
//  Reason verbatim: no_fill/timeout/network/config/not_ready/already_used/render_error/invalid_state/unknown.
//  Nhận NSInteger (MAError.code) để header không phụ thuộc AppLovin (provider isolation kiểu Kotlin object).
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGMaxError : NSObject

/**
 * LOAD (ClassifyAdError): NoFill→no_fill, NetworkTimeout→timeout, NetworkError/NoNetwork→network,
 * InvalidAdUnitIdentifier + FullscreenAdInvalidViewController (nhánh iOS)→config, else unknown.
 */
+ (NSString *)classifyLoad:(NSInteger)code;

/**
 * DISPLAY (ClassifyDisplayError): FullscreenAdNotReady→not_ready, FullscreenAdAlreadyShowing→already_used,
 * AdDisplayFailed(-4205)→render_error, Network*→network,
 * FullscreenAdLoadWhileShowing/FullscreenAdInvalidViewController→invalid_state, else unknown.
 */
+ (NSString *)classifyDisplay:(NSInteger)code;

@end

NS_ASSUME_NONNULL_END
