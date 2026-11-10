//
//  FGMainThreadDispatcher.mm — mirror KA/util/FGMainThreadDispatcher.kt (spec §14).
//
#import "FGMainThreadDispatcher.h"
#include <exception>

// Nuốt cả ObjC exception lẫn C++ exception để 1 callback hỏng không chặn flow (mirror runSafe Kotlin).
static void FGRunSafe(dispatch_block_t action) {
    if (!action) return;
    @try {
        try {
            action();
        } catch (const std::exception &e) {
            NSLog(@"[FGDispatcher] callback fail: %s", e.what());
        }
    } @catch (id ex) {
        NSLog(@"[FGDispatcher] callback fail: %@", ex);
    }
}

@implementation FGMainThreadDispatcher

+ (void)enqueue:(dispatch_block_t)action {
    if (NSThread.isMainThread) {
        FGRunSafe(action);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ FGRunSafe(action); });
    }
}

+ (void)postDelayed:(int64_t)delayMs action:(dispatch_block_t)action {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delayMs * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ FGRunSafe(action); });
}

@end
