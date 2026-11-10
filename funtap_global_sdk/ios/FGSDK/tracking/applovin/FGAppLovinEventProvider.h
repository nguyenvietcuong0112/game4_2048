//
//  FGAppLovinEventProvider.h — mirror KA/tracking/applovin/FGAppLovinEventProvider.kt.
//  MỞ RỘNG ngoài Unity spec: kênh AppLovin EventService (SDK MAX tự log user event cho ad optimization).
//  ⚠️ Chỉ thư mục applovin/ import AppLovinSDK (import chỉ trong .mm). LogEvent → trackEvent:parameters:,
//  SetUserProperties/SetConsent = no-op. Chỉ nhận event có providers=[AppLovin].
//
#pragma once
#import <Foundation/Foundation.h>
#import "../ITrackingProvider.h"

#if !defined(__OBJC__)
#error "FGAppLovinEventProvider.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGAppLovinEventProvider : NSObject <ITrackingProvider>
@end

NS_ASSUME_NONNULL_END
