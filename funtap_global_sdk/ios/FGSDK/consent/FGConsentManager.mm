//
//  FGConsentManager.mm — mirror KA/consent/FGConsentManager.kt + NHÁNH iOS spec §6.1 (khác Android:
//  sau UMP còn bước ATT; !canRequestAds → (false,false) bỏ ATT).
//
#import "FGConsentManager.h"
#import "../util/FGSDKDefines.h"
#import "../util/FGMainThreadDispatcher.h"
#import "../util/FGViewControllerTracker.h"
#import <AppTrackingTransparency/AppTrackingTransparency.h>
#include <exception>

#if GOOGLE_MOBILE_ADS_ENABLE
#import <UserMessagingPlatform/UserMessagingPlatform.h>
#endif

static NSString *const kFGConsentTag = @"FGConsent";

#if GOOGLE_MOBILE_ADS_ENABLE
// Kotlin `@Volatile consentInformation` — nil tới khi RequestConsent chạy UMP
// (HasConsentForAds/CanRequestAds default true, IsConsentFormAvailable default false khi nil).
static UMPConsentInformation *sConsentInformation = nil;
#endif

@implementation FGConsentManager

/**
 * spec §6.1 nhánh iOS — áp lên kết quả UMP (kể cả đường UMP lỗi → can=true):
 *  - !canRequestAds → (NO, NO), BỎ QUA ATT vì IDFA vô dụng.
 *  - ATT NotDetermined → requestTrackingAuthorization fire-and-forget (mirror Unity RequestAuthorizationTracking;
 *    ⚠️ KHÁC đường polling độc lập FGATTManager §6.2) → (canRequestAds, YES).
 *  - exception → (YES, NO) fail-open (quirk 19).
 */
+ (void)finishIOSWithCanRequestAds:(BOOL)can onResult:(void (^)(BOOL, BOOL))onResult {
    if (!can) {
        onResult(NO, NO);
        return;
    }
    @try {
        if (@available(iOS 14, *)) {
            if (ATTrackingManager.trackingAuthorizationStatus == ATTrackingManagerAuthorizationStatusNotDetermined) {
                [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
                    // fire-and-forget — không chờ kết quả (spec §6.1)
                }];
            }
        }
        onResult(YES, YES);
    } @catch (id ex) {
        NSLog(@"[%@] ATT exception → fail-open (true,false): %@", kFGConsentTag, ex);
        onResult(YES, NO); // quirk 19
    }
}

/**
 * spec §6.1:
 *  - UMP Update OK → loadAndPresentIfRequired → nhánh iOS với canRequestAds.
 *  - UMP Update lỗi → coi như consent=true (mirror Kotlin (true,true)) → vẫn qua nhánh ATT.
 *  - exception ngoài (thiếu VC...) → onResult(YES, NO) (fail-open).
 */
+ (void)RequestConsent:(void (^)(BOOL, BOOL))onResult {
    [FGMainThreadDispatcher enqueue:^{
        @try {
            try {
#if GOOGLE_MOBILE_ADS_ENABLE
                UIViewController *vc = [FGViewControllerTracker topViewController];
                if (vc == nil) {
                    NSLog(@"[%@] thiếu ViewController → fail-open (true,false)", kFGConsentTag);
                    onResult(YES, NO);
                    return;
                }
                UMPConsentInformation *ci = UMPConsentInformation.sharedInstance;
                sConsentInformation = ci;
                UMPRequestParameters *params = [[UMPRequestParameters alloc] init];
                [ci requestConsentInfoUpdateWithParameters:params
                                         completionHandler:^(NSError * _Nullable updateError) {
                    // UMP iOS callback trên main thread — Kotlin cũng không re-enqueue ở đây
                    if (updateError != nil) {
                        NSLog(@"[%@] UMP update fail %ld: %@ → consent=true", kFGConsentTag,
                              (long)updateError.code, updateError.localizedDescription);
                        [self finishIOSWithCanRequestAds:YES onResult:onResult];
                        return;
                    }
                    // Update thành công → show form nếu cần rồi trả canRequestAds
                    UIViewController *presentVC = [FGViewControllerTracker topViewController] ?: vc;
                    [UMPConsentForm loadAndPresentIfRequiredFromViewController:presentVC
                                                             completionHandler:^(NSError * _Nullable formError) {
                        if (formError != nil) {
                            NSLog(@"[%@] form error %ld: %@", kFGConsentTag,
                                  (long)formError.code, formError.localizedDescription);
                        }
                        BOOL can = YES; // mirror runCatching { canRequestAds } default true
                        @try { can = ci.canRequestAds; } @catch (id ex) { can = YES; }
                        [self finishIOSWithCanRequestAds:can onResult:onResult];
                    }];
                }];
#else
                // Không define GOOGLE_MOBILE_ADS_ENABLE → UMP coi như consent=true ngay (spec §6.1), vẫn qua nhánh ATT
                [self finishIOSWithCanRequestAds:YES onResult:onResult];
#endif
            } catch (const std::exception &e) {
                NSLog(@"[%@] consent exception → fail-open (true,false): %s", kFGConsentTag, e.what());
                onResult(YES, NO); // quirk 19
            }
        } @catch (id ex) {
            NSLog(@"[%@] consent exception → fail-open (true,false): %@", kFGConsentTag, ex);
            onResult(YES, NO); // quirk 19
        }
    }];
}

/** spec §6.1 — ConsentStatus ∈ {Obtained, NotRequired}; chưa init UMP → true. */
+ (BOOL)HasConsentForAds {
#if GOOGLE_MOBILE_ADS_ENABLE
    UMPConsentInformation *ci = sConsentInformation;
    if (ci == nil) return YES;
    UMPConsentStatus s = ci.consentStatus;
    return s == UMPConsentStatusObtained || s == UMPConsentStatusNotRequired;
#else
    return YES; // không define → true (spec §6.1)
#endif
}

+ (BOOL)CanRequestAds {
#if GOOGLE_MOBILE_ADS_ENABLE
    UMPConsentInformation *ci = sConsentInformation;
    if (ci == nil) return YES;
    @try { return ci.canRequestAds; } @catch (id ex) { return YES; } // mirror runCatching default true
#else
    return YES;
#endif
}

+ (BOOL)IsConsentFormAvailable {
#if GOOGLE_MOBILE_ADS_ENABLE
    UMPConsentInformation *ci = sConsentInformation;
    if (ci == nil) return NO; // mirror Kotlin: chưa init UMP → false
    return ci.formStatus == UMPFormStatusAvailable; // iOS formStatus ≈ isConsentFormAvailable Android
#else
    return NO;
#endif
}

+ (void)ResetConsentState {
#if GOOGLE_MOBILE_ADS_ENABLE
    @try {
        UMPConsentInformation *ci = sConsentInformation;
        if (ci != nil) [ci reset]; // mirror consentInformation?.reset()
    } @catch (id ex) {
        NSLog(@"[%@] reset fail: %@", kFGConsentTag, ex);
    }
#endif
}

/** spec §6.1 — ShowPrivacyOptionsForm(Action<bool>): true nếu form đóng không lỗi. */
+ (void)ShowPrivacyOptionsForm:(void (^)(BOOL))onResult {
    [FGMainThreadDispatcher enqueue:^{
#if GOOGLE_MOBILE_ADS_ENABLE
        UIViewController *vc = [FGViewControllerTracker topViewController];
        if (vc == nil) {
            NSLog(@"[%@] ShowPrivacyOptionsForm: thiếu ViewController", kFGConsentTag);
            onResult(NO);
            return;
        }
        [UMPConsentForm presentPrivacyOptionsFormFromViewController:vc
                                                  completionHandler:^(NSError * _Nullable formError) {
            if (formError != nil) {
                NSLog(@"[%@] privacy form error %ld: %@", kFGConsentTag,
                      (long)formError.code, formError.localizedDescription);
            }
            onResult(formError == nil);
        }];
#else
        onResult(NO); // không define → không có form
#endif
    }];
}

@end
