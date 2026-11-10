//
//  FGDeeplinkManager.mm — mirror KA/deeplink/FGDeeplinkManager.kt (spec §12).
//
#import "FGDeeplinkManager.h"
#import "../config/FGConfigController.h"
#import "../event/FGEvent.h"

static NSString *const kTag = @"FGDeeplink";

static BOOL sRegistered = NO;
static NSString *sAction = @"";
static NSInteger sValue = 0;
static BOOL sIsDeepLink = NO;

/** spec §12 — ⚠️ guard `if (action=="" || value==0)` → null; nếu isDeepLink → trả (action, value) rồi reset (one-shot). */
static std::optional<std::pair<NSString *, NSInteger>> FGDLProcessCallbackToGame() {
    if (sAction.length == 0 || sValue == 0) return std::nullopt; // ⚠️ quirk 2: value==0 luôn loại
    if (!sIsDeepLink) return std::nullopt;
    auto result = std::make_pair(sAction, sValue);
    sAction = @""; sValue = 0; sIsDeepLink = NO;
    return result;
}

static void FGDLHandleDeferred(NSString *deepLinkValue, NSInteger sub1) {
    if (deepLinkValue.length == 0) return;
    sAction = [deepLinkValue copy];
    sValue = sub1; // ⚠️ AF provider luôn truyền 0 (quirk 1)
    sIsDeepLink = YES;
    NSLog(@"[%@] deferred deeplink action=%@ value=%ld", kTag, sAction, (long)sValue);
}

/** mirror Kotlin toIntOrNull() ?: 0 — parse chặt cả chuỗi, không phải số → 0 (integerValue quá dễ dãi). */
static NSInteger FGDLParseIntOrZero(NSString * _Nullable s) {
    if (s == nil || s.length == 0) return 0;
    NSScanner *scanner = [NSScanner scannerWithString:s];
    NSInteger v = 0;
    if ([scanner scanInteger:&v] && scanner.isAtEnd) return v;
    return 0;
}

@implementation FGDeeplinkManager

+ (void)register {
    if (sRegistered) return;
    sRegistered = YES;

    // GetDeeplinkResult (§4.6) → ProcessCallbackToGame (one-shot).
    FGEvent::Deeplink::OnRequestDeepLink = []() { return FGDLProcessCallbackToGame(); };

    // Deferred từ AppsFlyer (§12): (deep_link_value, deep_link_sub1). ⚠️ sub1 luôn 0 (quirk 1, AF provider truyền 0).
    FGEvent::Deeplink::OnDeferredDeepLinkReceived.add([](NSString *deepLinkValue, NSInteger sub1) {
        FGDLHandleDeferred(deepLinkValue, sub1);
    });

    // Cold start: iOS KHÔNG có Application.absoluteURL/Intent để tự đọc — AppDelegate
    // application:openURL: (cold start lẫn foreground) forward qua FGBridge handleOpenURL: → handleURL: dưới đây.
}

/** spec §12 — scheme phải == `gl{app_key}`; đọc deep_link_value → action, deep_link_sub1 → value (int, default 0). */
+ (void)handleURL:(NSURL *)url {
    NSString *appKey = FGConfigController.mainPlatform.app_key;
    if (appKey == nil) return;
    NSString *expectedScheme = [@"gl" stringByAppendingString:appKey];
    if (![url.scheme isEqualToString:expectedScheme]) {
        NSLog(@"[%@] scheme %@ != %@ → bỏ", kTag, url.scheme, expectedScheme);
        return;
    }

    // mirror Uri.getQueryParameter: lấy occurrence ĐẦU của mỗi key
    NSURLComponents *comps = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *deepLinkValue = @"";
    NSString *sub1Str = nil;
    BOOL foundValue = NO, foundSub1 = NO;
    for (NSURLQueryItem *item in comps.queryItems) {
        if (!foundValue && [item.name isEqualToString:@"deep_link_value"]) {
            deepLinkValue = item.value ?: @"";
            foundValue = YES;
        } else if (!foundSub1 && [item.name isEqualToString:@"deep_link_sub1"]) {
            sub1Str = item.value;
            foundSub1 = YES;
        }
    }
    if (deepLinkValue.length == 0) { NSLog(@"[%@] deep_link_value rỗng → bỏ", kTag); return; }
    NSInteger sub1 = FGDLParseIntOrZero(sub1Str);

    sAction = [deepLinkValue copy];
    sValue = sub1;
    sIsDeepLink = YES;
    NSLog(@"[%@] deeplink action=%@ value=%ld", kTag, sAction, (long)sValue);
}

@end
