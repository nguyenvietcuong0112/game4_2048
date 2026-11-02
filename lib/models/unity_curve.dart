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

class DigitLayoutMetrics {
  final double fontSize;
  final double characterSpacing;
  final double horizontalScale;

  const DigitLayoutMetrics({
    required this.fontSize,
    required this.characterSpacing,
    required this.horizontalScale,
  });
}

/// Exact serialized `BoardView` prefab values (`CAB-83ebb146b2b39830f83c925042e65c48`, `PathID 3015269056865960924`).
class UnityBoardConfig {
  static const double cellSize = 1.0;
  static const double footprintPlaneZ = 0.49;
  static const double stepHysteresis = 0.05; // Step commit threshold = 0.5 + 0.05 = 0.55 cells
  static const double softGiveCap = 0.12; // Max hyperbolic soft-wall give in cells
  static const double generosityRadius = 0.22; // Nearby unsurrounded pick radius = 0.5 + 0.22 = 0.72 cells
  static const double mergeOverlapTravel = 0.80; // Max hyperbolic merge push travel in cells
  static const double mergeOverlapThreshold = 0.50; // Free 1:1 linear merge overlap & 100% MergePush depth
  static const double mergeArmDepth = 0.15; // Overlap depth required to initially arm a merge candidate
  static const double tapMaxDuration = 0.25; // Seconds
  static const double tapMaxTravel = 0.15; // Cells
  static const int maxStepsPerFrame = 8;

  // Merge Sparks (`VFX_MergeSparks`) spawned on survivor blocks after normal merge commit
  static const double mergeSparksDelay = 0.10; // Seconds
  static const double mergeSparksLift = 0.15; // Cells
  static const double mergeSparksDownOffset = 0.15; // Cells
}

/// Exact serialized `StationaryBlocksParts`, `MovementComponentView`, `NumberComponentView`, and `IceComponentView` values.
class UnityComponentVisualConfig {
  // StationaryBlocksParts (`#-8540116936377298364`)
  static const double multiBlockCornerOffsetX = 0.23979275;
  static const double multiBlockCornerOffsetY = 0.23799400;
  static const double singleBlockScale = 0.65;
  static const double singleBlockCornerOffset = 0.30;

  // MovementMechanicView (`#5750178936031051496`)
  static const double arrowZOffset = -1.05;
  static const double shadowAlphaMultiplier = 1.0;
  static const double compactArrowScale = 0.55;
  static const double compactSideOffset = 0.30;
  static const double compactVerticalOffset = 0.30;
  static const double pushedArrowEdgeMargin = 0.04;
  static const double maxPinPush = 0.03;

  // NumberComponentView (`#6739655967930253057`)
  static const List<DigitLayoutMetrics> metricsByDigitCount = [
    DigitLayoutMetrics(fontSize: 7.03, characterSpacing: 0.0, horizontalScale: 1.00),
    DigitLayoutMetrics(fontSize: 7.03, characterSpacing: -3.0, horizontalScale: 1.00),
    DigitLayoutMetrics(fontSize: 6.15, characterSpacing: -5.0, horizontalScale: 0.95),
    DigitLayoutMetrics(fontSize: 4.40, characterSpacing: -7.0, horizontalScale: 0.90),
  ];
  static const double maxFontSize = 4.875;
  static const double roomSideMargin = 0.08;
  static const double arrowMargin = 0.05;
  static const double compactScale = 0.60;

  // IceComponentView (`#-8943221095319416374`)
  static const double icePopClipDuration = 0.38333333; // 23 frames @ 60fps
  static const double icePopPeakScale = 1.62907;
  static const double iceDamageShakeRangeMultiplier = 1.5;
}

/// Exact serialized `TutorialHandConfig` (`#1636236552152265269`).
class UnityTutorialHandConfig {
  static const double spawnOffsetX = 100.0;
  static const double spawnOffsetY = 0.0;
  static const double startDelay = 0.0;
  static const double toPoint1Duration = 0.60;
  static const UnityCurve toPoint1Curve = UnityCurve([
    UnityKeyframe(time: 0.0, value: 0.0, inSlope: 2.06389594, outSlope: 2.06389594),
    UnityKeyframe(time: 1.0, value: 1.0, inSlope: 0.0, outSlope: 0.0),
  ]);
  static const double fadeInDuration = 0.30;
  static const double pauseAtPoint1 = 0.50;
  static const double toPoint2Duration = 0.80;
  static const UnityCurve toPoint2Curve = UnityCurve([
    UnityKeyframe(time: 0.0, value: 0.0, inSlope: 0.0, outSlope: 0.0),
    UnityKeyframe(time: 1.0, value: 1.0, inSlope: 0.0, outSlope: 0.0),
  ]);
  static const double pauseAtPoint2 = 0.50;
  static const double fadeOutDuration = 0.50;
  static const double pauseBeforeRepeat = 0.50;
}

class PieceVisualSettings {
  final double followSmoothing;
  final double settleSmoothing;
  final double offsetWhileDragging;
  final double shakeDuration;
  final double shakeRange;
  final double jellyLeanPerLagCell;
  final double jellyLeanMax;
  final double jellyLeanSizeFalloff;
  final double jellyTiltPerLeanCell;
  final double jellyStiffness;
  final double jellyDamping;

  final double stationaryAnchorShrinkDuration;
  final UnityCurve stationaryAnchorShrinkCurve;

  final double mergeCandidatePulseDuration;
  final UnityCurve mergeCandidatePulseScale;
  final double mergeCandidateReleaseDuration;
  final UnityCurve mergeCandidateReleaseCurve;
  final double mergeCandidateSurvivorLift;
  final UnityCurve mergeCandidatePushInflate;
  final double mergeCandidatePushReleaseDuration;
  final UnityCurve mergeJoinStrength;

  final UnityCurve mergeTransitionRadius;
  final double mergeTransitionMinShapeSize;
  final double mergeTransitionSoftness;
  final double mergeTransitionExpandDuration;
  final UnityCurve mergeTransitionExpandCurve;

  final UnityCurve mergePreviewNumberSize;
  final UnityCurve mergePartnerNumberSize;
  final double mergePreviewNumberDepth;
  final double mergeNumberSettleDuration;
  final UnityCurve mergeNumberSettleSize;

  final double tapDuration;
  final UnityCurve tapScaleZ;
  final UnityCurve tapInflate;

  final double mergeSurvivorMovesDuration;
  final double mergeSurvivorMovesPulseScale;
  final UnityCurve mergeSurvivorMovesPulseCurve;

  final double mergeSurvivorStaysDuration;
  final double mergeSurvivorStaysPulseScale;
  final UnityCurve mergeSurvivorStaysPulseCurve;
  final UnityCurve mergeSurvivorStaysImpulseCurve;

  final double reflectionAlpha;

  final double cameraIntroSizeOffset;
  final double cameraIntroDuration;
  final UnityCurve cameraIntroCurve;
  final double cameraWinZoomFactor;
  final double cameraWinDuration;
  final UnityCurve cameraWinCurve;

  final double levelUpLiftHeight;
  final double levelUpLiftDuration;
  final UnityCurve levelUpLiftCurve;
  final UnityCurve levelUpLiftJiggleCurve;
  final double levelUpTravelDuration;
  final UnityCurve levelUpTravelCurve;
  final double levelUpMergeArmDistance;
  final UnityCurve levelUpShrinkCurve;
  final double levelUpLandDelay;
  final double levelUpLandDuration;
  final UnityCurve levelUpLandCurve;
  final UnityCurve levelUpLandJiggleCurve;
  final double levelUpGlowDuration;
  final UnityCurve levelUpGlowIntensity;

  const PieceVisualSettings({
    required this.followSmoothing,
    required this.settleSmoothing,
    required this.offsetWhileDragging,
    required this.shakeDuration,
    required this.shakeRange,
    required this.jellyLeanPerLagCell,
    required this.jellyLeanMax,
    required this.jellyLeanSizeFalloff,
    this.jellyTiltPerLeanCell = 90.0,
    required this.jellyStiffness,
    required this.jellyDamping,
    required this.stationaryAnchorShrinkDuration,
    required this.stationaryAnchorShrinkCurve,
    required this.mergeCandidatePulseDuration,
    required this.mergeCandidatePulseScale,
    required this.mergeCandidateReleaseDuration,
    required this.mergeCandidateReleaseCurve,
    required this.mergeCandidateSurvivorLift,
    required this.mergeCandidatePushInflate,
    required this.mergeCandidatePushReleaseDuration,
    required this.mergeJoinStrength,
    required this.mergeTransitionRadius,
    required this.mergeTransitionMinShapeSize,
    required this.mergeTransitionSoftness,
    required this.mergeTransitionExpandDuration,
    required this.mergeTransitionExpandCurve,
    required this.mergePreviewNumberSize,
    required this.mergePartnerNumberSize,
    required this.mergePreviewNumberDepth,
    required this.mergeNumberSettleDuration,
    required this.mergeNumberSettleSize,
    required this.tapDuration,
    required this.tapScaleZ,
    required this.tapInflate,
    required this.mergeSurvivorMovesDuration,
    required this.mergeSurvivorMovesPulseScale,
    required this.mergeSurvivorMovesPulseCurve,
    required this.mergeSurvivorStaysDuration,
    required this.mergeSurvivorStaysPulseScale,
    required this.mergeSurvivorStaysPulseCurve,
    required this.mergeSurvivorStaysImpulseCurve,
    required this.reflectionAlpha,
    this.cameraIntroSizeOffset = 5.0,
    required this.cameraIntroDuration,
    required this.cameraIntroCurve,
    required this.cameraWinZoomFactor,
    required this.cameraWinDuration,
    required this.cameraWinCurve,
    required this.levelUpLiftHeight,
    required this.levelUpLiftDuration,
    required this.levelUpLiftCurve,
    required this.levelUpLiftJiggleCurve,
    required this.levelUpTravelDuration,
    required this.levelUpTravelCurve,
    required this.levelUpMergeArmDistance,
    required this.levelUpShrinkCurve,
    required this.levelUpLandDelay,
    required this.levelUpLandDuration,
    required this.levelUpLandCurve,
    required this.levelUpLandJiggleCurve,
    required this.levelUpGlowDuration,
    required this.levelUpGlowIntensity,
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
      shakeRange: d(pv, 'ShakeRange', 0.03),
      jellyLeanPerLagCell: d(pv, 'JellyLeanPerLagCell', 1.35),
      jellyLeanMax: d(pv, 'JellyLeanMax', 0.075),
      jellyLeanSizeFalloff: d(pv, 'JellyLeanSizeFalloff', 0.5),
      jellyTiltPerLeanCell: d(pv, 'JellyTiltPerLeanCell', 90.0),
      jellyStiffness: d(pv, 'JellyStiffness', 300.0),
      jellyDamping: d(pv, 'JellyDamping', 0.20),
      stationaryAnchorShrinkDuration:
          d(pv, 'MovementStationaryAnchorShrinkDuration', 0.20),
      stationaryAnchorShrinkCurve: UnityCurve.fromJson(
        pv['MovementStationaryAnchorShrinkCurve'] as Map<String, dynamic>?,
      ),
      mergeCandidatePulseDuration: d(pv, 'MergeCandidatePulseDuration', 1.0),
      mergeCandidatePulseScale: UnityCurve.fromJson(
        pv['MergeCandidatePulseScaleZ'] as Map<String, dynamic>?,
      ),
      mergeCandidateReleaseDuration:
          d(pv, 'MergeCandidateReleaseDuration', 1.0),
      mergeCandidateReleaseCurve: UnityCurve.fromJson(
        pv['MergeCandidateReleaseCurve'] as Map<String, dynamic>?,
      ),
      mergeCandidateSurvivorLift: d(pv, 'MergeCandidateSurvivorLift', 0.0),
      mergeCandidatePushInflate: UnityCurve.fromJson(
        pv['MergeCandidatePushInflate'] as Map<String, dynamic>?,
      ),
      mergeCandidatePushReleaseDuration:
          d(pv, 'MergeCandidatePushReleaseDuration', 0.20),
      mergeJoinStrength: UnityCurve.fromJson(
        pv['MergeJoinStrength'] as Map<String, dynamic>?,
      ),
      mergeTransitionRadius: UnityCurve.fromJson(
        pv['MergeTransitionRadius'] as Map<String, dynamic>?,
      ),
      mergeTransitionMinShapeSize: d(pv, 'MergeTransitionMinShapeSize', 1.5),
      mergeTransitionSoftness: d(pv, 'MergeTransitionSoftness', 0.60),
      mergeTransitionExpandDuration:
          d(pv, 'MergeTransitionExpandDuration', 0.30),
      mergeTransitionExpandCurve: UnityCurve.fromJson(
        pv['MergeTransitionExpandCurve'] as Map<String, dynamic>?,
      ),
      mergePreviewNumberSize: UnityCurve.fromJson(
        pv['MergePreviewNumberSize'] as Map<String, dynamic>?,
      ),
      mergePartnerNumberSize: UnityCurve.fromJson(
        pv['MergePartnerNumberSize'] as Map<String, dynamic>?,
      ),
      mergePreviewNumberDepth: d(pv, 'MergePreviewNumberDepth', 0.05),
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
      mergeSurvivorStaysDuration: d(pv, 'MergeSurvivorStaysDuration', 0.28),
      mergeSurvivorStaysPulseScale: d(pv, 'MergeSurvivorStaysPulseScale', 1.20),
      mergeSurvivorStaysPulseCurve: UnityCurve.fromJson(
        pv['MergeSurvivorStaysPulseCurve'] as Map<String, dynamic>?,
      ),
      mergeSurvivorStaysImpulseCurve: UnityCurve.fromJson(
        pv['MergeSurvivorStaysImpulseCurve'] as Map<String, dynamic>?,
      ),
      reflectionAlpha: d(pv, 'ReflectionAlpha', 0.197),
      cameraIntroSizeOffset: d(cam, 'IntroSizeOffset', 5.0),
      cameraIntroDuration: d(cam, 'IntroDuration', 0.35),
      cameraIntroCurve:
          UnityCurve.fromJson(cam['IntroCurve'] as Map<String, dynamic>?),
      cameraWinZoomFactor: d(cam, 'WinZoomInFactor', 0.90),
      cameraWinDuration: d(cam, 'WinDuration', 0.35),
      cameraWinCurve:
          UnityCurve.fromJson(cam['WinCurve'] as Map<String, dynamic>?),
      levelUpLiftHeight: d(lu, 'LiftHeight', 2.0),
      levelUpLiftDuration: d(lu, 'LiftDuration', 0.35),
      levelUpLiftCurve:
          UnityCurve.fromJson(lu['LiftCurve'] as Map<String, dynamic>?),
      levelUpLiftJiggleCurve:
          UnityCurve.fromJson(lu['LiftJiggleCurve'] as Map<String, dynamic>?),
      levelUpTravelDuration: d(lu, 'TravelDuration', 0.50),
      levelUpTravelCurve:
          UnityCurve.fromJson(lu['TravelCurve'] as Map<String, dynamic>?),
      levelUpMergeArmDistance: d(lu, 'MergeArmDistance', 1.0),
      levelUpShrinkCurve:
          UnityCurve.fromJson(lu['ShrinkCurve'] as Map<String, dynamic>?),
      levelUpLandDelay: d(lu, 'LandDelay', 0.25),
      levelUpLandDuration: d(lu, 'LandDuration', 0.35),
      levelUpLandCurve:
          UnityCurve.fromJson(lu['LandCurve'] as Map<String, dynamic>?),
      levelUpLandJiggleCurve:
          UnityCurve.fromJson(lu['LandJiggleCurve'] as Map<String, dynamic>?),
      levelUpGlowDuration: d(lu, 'GlowDuration', 1.50),
      levelUpGlowIntensity:
          UnityCurve.fromJson(lu['GlowIntensity'] as Map<String, dynamic>?),
    );
  }
}
