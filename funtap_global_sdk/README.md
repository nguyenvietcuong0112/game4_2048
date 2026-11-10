# funtap_global_sdk — Funtap Global SDK cho Flutter

Plugin Flutter (Android + iOS) của **Funtap Global SDK** `3.2.6`: ads (AppLovin MAX + AdMob backfill), tracking (Firebase / AppsFlyer / Facebook / AppLovin), remote config, IAP, deeplink.

**Dùng chung lõi native** với 2 package Cocos (`funtap-global-sdk-cocos`, `funtap-global-sdk-cocos2x`) qua đúng một protocol bridge (`FGBridgeCore`) ⇒ tên event / param / hành vi **y hệt**, chỉ khác đường truyền:

```
Dart  ──MethodChannel "fgsdk"────────►  FGSDKFlutterPlugin ──► FGBridgeCore ──► FGSDK native
      ◄─EventChannel  "fgsdk/events"──
```

---

## 1. Cài

Copy `install-fgsdk-flutter-<batver>.bat` vào **root project Flutter** (ngang `pubspec.yaml`) → **double-click**.

Bat sẽ: kéo package từ registry → giải nén vào `<project>/funtap_global_sdk/` → thêm `path:` dependency vào `pubspec.yaml` → ép `minSdk >= 24` → đặt `platform :ios, '13.0'` + ép deployment target cho pod (nếu đã có `ios/Podfile`) → rải `fetch-config-flutter.*` ra root.

> **Vì sao phải qua bat?** `pub` chỉ đọc được pub.dev / pub server / git / thư mục local — **không đọc được npm registry**. Nên package phải được tải xuống đĩa trước, rồi `pubspec.yaml` trỏ `path:`. Bat chỉ tự động hoá đúng 3 bước đó.
>
> Số trong tên bat = version **của file bat**, KHÔNG phải version SDK (bat luôn kéo SDK mới nhất, và in cả 2 số lúc chạy).

Rồi:
```bash
flutter pub get
```

## 2. Config

Double-click **`fetch-config-flutter.bat`** ở root → nhập **API Key**. Nó kéo về và đặt đúng chỗ:

| File | Đích |
|---|---|
| `fg_main_config.json` | `android/app/src/main/assets/` + `ios/Runner/` |
| `google-services.json` | `android/app/` |
| `GoogleService-Info.plist` | `ios/Runner/` |
| keystore + `key.properties` | `android/` |
| AdMob app id | ghi `FGSDK_ADMOB_APP_ID=…` vào `android/gradle.properties` (Android) + key `GADApplicationIdentifier` trong `Info.plist` (iOS) |
| Facebook / AppsFlyer / ATT / URL scheme / SKAdNetwork | patch thẳng `ios/Runner/Info.plist` |
| 2 file config iOS ở trên | tự đăng ký vào **Copy Bundle Resources** của target `Runner` (`Runner.xcodeproj`) |
| `iap_packs.json` | bản **mẫu** được gieo sẵn lúc cài vào `android/app/src/main/assets/` + `ios/Runner/` — **dev tự sửa product ID** |

> ⚠️ **Thiếu `fg_main_config.json` = SDK không init** (`isInit()` trả `false`). Trên iOS, file nằm trong `ios/Runner/` là chưa đủ — nó phải nằm trong *Copy Bundle Resources* thì `[NSBundle mainBundle]` mới thấy; fetch script tự làm việc này, file gốc backup `.fgsdkbak`.
> ⚠️ `key.properties` + keystore chứa secret — **đừng commit vào git**.
> ⚠️ Chạy fetch **trước** khi mở Xcode. Nếu Xcode đang mở sẵn project thì đóng/mở lại để nó nạp `project.pbxproj` mới.

### IAP — `iap_packs.json`

Server config **không** trả file này (giống Unity/Cocos): product ID là do bạn khai trên store. Lúc cài, wire script gieo **bản mẫu** vào `android/app/src/main/assets/iap_packs.json` + `ios/Runner/iap_packs.json` — sửa cho khớp store rồi build lại. Chạy lại installer **không ghi đè** file bạn đã sửa.

```json
{
  "consumablePack":    ["com.funtap.global.gems_small"],
  "nonConsumablePack": ["com.funtap.global.remove_ads"],
  "subscriptionPack":  ["com.funtap.global.vip_monthly"]
}
```

> Schema **verbatim** spec §11: chỉ product ID, KHÔNG có reward/display_name. Thiếu file ⇒ `onIAPInitialized(false)` — lỗi im lặng, dễ tưởng SDK hỏng.
> iOS: file phải nằm trong *Copy Bundle Resources*; chạy `fetch-config-flutter.bat` sau khi cài là nó tự đăng ký.


## Build Info — file kê khai cạnh thư mục build

Mỗi lần build xong sinh `<package>_<version>_<PLATFORM>_BUILD_INFO.txt` **ngay trong thư mục build**, bố cục **y hệt bản Unity** (`BuildInfo.cs`): id quảng cáo, khoá MAX/AppsFlyer/Facebook, version từng third-party, bảng ad unit `[Android]` + `[iOS]`, và khối `ANDROID vs iOS` chỉ ra chỗ 2 nền khai lệch nhau.

Nguồn số liệu: `fg_main_config.json` (id/khoá) · `fgsdk-deps.gradle` (version Android) · `ios/Podfile.lock` (version iOS **thật sự** CocoaPods giải ra — chưa `pod install` thì ghi rõ "chưa pod install" chứ không đoán).

Xem mẫu: [`docs/sample_BUILD_INFO.txt`](../../docs/sample_BUILD_INFO.txt).

Bản Flutter sinh bằng tay sau khi build (Flutter không có hook build cho plugin): double-click **`build-info-flutter.bat`** ở root project — nó làm **cả android lẫn ios** trong một lần chạy. File bat này được `wire-flutter.js` rải ra root lúc cài.


## Build Info — file kê khai cạnh thư mục build

Mỗi lần build xong sinh `<package>_<version>_<PLATFORM>_BUILD_INFO.txt` **ngay trong thư mục build**, bố cục **y hệt bản Unity** (`BuildInfo.cs`): id quảng cáo, khoá MAX/AppsFlyer/Facebook, version từng third-party, bảng ad unit `[Android]` + `[iOS]`, và khối `ANDROID vs iOS` chỉ ra chỗ 2 nền khai lệch nhau.

Nguồn số liệu: `fg_main_config.json` (id/khoá) · `fgsdk-deps.gradle` (version Android) · `ios/Podfile.lock` (version iOS **thật sự** CocoaPods giải ra — chưa `pod install` thì ghi rõ "chưa pod install" chứ không đoán).

Xem mẫu: [`docs/sample_BUILD_INFO.txt`](../../docs/sample_BUILD_INFO.txt).

Bản Flutter sinh bằng tay sau khi build (Flutter không có hook build cho plugin): double-click **`build-info-flutter.bat`** ở root project — nó làm **cả android lẫn ios** trong một lần chạy. File bat này được `wire-flutter.js` rải ra root lúc cài.

## 3. Dùng

```dart
import 'package:funtap_global_sdk/funtap_global_sdk.dart';

// SDK TỰ init lúc app khởi động — không cần gọi hàm init nào.
final ready = await FGSDK.isInit();

// Ads
FGSDK.onRewardedCompleted.listen((info) => grantReward(info));   // nhận thưởng ở đây
await FGSDK.showRewarded('double_coin', 'classic', 12);
await FGSDK.showInterstitial('main_menu', 'classic', 12);
FGSDK.showBanner('bottom', 'classic', 12);

// Tracking (event/param VERBATIM, bắn Firebase)
FGSDK.logLevelStart(12, 3, 1, 'classic');
FGSDK.logLevelEnd(12, 3, 1, 'classic', 45.2, true, 'clear');
FGSDK.logSpendResource('classic', 12, 'booster', 'gold', 30, 'shop', 'buy', 'sword', 'booster', 170);
FGSDK.logTutorial('success', 'step_3');
FGSDK.logEvent('custom_event', params: {'k': 'v'});

// IAP
final r = await FGSDK.buyProduct('com.game.pack1', 'shop', 'classic', 12);
if (r.ok) print(r.transactionId);
```

Quy ước: getter / `show*` / `buy*` trả **`Future`**; `on*` trả **`Stream`** (broadcast). Không có native (unit test / web / desktop) → **no-op**, getter trả default.

App mẫu đầy đủ nút test: [`example/lib/main.dart`](example/lib/main.dart).

### Hàm tracking gọi sẵn

| Hàm | Event Firebase |
|---|---|
| `logLevelStart(level, playCount, loseCount, playMode, {extra})` | `level_start` |
| `logLevelEnd(level, playCount, loseCount, playMode, playDuration, success, reason, {extra})` | `level_end` |
| `logEarnResource(playMode, level, itemType, name, amount, earnPlacement, item, booster, balance, {extra})` | `resource_source` |
| `logSpendResource(playMode, level, itemType, name, amount, spendPlacement, spendReason, item, booster, balance, {extra})` | `resource_sink` |
| `logTutorial(actionName, actionValue, {extra})` | `tut_action` |
| `logLoadingStart(placement, {extra})` / `logLoadingEnd(placement, isLoad, loadTime, {extra})` | `loading_start` / `loading_finish` |
| `logIAPShow(...)` / `logIAPClick(...)` | `iap_show` / `iap_click` |

`logEvent` không truyền `providers` = **chỉ Firebase** (không phải tất cả provider).

### Event SDK tự log (không cần gọi tay)

- **Firebase**: `ad_request`, `ad_display`, `ad_completed`, `ad_impression`, `ad_revenue_sdk`, `ad_click`.
- **AppLovin** (tự mirror từ event ở trên): `ad_view`, `rewarded_ad_opportunity`, `ad_click`, `level_start`, `level_complete`, `virtual_resource_transaction`, `tutorial_complete`, `use_prop`, `app_open`. Không cần init riêng — bám instance MAX SDK (điều kiện: app dùng mediation có MAX).

---

## 4. iOS

Từ **1.0.4**, lõi native iOS đi kèm dạng **source pod**: source ObjC++ nằm ở `ios/FGSDK/`, CocoaPods compile lúc `pod install` — giống hệt bản Cocos 3.x. Không cần làm gì thêm, `flutter build ios` là chạy.

> Trước 1.0.4 bản iOS là `.xcframework` binary và **phải có máy Mac ở phía Funtap** build lại mỗi lần sửa một dòng ObjC++ mới publish được — chặn cả những thay đổi chỉ liên quan Android. Đổi sang source pod để bỏ hẳn ràng buộc đó. Dev game build iOS thì kiểu gì cũng cần Mac (Apple bắt), nên không phát sinh gánh nặng mới.

Lần `pod install` đầu lâu hơn chút vì phải compile SDK + kéo third-party.

### Những gì tool tự lo (không phải sửa tay)

| Việc | Ai làm | Khi nào |
|---|---|---|
| `platform :ios, '13.0'` trong `Podfile` | `wire-flutter.js` | lúc cài |
| ép `IPHONEOS_DEPLOYMENT_TARGET >= 13.0` cho mọi pod (chèn vào `post_install` có sẵn) | `wire-flutter.js` | lúc cài |
| `Info.plist`: `FacebookAppID` / `FacebookClientToken` / `FacebookDisplayName`, `AppsFlyerDevKey` / `AppleAppID`, `NSUserTrackingUsageDescription`, `GADApplicationIdentifier`, URL scheme `fb<app_id>` + `gl<app_key>`, `LSApplicationQueriesSchemes`, `UIBackgroundModes`, `SKAdNetworkItems`, key Firebase/notification | `fetch-config-flutter.js` | mỗi lần fetch config |
| add `fg_main_config.json` + `GoogleService-Info.plist` vào target `Runner` | `fetch-config-flutter.js` | mỗi lần fetch config |

Map field Info.plist **verbatim** với extension Cocos 3.x ⇒ 3 engine ra cùng một Info.plist. Mọi bước idempotent (chạy lại không nhân đôi) và backup `.fgsdkbak` trước khi sửa.

> ⚠️ `ios/Podfile` do `flutter build ios` sinh ra — **không có sẵn** sau `flutter create`. Cài trên Windows thì 2 dòng đầu bảng sẽ báo "chưa có Podfile"; trên Mac chạy `flutter build ios --no-codesign` một lần rồi chạy lại:
> ```bash
> node funtap_global_sdk/tools/wire-flutter.js --project .
> ```
>
> ⚠️ Vẫn phải tự làm: bật **Push Notifications** / capability khác nếu game cần, và `pod install` (Flutter tự gọi lúc build iOS).

*Maintainer:* build trên máy Mac —
```bash
brew install xcodegen cocoapods
node tools/sync-sdk.js       # copy source mới native/ios/FGSDK -> ios/FGSDK
```
rồi publish lại package. **Không cần máy Mac.** (Script `native/ios/tools/build-xcframework.sh` vẫn giữ trong repo, phòng khi cần bản binary giao cho đối tác ngoài.)

---

## 5. Cập nhật version mới

Chạy lại `install-fgsdk-flutter-<batver>.bat` → `flutter pub get` → build lại. Config giữ nguyên, khỏi fetch lại.

## 6. Troubleshooting

| Triệu chứng | Xử lý |
|---|---|
| `isInit()` = false (Android) | Thiếu `fg_main_config.json` trong `android/app/src/main/assets` → chạy fetch config |
| `isInit()` = false (iOS), log "thiếu/parse lỗi fg_main_config.json" | File chưa vào *Copy Bundle Resources*. Chạy lại `fetch-config-flutter.bat`; nếu nó báo "khong doc duoc cau truc Runner.xcodeproj" thì kéo tay 2 file trong `ios/Runner/` vào target `Runner` của Xcode |
| Pod báo deployment target thấp / `platform :ios` | Chạy lại `node funtap_global_sdk/tools/wire-flutter.js --project .` trên Mac (Podfile chỉ có sau lần build iOS đầu) |
| Quảng cáo không ra tiền (bản release) | AdMob app id vẫn là bản TEST. Kiểm `FGSDK_ADMOB_APP_ID` trong `android/gradle.properties` — thiếu thì chạy lại fetch config. (Đặt ở `app/build.gradle` **không có tác dụng**: meta-data nằm trong manifest của plugin.) |
| `pod install` báo thiếu `ios/FGSDK` | Pack hỏng — cài lại bằng installer bat; vẫn thiếu thì báo Funtap |
| iOS lỗi compile trong pod `funtap_global_sdk` | Source SDK compile trên máy bạn (source pod) — gửi log cho Funtap |
| IAP init `false` | Thiếu/sai `iap_packs.json` (xem §2). iOS còn cần file đó nằm trong *Copy Bundle Resources* → chạy `fetch-config-flutter.bat` |
| Gọi hàm mới mà im re | Package cũ — chạy lại install bat + `flutter pub get` |
| Build lỗi minSdk | Cần `minSdk >= 24`; wire script tự sửa, kiểm lại `android/app/build.gradle` |

---

Version package ≠ version native SDK (`getSdkVersion()` = `3.2.6`, verbatim Unity).
