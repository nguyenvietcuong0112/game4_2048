//
//  FGMainThreadDispatcher.h — mirror KA/util/FGMainThreadDispatcher.kt (spec §14):
//  mọi callback từ SDK bên thứ ba phải marshal về main thread trước khi chạm state / gọi game.
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGMainThreadDispatcher : NSObject

/** Đang main thread → chạy ngay; else dispatch_async main (mirror Unity EnqueueCallback). Nuốt exception. */
+ (void)enqueue:(dispatch_block_t)action;

/** Chạy trên main sau delayMs (thay Handler.postDelayed). Nuốt exception. */
+ (void)postDelayed:(int64_t)delayMs action:(dispatch_block_t)action;

@end

NS_ASSUME_NONNULL_END
