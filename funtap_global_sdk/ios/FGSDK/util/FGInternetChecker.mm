//
//  FGInternetChecker.mm — mirror KA/util/FGInternetChecker.kt (spec §14).
//  NWPathMonitor queue = main → handler đã ở main thread (thoả rule marshal §14),
//  vẫn bọc FGMainThreadDispatcher.enqueue để nuốt exception như runSafe Kotlin.
//
#import "FGInternetChecker.h"
#import "FGMainThreadDispatcher.h"
#import <Network/Network.h>
#include "../event/FGEvent.h"

static nw_path_monitor_t sMonitor = nil;
static BOOL sStarted = NO;
// state chỉ đọc/ghi trên main queue (handler + getters chạy từ main theo flow SDK)
static BOOL sConnected = NO;
static BOOL sHasBaseline = NO;
static NSString *sNetworkType = @"none";

@implementation FGInternetChecker

+ (BOOL)isConnected { return sConnected; }

+ (NSString *)networkType { return sNetworkType; }

+ (void)start {
    if (sStarted) return;
    sStarted = YES;
    sHasBaseline = NO; // update đầu tiên = baseline (≈ computeConnected() lúc start bên Kotlin)

    sMonitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(sMonitor, dispatch_get_main_queue());
    nw_path_monitor_set_update_handler(sMonitor, ^(nw_path_t _Nonnull path) {
        BOOL now = (nw_path_get_status(path) == nw_path_status_satisfied);
        NSString *type = @"none";
        if (now) {
            if (nw_path_uses_interface_type(path, nw_interface_type_wifi)) type = @"wifi";
            else if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) type = @"cellular";
            // else giữ "none" — mirror when{} Kotlin (transport khác wifi/cellular → "none")
        }
        [FGMainThreadDispatcher enqueue:^{
            sNetworkType = type;
            if (!sHasBaseline) {
                // set baseline, KHÔNG emit lúc khởi động (spec §14)
                sHasBaseline = YES;
                sConnected = now;
                return;
            }
            if (now != sConnected) {
                sConnected = now;
                if (now) FGEvent::Network::OnNetworkRestored.invoke();
                else FGEvent::Network::OnNetworkLost.invoke();
            }
        }];
    });
    nw_path_monitor_start(sMonitor);
}

+ (void)stop {
    if (!sStarted) return;
    sStarted = NO;
    if (sMonitor) {
        nw_path_monitor_cancel(sMonitor);
        sMonitor = nil;
    }
    // giữ sConnected như Kotlin stop() (không reset trạng thái đã biết)
}

@end
