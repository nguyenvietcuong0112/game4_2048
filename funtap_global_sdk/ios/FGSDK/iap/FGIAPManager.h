//
//  FGIAPManager.h — mirror KA/iap/FGIAPManager.kt (spec §11). StoreKit 1 thay Google Play Billing (README).
//  ⚠️ chỉ module này import StoreKit. Guard compile-time UNITY_IAP_ENABLE (tên verbatim dù là StoreKit).
//  Flow verbatim:
//    Init: LoadPacksFromJson → SKProductsRequest → didReceiveResponse: cache → OnIAPInitialized(true) → FetchPurchases
//    BuyProduct: guard(init, product tồn tại, non-consumable chưa mua) → SKPayment addPayment
//    Purchased → ProcessPurchase → (verify server BỊ BYPASS → success, quirk 15) → FireTrackingSuccess
//      → OnPurchaseCompleted → ConfirmOrder (finishTransaction ≈ consume/acknowledge) → callback(true)
//  af_purchase: PurchaseConnector tự bắn (tracking own) — KHÔNG gọi thủ công ở đây.
//
#pragma once
#import <Foundation/Foundation.h>

#if !defined(__OBJC__)
#error "FGSDK iOS là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGIAPManager : NSObject

/// Kotlin `register()` — idempotent; wire facade FGEvent::IAP luôn (kể cả guard tắt), rồi loadOrders + initBilling.
+ (void)register;

@end

NS_ASSUME_NONNULL_END
