//
//  FGIAPManager.mm — mirror KA/iap/FGIAPManager.kt (spec §11). StoreKit 1 (README):
//  Google Play Billing → SKProductsRequest/SKPaymentQueue; consume/acknowledge → finishTransaction;
//  queryPurchasesAsync → ConfirmedOrders (persist) + transaction chưa finish trong SKPaymentQueue.
//  ⚠️ quirk 15: verify server bypass (trả success ngay); endpoint verify-iap để comment.
//  Consumable về mà không có lượt buyProduct nào chờ → GIỮ (chưa finish), trả ở lần buyProduct kế qua callback
//  (mirror Kotlin `held`): game cộng đồ trong callback, trả lúc mở app chỉ có event → game không nghe là mất đồ.
//
#import "FGIAPManager.h"
#import "FGIAPModels.h"
#import "../util/FGSDKDefines.h"
#import "../util/FGMainThreadDispatcher.h"
#import "../event/FGEvent.h"

#if UNITY_IAP_ENABLE
#import <StoreKit/StoreKit.h>
#endif

#include <atomic>
#include <functional>
#include <string>
#include <unordered_map>
#include <utility>

static NSString *const kFGIAPTag = @"FGIAP";
static NSString *const kFGIAPPacksResourceName = @"iap_packs"; // iap_packs.json — NSBundle thay assets (README)
// Android: SharedPreferences "FGSDK_IAP" → NSUserDefaults; key + format JSON map<productId,count> VERBATIM
static NSString *const kFGIAPOrdersKey = @"ConfirmedOrders";

/** Context của BuyProduct đang chờ (productId → tracking params) để FireTrackingSuccess sau. */
struct FGIAPPurchaseCtx {
    NSString *location;
    NSString *playMode;
    NSInteger level = 0;
    std::function<void(BOOL, NSString *)> cb;
};

static BOOL sRegistered = NO;
static std::atomic<bool> sIsInitialized{false}; // Kotlin @Volatile

static NSMutableDictionary<NSString *, FGProductInfo *> *sProducts;  // productId → info
static NSMutableDictionary<NSString *, NSNumber *> *sTypeById;       // productId → loại (từ packs)
static NSMutableDictionary<NSString *, NSNumber *> *sOrders;         // ConfirmedOrders: productId → count
static std::unordered_map<std::string, FGIAPPurchaseCtx> sPendingCtx;
static std::function<void(BOOL)> sRestoreCb; // callback RestorePurchase đang chờ restoreCompletedTransactions

#if UNITY_IAP_ENABLE
static SKProductsRequest *sProductsRequest; // giữ strong — SKProductsRequest không tự retain khi chạy
static id sObserver;                        // FGIAPStoreObserver — giữ strong: addTransactionObserver KHÔNG retain observer
// consumable đã trả tiền, CHƯA nhận hàng → chờ buyProduct (không cần "delivered" như Kotlin: finishTransaction
// gọi ngay sau OnPurchaseCompleted, không có đường lỗi async như consumeAsync)
static NSMutableDictionary<NSString *, SKPaymentTransaction *> *sHeld;

/** Delegate/observer StoreKit — instance ObjC riêng vì Kotlin object → class methods (README). */
@interface FGIAPStoreObserver : NSObject <SKProductsRequestDelegate, SKPaymentTransactionObserver>
@end
#endif

@interface FGIAPManager ()
+ (void)wireFacade;
+ (void)buyProduct:(NSString *)productId
          location:(NSString *)location
          playMode:(NSString *)playMode
             level:(NSInteger)level
                cb:(std::function<void(BOOL, NSString *)>)cb;
+ (void)restorePurchases:(std::function<void(BOOL)>)cb;
#if UNITY_IAP_ENABLE
+ (void)initBilling;
+ (FGIAPPacks *)loadPacks;
+ (void)fetchProducts;
+ (void)cacheProduct:(SKProduct *)product;
+ (void)onProductsFetched;
+ (void)fetchPurchases:(std::function<void(BOOL)>)cb;
+ (void)handleTransaction:(SKPaymentTransaction *)t;
+ (void)processPurchase:(SKPaymentTransaction *)t;
+ (void)processRestored:(SKPaymentTransaction *)t;
+ (void)failTransaction:(SKPaymentTransaction *)t;
+ (void)fireTrackingSuccess:(NSString *)productId
                transaction:(SKPaymentTransaction *)t
                       info:(FGProductInfo *)info
                        ctx:(const FGIAPPurchaseCtx *)ctx;
+ (void)confirmOrder:(NSString *)productId transaction:(SKPaymentTransaction *)t;
+ (void)onRestoreFinished:(BOOL)success;
+ (void)loadOrders;
+ (void)saveOrders;
#endif
@end

@implementation FGIAPManager

// ── Bootstrap ────────────────────────────────────────────────────────────────
+ (void)register {
    if (sRegistered) return;
    sRegistered = YES;
    sProducts = [NSMutableDictionary dictionary];
    sTypeById = [NSMutableDictionary dictionary];
    sOrders = [NSMutableDictionary dictionary];
    [self wireFacade]; // wire luôn kể cả guard tắt (mirror Kotlin) — buyProduct sẽ fail "not_initialized"
#if !UNITY_IAP_ENABLE
    NSLog(@"[%@] UNITY_IAP_ENABLE=false → IAP off", kFGIAPTag);
#else
    [self loadOrders];
    [self initBilling];
#endif
}

+ (void)wireFacade {
    FGEvent::IAP::BuyProduct = [](NSString *productId, NSString *location, NSString *playMode,
                                  NSInteger level, std::function<void(BOOL, NSString *)> cb) {
        [FGIAPManager buyProduct:productId location:location playMode:playMode level:level cb:std::move(cb)];
    };
    FGEvent::IAP::GetProductTitle = [](NSString *productId) -> NSString * {
        FGProductInfo *info = productId ? sProducts[productId] : nil;
        return info ? info.title : @"";
    };
    // ⚠️ localizedPriceString (kèm ký hiệu tiền tệ)
    FGEvent::IAP::GetProductPrice = [](NSString *productId) -> NSString * {
        FGProductInfo *info = productId ? sProducts[productId] : nil;
        return info ? info.priceString : @"";
    };
    FGEvent::IAP::RestorePurchase = [](std::function<void(BOOL)> cb) {
        [FGIAPManager restorePurchases:std::move(cb)];
    };
    // NonConsumable check ConfirmedOrders
    FGEvent::IAP::IsPurchased = [](NSString *productId) -> BOOL {
        return productId != nil && sOrders[productId] != nil;
    };
    FGEvent::IAP::GetPurchaseCount = [](NSString *productId) -> NSInteger {
        return productId ? sOrders[productId].integerValue : 0;
    };
}

// ── Buy ──────────────────────────────────────────────────────────────────────
+ (void)buyProduct:(NSString *)productId
          location:(NSString *)location
          playMode:(NSString *)playMode
             level:(NSInteger)level
                cb:(std::function<void(BOOL, NSString *)>)cb {
    if (!sIsInitialized.load()) { if (cb) cb(NO, @"not_initialized"); return; }
    FGProductInfo *info = productId ? sProducts[productId] : nil;
    if (!info) { if (cb) cb(NO, @"product_not_found"); return; }
    if (info.type == FGProductTypeNonConsumable && sOrders[productId] != nil) {
        if (cb) cb(NO, @"already_purchased");
        return;
    }
#if UNITY_IAP_ENABLE
    // Gói này còn giao dịch đã trả tiền mà chưa nhận hàng → trả luôn qua callback lượt mua này, KHÔNG addPayment
    // (addPayment thêm lần nữa = user trả tiền 2 lần cho 1 gói).
    SKPaymentTransaction *heldTx = sHeld[productId];
    if (heldTx) {
        sPendingCtx[std::string(productId.UTF8String)] =
            FGIAPPurchaseCtx{location ?: @"", playMode ?: @"", level, std::move(cb)};
        [self processPurchase:heldTx];
        return;
    }
    // guard "no_activity" Android-only (launchBillingFlow cần Activity) — StoreKit không cần, bỏ (README adaptation)
    SKProduct *product = [info.details isKindOfClass:[SKProduct class]] ? (SKProduct *)info.details : nil;
    if (!product) { if (cb) cb(NO, @"product_not_found"); return; }
    sPendingCtx[std::string(productId.UTF8String)] =
        FGIAPPurchaseCtx{location ?: @"", playMode ?: @"", level, std::move(cb)};
    // addPayment không trả result đồng bộ như launchBillingFlow → không có nhánh "flow_<code>";
    // lỗi về qua updatedTransactions (Failed)
    [[SKPaymentQueue defaultQueue] addPayment:[SKPayment paymentWithProduct:product]];
#endif
}

// ── Restore ──────────────────────────────────────────────────────────────────
+ (void)restorePurchases:(std::function<void(BOOL)>)cb {
    if (!sIsInitialized.load()) { if (cb) cb(NO); return; }
#if UNITY_IAP_ENABLE
    // Kotlin fetchPurchases(cb) = queryPurchasesAsync; StoreKit tương đương = restoreCompletedTransactions —
    // callback khi restoreCompletedTransactionsFinished / FailedWithError (observer)
    sRestoreCb = std::move(cb);
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
#endif
}

#if UNITY_IAP_ENABLE

// ── Init: packs + billing ────────────────────────────────────────────────────
+ (void)initBilling {
    FGIAPPacks *packs = [self loadPacks];
    if (!packs) {
        NSLog(@"[%@] iap_packs.json thiếu/parse lỗi", kFGIAPTag);
        FGEvent::IAP::OnIAPInitialized.invoke(NO);
        return;
    }
    for (NSString *pid in packs.consumablePack) sTypeById[pid] = @(FGProductTypeConsumable);
    for (NSString *pid in packs.nonConsumablePack) sTypeById[pid] = @(FGProductTypeNonConsumable);
    for (NSString *pid in packs.subscriptionPack) sTypeById[pid] = @(FGProductTypeSubscription);

    // ≈ BillingClient setListener + startConnection: StoreKit không có bước connect,
    // addTransactionObserver xong fetch luôn (transaction chưa finish sẽ về qua updatedTransactions)
    sHeld = [NSMutableDictionary dictionary]; // trước addTransactionObserver: giao dịch tồn về ngay sau khi add
    sObserver = [[FGIAPStoreObserver alloc] init];
    [[SKPaymentQueue defaultQueue] addTransactionObserver:sObserver];
    [self fetchProducts];
}

+ (FGIAPPacks *)loadPacks {
    NSString *path = [[NSBundle mainBundle] pathForResource:kFGIAPPacksResourceName ofType:@"json"];
    if (!path) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (!data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return nil; // mirror runCatching.getOrNull
    return [FGIAPPacks fromDict:(NSDictionary *)json];
}

+ (void)fetchProducts {
    // StoreKit query 1 request cho TẤT CẢ productId (không tách INAPP/SUBS như Billing)
    if (sTypeById.count == 0) { [self onProductsFetched]; return; } // mirror remaining==0
    NSSet<NSString *> *ids = [NSSet setWithArray:sTypeById.allKeys];
    sProductsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:ids];
    sProductsRequest.delegate = sObserver;
    [sProductsRequest start];
}

+ (void)cacheProduct:(SKProduct *)product {
    NSString *pid = product.productIdentifier;
    NSNumber *typeNum = pid ? sTypeById[pid] : nil;
    if (!typeNum) return; // mirror typeById[id] ?: return
    // formattedPrice Billing → NSNumberFormatter currencyStyle + priceLocale (kèm ký hiệu tiền tệ)
    NSNumberFormatter *fmt = [[NSNumberFormatter alloc] init];
    fmt.numberStyle = NSNumberFormatterCurrencyStyle;
    fmt.locale = product.priceLocale;
    NSString *priceString = [fmt stringFromNumber:product.price] ?: @"";
    // priceAmountMicros Billing → price * 1e6; llround tránh sai số float khi cast
    long long priceMicros = (long long)llround(product.price.doubleValue * 1e6);
    NSString *currency = [product.priceLocale objectForKey:NSLocaleCurrencyCode] ?: @"";
    sProducts[pid] = [[FGProductInfo alloc] initWithProductId:pid
                                                         type:(FGProductType)typeNum.integerValue
                                                        title:(product.localizedTitle ?: @"")
                                                  priceString:priceString
                                                  priceMicros:priceMicros
                                                     currency:currency
                                                      details:product];
}

+ (void)onProductsFetched {
    sProductsRequest = nil;
    sIsInitialized.store(true);
    FGEvent::IAP::OnIAPInitialized.invoke(YES);
    [self fetchPurchases:nullptr];
}

// ── FetchPurchases (init-time) ───────────────────────────────────────────────
/**
 * mirror vai trò Kotlin fetchPurchases/queryPurchasesAsync: StoreKit không có query async —
 * trạng thái sở hữu = ConfirmedOrders (persist) + transaction chưa finish còn trong SKPaymentQueue.
 * KHÔNG finish ở đây — observer sẽ nhận lại qua updatedTransactions và xử lý đủ flow.
 */
+ (void)fetchPurchases:(std::function<void(BOOL)>)cb {
    for (SKPaymentTransaction *t in [SKPaymentQueue defaultQueue].transactions) {
        if (t.transactionState != SKPaymentTransactionStatePurchased &&
            t.transactionState != SKPaymentTransactionStateRestored) continue;
        NSString *pid = t.payment.productIdentifier;
        NSNumber *typeNum = pid ? sTypeById[pid] : nil;
        // consumable tồn KHÔNG tính là "đã mua" — processPurchase giữ nó chờ buyProduct (mirror Kotlin queryPurchases)
        if (typeNum != nil && typeNum.integerValue == FGProductTypeConsumable) continue;
        if (pid && sOrders[pid] == nil) { sOrders[pid] = @1; [self saveOrders]; } // mirror orders[id]=1 nếu chưa có
    }
    if (cb) cb(YES);
    FGEvent::IAP::OnRestorePurchasesCompleted.invoke(YES); // mirror Kotlin: fetchPurchases init-time cũng fire
}

// ── Transactions ─────────────────────────────────────────────────────────────
+ (void)handleTransaction:(SKPaymentTransaction *)t {
    switch (t.transactionState) {
        case SKPaymentTransactionStatePurchasing: // đang xử lý — bỏ qua (mirror else -> Unit)
            break;
        case SKPaymentTransactionStateDeferred:   // chờ duyệt (Ask to Buy) — mirror PENDING
            FGEvent::IAP::OnPurchaseProcessing.invoke(t.payment.productIdentifier ?: @"");
            break;
        case SKPaymentTransactionStatePurchased:
            [self processPurchase:t];
            break;
        case SKPaymentTransactionStateFailed:
            [self failTransaction:t];
            break;
        case SKPaymentTransactionStateRestored:
            [self processRestored:t];
            break;
    }
}

/**
 * spec §11 — ⚠️ verify server BỊ BYPASS: trả success ngay (khối verify comment). Native giữ bypass (quirk 15).
 * // ── Verify server (đang tắt) ──
 * // POST {base_api_domain}/payment/verify-iap
 * //   header: x-app-key: {app_key}, Authorization: Bearer {token}
 * //   body: {device_id, device_name, device_os, os, network, app_key, game_code, product_id, receipt}
 * //   response code → 0 SuccessProduction / 2 SuccessSandbox / 4 Duplicate
 */
+ (void)processPurchase:(SKPaymentTransaction *)t {
    NSString *pid = t.payment.productIdentifier;
    if (!pid) return; // mirror products.firstOrNull() ?: return
    [sHeld removeObjectForKey:pid];
    auto it = sPendingCtx.find(std::string(pid.UTF8String));
    NSNumber *typeNum = sTypeById[pid];
    // Consumable về mà không có lượt buyProduct nào chờ (giao dịch chưa finish quay lại lúc mở app, Ask to Buy duyệt
    // muộn...) → không có callback cho game cộng đồ → GIỮ, chưa finish; trả ở lần buyProduct kế (mirror Kotlin).
    // typeNum nil = product lạ: FGProductTypeConsumable = 0 nên phải check nil trước.
    if (it == sPendingCtx.end() && typeNum != nil && typeNum.integerValue == FGProductTypeConsumable) {
        sHeld[pid] = t;
        NSLog(@"[%@] đơn %@ (%@) đã trả tiền nhưng chưa nhận hàng → trả ở lần buyProduct kế",
              kFGIAPTag, pid, t.transactionIdentifier);
        return;
    }
    FGProductInfo *info = sProducts[pid];
    FGIAPPurchaseCtx ctx;
    bool hasCtx = false;
    if (it != sPendingCtx.end()) { // mirror pendingCtx.remove
        ctx = std::move(it->second);
        sPendingCtx.erase(it);
        hasCtx = true;
    }
    NSString *txId = t.transactionIdentifier ?: @""; // orderId Billing → transactionIdentifier
    [self fireTrackingSuccess:pid transaction:t info:info ctx:(hasCtx ? &ctx : nullptr)];
    FGEvent::IAP::OnPurchaseCompleted.invoke(pid, txId);
    [self confirmOrder:pid transaction:t];
    if (hasCtx && ctx.cb) ctx.cb(YES, txId);
}

/** spec §11 — iap_sdk → Firebase {product_id, value(localizedPrice), currency(iso), transaction_id, + tracking params}. */
+ (void)fireTrackingSuccess:(NSString *)productId
                transaction:(SKPaymentTransaction *)t
                       info:(FGProductInfo *)info
                        ctx:(const FGIAPPurchaseCtx *)ctx {
    NSMutableDictionary<NSString *, id> *params = [NSMutableDictionary dictionary];
    params[@"product_id"] = productId;
    params[@"value"] = @(info ? info.localizedPrice : 0.0);
    params[@"currency"] = info ? info.currency : @"";
    params[@"transaction_id"] = t.transactionIdentifier ?: @"";
    if (ctx) {
        params[@"play_mode"] = ctx->playMode;
        params[@"level"] = @(ctx->level);
        params[@"location"] = ctx->location;
    }
    if (FGEvent::Tracking::LogEventWithParams) {
        FGEvent::Tracking::LogEventWithParams(@"iap_sdk", params); // → CHỈ Firebase
        // ⚠️ in_app_purchase — CHỈ iOS (spec §11); spec KHÔNG định nghĩa param riêng → dùng CÙNG dict với iap_sdk
        FGEvent::Tracking::LogEventWithParams(@"in_app_purchase", params);
    }
    // af_purchase: PurchaseConnector tự bắn (không gọi thủ công)
}

+ (void)confirmOrder:(NSString *)productId transaction:(SKPaymentTransaction *)t {
    sOrders[productId] = @(sOrders[productId].intValue + 1);
    [self saveOrders];
    // consume (consumable) / acknowledge (còn lại) Android → finishTransaction cho MỌI loại (StoreKit 1)
    [[SKPaymentQueue defaultQueue] finishTransaction:t];
}

+ (void)failTransaction:(SKPaymentTransaction *)t {
    NSString *pid = t.payment.productIdentifier ?: @"";
    // StoreKit báo lỗi THEO transaction (biết productId) — không cần failAll snapshot như Billing;
    // reason string mirror Kotlin: USER_CANCELED → "user_canceled", còn lại "billing_<code>"
    NSInteger code = t.error ? t.error.code : 0;
    NSString *reason = (code == SKErrorPaymentCancelled)
        ? @"user_canceled"
        : [NSString stringWithFormat:@"billing_%ld", (long)code];
    FGIAPPurchaseCtx ctx;
    bool hasCtx = false;
    auto it = sPendingCtx.find(std::string(pid.UTF8String));
    if (it != sPendingCtx.end()) {
        ctx = std::move(it->second);
        sPendingCtx.erase(it);
        hasCtx = true;
    }
    FGEvent::IAP::OnPurchaseFailed.invoke(pid, reason);
    if (hasCtx && ctx.cb) ctx.cb(NO, reason);
    [[SKPaymentQueue defaultQueue] finishTransaction:t];
}

/** Restored — xử lý như queryPurchases Kotlin: orders[id]=1 nếu chưa có + finish (≈ acknowledge). */
+ (void)processRestored:(SKPaymentTransaction *)t {
    NSString *pid = t.payment.productIdentifier ?: t.originalTransaction.payment.productIdentifier;
    if (pid && sOrders[pid] == nil) { sOrders[pid] = @1; [self saveOrders]; }
    [[SKPaymentQueue defaultQueue] finishTransaction:t];
}

+ (void)onRestoreFinished:(BOOL)success {
    auto cb = std::move(sRestoreCb);
    sRestoreCb = nullptr;
    if (cb) cb(success);
    FGEvent::IAP::OnRestorePurchasesCompleted.invoke(success);
}

// ── ConfirmedOrders persistence ──────────────────────────────────────────────
+ (void)loadOrders {
    NSString *json = [[NSUserDefaults standardUserDefaults] stringForKey:kFGIAPOrdersKey];
    if (!json) return;
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return;
    id map = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![map isKindOfClass:[NSDictionary class]]) return;
    [(NSDictionary *)map enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
        // mirror Kotlin Gson Map<String, Double> → toInt
        if ([k isKindOfClass:[NSString class]] && [v isKindOfClass:[NSNumber class]])
            sOrders[(NSString *)k] = @([(NSNumber *)v intValue]);
    }];
}

+ (void)saveOrders {
    NSData *data = [NSJSONSerialization dataWithJSONObject:sOrders options:0 error:nil];
    if (!data) return;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [[NSUserDefaults standardUserDefaults] setObject:json forKey:kFGIAPOrdersKey];
}

#endif // UNITY_IAP_ENABLE

@end

#if UNITY_IAP_ENABLE

@implementation FGIAPStoreObserver

// spec §14 — callback StoreKit về queue bất kỳ → marshal FGMainThreadDispatcher trước khi chạm state/gọi game

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    [FGMainThreadDispatcher enqueue:^{
        for (SKProduct *p in response.products) [FGIAPManager cacheProduct:p];
        for (NSString *invalid in response.invalidProductIdentifiers)
            NSLog(@"[%@] product id không có trên App Store Connect: %@", kFGIAPTag, invalid);
        [FGIAPManager onProductsFetched];
    }];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    [FGMainThreadDispatcher enqueue:^{
        // mirror nhánh billing setup fail Kotlin: log + OnIAPInitialized(false)
        NSLog(@"[%@] SKProductsRequest fail: %@", kFGIAPTag, error);
        sProductsRequest = nil;
        FGEvent::IAP::OnIAPInitialized.invoke(NO);
    }];
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray<SKPaymentTransaction *> *)transactions {
    [FGMainThreadDispatcher enqueue:^{
        for (SKPaymentTransaction *t in transactions) [FGIAPManager handleTransaction:t];
    }];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue {
    [FGMainThreadDispatcher enqueue:^{
        [FGIAPManager onRestoreFinished:YES];
    }];
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    [FGMainThreadDispatcher enqueue:^{
        NSLog(@"[%@] restoreCompletedTransactions fail: %@", kFGIAPTag, error);
        [FGIAPManager onRestoreFinished:NO];
    }];
}

@end

#endif // UNITY_IAP_ENABLE
