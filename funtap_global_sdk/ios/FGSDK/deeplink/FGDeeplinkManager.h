//
//  FGDeeplinkManager.h — mirror KA/deeplink/FGDeeplinkManager.kt (spec §12). State tĩnh action/value/isDeepLink.
//  Nguồn: (1) normal deeplink (custom scheme `gl{app_key}`) — iOS KHÔNG có Application.absoluteURL/Intent,
//         host app forward qua application:openURL: → FGBridge handleOpenURL: → handleURL:;
//         (2) deferred từ AppsFlyer → FGEvent::Deeplink::OnDeferredDeepLinkReceived.
//  ⚠️ 2 quirk giữ 100%: (1) deferred deep_link_sub1 KHÔNG parse → luôn 0; (2) guard `value==0` loại value 0.
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGDeeplinkManager : NSObject

+ (void)register;

/** Host app / FGBridge gọi khi nhận URL (cold start + foreground) — thay handleIntent bên Android. */
+ (void)handleURL:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
