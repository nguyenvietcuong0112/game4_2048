//
//  FGAuthManager.h — mirror KA/auth/FGAuthManager.kt (spec §13): Auth HTTP backend, không third-party.
//  HttpURLConnection + single-thread executor bên Kotlin → NSURLSession + serial dispatch queue + semaphore
//  (giữ semantics sync/retry/poll y hệt — README adaptation table).
//  Base = base_api_domain (TrimEnd '/'). Header verbatim: Content-Type, x-app-key, os, Authorization Bearer (khi token khác rỗng).
//  Login POST /auth/login {device_id} → data.access_token. EnsureAuthenticated poll 5s. CallAPI retry 3, delay 1s.
//
#pragma once
#import <Foundation/Foundation.h>
#import "FGAuthModels.h"

NS_ASSUME_NONNULL_BEGIN

@interface FGAuthManager : NSObject

+ (void)register;

/** Async: đã auth → skip; đang auth → poll 5s; else DoAuthen. Timeout → (NO, 401). Callback trên queue FGAuth (mirror Kotlin). */
+ (void)ensureAuthenticated:(void (^)(BOOL success, NSInteger code))onResult;

/** retry maxRetries=3, delay 1s. GET → query string; POST/PUT/DELETE → JSON body. BLOCKING — đừng gọi trên main. */
+ (FGApiResult *)callAPISync:(NSString *)method path:(NSString *)path jsonBody:(NSString * _Nullable)jsonBody;

/** cho phép module khác (IAP verify) set token nếu cần. */
+ (void)setAccessToken:(NSString *)token;

@end

NS_ASSUME_NONNULL_END
