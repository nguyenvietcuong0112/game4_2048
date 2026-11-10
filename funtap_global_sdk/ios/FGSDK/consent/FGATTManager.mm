//
//  FGATTManager.mm — spec §6.2. Giữ nguyên cơ chế POLLING của Unity (không resolve bằng
//  completion OS) để hành vi/timing giống 100% — kể cả timeout 60s → DENIED.
//
#import "FGATTManager.h"
#import "../util/FGMainThreadDispatcher.h"
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#include <atomic>

static NSString *const kFGATTTag = @"FGATT";

// spec §6.2 — verbatim
static const int64_t kPollIntervalMs = 200;
static const int64_t kTimeoutSeconds = 60;

// C# static fields _resolved/_authorized → std::atomic
static std::atomic<bool> sResolved{false};
static std::atomic<bool> sAuthorized{false};

@implementation FGATTManager

+ (BOOL)IsAuthorized {
    return sResolved.load() && sAuthorized.load();
}

// resolve chung — đã trên main thread (RequestTrackingAsync enqueue main + timer chạy main queue)
+ (void)resolveAuthorized:(BOOL)authorized onResult:(void (^ _Nullable)(BOOL))onResult {
    sResolved.store(true);
    sAuthorized.store(authorized);
    if (onResult) onResult(authorized);
}

+ (void)RequestTrackingAsync:(void (^ _Nullable)(BOOL))onResult {
    [FGMainThreadDispatcher enqueue:^{
        if (@available(iOS 14, *)) {
            ATTrackingManagerAuthorizationStatus st = ATTrackingManager.trackingAuthorizationStatus;
            if (st != ATTrackingManagerAuthorizationStatusNotDetermined) {
                // đã có kết quả từ trước → resolve ngay (spec §6.2)
                [self resolveAuthorized:(st == ATTrackingManagerAuthorizationStatusAuthorized) onResult:onResult];
                return;
            }
            // show dialog; completion CHỈ để OS gọi — kết quả lấy bằng polling (mirror Unity)
            [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus s) {}];

            __block int64_t elapsedMs = 0;
            dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
            dispatch_source_set_timer(timer,
                                      dispatch_time(DISPATCH_TIME_NOW, kPollIntervalMs * NSEC_PER_MSEC),
                                      (uint64_t)(kPollIntervalMs * NSEC_PER_MSEC),
                                      10 * NSEC_PER_MSEC);
            // handler giữ timer strong — GCD release handler sau cancel nên không leak
            dispatch_source_set_event_handler(timer, ^{
                if (@available(iOS 14, *)) {
                    elapsedMs += kPollIntervalMs;
                    ATTrackingManagerAuthorizationStatus cur = ATTrackingManager.trackingAuthorizationStatus;
                    if (cur != ATTrackingManagerAuthorizationStatusNotDetermined) {
                        dispatch_source_cancel(timer);
                        [self resolveAuthorized:(cur == ATTrackingManagerAuthorizationStatusAuthorized) onResult:onResult];
                    } else if (elapsedMs >= kTimeoutSeconds * 1000) {
                        dispatch_source_cancel(timer);
                        NSLog(@"[%@] poll timeout %llds → DENIED (spec §6.2)", kFGATTTag, (long long)kTimeoutSeconds);
                        [self resolveAuthorized:NO onResult:onResult];
                    }
                }
            });
            dispatch_resume(timer);
        } else {
            // < iOS 14 không có ATT → coi như Authorized (mirror binding Unity trả AUTHORIZED khi thiếu framework)
            [self resolveAuthorized:YES onResult:onResult];
        }
    }];
}

@end
