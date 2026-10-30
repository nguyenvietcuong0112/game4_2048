import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BlockColorStyle {
  final int number;
  final Color topBright;
  final Color topMid;
  final Color bottomLip;
  final Color rimHighlight;
  final Color accent;
  final Color numberStrokeOuter;
  final Color numberStrokeMid;
  final Color numberStrokeInner;
  final Color screwBright;
  final Color screwDark;
  final Color arrowStroke;
  final Color arrowShadow;

  const BlockColorStyle({
    required this.number,
    required this.topBright,
    required this.topMid,
    required this.bottomLip,
    required this.rimHighlight,
    required this.accent,
    required this.numberStrokeOuter,
    required this.numberStrokeMid,
    required this.numberStrokeInner,
    required this.screwBright,
    required this.screwDark,
    required this.arrowStroke,
    required this.arrowShadow,
  });
}

class BlockOrderPalette {
  final Map<int, BlockColorStyle> _styles;

  const BlockOrderPalette(this._styles);

  /// Exact ColorRamp & `ref_gameplay.png` sampled stops: `[bottomLip, topMid, topBright]`.
  static const Map<int, List<Color>> _rampColors = {
    2: [Color(0xFFCFA161), Color(0xFFF1D499), Color(0xFFFAF0C5)],
    4: [Color(0xFFCB5700), Color(0xFFF38A0F), Color(0xFFFD9F16)],
    8: [Color(0xFFC8142E), Color(0xFFF33C5E), Color(0xFFFC557C)],
    16: [Color(0xFFB30295), Color(0xFFEC24CA), Color(0xFFFA38DC)],
    32: [Color(0xFF6703B2), Color(0xFF9E1CF4), Color(0xFFB32BFF)],
    64: [Color(0xFF2B13BF), Color(0xFF3E22F6), Color(0xFF5339FF)],
    128: [Color(0xFF035299), Color(0xFF0574CE), Color(0xFF1490F0)],
    256: [Color(0xFF058354), Color(0xFF0BA870), Color(0xFF13C485)],
    512: [Color(0xFF21862A), Color(0xFF36C226), Color(0xFF4AE02E)],
    1024: [Color(0xFF409703), Color(0xFF88CB0A), Color(0xFFA7E20F)],
    2048: [Color(0xFFD98102), Color(0xFFF8BA04), Color(0xFFFFD812)],
    4096: [Color(0xFF5A29E6), Color(0xFF8465F8), Color(0xFF9B82FD)],
    8192: [Color(0xFF0AA5BE), Color(0xFF28C3EC), Color(0xFF48DCFF)],
    0: [Color(0xFF743508), Color(0xFFA85C24), Color(0xFFBF6F34)], // Dud
    -1: [Color(0xFF197AF0), Color(0xFF63A2FA), Color(0xFF82BEFF)], // Ice
  };

  static Color _parseUnityColor(Map<String, dynamic>? m, Color fallback) {
    if (m == null) return fallback;
    final r = ((m['r'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0);
    final g = ((m['g'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0);
    final b = ((m['b'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0);
    final a = ((m['a'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0);
    return Color.fromARGB(
      (a * 255).round(),
      (r * 255).round(),
      (g * 255).round(),
      (b * 255).round(),
    );
  }

  static Future<BlockOrderPalette> loadFromAssets() async {
    final jsonStr = await rootBundle.loadString('assets/configs/palette.json');
    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    final entries = (decoded['data']?['_entries'] as List<dynamic>?) ?? [];

    final Map<int, BlockColorStyle> map = {};
    for (final raw in entries) {
      if (raw is! Map<String, dynamic>) continue;
      final numVal = (raw['_number'] as num?)?.toInt() ?? 2;
      final ramp = _rampColors[numVal] ?? _rampColors[2048]!;
      final bottomLip = ramp[0];
      final topMid = ramp[1];
      final topBright = ramp[2];
      final rim = Color.lerp(
        topBright,
        Colors.white,
        numVal == -1 ? 0.66 : (numVal == 2 ? 0.50 : 0.38),
      )!;

      final accent =
          _parseUnityColor(raw['_accent'] as Map<String, dynamic>?, topBright);
      final s1 = _parseUnityColor(
        raw['_numberStroke1Color'] as Map<String, dynamic>?,
        const Color(0xFF2B1805),
      );
      final s2 = _parseUnityColor(
        raw['_numberStroke2Color'] as Map<String, dynamic>?,
        bottomLip,
      );
      final s3 = _parseUnityColor(
        raw['_numberStroke3Color'] as Map<String, dynamic>?,
        accent,
      );
      final scBright = _parseUnityColor(
        raw['_stationaryBlockScrewShadowBrightColor'] as Map<String, dynamic>?,
        topMid,
      );
      final scDark = _parseUnityColor(
        raw['_stationaryBlockScrewShadowDarkColor'] as Map<String, dynamic>?,
        bottomLip,
      );
      final arStroke = _parseUnityColor(
        raw['_movementArrowStrokeColor'] as Map<String, dynamic>?,
        bottomLip,
      );
      final arShadow = _parseUnityColor(
        raw['_movementArrowShadowColor'] as Map<String, dynamic>?,
        s1,
      );

      map[numVal] = BlockColorStyle(
        number: numVal,
        topBright: topBright,
        topMid: topMid,
        bottomLip: bottomLip,
        rimHighlight: rim,
        accent: accent,
        numberStrokeOuter: s1,
        numberStrokeMid: s2,
        numberStrokeInner: s3,
        screwBright: scBright,
        screwDark: scDark,
        arrowStroke: arStroke,
        arrowShadow: arShadow,
      );
    }

    return BlockOrderPalette(map);
  }

  BlockColorStyle styleFor({required int? number, required bool isFrozen}) {
    if (isFrozen) {
      return _styles[-1] ?? _fallbackStyle(-1);
    }
    if (number == null || number == 0) {
      return _styles[0] ?? _fallbackStyle(0);
    }
    if (_styles.containsKey(number)) {
      return _styles[number]!;
    }
    int wrapped = number;
    while (wrapped > 8192) {
      wrapped = wrapped ~/ 2;
    }
    return _styles[wrapped] ?? _fallbackStyle(2048);
  }

  BlockColorStyle _fallbackStyle(int key) {
    final ramp = _rampColors[key] ?? _rampColors[2048]!;
    return BlockColorStyle(
      number: key,
      topBright: ramp[2],
      topMid: ramp[1],
      bottomLip: ramp[0],
      rimHighlight: Color.lerp(ramp[2], Colors.white, key == -1 ? 0.66 : 0.38)!,
      accent: ramp[2],
      numberStrokeOuter: const Color(0xFF251506),
      numberStrokeMid: ramp[0],
      numberStrokeInner: ramp[2],
      screwBright: ramp[1],
      screwDark: ramp[0],
      arrowStroke: ramp[0],
      arrowShadow: const Color(0xFF251506),
    );
  }
}
