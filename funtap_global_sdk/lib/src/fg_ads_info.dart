/// Thông tin 1 lần hiển thị/sự kiện quảng cáo (spec §5.3 — 10 field).
///
/// ⚠️ Key JSON trên dây giữ VERBATIM PascalCase như bản Unity/Cocos
/// (`AdID`, `AdFormat`, …). Field Dart đặt theo lowerCamelCase cho đúng
/// convention Dart — bảng ánh xạ ghi ngay cạnh từng field.
class FGAdsInfo {
  const FGAdsInfo({
    required this.adId,
    required this.adFormat,
    required this.networkName,
    required this.networkPlacement,
    required this.placement,
    required this.creativeIdentifier,
    required this.revenue,
    required this.revenuePrecision,
    required this.latencyMillis,
    required this.dspName,
  });

  /// `AdID`
  final String adId;

  /// `AdFormat` — `interstitial` / `reward` / `banner` / `app_open` / `mrec`.
  final String adFormat;

  /// `NetworkName`
  final String networkName;

  /// `NetworkPlacement`
  final String networkPlacement;

  /// `Placement` — placement do game truyền lúc gọi `show*`.
  final String placement;

  /// `CreativeIdentifier`
  final String creativeIdentifier;

  /// `Revenue` — doanh thu ước tính (USD).
  final double revenue;

  /// `RevenuePrecision`
  final String revenuePrecision;

  /// `LatencyMillis`
  final int latencyMillis;

  /// `DspName`
  final String dspName;

  static String _s(Map<Object?, Object?> m, String k) => (m[k] as String?) ?? '';
  static double _d(Map<Object?, Object?> m, String k) =>
      (m[k] as num?)?.toDouble() ?? 0.0;
  static int _i(Map<Object?, Object?> m, String k) => (m[k] as num?)?.toInt() ?? 0;

  /// Parse từ map JSON native gửi lên (key PascalCase verbatim).
  factory FGAdsInfo.fromMap(Map<Object?, Object?> m) => FGAdsInfo(
        adId: _s(m, 'AdID'),
        adFormat: _s(m, 'AdFormat'),
        networkName: _s(m, 'NetworkName'),
        networkPlacement: _s(m, 'NetworkPlacement'),
        placement: _s(m, 'Placement'),
        creativeIdentifier: _s(m, 'CreativeIdentifier'),
        revenue: _d(m, 'Revenue'),
        revenuePrecision: _s(m, 'RevenuePrecision'),
        latencyMillis: _i(m, 'LatencyMillis'),
        dspName: _s(m, 'DspName'),
      );

  @override
  String toString() => 'FGAdsInfo(adFormat: $adFormat, networkName: $networkName, '
      'placement: $placement, revenue: $revenue)';
}
