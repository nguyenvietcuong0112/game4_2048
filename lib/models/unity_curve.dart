import 'dart:convert';
import 'package:flutter/services.dart';

class UnityKeyframe {
  final double time;
  final double value;
  final double inSlope;
  final double outSlope;

  const UnityKeyframe({
    required this.time,
    required this.value,
    this.inSlope = 0.0,
    this.outSlope = 0.0,
  });

  factory UnityKeyframe.fromJson(Map<String, dynamic> json) {
    return UnityKeyframe(
      time: (json['time'] as num?)?.toDouble() ?? 0.0,
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      inSlope: (json['inSlope'] as num?)?.toDouble() ?? 0.0,
      outSlope: (json['outSlope'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Evaluates Unity AnimationCurve (`m_Curve`) using exact Cubic Hermite Splines.
class UnityCurve {
  final List<UnityKeyframe> keys;

  const UnityCurve(this.keys);

  factory UnityCurve.linear([double start = 0.0, double end = 1.0]) {
    return UnityCurve([
      UnityKeyframe(time: 0.0, value: start, inSlope: end - start, outSlope: end - start),
      UnityKeyframe(time: 1.0, value: end, inSlope: end - start, outSlope: end - start),
    ]);
  }

  factory UnityCurve.fromJson(Map<String, dynamic>? json, {UnityCurve? fallback}) {
    if (json == null) return fallback ?? UnityCurve.linear();
    final rawList = json['m_Curve'] as List<dynamic>?;
    if (rawList == null || rawList.isEmpty) {
      return fallback ?? UnityCurve.linear();
    }
    final parsed = rawList
        .whereType<Map<String, dynamic>>()
        .map(UnityKeyframe.fromJson)
        .toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return UnityCurve(parsed);
  }

  double evaluate(double t) {
    if (keys.isEmpty) return t;
    if (keys.length == 1 || t <= keys.first.time) return keys.first.value;
    if (t >= keys.last.time) return keys.last.value;

    for (int i = 0; i < keys.length - 1; i++) {
      final k0 = keys[i];
      final k1 = keys[i + 1];
      if (t >= k0.time && t <= k1.time) {
        final dt = k1.time - k0.time;
        if (dt <= 1e-6) return k1.value;
        final u = (t - k0.time) / dt;
        final u2 = u * u;
        final u3 = u2 * u;

        // Handle stepped tangents (>100 slope in Unity)
        if (k0.outSlope.abs() > 200 || k1.inSlope.abs() > 200) {
          return k0.value;
        }

        final h00 = 2 * u3 - 3 * u2 + 1;
        final h10 = u3 - 2 * u2 + u;
        final h01 = -2 * u3 + 3 * u2;
        final h11 = u3 - u2;

        final m0 = k0.outSlope * dt;
        final m1 = k1.inSlope * dt;
        return h00 * k0.value + h10 * m0 + h01 * k1.value + h11 * m1;
      }
    }
    return keys.last.value;
  }
}

class PieceVisualSettings {
  final double followSmoothing;
  final double settleSmoothing;
  final double offsetWhileDragging;
  final double shakeDuration;
  final double shakeRange;
  final double jellyLeanMax;
  final double jellyStiffness;
  final double jellyDamping;

  final double mergeCandidatePulseDuration;
  final UnityCurve mergeCandidatePulseScale;
  final double mergeTransitionExpandDuration;
  final UnityCurve mergeTransitionExpandCurve;
  final double mergeNumberSettleDuration;
  final UnityCurve mergeNumberSettleSize;

  final double tapDuration;
  final UnityCurve tapScaleZ;
  final UnityCurve tapInflate;

  final double mergeSurvivorMovesDuration;
  final double mergeSurvivorMovesPulseScale;
  final UnityCurve mergeSurvivorMovesPulseCurve;
  final double reflectionAlpha;

  final double cameraIntroDuration;
  final UnityCurve cameraIntroCurve;
  final double cameraWinZoomFactor;
  final double cameraWinDuration;
  final UnityCurve cameraWinCurve;

  final double levelUpLiftDuration;
  final UnityCurve levelUpLiftCurve;
  final double levelUpTravelDuration;
  final UnityCurve levelUpTravelCurve;
  final double levelUpLandDuration;
  final UnityCurve levelUpLandCurve;

  const PieceVisualSettings({
    required this.followSmoothing,
    required this.settleSmoothing,
    required this.offsetWhileDragging,
    required this.shakeDuration,
    required this.shakeRange,
    required this.jellyLeanMax,
    required this.jellyStiffness,
    required this.jellyDamping,
    required this.mergeCandidatePulseDuration,
    required this.mergeCandidatePulseScale,
    required this.mergeTransitionExpandDuration,
    required this.mergeTransitionExpandCurve,
    required this.mergeNumberSettleDuration,
    required this.mergeNumberSettleSize,
    required this.tapDuration,
    required this.tapScaleZ,
    required this.tapInflate,
    required this.mergeSurvivorMovesDuration,
    required this.mergeSurvivorMovesPulseScale,
    required this.mergeSurvivorMovesPulseCurve,
    required this.reflectionAlpha,
    required this.cameraIntroDuration,
    required this.cameraIntroCurve,
    required this.cameraWinZoomFactor,
    required this.cameraWinDuration,
    required this.cameraWinCurve,
    required this.levelUpLiftDuration,
    required this.levelUpLiftCurve,
    required this.levelUpTravelDuration,
    required this.levelUpTravelCurve,
    required this.levelUpLandDuration,
    required this.levelUpLandCurve,
  });

  static Future<PieceVisualSettings> loadFromAssets() async {
    final pvStr = await rootBundle.loadString('assets/configs/piece_visual.json');
    final camStr = await rootBundle.loadString('assets/configs/camera_anim.json');
    final luStr = await rootBundle.loadString('assets/configs/level_up_visual.json');

    final pv = (jsonDecode(pvStr)['data'] as Map<String, dynamic>?) ?? {};
    final cam = (jsonDecode(camStr)['data'] as Map<String, dynamic>?) ?? {};
    final lu = (jsonDecode(luStr)['data'] as Map<String, dynamic>?) ?? {};

    double d(Map<String, dynamic> m, String k, double def) =>
        (m[k] as num?)?.toDouble() ?? def;

    return PieceVisualSettings(
      followSmoothing: d(pv, 'FollowSmoothing', 45.0),
      settleSmoothing: d(pv, 'SettleSmoothing', 20.0),
      offsetWhileDragging: d(pv, 'OffsetWhileDragging', 0.10),
      shakeDuration: d(pv, 'ShakeDuration', 0.20),
      shakeRange: d(pv, 'ShakeRange', 0.06),
      jellyLeanMax: d(pv, 'JellyLeanMax', 0.075),
      jellyStiffness: d(pv, 'JellyStiffness', 300.0),
      jellyDamping: d(pv, 'JellyDamping', 0.20),
      mergeCandidatePulseDuration: d(pv, 'MergeCandidatePulseDuration', 1.0),
      mergeCandidatePulseScale: UnityCurve.fromJson(
        pv['MergeCandidatePulseScaleZ'] as Map<String, dynamic>?,
      ),
      mergeTransitionExpandDuration: d(pv, 'MergeTransitionExpandDuration', 0.30),
      mergeTransitionExpandCurve: UnityCurve.fromJson(
        pv['MergeTransitionExpandCurve'] as Map<String, dynamic>?,
      ),
      mergeNumberSettleDuration: d(pv, 'MergeNumberSettleDuration', 0.50),
      mergeNumberSettleSize: UnityCurve.fromJson(
        pv['MergeNumberSettleSize'] as Map<String, dynamic>?,
      ),
      tapDuration: d(pv, 'TapDuration', 0.50),
      tapScaleZ: UnityCurve.fromJson(pv['TapScaleZ'] as Map<String, dynamic>?),
      tapInflate: UnityCurve.fromJson(pv['TapInflate'] as Map<String, dynamic>?),
      mergeSurvivorMovesDuration: d(pv, 'MergeSurvivorMovesDuration', 0.28),
      mergeSurvivorMovesPulseScale: d(pv, 'MergeSurvivorMovesPulseScale', 1.12),
      mergeSurvivorMovesPulseCurve: UnityCurve.fromJson(
        pv['MergeSurvivorMovesPulseCurve'] as Map<String, dynamic>?,
      ),
      reflectionAlpha: d(pv, 'ReflectionAlpha', 0.197),
      cameraIntroDuration: d(cam, 'IntroDuration', 0.35),
      cameraIntroCurve: UnityCurve.fromJson(cam['IntroCurve'] as Map<String, dynamic>?),
      cameraWinZoomFactor: d(cam, 'WinZoomInFactor', 0.90),
      cameraWinDuration: d(cam, 'WinDuration', 0.35),
      cameraWinCurve: UnityCurve.fromJson(cam['WinCurve'] as Map<String, dynamic>?),
      levelUpLiftDuration: d(lu, 'LiftDuration', 0.35),
      levelUpLiftCurve: UnityCurve.fromJson(lu['LiftCurve'] as Map<String, dynamic>?),
      levelUpTravelDuration: d(lu, 'TravelDuration', 0.45),
      levelUpTravelCurve: UnityCurve.fromJson(lu['TravelCurve'] as Map<String, dynamic>?),
      levelUpLandDuration: d(lu, 'LandDuration', 0.35),
      levelUpLandCurve: UnityCurve.fromJson(lu['LandCurve'] as Map<String, dynamic>?),
    );
  }
}
