//
//  FGSDKFlutterPlugin.h — plugin Flutter cho Funtap Global SDK (iOS).
//
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

/// Nối kênh Flutter (MethodChannel/EventChannel) vào `FGBridgeCoreIOS` — lõi bridge
/// engine-agnostic dùng CHUNG với 2 bản Cocos.
@interface FGSDKFlutterPlugin : NSObject <FlutterPlugin>
@end

NS_ASSUME_NONNULL_END
