//
//  FGFirebaseProvider.h — mirror KA/tracking/firebase/FGFirebaseProvider.kt (spec §9.3).
//  ⚠️ chỉ thư mục firebase/ import Firebase (provider isolation — import chỉ trong .mm).
//  Init fail → không gọi function Firebase nào, NHƯNG vẫn LUÔN fire OnProviderReady (quirk 20).
//
#pragma once
#import <Foundation/Foundation.h>
#import "../ITrackingProvider.h"

#if !defined(__OBJC__)
#error "FGFirebaseProvider.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGFirebaseProvider : NSObject <ITrackingProvider>
@end

NS_ASSUME_NONNULL_END
