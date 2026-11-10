#
# funtap_global_sdk.podspec — phần iOS của plugin Flutter.
#
# Lõi SDK đi kèm dạng **SOURCE** (`ios/FGSDK/`, ObjC++), CocoaPods compile lúc `pod install`
# trên máy build của game — giống hệt cách bản Cocos 3.x đóng gói.
#
# Vì sao KHÔNG dùng `.xcframework` binary như dự tính ban đầu:
#   - Binary bắt buộc phải có máy Mac Ở PHÍA MÌNH để build lại **mỗi lần sửa một dòng ObjC++**,
#     rồi mới publish được → chặn cả những thay đổi chỉ liên quan Android.
#   - Mà nó KHÔNG giấu được gì thêm: package `funtap-global-sdk-cocos` (bản 3.x) vốn đã ship
#     nguyên source iOS này và registry cho đọc ẩn danh.
#   - Dev game build iOS thì kiểu gì cũng cần Mac (Apple bắt), nên chuyển chỗ compile sang họ
#     không phát sinh gánh nặng mới.
# Script `native/ios/tools/build-xcframework.sh` vẫn giữ trong repo, phòng khi cần bản binary
# để giao cho đối tác ngoài.
#
Pod::Spec.new do |s|
  s.name             = 'funtap_global_sdk'
  s.version          = '1.0.5'
  s.summary          = 'Funtap Global SDK — ads, tracking, remote config, IAP, deeplink cho Flutter.'
  s.description      = 'Plugin Flutter dùng chung lõi native với 2 package Cocos (protocol FGBridgeCore).'
  s.homepage         = 'https://funtapglobal.com'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Funtap' => 'ducta@funtap.vn' }
  s.source           = { :path => '.' }

  s.platform         = :ios, '13.0'   # ATT (§6.1/§6.2) + connectedScenes cần iOS 13+
  s.requires_arc     = true

  # Glue plugin (Classes/) + lõi SDK (FGSDK/) — cùng compile vào pod của plugin.
  s.source_files        = 'Classes/**/*.{h,mm}', 'FGSDK/**/*.{h,mm}'
  s.public_header_files  = 'Classes/**/*.h'

  s.dependency 'Flutter'

  # ObjC++ C++17 (SDK dùng std::function / std::optional / inline variable)
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY'           => 'libc++',
    'DEFINES_MODULE'              => 'YES',
    'HEADER_SEARCH_PATHS'         => '"${PODS_TARGET_SRCROOT}/FGSDK"',
    # Flutter build cho iOS device: loại i386
    'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64 arm64',
  }

  s.frameworks = 'StoreKit', 'AppTrackingTransparency', 'AdSupport', 'Network', 'UIKit', 'Foundation'

  # Third-party mà FGSDK cần (baseline spec §17 — khớp FGSDK.podspec bản Cocos).
  s.dependency 'AppLovinSDK'                    # ads MAX §7 (+ UMP đi kèm)
  s.dependency 'Google-Mobile-Ads-SDK'          # admob backfill §8
  s.dependency 'GoogleUserMessagingPlatform'    # consent UMP §6.1
  s.dependency 'FirebaseAnalytics'              # tracking §9
  s.dependency 'FirebaseRemoteConfig'           # remote config §10
  # AppsFlyer GHIM đúng bản Unity (AppsFlyerDependencies.xml): để trống CocoaPods kéo 7.x — major mới, code
  # ObjC++ viết cho 6.x, và Android đã dính cặp lệch làm connector chết lặng (mất af_purchase).
  s.dependency 'AppsFlyerFramework', '6.17.8'   # tracking §9.4
  s.dependency 'PurchaseConnector', '6.17.8'    # ROI360 af_purchase §11 (StoreKit 1)
  s.dependency 'FBSDKCoreKit'                   # facebook §9.5

  # Báo lỗi SỚM + rõ ràng nếu package bị thiếu source (pack hỏng), thay vì để CocoaPods
  # fail bằng một thông báo khó hiểu ở tận bước compile.
  unless File.directory?(File.join(__dir__, 'FGSDK'))
    raise <<~MSG
      [funtap_global_sdk] Thiếu thư mục ios/FGSDK — package tải về bị thiếu source iOS.
      Cài lại bằng install-fgsdk-flutter-<batver>.bat; vẫn thiếu thì báo Funtap (lỗi đóng gói).
    MSG
  end
end
