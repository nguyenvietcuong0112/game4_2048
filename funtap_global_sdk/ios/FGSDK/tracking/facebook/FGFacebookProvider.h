//
//  FGFacebookProvider.h — mirror KA/tracking/facebook/FGFacebookProvider.kt (spec §9.5).
//  ⚠️ chỉ thư mục facebook/ import FBSDKCoreKit (import chỉ trong .mm).
//  Chỉ init / ActivateApp / consent. ⚠️ LogEvent = NO-OP, SetUserProperties = NO-OP (quirk 10).
//
#pragma once
#import <Foundation/Foundation.h>
#import "../ITrackingProvider.h"

#if !defined(__OBJC__)
#error "FGFacebookProvider.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGFacebookProvider : NSObject <ITrackingProvider>
@end

NS_ASSUME_NONNULL_END
