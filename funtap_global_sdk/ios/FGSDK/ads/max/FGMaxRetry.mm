//
//  FGMaxRetry.mm — mirror KA/ads/max/FGMaxRetry.kt (spec §7.6).
//
#import "FGMaxRetry.h"
#import "../../util/FGMainThreadDispatcher.h"
#include <cmath>

static NSString *const TAG = @"FGMaxRetry";
static const NSInteger kMaxRetryAttempts = 8; // ⚠️ comment gốc "5" — giá trị verbatim là 8 (quirk §16-4)
static const float kBaseRetryDelay = 2.0f;

@implementation FGMaxRetry

+ (NSInteger)MaxRetryAttempts { return kMaxRetryAttempts; }
+ (float)BaseRetryDelay { return kBaseRetryDelay; }

+ (void)retryLoadAd:(NSInteger)count format:(NSString *)format loadAction:(dispatch_block_t)loadAction {
    if (count >= kMaxRetryAttempts) {
        NSLog(@"[%@] %@: retry exhausted (%ld >= %ld)", TAG, format, (long)count, (long)kMaxRetryAttempts);
        return;
    }
    // delay = 2 * 2^count → 2,4,8,...,256s (count = giá trị TRƯỚC khi caller tăng — spec §7.6)
    double delaySec = kBaseRetryDelay * std::pow(2.0, (double)count);
    int64_t delayMs = (int64_t)(delaySec * 1000);
    NSLog(@"[%@] %@: retry #%ld in %.1fs", TAG, format, (long)count, delaySec);
    [FGMainThreadDispatcher postDelayed:delayMs action:loadAction];
}

@end
