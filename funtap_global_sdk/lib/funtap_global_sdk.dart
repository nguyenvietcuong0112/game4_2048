/// Funtap Global SDK cho Flutter — ads (MAX + AdMob backfill), tracking
/// (Firebase/AppsFlyer/Facebook/AppLovin), remote config, IAP, deeplink.
///
/// Dùng chung lõi native với 2 package Cocos (`funtap-global-sdk-cocos`,
/// `funtap-global-sdk-cocos2x`) nên hành vi/tên event là y hệt.
///
/// ```dart
/// import 'package:funtap_global_sdk/funtap_global_sdk.dart';
///
/// final ok = await FGSDK.isInit();
/// FGSDK.onRewardedCompleted.listen(grantReward);
/// await FGSDK.showRewarded('double_coin', 'classic', 12);
/// FGSDK.logLevelStart(12, 3, 1, 'classic');
/// ```
library;

export 'src/fg_ads_info.dart';
export 'src/fg_sdk.dart';
export 'src/fg_types.dart';
