//
//  FGIAPModels.mm — mirror KA/iap/FGIAPModels.kt (spec §11).
//  Gson → NSJSONSerialization + map field tay (README): field vắng / sai kiểu → giữ default rỗng.
//
#import "FGIAPModels.h"

// mirror Gson default emptyList: field vắng / sai kiểu → mảng rỗng (không nil)
static NSArray<NSString *> *FGIAPStrArray(NSDictionary *d, NSString *k) {
    id v = d[k];
    if (![v isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (id e in (NSArray *)v) {
        if ([e isKindOfClass:[NSString class]]) [out addObject:(NSString *)e];
    }
    return out;
}

@implementation FGIAPPacks

- (instancetype)init {
    if (self = [super init]) {
        _consumablePack = @[];
        _nonConsumablePack = @[];
        _subscriptionPack = @[];
    }
    return self;
}

+ (instancetype)fromDict:(NSDictionary *)dict {
    FGIAPPacks *p = [[FGIAPPacks alloc] init];
    // field JSON VERBATIM (spec §11)
    p.consumablePack = FGIAPStrArray(dict, @"consumablePack");
    p.nonConsumablePack = FGIAPStrArray(dict, @"nonConsumablePack");
    p.subscriptionPack = FGIAPStrArray(dict, @"subscriptionPack");
    return p;
}

@end

@implementation FGProductInfo

- (instancetype)initWithProductId:(NSString *)productId
                             type:(FGProductType)type
                            title:(NSString *)title
                      priceString:(NSString *)priceString
                      priceMicros:(long long)priceMicros
                         currency:(NSString *)currency
                          details:(id _Nullable)details {
    if (self = [super init]) {
        _productId = [productId copy];
        _type = type;
        _title = [title copy];
        _priceString = [priceString copy];
        _priceMicros = priceMicros;
        _currency = [currency copy];
        _details = details;
    }
    return self;
}

// mirror Kotlin computed property: localizedPrice = priceMicros / 1_000_000.0
- (double)localizedPrice {
    return _priceMicros / 1000000.0;
}

@end
