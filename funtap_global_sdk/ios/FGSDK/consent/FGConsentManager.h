//
//  FGConsentManager.h — mirror KA/consent/FGConsentManager.kt (spec §6.1) + NHÁNH iOS (UMP → ATT).
//  Callback (isConsent, isATTAuthorized). fail-open: mọi lỗi/exception → mặc định cho phép ads (quirk 19).
//  ⚠️ consent/ là NƠI DUY NHẤT được import UMP (provider isolation) — import UMP chỉ nằm trong .mm.
//
#pragma once
#import <Foundation/Foundation.h>

#if !defined(__OBJC__)
#error "FGConsentManager.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGConsentManager : NSObject

/**
 * spec §6.1 nhánh iOS: UMP trước → nếu !canRequestAds → (NO, NO) BỎ QUA ATT (IDFA vô dụng);
 * nếu ATT status == NotDetermined → RequestAuthorizationTracking fire-and-forget → (canRequestAds, YES).
 * UMP update lỗi → coi như consent=true. Exception bất kỳ → (YES, NO) fail-open (quirk 19).
 */
+ (void)RequestConsent:(void (^)(BOOL isConsent, BOOL isATTAuthorized))onResult;

/// spec §6.1 — ConsentStatus ∈ {Obtained, NotRequired}; chưa init UMP / không define → YES.
+ (BOOL)HasConsentForAds;

+ (BOOL)CanRequestAds;

+ (BOOL)IsConsentFormAvailable;

+ (void)ResetConsentState;

/// spec §6.1 — YES nếu form đóng không lỗi.
+ (void)ShowPrivacyOptionsForm:(void (^)(BOOL success))onResult;

@end

NS_ASSUME_NONNULL_END
