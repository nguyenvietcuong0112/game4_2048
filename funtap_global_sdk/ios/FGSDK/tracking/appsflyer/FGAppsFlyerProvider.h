//
//  FGAppsFlyerProvider.h — mirror KA/tracking/appsflyer/FGAppsFlyerProvider.kt (spec §9.4).
//  ⚠️ chỉ thư mục appsflyer/ import AppsFlyer/PurchaseConnector (import chỉ trong .mm).
//  ⚠️ SetUserProperties = NO-OP (quirk 10). `af_revenue` → logAdRevenue, KHÔNG logEvent (quirk 11).
//  ⚠️ KHÔNG port FCM uninstall token — đường Android-only (spec §9.4, adaptation README).
//
#pragma once
#import <Foundation/Foundation.h>
#import "../ITrackingProvider.h"

#if !defined(__OBJC__)
#error "FGAppsFlyerProvider.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGAppsFlyerProvider : NSObject <ITrackingProvider>
@end

NS_ASSUME_NONNULL_END
