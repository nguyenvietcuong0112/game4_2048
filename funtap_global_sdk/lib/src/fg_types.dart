/// Kiểu dùng chung của Funtap Global SDK.
///
/// ⚠️ Giá trị "trên dây" (wire) gửi xuống native phải VERBATIM khớp enum
/// `ProviderType` bên Kotlin/ObjC++ — xem [FGProviderType.wireName].
library;

/// Param của event/tracking. Value cho phép String/num/bool/null
/// (khớp `Params = Map<String, Any?>` bên Kotlin).
typedef FGParams = Map<String, Object?>;

/// Provider đích của một tracking event (spec §3.6).
///
/// Overload KHÔNG chỉ định provider = **chỉ Firebase** (không phải tất cả).
enum FGProviderType {
  firebase('Firebase'),
  appsFlyer('AppsFlyer'),
  facebook('Facebook'),

  /// Kênh AppLovin EventService (mở rộng ngoài Unity spec).
  appLovin('AppLovin');

  const FGProviderType(this.wireName);

  /// Tên gửi xuống native — PHẢI khớp tên enum Kotlin (`ProviderType.valueOf`).
  final String wireName;
}

/// Vị trí MRec: hoặc preset (số nguyên của SDK), hoặc toạ độ màn hình.
///
/// Mirror kiểu `number | {x,y}` bên wrapper TS/JS của bản Cocos.
class FGMRecPosition {
  const FGMRecPosition._(this._preset, this._x, this._y);

  /// Preset dựng sẵn của SDK (`adPosition`).
  const FGMRecPosition.preset(int adPosition) : this._(adPosition, null, null);

  /// Toạ độ màn hình.
  const FGMRecPosition.screen(double x, double y) : this._(null, x, y);

  final int? _preset;
  final double? _x;
  final double? _y;

  /// Trộn vào args gửi native: `adPosition` HOẶC cặp `x`/`y`
  /// (native phân nhánh bằng `has("adPosition")`).
  Map<String, Object?> toArgs() =>
      _preset != null ? {'adPosition': _preset} : {'x': _x, 'y': _y};
}
