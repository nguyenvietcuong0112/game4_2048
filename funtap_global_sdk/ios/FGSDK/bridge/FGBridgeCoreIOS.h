//
//  FGBridgeCoreIOS.h — mirror KA/bridge/FGBridgeCore.kt (engine-agnostic).
//
//  Nhận command JSON từ lớp script (Cocos JS / Flutter Dart), dispatch sang FGSDKIOS;
//  đẩy callback/event ngược lên qua block `emit` do platform glue set.
//
//  ⚠️ KHÔNG import engine nào (không JsbBridgeWrapper, không Flutter) → dùng chung cho
//     mọi engine. Glue mỏng theo engine nằm ở:
//       - Cocos  : native/bridge/ios/FGBridge.mm
//       - Flutter: flutter/funtap_global_sdk/ios/Classes/FGSDKFlutterPlugin.mm
//
//  Protocol (giống hệt bản Android):
//    script→native : handle(json) với `{ "m": method, "args": {...}, "cb": id? }`
//    native→script : emit(json):
//      kết quả getter / callback  → `{ "e":"ret", "cb":id, "v":<json> }`
//      public ad event            → `{ "e":"ad.<format>.<name>", "info":<FGAdsInfo 10 field> }`
//                                    (*.request → `{ "args":[placement] }`)
//      iap callback               → `{ "e":"iap.<name>", "args":[...] }`
//      remoteconfig fetched       → `{ "e":"remoteconfig.fetched" }`
//
#pragma once
#import <Foundation/Foundation.h>

#if !defined(__OBJC__)
#error "FGBridgeCoreIOS.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGBridgeCoreIOS : NSObject

/// Platform glue set 1 lần: nhận chuỗi JSON event → chuyển về script/Dart.
/// Mirror `FGBridgeCore.emit` (Kotlin). nil = nuốt event.
@property (class, nonatomic, copy, nullable) void (^emit)(NSString *json);

/// script → native. Tự marshal về main thread trước khi chạm state (spec §14),
/// nuốt + log exception (mirror `runCatching` bên Kotlin).
+ (void)handle:(NSString *)json;

/// Đăng ký forward mọi public event/callback (ad/iap/remoteconfig) → `emit`.
/// Idempotent — gọi 1 lần lúc glue nối kênh.
+ (void)start;

@end

NS_ASSUME_NONNULL_END
