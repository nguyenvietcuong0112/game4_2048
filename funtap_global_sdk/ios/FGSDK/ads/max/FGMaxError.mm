//
//  FGMaxError.mm — mirror KA/ads/max/FGMaxError.kt (spec §8), map theo MAErrorCode iOS.
//
#import "FGMaxError.h"
#import <AppLovinSDK/AppLovinSDK.h>

// MAErrorCode iOS không có hằng AdDisplayFailed → literal -4205 (mirror Kotlin AD_DISPLAY_FAILED_CODE).
static const NSInteger kAdDisplayFailedCode = -4205;

@implementation FGMaxError

+ (NSString *)classifyLoad:(NSInteger)code {
    switch (code) {
        case MAErrorCodeNoFill:
            return @"no_fill";
        case MAErrorCodeNetworkTimeout:
            return @"timeout";
        case MAErrorCodeNetworkError:
        case MAErrorCodeNoNetwork:
            return @"network";
        case MAErrorCodeInvalidAdUnitIdentifier:
        case MAErrorCodeFullscreenAdInvalidViewController: // nhánh iOS: thiếu VC = lỗi cấu hình
            return @"config";
        default:
            return @"unknown";
    }
}

+ (NSString *)classifyDisplay:(NSInteger)code {
    switch (code) {
        case MAErrorCodeFullscreenAdNotReady:
            return @"not_ready";
        case MAErrorCodeFullscreenAdAlreadyShowing:
            return @"already_used";
        case kAdDisplayFailedCode:
            return @"render_error";
        case MAErrorCodeNetworkError:
        case MAErrorCodeNoNetwork:
        case MAErrorCodeNetworkTimeout:
            return @"network";
        case MAErrorCodeFullscreenAdInvalidViewController:
            return @"invalid_state";
        default:
            return @"unknown";
    }
}

@end
