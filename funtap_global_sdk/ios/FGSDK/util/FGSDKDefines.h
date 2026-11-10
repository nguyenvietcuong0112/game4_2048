//
//  FGSDKDefines.h — guard macro + typedef chung. Mirror define Unity / BuildConfig Android.
//  Default BẬT (=1); tắt bằng GCC_PREPROCESSOR_DEFINITIONS của project tích hợp.
//
#pragma once
#import <Foundation/Foundation.h>

#if !defined(__OBJC__)
#error "FGSDK iOS là ObjC++ — chỉ include từ file .mm"
#endif

#ifndef GOOGLE_MOBILE_ADS_ENABLE
#define GOOGLE_MOBILE_ADS_ENABLE 1        // UMP + AdMob (spec §6.1, §7.8)
#endif
#ifndef APPSFLYER_SDK_ENABLE
#define APPSFLYER_SDK_ENABLE 1            // spec §8, §9.4
#endif
#ifndef APPSFLYER_CONNECTOR_SANDBOX
#define APPSFLYER_CONNECTOR_SANDBOX 0     // sandbox PurchaseConnector (spec §9.4)
#endif
#ifndef FIREBASE_REMOTECONFIG_ENABLE
#define FIREBASE_REMOTECONFIG_ENABLE 1    // spec §10
#endif
#ifndef UNITY_IAP_ENABLE
#define UNITY_IAP_ENABLE 1                // giữ tên verbatim (Android BuildConfig cùng tên) — iOS = StoreKit 1
#endif
#ifndef FACEBOOK_SDK_ENABLE
#define FACEBOOK_SDK_ENABLE 1             // spec §9.5
#endif

// Kotlin `Params` = Map<String, Any?> (KA/event/FGEventTypes.kt)
typedef NSDictionary<NSString *, id> * FGParams;
