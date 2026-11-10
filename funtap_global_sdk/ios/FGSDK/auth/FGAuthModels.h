//
//  FGAuthModels.h — mirror KA/auth/FGAuthModels.kt (spec §13): DTO `FGVerifyResponseObjects` + kết quả CallAPI.
//  Default mirror Kotlin: success=true, code=0, message="", data={}.
//  Không có endpoint /verify riêng; dùng chung cho login + data-checklist.
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// spec §13 — response DTO. Field JSON VERBATIM (success/code/message/data).
@interface FGVerifyResponse : NSObject
@property (nonatomic, assign) BOOL success;                       // default YES
@property (nonatomic, assign) NSInteger code;                     // default 0
@property (nonatomic, copy) NSString *message;                    // default @""
@property (nonatomic, copy) NSDictionary<NSString *, id> *data;   // default @{} (Kotlin JsonObject rỗng)
+ (instancetype)fromDict:(NSDictionary * _Nullable)dict;
@end

/// Kết quả CallAPI nội bộ (statusCode + body thô). Constructor mirror Kotlin data class.
@interface FGApiResult : NSObject
@property (nonatomic, assign, readonly) NSInteger statusCode;
@property (nonatomic, copy, readonly) NSString *body;
- (instancetype)initWithStatusCode:(NSInteger)statusCode body:(NSString *)body;
@end

NS_ASSUME_NONNULL_END
