//
//  FGAuthManager.mm — mirror KA/auth/FGAuthManager.kt (spec §13).
//
#import "FGAuthManager.h"
#import "../config/FGConfigController.h"
#import "../util/FGConstValue.h"
#import "../util/FGDeviceInfo.h"
#include <atomic>
#include <mutex>
#include <utility>

static NSString *const kTag = @"FGAuth";
static const NSInteger kMaxRetries = 3;
static const NSTimeInterval kRetryDelaySec = 1.0;        // RETRY_DELAY_MS
static const NSTimeInterval kAuthPollTimeoutSec = 5.0;   // AUTH_POLL_TIMEOUT_MS
static const NSTimeInterval kAuthPollIntervalSec = 0.1;  // AUTH_POLL_INTERVAL_MS
static const NSTimeInterval kRequestTimeoutSec = 15.0;   // connectTimeout/readTimeout 15000 bên Kotlin

// Kotlin @Volatile → std::atomic; token là pointer ObjC → mutex riêng
static std::atomic<bool> sIsAuthenticated{false};
static std::atomic<bool> sIsAuthenticating{false};
static std::mutex sTokenMutex;
static NSString *sAccessToken = @"";

// mirror Executors.newSingleThreadExecutor("FGAuth")
static dispatch_queue_t FGAuthQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("FGAuth", DISPATCH_QUEUE_SERIAL); });
    return q;
}

static NSString *FGAuthGetToken(void) {
    std::lock_guard<std::mutex> l(sTokenMutex);
    return sAccessToken;
}

static void FGAuthSetToken(NSString *token) {
    std::lock_guard<std::mutex> l(sTokenMutex);
    sAccessToken = [token copy] ?: @"";
}

/** base = base_api_domain TrimEnd '/' (spec §13). */
static NSString * _Nullable FGAuthBaseUrl(void) {
    NSString *d = FGConfigController.mainPlatform.base_api_domain;
    if (d == nil) return nil;
    while ([d hasSuffix:@"/"]) d = [d substringToIndex:d.length - 1];
    return d;
}

static NSString *FGAuthAppKey(void) {
    return FGConfigController.mainPlatform.app_key ?: @"";
}

/** spec §13 — DefaultHeaderParams. Authorization chỉ khi token khác rỗng. Header VERBATIM. */
static NSDictionary<NSString *, NSString *> *FGAuthDefaultHeaders(void) {
    NSMutableDictionary<NSString *, NSString *> *h = [NSMutableDictionary new];
    h[@"Content-Type"] = @"application/json";
    h[@"x-app-key"] = FGAuthAppKey();
    h[@"os"] = FGDeviceInfo.OS; // "ios" (adaptation table)
    NSString *token = FGAuthGetToken();
    if (token.length > 0) h[@"Authorization"] = [@"Bearer " stringByAppendingString:token];
    return h;
}

/** mirror URLEncoder.encode(s, "UTF-8") — encode hết trừ unreserved của form-encoding, space → '+'. */
static NSString *FGAuthUrlEncode(NSString *s) {
    static NSCharacterSet *allowed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        allowed = [NSCharacterSet characterSetWithCharactersInString:
                   @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._*"];
    });
    NSString *enc = [s stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
    return [enc stringByReplacingOccurrencesOfString:@"%20" withString:@"+"];
}

/** mirror jsonToQuery: JSON object → "k=v&k=v" (giá trị lấy dạng chuỗi như JsonPrimitive.asString). */
static NSString *FGAuthJsonToQuery(NSString *json) {
    NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) return @"";
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![obj isKindOfClass:[NSDictionary class]]) return @"";
    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    [(NSDictionary *)obj enumerateKeysAndObjectsUsingBlock:^(NSString *k, id v, BOOL *stop) {
        NSString *sv = [v isKindOfClass:[NSString class]] ? v : [v description];
        [parts addObject:[NSString stringWithFormat:@"%@=%@", FGAuthUrlEncode(k), FGAuthUrlEncode(sv)]];
    }];
    return [parts componentsJoinedByString:@"&"];
}

/** 1 request sync qua semaphore (giữ semantics HttpURLConnection blocking). err → nil out-param. */
static FGApiResult * _Nullable FGAuthDoRequest(NSMutableURLRequest *req, NSError * _Nullable __autoreleasing *outErr) {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSData *respData = nil;
    __block NSURLResponse *resp = nil;
    __block NSError *err = nil;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
            respData = d; resp = r; err = e;
            dispatch_semaphore_signal(sem);
        }];
    [task resume];
    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

    if (err != nil || ![resp isKindOfClass:[NSHTTPURLResponse class]]) {
        if (outErr) *outErr = err;
        return nil;
    }
    // NSURLSession trả body cả khi non-2xx (≈ inputStream/errorStream bên Kotlin)
    NSString *text = respData ? ([[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding] ?: @"") : @"";
    return [[FGApiResult alloc] initWithStatusCode:((NSHTTPURLResponse *)resp).statusCode body:text];
}

/** spec §13 — POST /auth/login {device_id} → token ở data.access_token. */
static std::pair<BOOL, NSInteger> FGAuthDoAuthen(void) {
    sIsAuthenticating.store(true);
    std::pair<BOOL, NSInteger> result{NO, 401};
    @try {
        NSDictionary *bodyDict = @{ FGConstValue.DeviceId : FGConstValue.UserDeviceId };
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
        NSString *body = bodyData ? ([[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] ?: @"{}") : @"{}";
        FGApiResult *res = [FGAuthManager callAPISync:@"POST" path:@"/auth/login" jsonBody:body];
        if (res.statusCode >= 200 && res.statusCode <= 299) {
            NSData *respData = [res.body dataUsingEncoding:NSUTF8StringEncoding];
            id parsed = respData ? [NSJSONSerialization JSONObjectWithData:respData options:0 error:nil] : nil;
            FGVerifyResponse *vr = [FGVerifyResponse fromDict:parsed];
            id tokenObj = vr.data[@"access_token"];
            NSString *token = [tokenObj isKindOfClass:[NSString class]] ? tokenObj : @"";
            if (token.length > 0) {
                FGAuthSetToken(token);
                sIsAuthenticated.store(true);
                result = {YES, 0};
            } else {
                result = {NO, 401};
            }
        } else {
            result = {NO, res.statusCode};
        }
    } @catch (id ex) {
        NSLog(@"[%@] doAuthen fail: %@", kTag, ex);
        result = {NO, 401};
    }
    sIsAuthenticating.store(false); // finally
    return result;
}

/** Sync: đã auth → skip; đang auth → poll tối đa 5s → timeout 401; else DoAuthen (spec §13). */
static std::pair<BOOL, NSInteger> FGAuthEnsureAuthenticatedSync(void) {
    if (sIsAuthenticated.load()) return {YES, 0};
    if (sIsAuthenticating.load()) {
        NSTimeInterval waited = 0;
        while (sIsAuthenticating.load() && waited < kAuthPollTimeoutSec) {
            [NSThread sleepForTimeInterval:kAuthPollIntervalSec];
            waited += kAuthPollIntervalSec;
        }
        if (sIsAuthenticated.load()) return {YES, 0};
        return {NO, 401}; // timeout → 401
    }
    return FGAuthDoAuthen();
}

/** spec §13 — POST /sdk-checklists/data-checklist {bundle_number, app_version, data_verify}. */
static void FGAuthDataChecklistSync(void) {
    NSDictionary *bodyDict = @{
        @"bundle_number" : @(FGDeviceInfo.bundleNumber),
        @"app_version" : FGDeviceInfo.appVersion,
        @"data_verify" : @"", // spec không định nghĩa nội dung → rỗng (diễn giải — mirror Kotlin)
    };
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
    if (bodyData == nil) { NSLog(@"[%@] data-checklist fail: body json", kTag); return; }
    NSString *body = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding] ?: @"{}";
    @try {
        [FGAuthManager callAPISync:@"POST" path:@"/sdk-checklists/data-checklist" jsonBody:body];
    } @catch (id ex) {
        NSLog(@"[%@] data-checklist fail: %@", kTag, ex);
    }
}

@implementation FGAuthManager

+ (void)register {
    NSString *base = FGAuthBaseUrl();
    if (base == nil || base.length == 0) { NSLog(@"[%@] base_api_domain rỗng → Auth off", kTag); return; }
    // Data checklist khi init (§13). Cần auth trước.
    dispatch_async(FGAuthQueue(), ^{
        FGAuthEnsureAuthenticatedSync();
        FGAuthDataChecklistSync();
    });
}

+ (void)ensureAuthenticated:(void (^)(BOOL, NSInteger))onResult {
    dispatch_async(FGAuthQueue(), ^{
        auto r = FGAuthEnsureAuthenticatedSync();
        onResult(r.first, r.second);
    });
}

+ (FGApiResult *)callAPISync:(NSString *)method path:(NSString *)path jsonBody:(NSString * _Nullable)jsonBody {
    NSString *base = FGAuthBaseUrl();
    if (base == nil) return [[FGApiResult alloc] initWithStatusCode:-1 body:@""];
    FGApiResult *lastErr = [[FGApiResult alloc] initWithStatusCode:-1 body:@""];
    for (NSInteger attempt = 0; attempt < kMaxRetries; attempt++) {
        BOOL isGet = ([method caseInsensitiveCompare:@"GET"] == NSOrderedSame);
        NSString *urlStr = (isGet && jsonBody != nil)
            ? [NSString stringWithFormat:@"%@%@?%@", base, path, FGAuthJsonToQuery(jsonBody)]
            : [NSString stringWithFormat:@"%@%@", base, path];
        NSURL *url = [NSURL URLWithString:urlStr];
        NSError *err = nil;
        FGApiResult *res = nil;
        if (url != nil) {
            NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
            req.HTTPMethod = method;
            req.timeoutInterval = kRequestTimeoutSec;
            [FGAuthDefaultHeaders() enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
                [req setValue:v forHTTPHeaderField:k];
            }];
            if (!isGet && jsonBody != nil) {
                req.HTTPBody = [jsonBody dataUsingEncoding:NSUTF8StringEncoding];
            }
            res = FGAuthDoRequest(req, &err);
        }
        if (res != nil) return res;
        lastErr = [[FGApiResult alloc] initWithStatusCode:-1 body:(err.localizedDescription ?: @"")];
        NSLog(@"[%@] callAPI %@ %@ attempt %ld fail: %@", kTag, method, path, (long)(attempt + 1), err);
        if (attempt < kMaxRetries - 1) [NSThread sleepForTimeInterval:kRetryDelaySec];
    }
    return lastErr;
}

+ (void)setAccessToken:(NSString *)token {
    FGAuthSetToken(token);
}

@end
