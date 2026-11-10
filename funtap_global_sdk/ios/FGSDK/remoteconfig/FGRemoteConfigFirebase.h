//
//  FGRemoteConfigFirebase.h — mirror KA/remoteconfig/FGRemoteConfigFirebase.kt (spec §10).
//  ⚠️ chỉ module này import FirebaseRemoteConfig.
//  Register khi FirebaseInitComplete → fetch(0) (ép mới, bỏ throttle) → activate → isInitialize=true
//  → fire OnRemoteConfigFetched. OnNetworkRestored: chưa init → fetch lại.
//  Guard compile-time FIREBASE_REMOTECONFIG_ENABLE: tắt → không subscribe, getter trả default.
//
#pragma once
#import <Foundation/Foundation.h>

#if !defined(__OBJC__)
#error "FGSDK iOS là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGRemoteConfigFirebase : NSObject

/// Kotlin `register()` — idempotent; wire facade FGEvent::RemoteConfig luôn (kể cả guard tắt).
+ (void)register;

@end

NS_ASSUME_NONNULL_END
