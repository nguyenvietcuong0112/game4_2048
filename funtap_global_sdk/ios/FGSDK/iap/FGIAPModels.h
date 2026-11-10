//
//  FGIAPModels.h — mirror KA/iap/FGIAPModels.kt (spec §11).
//  Field JSON VERBATIM: consumablePack / nonConsumablePack / subscriptionPack.
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * spec §11 — iap_packs.json: chỉ product ID string, KHÔNG reward/display_name.
 * { "consumablePack": [...], "nonConsumablePack": [...], "subscriptionPack": [...] }
 * Field vắng trong JSON giữ default rỗng (mirror Gson default emptyList).
 */
@interface FGIAPPacks : NSObject
@property (nonatomic, copy) NSArray<NSString *> *consumablePack;
@property (nonatomic, copy) NSArray<NSString *> *nonConsumablePack;
@property (nonatomic, copy) NSArray<NSString *> *subscriptionPack;
+ (instancetype)fromDict:(NSDictionary *)dict;
@end

/**
 * Phân loại product (Unity ProductType). Android: Consumable/NonConsumable → INAPP, Subscription → SUBS;
 * StoreKit 1 query không phân loại — type chỉ dùng cho guard non-consumable + confirm order.
 */
typedef NS_ENUM(NSInteger, FGProductType) {
    FGProductTypeConsumable    = 0,
    FGProductTypeNonConsumable = 1,
    FGProductTypeSubscription  = 2,
};

/**
 * Cache 1 product sau khi fetch: title/localizedPriceString/localizedPrice/currency.
 * `priceString` = localizedPriceString (kèm ký hiệu tiền tệ) → GetProductPrice.
 * `priceMicros`/1e6 = localizedPrice (số thuần, chỉ nội bộ tracking iap_sdk value).
 */
@interface FGProductInfo : NSObject
@property (nonatomic, copy, readonly) NSString *productId;
@property (nonatomic, assign, readonly) FGProductType type;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *priceString;
@property (nonatomic, assign, readonly) long long priceMicros;
@property (nonatomic, copy, readonly) NSString *currency;
/** SKProduct — `id` để giữ provider isolation cho model (mirror Kotlin `Any?`). */
@property (nonatomic, strong, readonly, nullable) id details;
/** = priceMicros / 1e6 (mirror Kotlin computed property). */
@property (nonatomic, assign, readonly) double localizedPrice;

- (instancetype)initWithProductId:(NSString *)productId
                             type:(FGProductType)type
                            title:(NSString *)title
                      priceString:(NSString *)priceString
                      priceMicros:(long long)priceMicros
                         currency:(NSString *)currency
                          details:(id _Nullable)details;

@end

NS_ASSUME_NONNULL_END
