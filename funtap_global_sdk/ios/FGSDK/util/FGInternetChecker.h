//
//  FGInternetChecker.h — mirror KA/util/FGInternetChecker.kt (spec §14):
//  chỉ emit FGEvent::Network khi ĐỔI trạng thái, KHÔNG phát event lúc khởi động.
//  iOS thay poll ConnectivityManager 5s bằng NWPathMonitor (Network.framework) — adaptation README.
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGInternetChecker : NSObject

@property (class, nonatomic, readonly) BOOL isConnected;

/**
 * Loại mạng hiện tại "wifi"/"cellular"/"none" (cho FGDeviceInfo.network — iOS không query sync
 * được như ConnectivityManager nên dùng state của monitor; chưa start() → "none").
 */
@property (class, nonatomic, readonly) NSString *networkType;

/** Gọi từ init SDK. Update đầu tiên của monitor = baseline, KHÔNG emit (spec §14). */
+ (void)start;

+ (void)stop;

@end

NS_ASSUME_NONNULL_END
