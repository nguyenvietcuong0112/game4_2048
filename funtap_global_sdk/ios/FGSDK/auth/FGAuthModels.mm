//
//  FGAuthModels.mm — mirror KA/auth/FGAuthModels.kt (spec §13).
//
#import "FGAuthModels.h"

@implementation FGVerifyResponse

- (instancetype)init {
    if (self = [super init]) {
        // default mirror Kotlin data class
        _success = YES;
        _code = 0;
        _message = @"";
        _data = @{};
    }
    return self;
}

+ (instancetype)fromDict:(NSDictionary * _Nullable)dict {
    FGVerifyResponse *r = [FGVerifyResponse new];
    if (![dict isKindOfClass:[NSDictionary class]]) return r; // parse hỏng → default (mirror Gson getOrNull)
    id success = dict[@"success"];
    if ([success isKindOfClass:[NSNumber class]]) r.success = [success boolValue];
    id code = dict[@"code"];
    if ([code isKindOfClass:[NSNumber class]]) r.code = [code integerValue];
    id message = dict[@"message"];
    if ([message isKindOfClass:[NSString class]]) r.message = message;
    id data = dict[@"data"];
    if ([data isKindOfClass:[NSDictionary class]]) r.data = data;
    return r;
}

@end

@implementation FGApiResult

- (instancetype)initWithStatusCode:(NSInteger)statusCode body:(NSString *)body {
    if (self = [super init]) {
        _statusCode = statusCode;
        _body = [body copy] ?: @"";
    }
    return self;
}

@end
