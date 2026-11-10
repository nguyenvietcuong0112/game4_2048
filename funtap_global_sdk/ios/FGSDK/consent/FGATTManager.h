//
//  FGATTManager.h — spec §6.2 (iOS only, KHÔNG có bản Kotlin): API polling ATT độc lập.
//  ⚠️ Có 2 đường ATT khác nhau: FGConsentManager.RequestConsent gọi fire-and-forget;
//  FGATTManager là API polling độc lập (spec §6.2) — KHÔNG gộp chung.
//
#pragma once
#import <Foundation/Foundation.h>

#if !defined(__OBJC__)
#error "FGATTManager.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGATTManager : NSObject

/// spec §6.2 — IsAuthorized = _resolved && _authorized (NO tới khi RequestTrackingAsync resolve).
+ (BOOL)IsAuthorized;

/**
 * spec §6.2 — status != NotDetermined → resolve ngay; else show dialog + poll 200ms
 * tới khi có kết quả hoặc timeout 60s (timeout → DENIED). Dialog chỉ show 1 lần/cài đặt
 * (OS quản lý qua NotDetermined). Unity Task<bool> → completion block, gọi trên main thread.
 */
+ (void)RequestTrackingAsync:(void (^ _Nullable)(BOOL isAuthorized))onResult;

@end

NS_ASSUME_NONNULL_END
