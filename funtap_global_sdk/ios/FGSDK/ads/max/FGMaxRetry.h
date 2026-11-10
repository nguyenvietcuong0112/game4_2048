//
//  FGMaxRetry.h — mirror KA/ads/max/FGMaxRetry.kt (spec §7.6): retry load MAX (& AdMob giống nhau).
//  ⚠️ MaxRetryAttempts = 8 (comment gốc ghi "5" nhưng giá trị thực là 8 — quirk §16-4).
//  BaseRetryDelay = 2f. delay = 2 * 2^count → 2,4,8,16,32,64,128,256s.
//
//  Pattern gọi (spec §7.6): on load-failed gọi retryLoadAd(count, ...) RỒI count++ ở caller
//  (delay dùng count trước tăng; retry đầu = 2s). Reset count = 0 khi load success.
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGMaxRetry : NSObject

@property (class, nonatomic, readonly) NSInteger MaxRetryAttempts; // ⚠️ 8 — quirk §16-4
@property (class, nonatomic, readonly) float BaseRetryDelay;       // 2

+ (void)retryLoadAd:(NSInteger)count format:(NSString *)format loadAction:(dispatch_block_t)loadAction;

@end

NS_ASSUME_NONNULL_END
