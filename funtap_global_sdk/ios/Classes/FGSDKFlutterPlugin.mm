//
//  FGSDKFlutterPlugin.mm — glue MỎNG nối FGBridgeCoreIOS vào kênh Flutter.
//
//  Tương đương `FGSDKFlutterPlugin.kt` bên Android và `FGBridge.mm` bên Cocos:
//    Dart→native : MethodChannel "fgsdk", method "send", arg = chuỗi JSON {m,args,cb}
//    native→Dart : EventChannel  "fgsdk/events", đẩy chuỗi JSON {e,…}
//
//  ⚠️ ObjC++ (KHÔNG Swift): `FGSDKIOS.h` có `std::vector<ProviderType>` trong signature
//     nên Swift không import được.
//
#import "FGSDKFlutterPlugin.h"

// Lõi SDK nằm CÙNG pod (source pod từ 1.0.4) → import theo tên file, không phải
// <FGSDK/...> kiểu framework riêng. CocoaPods gom public header của pod vào một chỗ
// nên quoted import tìm thấy; dùng angle-bracket ở đây sẽ lỗi "module FGSDK not found".
#import "FGSDKIOS.h"
#import "FGBridgeCoreIOS.h"

/// Event phát sinh TRƯỚC khi Dart kịp `listen` được đệm lại rồi flush (SDK init sớm
/// có thể bắn init_sdk / remoteconfig.fetched trước khi widget tree gắn stream).
static const NSUInteger kFGMaxPending = 64;

@interface FGSDKFlutterPlugin () <FlutterStreamHandler>
@property (nonatomic, copy, nullable) FlutterEventSink sink;
@property (nonatomic, strong) NSMutableArray<NSString *> *pending;
@end

@implementation FGSDKFlutterPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    FGSDKFlutterPlugin *instance = [[FGSDKFlutterPlugin alloc] init];
    instance.pending = [NSMutableArray array];

    FlutterMethodChannel *method =
        [FlutterMethodChannel methodChannelWithName:@"fgsdk"
                                    binaryMessenger:[registrar messenger]];
    [registrar addMethodCallDelegate:instance channel:method];

    FlutterEventChannel *events =
        [FlutterEventChannel eventChannelWithName:@"fgsdk/events"
                                  binaryMessenger:[registrar messenger]];
    [events setStreamHandler:instance];

    // Nhận openURL để bắt deeplink / AppsFlyer OneLink (spec §12).
    [registrar addApplicationDelegate:instance];

    // 1) Khởi tạo SDK.
    [FGSDKIOS initSDK];
    // 2) native → Dart.
    __weak FGSDKFlutterPlugin *weakSelf = instance;
    FGBridgeCoreIOS.emit = ^(NSString *json) { [weakSelf emit:json]; };
    // 3) Forward mọi public event/callback → emit.
    [FGBridgeCoreIOS start];
}

// ── Dart → native ─────────────────────────────────────────────────────────────

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if (![call.method isEqualToString:@"send"]) { result(FlutterMethodNotImplemented); return; }
    NSString *json = call.arguments;
    if (![json isKindOfClass:NSString.class]) {
        result([FlutterError errorWithCode:@"bad_args" message:@"send cần đúng 1 chuỗi JSON" details:nil]);
        return;
    }
    // Kết quả (nếu có) quay về qua EventChannel dạng {e:"ret",cb,v} — giống bản Cocos.
    [FGBridgeCoreIOS handle:json];
    result(nil);
}

// ── native → Dart ─────────────────────────────────────────────────────────────

- (FlutterError *)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)events {
    self.sink = events;
    @synchronized (self.pending) {
        for (NSString *json in self.pending) events(json);
        [self.pending removeAllObjects];
    }
    return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
    self.sink = nil;
    return nil;
}

/// FlutterEventSink CHỈ được gọi trên main thread; callback SDK có thể ở thread khác.
- (void)emit:(NSString *)json {
    if (json == nil) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        FlutterEventSink s = self.sink;
        if (s != nil) {
            s(json);
        } else {
            @synchronized (self.pending) {
                if (self.pending.count >= kFGMaxPending) [self.pending removeObjectAtIndex:0];
                [self.pending addObject:json];
            }
        }
    });
}

// ── Deeplink ──────────────────────────────────────────────────────────────────

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    [FGSDKIOS handleOpenURL:url];
    return NO; // không "nuốt" URL — plugin khác vẫn được xử lý
}

@end
