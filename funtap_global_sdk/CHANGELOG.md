# Changelog — funtap_global_sdk (Flutter)

## 1.0.5

### Fixed
- **af_purchase không bao giờ lên AppsFlyer (Android, mọi bản ≤ 1.0.4)** — `purchase-connector` 2.3.0 build cho AppsFlyer SDK 7.x, chạy với AF 6.17.0 thì `NoClassDefFoundError: com.appsflyer.sdk_base.logger.LogTag` lúc khởi động → connector chết lặng. Đổi về đúng cặp bản Unity: `af-android-sdk` **6.17.5** + `purchase-connector` **2.2.0** (hỗ trợ Billing 8), thêm `installreferrer:2.1`. iOS ghim `AppsFlyerFramework` + `PurchaseConnector` **6.17.8** (để trống sẽ kéo 7.0.2); ai đã `pod install` trước đó chạy `pod update AppsFlyerFramework PurchaseConnector` một lần.
- **IAP: đơn consumable kẹt vĩnh viễn** — trả tiền không nhận hàng, mua lại gói đó bị `ITEM_ALREADY_OWNED` (`billing_7`). Lúc init SDK chỉ acknowledge đơn tồn (không consume, không trả hàng), nên đơn nào lỡ bước consume (app bị kill, mất mạng, pending payment, consume lỗi) là kẹt mãi.
  - Giờ đơn tồn được **giữ lại** và trả ở lần `buyProduct` kế của đúng gói đó qua kết quả `buyProduct` (`ok = true`), không mở lại Play/App Store, không thu tiền lần 2. Không trả lúc init vì game cộng đồ trong kết quả `buyProduct` — trả lúc init chỉ có event, game không nghe là mất đồ.
  - `ITEM_ALREADY_OWNED` khi mua → tự tìm và xử lý đơn tồn. Consume/acknowledge có retry; token đã trả hàng được ghi lại nên không bao giờ trả 2 lần.
  - iOS áp cùng luật với giao dịch chưa finish quay lại lúc mở app.

### Removed
- **`FGDebugReporter`** — kênh gửi log debug về server `fgtool` (service đã tắt, endpoint không còn; Unity đã xoá). Không mất event analytics nào.

## 1.0.4

### Changed
- **iOS chuyển từ `.xcframework` binary sang SOURCE POD** — source ObjC++ ship trong `ios/FGSDK/`, CocoaPods compile lúc `pod install` trên máy build của game (giống bản Cocos 3.x). `pod install` không còn đòi binary, **bỏ hẳn ràng buộc phải có máy Mac ở phía Funtap**.
  - Lý do: binary bắt buộc build lại trên Mac **mỗi lần sửa một dòng ObjC++** mới publish được — chặn cả những thay đổi chỉ liên quan Android. Mà nó không giấu thêm được gì: package `funtap-global-sdk-cocos` (3.x) vốn đã ship nguyên source iOS này và registry cho đọc ẩn danh.
  - `Classes/FGSDKFlutterPlugin.mm` đổi `#import <FGSDK/...>` → `#import "..."`: lõi SDK giờ nằm **cùng một pod** với glue, dùng angle-bracket sẽ lỗi "module FGSDK not found".
  - `tools/sync-sdk.js` thêm đích `flutter/funtap_global_sdk/ios/FGSDK` → source iOS tự đồng bộ từ master như 2 đích Cocos, hết cảnh sửa native mà quên bản copy.
  - Đổi lại: `pod install` lần đầu lâu hơn, và lỗi compile iOS (nếu có) nổ trên máy dev game.

## 1.0.3

### Added
- **`FGSDK.showMediationDebugger()`** — mở Mediation Debugger của AppLovin MAX để QA soi adapter / ad unit / waterfall ngay trên máy thật. Mirror `MaxSdk.ShowMediationDebugger()` bên Unity; có đủ ở cả 3 engine. MAX chưa init thì native bỏ qua, không crash.
- **File BUILD INFO cạnh thư mục build** — `build-info-flutter.bat` (rải ra root lúc cài) sinh `<pkg>_<ver>_ANDROID_BUILD_INFO.txt` + `..._IOS_BUILD_INFO.txt`, bố cục y hệt bản Unity. Đọc id/khoá từ `fg_main_config.json`, version third-party từ `fgsdk-deps.gradle` (Android) và `ios/Podfile.lock` (iOS), kèm khối `ANDROID vs iOS` chỉ ra field 2 nền khai lệch nhau.

## 1.0.2

### Added
- **iOS: tự động hoá phía project ngang bằng Android.** Trước đây bản iOS chỉ có glue + podspec; mọi thứ còn lại (Info.plist, đưa config vào app bundle, deployment target) dev phải làm tay trong Xcode.
  - `wire-flutter.js`: `ios/Podfile` → `platform :ios, '13.0'` + chèn vào `post_install` **có sẵn** đoạn ép `IPHONEOS_DEPLOYMENT_TARGET >= 13.0` cho mọi pod (CocoaPods chỉ nhận MỘT `post_install` — khai lần 2 là đè lần 1, nên chèn vào chứ không append block mới).
  - `fetch-config-flutter.js`: patch `ios/Runner/Info.plist` — Facebook (`FacebookAppID`/`ClientToken`/`DisplayName` + 2 cờ auto-log), AppsFlyer (`AppsFlyerDevKey`/`AppleAppID`), ATT (`NSUserTrackingUsageDescription`), AdMob (`GADApplicationIdentifier`), URL scheme `fb<app_id>` + `gl<app_key>`, `LSApplicationQueriesSchemes`, `UIBackgroundModes`, key Firebase/notification, seed 2 `SKAdNetworkItems`. **Map field verbatim** với extension Cocos 3.x ⇒ 3 engine ra cùng một Info.plist.
  - `fetch-config-flutter.js`: đăng ký `fg_main_config.json` + `GoogleService-Info.plist` vào **Copy Bundle Resources** của target `Runner` (patch `project.pbxproj`). Đây là mắt xích thiếu quan trọng nhất: file nằm trong `ios/Runner/` mà không có trong build phase thì `[NSBundle mainBundle] pathForResource:` trả `nil` → `FGSDKIOS` bỏ init vì "thiếu fg_main_config.json".
  - Cả 2 tool vẫn là **Node thuần, không npm install** (bat rải ra root project chạy) → tự viết parser/serializer XML plist và patch pbxproj thay vì dùng lib `plist`/`xcode` như bản Cocos.
  - Idempotent + backup `.fgsdkbak`. **Verify 36/36 PASS** trên project Flutter giả lập (Info.plist round-trip parse lại được, đúng Resources phase của `Runner` chứ không phải `RunnerTests`, chạy lần 2 không đổi byte nào).

- **`iap_packs.json`: bản Flutter trước đây không có đường nào để có file này** — không sample, không tool, không docs (Cocos 3.x có panel IAP, 2.x có sample). Mà native bắt buộc đọc nó (`FGIAPManager` Android đọc asset, iOS đọc bundle resource) ⇒ game dùng IAP thì init `false` mà không hiểu vì sao. Nay `config/iap_packs.sample.json` đi kèm package, `wire-flutter.js` gieo vào `android/app/src/main/assets/` + `ios/Runner/` **nếu chưa có** (không ghi đè bản dev đã sửa), `fetch-config-flutter.js` đăng ký vào Copy Bundle Resources. Docs README §2.

### Notes
- Vẫn còn nợ: `ios/Frameworks/FGSDK.xcframework` phải build trên Mac (`native/ios/tools/build-xcframework.sh`) rồi publish lại — chưa có binary thì `pod install` báo lỗi và chỉ build được Android.
- `ios/Podfile` do `flutter build ios` sinh; cài trên Windows sẽ bỏ qua 2 bước Podfile — trên Mac chạy lại `node funtap_global_sdk/tools/wire-flutter.js --project .`

## 1.0.0

Bản đầu tiên. Plugin Flutter cho Funtap Global SDK `3.2.6`, **dùng chung lõi native** với 2 package Cocos.

### Added
- **Dart API** mirror 1:1 wrapper Cocos (`fgsdk.ts`): core, tracking (9 hàm gọi sẵn + `logEvent`/`setUserProperties`), ads (interstitial/reward/banner/app-open/mrec), remote config, IAP, deeplink. `on*` trả `Stream` broadcast; getter/`show*`/`buy*` trả `Future`.
- **Bridge** MethodChannel `fgsdk` + EventChannel `fgsdk/events`, giữ **nguyên protocol JSON** `{m,args,cb}` / `{e,…}` của `FGBridgeCore` ⇒ hành vi y hệt bản Cocos.
- **Android**: `FGSDKFlutterPlugin.kt` (ActivityAware — init SDK, forward event, `onNewIntent` deeplink) + nhúng `fgsdk-release.aar` + `fgsdk-deps.gradle`. Manifest plugin tự merge permission + AdMob meta-data (không phải dán tay như Cocos).
- **iOS**: `FGSDKFlutterPlugin.mm` (ObjC++) + podspec vendor `FGSDK.xcframework` + khai third-party pods (spec §17). Nhận `openURL` cho deeplink.
- **Tooling**: `install-fgsdk-flutter-1.0.0.bat` (kéo registry → `path:` dependency → wire minSdk), `fetch-config-flutter.{bat,js}` (API Key → config/google-services/keystore + chèn AdMob app id), `publish-fgsdk-flutter.bat`, `native/ios/tools/build-xcframework.sh`.
- **example/** app tester đủ nút test API + log panel.

### Notes
- Event phát sinh trước khi Dart kịp `listen` được **đệm** (tối đa 64) rồi flush — bản Cocos không cần vì bridge cài đồng bộ lúc khởi động.
- Chưa build được `FGSDK.xcframework` từ Windows → bản đầu chỉ chạy thật ở **Android**; iOS cần chạy `build-xcframework.sh` trên Mac rồi publish lại.
