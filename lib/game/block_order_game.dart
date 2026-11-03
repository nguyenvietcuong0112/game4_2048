import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show Canvas, Color, Colors, Offset, Paint, Rect;
import '../models/level_models.dart';
import '../models/palette.dart';
import '../models/unity_curve.dart';
import '../services/audio_haptics_service.dart';
import 'board_component.dart';
import 'piece_component.dart';
import 'sand_jar_component.dart';
import 'vfx_components.dart';

class _ResolvedMergeOutcome {
  final PieceComponent survivor;
  final PieceComponent partner;
  final bool survivorMoves;
  final int survivorNextCol;
  final int survivorNextRow;

  const _ResolvedMergeOutcome({
    required this.survivor,
    required this.partner,
    required this.survivorMoves,
    required this.survivorNextCol,
    required this.survivorNextRow,
  });
}

class _MergeContactCandidate {
  final PieceComponent target;
  final PieceComponent survivor;
  final GridCell pushDir;
  final GridCell contactOrigin;
  final double magnitude;

  const _MergeContactCandidate({
    required this.target,
    required this.survivor,
    required this.pushDir,
    required this.contactOrigin,
    required this.magnitude,
  });
}

class _MergeSeamContactGeometry {
  final Vector2 heldEdgeLocal;
  final Vector2 seamWorld;

  const _MergeSeamContactGeometry({
    required this.heldEdgeLocal,
    required this.seamWorld,
  });
}

enum _MergeTransitionStage {
  following,
  releasing,
  committed,
  expanding,
  finished,
}

/// Exact port of Unity's `Game.BlockOrder.MergeColorTransition` (`5` stages):
/// 1. `following`: updates `_MergeCylinder` center (`heldEdgeOffSeam`) & `radiusFor(proximity)`.
/// 2. `releasing` (`0.20s`): smoothly retracts cylinder radius back to `0` on drag-away cancel.
/// 3. `committed`: freezes cylinder at current center/radius on finger release until `expand(...)`.
/// 4. `expanding` (`0.30s`, `t^2` curve): sweeps radial cylinder across `coverRadius + softness`
///    before handing off `survivor.applyMergedAppearance(targetStyle)`.
/// 5. `finished`: clears `_MergeCylinder` on remaining pieces and retires from `_mergeTransitions`.
class _MergeColorTransitionController {
  final PieceComponent held;
  final List<PieceComponent> pieces;
  final PieceVisualSettings visualSettings;
  final double cellSize;
  BlockColorStyle targetStyle;

  Vector2 heldEdgeLocal;
  Vector2 seamWorld;
  Vector2 pushUnit;
  final double radiusScale;
  final double softness;

  _MergeTransitionStage stage = _MergeTransitionStage.following;
  PieceComponent? _expandSurvivor;
  Vector2 center = Vector2.zero();
  double radius = 0.0;

  double _proximity = 0.0;
  double _releaseFromProximity = 0.0;
  double _expandFromRadius = 0.0;
  double _expandToRadius = 0.0;
  double _stageElapsed = 0.0;

  _MergeColorTransitionController({
    required this.held,
    required PieceComponent candidate,
    required this.visualSettings,
    required this.cellSize,
    required this.targetStyle,
    required this.heldEdgeLocal,
    required this.seamWorld,
    required this.pushUnit,
  })  : pieces = <PieceComponent>[held, candidate],
        radiusScale = cellSize *
            math.max(
              visualSettings.mergeTransitionMinShapeSize,
              math.max(
                held.model.shapeDimension,
                candidate.model.shapeDimension,
              ).toDouble(),
            ),
        softness = visualSettings.mergeTransitionSoftness * cellSize {
    center = _heldEdgeOffSeam();
    radius = _radiusFor(0.0);
    _writeToPieces();
  }

  bool get isFinished => stage == _MergeTransitionStage.finished;

  Vector2 _heldEdgeOffSeam() {
    final worldEdge = held.position + heldEdgeLocal;
    final pastSeam = math.max(0.0, (worldEdge - seamWorld).dot(pushUnit));
    return worldEdge - pushUnit * pastSeam;
  }

  double _radiusFor(double amount) {
    return visualSettings.mergeTransitionRadius
            .evaluate(amount.clamp(0.0, 1.0)) *
        radiusScale;
  }

  void moveContact({
    required Vector2 newHeldEdgeLocal,
    required Vector2 newSeamWorld,
    required Vector2 newPushUnit,
  }) {
    heldEdgeLocal = newHeldEdgeLocal;
    seamWorld = newSeamWorld;
    pushUnit = newPushUnit;
    if (stage == _MergeTransitionStage.following) {
      center = _heldEdgeOffSeam();
      _writeToPieces();
    }
  }

  void setProximity(double amount) {
    _proximity = amount.clamp(0.0, 1.0);
    if (stage == _MergeTransitionStage.following) {
      center = _heldEdgeOffSeam();
      radius = _radiusFor(_proximity);
      _writeToPieces();
    }
  }

  void release() {
    if (stage != _MergeTransitionStage.following) return;
    _releaseFromProximity = _proximity;
    _stageElapsed = 0.0;
    stage = _MergeTransitionStage.releasing;
    if (_releaseFromProximity <= 1e-4 && radius <= 1e-4) {
      clearAllImmediate();
    }
  }

  void commit() {
    if (stage == _MergeTransitionStage.following) {
      center = _heldEdgeOffSeam();
      radius = _radiusFor(_proximity);
      stage = _MergeTransitionStage.committed;
      _writeToPieces();
    }
  }

  void expand({
    required PieceComponent survivor,
    required BlockColorStyle newTargetStyle,
  }) {
    targetStyle = newTargetStyle;
    _expandSurvivor = survivor;
    if (!pieces.contains(survivor)) {
      pieces.add(survivor);
    }
    _expandFromRadius = radius;
    _expandToRadius = _coverRadius() + softness;
    _stageElapsed = 0.0;
    stage = _MergeTransitionStage.expanding;
    _writeToPieces();
  }

  double _coverRadius() {
    double maxDist = 0.0;
    for (final p in pieces) {
      for (final corner in p.computeWorldBlockCorners()) {
        final d = (corner - center).length;
        if (d > maxDist) maxDist = d;
      }
    }
    final survivor = _expandSurvivor;
    if (survivor != null) {
      final targetOrigin =
          survivor.targetWorldOriginForGrid(survivor.model.col, survivor.model.row);
      final delta = targetOrigin - survivor.position;
      for (final corner in survivor.computeWorldBlockCorners()) {
        final d = ((corner + delta) - center).length;
        if (d > maxDist) maxDist = d;
      }
    }
    return maxDist;
  }

  void drop(PieceComponent consumed) {
    if (pieces.remove(consumed)) {
      consumed.clearMergeCylinder();
    }
  }

  void clearAllImmediate() {
    for (final p in pieces) {
      p.clearMergeCylinder();
    }
    pieces.clear();
    stage = _MergeTransitionStage.finished;
  }

  void _writeToPieces() {
    for (final p in pieces) {
      p.setMergeCylinder(
        worldCenter: center,
        worldRadius: radius,
        worldSoftness: softness,
        targetStyle: targetStyle,
      );
    }
  }

  void tick(double dt) {
    switch (stage) {
      case _MergeTransitionStage.following:
        center = _heldEdgeOffSeam();
        radius = _radiusFor(_proximity);
        _writeToPieces();
        break;

      case _MergeTransitionStage.releasing:
        final dur =
            math.max(0.01, visualSettings.mergeCandidatePushReleaseDuration);
        _stageElapsed += dt;
        final t = (_stageElapsed / dur).clamp(0.0, 1.0);
        final prox = ui.lerpDouble(_releaseFromProximity, 0.0, t)!;
        radius = _radiusFor(prox);
        if (t >= 1.0 || radius <= 1e-4) {
          clearAllImmediate();
        } else {
          _writeToPieces();
        }
        break;

      case _MergeTransitionStage.committed:
        _writeToPieces();
        break;

      case _MergeTransitionStage.expanding:
        final dur =
            math.max(0.01, visualSettings.mergeTransitionExpandDuration);
        _stageElapsed += dt;
        final t = (_stageElapsed / dur).clamp(0.0, 1.0);
        final curved =
            visualSettings.mergeTransitionExpandCurve.evaluate(t).clamp(0.0, 1.0);
        radius = ui.lerpDouble(_expandFromRadius, _expandToRadius, curved)!;
        if (t >= 1.0) {
          _expandSurvivor?.applyMergedAppearance(targetStyle);
          clearAllImmediate();
        } else {
          _writeToPieces();
        }
        break;

      case _MergeTransitionStage.finished:
        break;
    }
  }
}

class _AbsorbingMergeAnim {
  final PieceComponent consumed;
  final PieceComponent survivor;
  final _MergeColorTransitionController? transition;
  final Color topTargetColor;
  final double initialOverlapStrength;
  double elapsed = 0.0;
  bool mergeImpactHapticFired = false;
  final double duration;

  _AbsorbingMergeAnim({
    required this.consumed,
    required this.survivor,
    required this.transition,
    required this.topTargetColor,
    required this.initialOverlapStrength,
    required this.duration,
  });
}

class _LevelUpFlightAnim {
  final PieceComponent spent;
  final PieceComponent kept;
  final Vector2 startOrigin;
  final double liftHeight;
  double elapsed = 0.0;
  double sparkTimer = 0.0;
  bool armedTargetPreview = false;
  final double liftDur;
  final double travelDur;
  final Color sparkColor;

  _LevelUpFlightAnim({
    required this.spent,
    required this.kept,
    required this.startOrigin,
    required this.liftHeight,
    required this.liftDur,
    required this.travelDur,
    required this.sparkColor,
  });

  double get totalDuration => liftDur + travelDur;
}

class _TutorialTrailNode {
  final Offset pos;
  double age = 0.0;
  _TutorialTrailNode(this.pos);
}

/// Exact 6-phase Level 1 tutorial hand matching `TutorialHand.prefab` & `TutorialHandView.cs`:
/// - `Hand_01.png` (`208x256`, `sz=(138.88, 174.49)`, fingertip `piv=(0.21, 0.97)`, `rot=-4.2°`)
/// - `initialDelay = 0.25s` before first cycle, pauses while `isPausedProvider()` is true
/// - 1. `0.60s` move from `point1 + spawnOffset` to `point1` (`toPoint1Curve`, `0.30s` fade-in)
/// - 2. Tap ripple burst + `0.50s` pause at `point1`
/// - 3. `0.80s` slide from `point1` to `point2` (`toPoint2Curve`) with glowing fingertip swipe trail
/// - 4. `0.50s` hold pause at `point2`
/// - 5. `0.50s` fade-out at `point2`
/// - 6. `0.50s` pause before repeating loop
/// - Permanent `0.30s` `FadeOutAsync` ONLY when a piece actually steps to a new cell or merges!
class _TutorialHandComponent extends PositionComponent {
  final Vector2 fromPos;
  final Vector2 toPos;
  final double cellSize;
  final bool Function() isPausedProvider;
  ui.Image? _handImg;
  double _initialDelayRemaining = 0.25;
  double _elapsed = 0.0;
  bool _tapBurstTriggeredInCycle = false;
  double _tapBurstAge = -1.0;
  final List<_TutorialTrailNode> _trail = <_TutorialTrailNode>[];
  double _trailSampleAcc = 0.0;

  bool isFadingOut = false;
  double _dismissFadeElapsed = 0.0;
  static const double _dismissFadeDuration = 0.30;
  static const double _trailLifetime = 0.28;

  static const double _phase1End = UnityTutorialHandConfig.toPoint1Duration; // 0.60
  static const double _phase2End =
      _phase1End + UnityTutorialHandConfig.pauseAtPoint1; // 1.10
  static const double _phase3End =
      _phase2End + UnityTutorialHandConfig.toPoint2Duration; // 1.90
  static const double _phase4End =
      _phase3End + UnityTutorialHandConfig.pauseAtPoint2; // 2.40
  static const double _phase5End =
      _phase4End + UnityTutorialHandConfig.fadeOutDuration; // 2.90
  static const double _cycleDuration =
      _phase5End + UnityTutorialHandConfig.pauseBeforeRepeat; // 3.40

  _TutorialHandComponent({
    required this.fromPos,
    required this.toPos,
    required this.cellSize,
    required this.isPausedProvider,
  }) : super(priority: 250) {
    if (Flame.images.containsKey('Hand_01.png')) {
      try {
        _handImg = Flame.images.fromCache('Hand_01.png');
      } catch (_) {}
    }
  }

  void fadeOutAndRemove() {
    if (isFadingOut) return;
    isFadingOut = true;
    _dismissFadeElapsed = 0.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isFadingOut) {
      _dismissFadeElapsed += dt;
      for (int i = _trail.length - 1; i >= 0; i--) {
        _trail[i].age += dt;
        if (_trail[i].age >= _trailLifetime) _trail.removeAt(i);
      }
      if (_dismissFadeElapsed >= _dismissFadeDuration) {
        removeFromParent();
      }
      return;
    }

    if (isPausedProvider()) return;

    if (_initialDelayRemaining > 0.0) {
      _initialDelayRemaining -= dt;
      if (_initialDelayRemaining > 0.0) return;
    }

    final prevElapsed = _elapsed;
    _elapsed += dt;
    if (_elapsed >= _cycleDuration) {
      _elapsed %= _cycleDuration;
      _tapBurstTriggeredInCycle = false;
      _trail.clear();
    } else if (_elapsed < prevElapsed) {
      _tapBurstTriggeredInCycle = false;
      _trail.clear();
    }

    for (int i = _trail.length - 1; i >= 0; i--) {
      _trail[i].age += dt;
      if (_trail[i].age >= _trailLifetime) {
        _trail.removeAt(i);
      }
    }
    if (_tapBurstAge >= 0.0) {
      _tapBurstAge += dt;
      if (_tapBurstAge > 0.42) _tapBurstAge = -1.0;
    }

    // `spawnOffset = (100px, 0)` scaled proportionally to stage cell size
    final spawnOffset = Vector2(
      cellSize * (UnityTutorialHandConfig.spawnOffsetX / 78.0),
      cellSize * (UnityTutorialHandConfig.spawnOffsetY / 78.0),
    );
    final spawnPos = fromPos + spawnOffset;

    if (_elapsed < _phase1End) {
      final t = (_elapsed / UnityTutorialHandConfig.toPoint1Duration)
          .clamp(0.0, 1.0);
      final curved =
          UnityTutorialHandConfig.toPoint1Curve.evaluate(t).clamp(0.0, 1.1);
      position = Vector2(
        ui.lerpDouble(spawnPos.x, fromPos.x, curved)!,
        ui.lerpDouble(spawnPos.y, fromPos.y, curved)!,
      );
    } else if (_elapsed < _phase2End) {
      position = fromPos.clone();
      if (!_tapBurstTriggeredInCycle) {
        _tapBurstTriggeredInCycle = true;
        _tapBurstAge = 0.0;
      }
    } else if (_elapsed < _phase3End) {
      final t =
          ((_elapsed - _phase2End) / UnityTutorialHandConfig.toPoint2Duration)
              .clamp(0.0, 1.0);
      final curved =
          UnityTutorialHandConfig.toPoint2Curve.evaluate(t).clamp(0.0, 1.0);
      position = Vector2(
        ui.lerpDouble(fromPos.x, toPos.x, curved)!,
        ui.lerpDouble(fromPos.y, toPos.y, curved)!,
      );
      _trailSampleAcc += dt;
      if (_trail.isEmpty || _trailSampleAcc >= 0.014) {
        _trailSampleAcc = 0.0;
        _trail.add(_TutorialTrailNode(Offset(position.x, position.y)));
      }
    } else {
      position = toPos.clone();
    }
  }

  @override
  void render(Canvas canvas) {
    final img = _handImg;
    if (_initialDelayRemaining > 0.0 && !isFadingOut) return;

    final dismissMul = isFadingOut
        ? (1.0 - (_dismissFadeElapsed / _dismissFadeDuration)).clamp(0.0, 1.0)
        : 1.0;
    if (dismissMul <= 0.01) return;

    // 1. Render glowing fingertip swipe trail (`TrailRenderer` in stage space -> local offset)
    if (_trail.length >= 2) {
      for (int i = 1; i < _trail.length; i++) {
        final a = _trail[i - 1];
        final b = _trail[i];
        final lifeFrac = (1.0 - (b.age / _trailLifetime)).clamp(0.0, 1.0);
        if (lifeFrac <= 0.02) continue;
        final p0 = a.pos - Offset(position.x, position.y);
        final p1 = b.pos - Offset(position.x, position.y);
        canvas.drawLine(
          p0,
          p1,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.52 * lifeFrac * dismissMul)
            ..strokeWidth = cellSize * 0.14 * lifeFrac
            ..strokeCap = ui.StrokeCap.round,
        );
      }
    }

    // 2. Render fingertip tap ripple burst at `fromPos`
    if (_tapBurstAge >= 0.0 && _tapBurstAge <= 0.42) {
      final bt = (_tapBurstAge / 0.42).clamp(0.0, 1.0);
      final localBurstCenter = Offset(
        fromPos.x - position.x,
        fromPos.y - position.y,
      );
      final ringRadius = cellSize * (0.14 + 0.34 * bt);
      canvas.drawCircle(
        localBurstCenter,
        ringRadius,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = (cellSize * 0.045 * (1.0 - bt)).clamp(1.0, 6.0)
          ..color = Colors.white.withValues(
            alpha: (0.72 * (1.0 - bt) * dismissMul).clamp(0.0, 1.0),
          ),
      );
    }

    if (img == null || (_elapsed >= _phase5End && !isFadingOut)) return;

    double alpha = 1.0;
    if (_elapsed < UnityTutorialHandConfig.fadeInDuration) {
      alpha =
          (_elapsed / UnityTutorialHandConfig.fadeInDuration).clamp(0.0, 1.0);
    } else if (_elapsed >= _phase4End) {
      alpha = (1.0 -
              (_elapsed - _phase4End) /
                  UnityTutorialHandConfig.fadeOutDuration)
          .clamp(0.0, 1.0);
    }
    alpha *= dismissMul;
    if (alpha <= 0.01) return;

    double pressScale = 1.0;
    if (_elapsed >= _phase1End && _elapsed < _phase4End) {
      final pressIn = ((_elapsed - _phase1End) / 0.16).clamp(0.0, 1.0);
      pressScale = ui.lerpDouble(1.0, 0.90, pressIn)!;
    } else if (_elapsed >= _phase4End) {
      final releaseOut =
          ((_elapsed - _phase4End) / UnityTutorialHandConfig.fadeOutDuration)
              .clamp(0.0, 1.0);
      pressScale = ui.lerpDouble(0.90, 1.06, releaseOut)!;
    }

    // `TutorialHand.prefab`: `Hand` `sz = (138.88, 174.49)`, fingertip `piv = (0.21, 0.97)`, `rot = -4.2°`
    final handW = cellSize * 0.92;
    final handH = handW * (img.height / img.width);
    canvas.save();
    canvas.scale(pressScale, pressScale);
    canvas.rotate(-4.2 * math.pi / 180.0);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(
        -handW * 0.21,
        -handH * 0.03,
        handW,
        handH,
      ),
      Paint()
        ..filterQuality = ui.FilterQuality.medium
        ..color = Color.fromRGBO(255, 255, 255, alpha * 0.96),
    );
    canvas.restore();
  }
}

class BlockOrderGame extends FlameGame with DragCallbacks {
  static const double _absorbDurationSeconds = 0.28;

  final BlockOrderPalette palette;
  final PieceVisualSettings visualSettings;
  final AudioHapticsService audio;
  final VoidCallback onLevelWon;
  final VoidCallback onTimeExpired;
  final VoidCallback? onFirstAction;

  LevelDefinition _level;
  LevelDefinition get currentLevel => _level;

  final ValueNotifier<int> remainingSecondsNotifier = ValueNotifier<int>(120);
  final ValueNotifier<double> timeFreezeNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<bool> isTimeFrozenNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> canLevelUpNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isTimerStartedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> winScreenFlashNotifier =
      ValueNotifier<double>(0.0);
  final ValueNotifier<Color> winScreenFlashColorNotifier =
      ValueNotifier<Color>(const Color(0xFFFFFFFF));
  final ValueNotifier<bool> isWinSequenceActiveNotifier =
      ValueNotifier<bool>(false);

  bool isModalPaused = false;
  bool allowEngineSleepBehindModal = false;
  bool isTimeFreezeIntroInFlight = false;
  bool _isReady = false;
  bool _hasWon = false;
  bool _hasLost = false;
  bool _firstActionTriggered = false;
  double _winSequenceElapsed = -1.0;
  bool _winSandStreamSpawned = false;
  bool _winJarOpened = false;
  bool _winCallbackFired = false;
  PieceComponent? _finalWinningPiece;
  double _elapsedGameTime = 0.0;

  // Countdown timer accumulators
  double _countdownFrac = 0.0;
  double _timeFreezeRemaining = 0.0;
  static const double maxTimeFreezeSeconds = 20.0;

  // Stage & board layout
  final PositionComponent _boardStage = PositionComponent(priority: 5);
  final List<PieceComponent> _pieces = [];
  final List<(PieceComponent, int)> _pendingNumberPrewarms = [];
  _TutorialHandComponent? _tutorialHand;
  MagicSandJarComponent? _sandJar;
  JarOpenAndFullscreenLightWaveVfx? _jarOpenWaveVfx;

  // Flat O(1) playable & piece occupancy grids (zero HashSet allocations during 120Hz drags!)
  int _gridCols = 0;
  int _gridRows = 0;
  Uint8List _playableGrid = Uint8List(0);
  Int32List _occupancyGrid = Int32List(0);

  double _cellSize = 40.0;
  Vector2 _boardOrigin = Vector2.zero();
  Vector2 _lastLayoutSize = Vector2.zero();
  double _safeTop = 0.0;
  double _safeBottom = 0.0;
  bool _needsSafeAreaRelayout = false;

  // Camera Intro & Win Zoom (`CameraAnimationConfig`: `IntroSizeOffset = 5.0`)
  double _introTimer = 0.0;
  double _introStartZoom = 0.58;
  double _winZoomTimer = -1.0;
  double _stageZoom = 1.0;

  // Exact `FingerDragInput` & Hold-to-Merge Candidate State
  int? _activePointerId;
  PieceComponent? _draggedPiece;
  Vector2 _activePointerCanvasPos = Vector2.zero();
  Vector2 _grabOffsetFromPieceOrigin = Vector2.zero();
  Vector2 _grabStagePos = Vector2.zero();
  double _grabStartTime = 0.0;
  bool _isTapCandidate = false;
  int _dragStartCol = 0;
  int _dragStartRow = 0;
  Vector2 _lastOverlap = Vector2.zero();

  // Blocked feedback deduplication
  PieceComponent? _lastBlockedFeedbackPiece;
  double _lastBlockedFeedbackTime = -10.0;

  // Active Hold-to-Merge candidate & `MergeColorTransition` controllers
  PieceComponent? _mergeCandidate;
  PieceComponent? _mergeSurvivor;
  GridCell _mergePushDir = (0, 0);
  GridCell _mergeContactOrigin = (0, 0);
  double _mergeArmMagnitude = 0.0;
  double _currentMergePushAmount = 0.0;
  _MergeColorTransitionController? _candidateTransition;
  final List<_MergeColorTransitionController> _mergeTransitions = [];

  // Active `0.28s` linear absorb & Level-Up flight animations
  final List<_AbsorbingMergeAnim> _absorbingAnims = [];
  _LevelUpFlightAnim? _levelUpFlight;

  BlockOrderGame({
    required LevelDefinition initialLevel,
    required this.palette,
    required this.visualSettings,
    required this.audio,
    required this.onLevelWon,
    required this.onTimeExpired,
    this.onFirstAction,
  }) : _level = initialLevel {
    remainingSecondsNotifier.value = initialLevel.timeSeconds;
  }

  @override
  Color backgroundColor() => const Color(0x00000000);

  bool get isBusyWithPowerUp =>
      _levelUpFlight != null || isTimeFreezeIntroInFlight;

  bool get isResolving =>
      _levelUpFlight != null ||
      _absorbingAnims.isNotEmpty ||
      isTimeFreezeIntroInFlight;

  bool get isTimeFrozen => _timeFreezeRemaining > 0.05;

  void _setTimeFreezeRemaining(double value, {bool forceNotify = false}) {
    final clamped = value <= 0.0 ? 0.0 : value;
    _timeFreezeRemaining = clamped;
    final frozenNow = clamped > 0.05;
    if (isTimeFrozenNotifier.value != frozenNow) {
      isTimeFrozenNotifier.value = frozenNow;
    }
    if (forceNotify ||
        clamped <= 0.0 ||
        (clamped - timeFreezeNotifier.value).abs() >= 0.033) {
      if (timeFreezeNotifier.value != clamped) {
        timeFreezeNotifier.value = clamped;
      }
    }
  }

  /// Coordinates modal gameplay pause with smart `FlameGame` engine sleep:
  /// - Wakes `FlameGame` immediately when `canSuspendBoard` becomes `false` (including
  ///   `"Tap to see the board"` peek in `LoseOverlay` or closing any modal).
  /// - When `canSuspendBoard` is `true`, `update(dt)` allows all active camera zooms,
  ///   piece settles, and particle VFX to complete 100% before calling `pauseEngine()`.
  void setModalPauseState({
    required bool modalPaused,
    required bool canSuspendBoard,
  }) {
    isModalPaused = modalPaused;
    allowEngineSleepBehindModal = modalPaused && canSuspendBoard;
    if (!allowEngineSleepBehindModal && paused) {
      resumeEngine();
    }
  }

  bool _isBoardCompletelyAtRest() {
    if (!_isReady || _needsSafeAreaRelayout || size.x <= 10 || size.y <= 10) {
      return false;
    }
    if (_introTimer < visualSettings.cameraIntroDuration) return false;
    if (_winZoomTimer >= 0 && _winZoomTimer < visualSettings.cameraWinDuration) {
      return false;
    }
    if (_winSequenceElapsed >= 0 && !_winCallbackFired) return false;
    if (_sandJar?.isAnimating == true) return false;
    if (_draggedPiece != null || _mergeCandidate != null) return false;
    if (isResolving || _mergeTransitions.isNotEmpty) return false;
    if (_pendingNumberPrewarms.isNotEmpty) return false;

    for (final child in _boardStage.children) {
      if (child is PieceComponent) {
        if (!child.isVisuallyAtRest) return false;
      } else if (child is! BoardComponent &&
          child is! _TutorialHandComponent &&
          child is! MagicSandJarComponent) {
        return false;
      }
    }
    return true;
  }

  void _rebuildPlayableGrid() {
    _gridCols = _level.cols;
    _gridRows = _level.rows;
    final total = _gridCols * _gridRows;
    if (_playableGrid.length != total) {
      _playableGrid = Uint8List(total);
    }
    for (int r = 0; r < _gridRows; r++) {
      final rowBase = r * _gridCols;
      for (int c = 0; c < _gridCols; c++) {
        _playableGrid[rowBase + c] = _level.isPlayableCell(c, r) ? 1 : 0;
      }
    }
  }

  void _syncOccupancyGrid() {
    final total = _gridCols * _gridRows;
    if (total <= 0) return;
    if (_occupancyGrid.length != total) {
      _occupancyGrid = Int32List(total);
    }
    _occupancyGrid.fillRange(0, total, -1);
    for (int i = 0; i < _pieces.length; i++) {
      final p = _pieces[i];
      if (p.isFlyingOrSwallowed) continue;
      final m = p.model;
      final baseCol = m.col;
      final baseRow = m.row;
      final local = m.localCells;
      for (int k = 0; k < local.length; k++) {
        final cell = local[k];
        final c = baseCol + cell.$1;
        final r = baseRow + cell.$2;
        if (c >= 0 && c < _gridCols && r >= 0 && r < _gridRows) {
          _occupancyGrid[r * _gridCols + c] = i;
        }
      }
    }
  }

  /// Exact `GameplayPresenter.DoesGameStatePermitUsage(PowerUpType.TimeFreeze)`:
  /// Timed level, timer has started (`GameplayTimer.IsStarted`), and not already frozen.
  bool get canUseTimeFreeze =>
      !_level.timerDisabled &&
      isTimerStartedNotifier.value &&
      !isTimeFrozen &&
      !isTimeFreezeIntroInFlight &&
      !_hasWon &&
      !_hasLost;

  void updateSafeAreaInsets({required double top, required double bottom}) {
    if ((top - _safeTop).abs() < 0.5 && (bottom - _safeBottom).abs() < 0.5) {
      return;
    }
    _safeTop = top;
    _safeBottom = bottom;
    if (_isReady && size.x > 10 && size.y > 10) {
      _needsSafeAreaRelayout = true;
      if (paused) resumeEngine();
    }
  }

  @visibleForTesting
  double get debugCellSize => _cellSize;

  @visibleForTesting
  List<PieceComponent> get debugPieces => List.unmodifiable(_pieces);

  @visibleForTesting
  bool get debugHasTutorialHand =>
      _tutorialHand != null &&
      _tutorialHand!.isMounted &&
      !_tutorialHand!.isFadingOut;

  @visibleForTesting
  MagicSandJarComponent? get debugSandJar => _sandJar;

  @visibleForTesting
  int? get debugJarColorNumber => _sandJar?.style.number;

  @visibleForTesting
  double get debugJarFillProgress => _sandJar?.fillProgress ?? 0.0;

  @visibleForTesting
  double get debugJarGlowIntensity => _sandJar?.glowIntensity ?? 0.0;

  @visibleForTesting
  double get debugJarShakeIntensity => _sandJar?.shakeIntensity ?? 0.0;

  @visibleForTesting
  bool get debugIsJarOpen => _sandJar?.isOpened ?? false;

  @visibleForTesting
  Offset debugCellCenterCanvas(int col, int row) {
    final stagePt = _cellCenterWorld(col, row);
    final canvasPt = _boardStage.position + stagePt * _stageZoom;
    return Offset(canvasPt.x, canvasPt.y);
  }

  Vector2 _cellCenterWorld(int col, int row) => Vector2(
        _boardOrigin.x + (col + 0.5) * _cellSize,
        _boardOrigin.y + (row + 0.5) * _cellSize,
      );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    const spritesToLoad = [
      'IceLock.png',
      'IceBlocks.png',
      'Ice_Shards.png',
      'Screw_Greyscale_01.png',
      'Screw_Greyscale_02.png',
      'Screw_Greyscale_03.png',
      'Movement_Single-Horizontal_Shadow.png',
      'Movement_Single-Horizontal_Stroke.png',
      'Movement_Single-Horizontal_Top.png',
      'Movement_Double_Horizontal.png',
      'Movement_Double_Vertical.png',
      'Sparkle_01.png',
      'ParticleFlare.png',
      'Explosion_Halo.png',
      'Glow_Ring.png',
      'Glow_02.png',
      'PowerUp_Icon_Arrow.png',
      'Hand_01.png',
    ];
    for (final s in spritesToLoad) {
      try {
        await Flame.images.load(s);
      } catch (e) {
        debugPrint('Flame image preload warning for $s: $e');
      }
    }
    await ScrewTextureCleaner.ensureCleanedScrewsLoaded();

    add(_boardStage);
    _isReady = true;
    if (size.x > 10 && size.y > 10) {
      _buildLevelStage(preserveModels: false);
    }
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!_isReady || size.x <= 10 || size.y <= 10) return;
    if ((size - _lastLayoutSize).length > 2.0) {
      if (paused) resumeEngine();
      _buildLevelStage(preserveModels: _pieces.isNotEmpty);
    }
  }

  void loadLevel(LevelDefinition newLevel) {
    if (paused) resumeEngine();
    _level = newLevel;
    _hasWon = false;
    _hasLost = false;
    _winSequenceElapsed = -1.0;
    _winSandStreamSpawned = false;
    _winJarOpened = false;
    _winCallbackFired = false;
    _finalWinningPiece = null;
    _jarOpenWaveVfx = null;
    winScreenFlashNotifier.value = 0.0;
    isWinSequenceActiveNotifier.value = false;
    _firstActionTriggered = false;
    isTimerStartedNotifier.value = false;
    isTimeFreezeIntroInFlight = false;
    _countdownFrac = 0.0;
    remainingSecondsNotifier.value = newLevel.timeSeconds;
    _setTimeFreezeRemaining(0.0, forceNotify: true);
    _cancelDrag(silent: true);
    for (final t in _mergeTransitions) {
      t.clearAllImmediate();
    }
    _mergeTransitions.clear();
    _candidateTransition = null;
    _absorbingAnims.clear();
    _levelUpFlight = null;
    _pendingNumberPrewarms.clear();
    if (_isReady && size.x > 10 && size.y > 10) {
      _buildLevelStage(preserveModels: false);
    }
  }

  void restartLevel() {
    loadLevel(_level);
  }

  void addExtraTime(int extraSeconds) {
    if (_hasWon) return;
    if (paused) resumeEngine();
    _hasLost = false;
    _countdownFrac = 0.0;
    remainingSecondsNotifier.value += extraSeconds;
    if (!_level.timerDisabled) {
      isTimerStartedNotifier.value = true;
    }
  }

  void _startTimerIfNeeded() {
    if (!_level.timerDisabled && !isTimerStartedNotifier.value) {
      isTimerStartedNotifier.value = true;
    }
  }

  void _buildLevelStage({required bool preserveModels}) {
    _lastLayoutSize = size.clone();

    final savedModels = preserveModels
        ? _pieces.map((p) => p.model.clone()).toList()
        : _level.initialPieces.map((p) => p.clone()).toList();

    _boardStage.removeAll(_boardStage.children.toList());
    _pieces.clear();
    _pendingNumberPrewarms.clear();
    _tutorialHand = null;
    _sandJar = null;
    _jarOpenWaveVfx = null;
    for (final t in _mergeTransitions) {
      t.clearAllImmediate();
    }
    _mergeTransitions.clear();
    _candidateTransition = null;
    _absorbingAnims.clear();

    // Exact decompiled Unity `GameplayView::GetPlayableAreaLayout` +
    // `BoardBlockBuilder::PlayAreaRimWorldCorners` (`contractionDisplacement = -0.15`) +
    // `BoardView._bordersScale.y = 1.0376` + `GameCameraView` (`_cameraAngle = 10°`, `framingMargin = 0.30`):
    final u = math.min(size.x / 1080.0, size.y / 1920.0);
    final safeH = (size.y - _safeTop - _safeBottom).clamp(160.0, 4000.0);
    final isTutorialLevel = !_level.isBonus && _level.number <= 3;

    final availW = (size.x - 0.40 * u).clamp(120.0, 2400.0);
    final double availH;
    final double centerY;
    if (isTutorialLevel) {
      // `_tutorialPlayableArea` (`pid=-6052835297309315330`: `amax.y=0.75, apos.y=141.6599, sdelta.y=-278.32`)
      availH = (0.75 * safeH - 278.32 * u).clamp(140.0, 3000.0);
      centerY = size.y - _safeBottom - (0.375 * safeH + 141.6599 * u);
    } else {
      // `_playableArea` (`pid=-6440393603461435650`: `amax.y=0.81, apos.y=145.4603, sdelta.y=-270.72`)
      availH = (0.81 * safeH - 270.72 * u).clamp(140.0, 3000.0);
      centerY = size.y - _safeBottom - (0.405 * safeH + 145.4603 * u);
    }

    final framedCols = _level.cols + 0.90;
    final framedRows = (_level.rows + 0.30) * 1.021836 + 0.60;
    _cellSize = math
        .min(availW / framedCols, availH / framedRows)
        .clamp(24.0, 220.0);

    final boardW = _level.cols * _cellSize;
    final boardH = _level.rows * _cellSize;
    _boardOrigin = Vector2(-boardW * 0.5, -boardH * 0.5 - _cellSize * 0.10);

    // The Magic Sand Jar stays hidden during gameplay and materializes right above the board
    // when the level is completed (at the exact moment the Timer hides!).
    final jarHeight =
        math.min(_cellSize * 1.68, size.y * 0.165).clamp(92.0, 178.0);
    final jarWidth = jarHeight * 0.90;
    final topBoardRimY = _boardOrigin.y - _cellSize * 0.24;
    double jarCenterY = topBoardRimY - jarHeight * 0.50 - _cellSize * 0.05;

    double stageCenterY = centerY;
    // Since the Timer hides on win, the Jar only needs to stay below the top Coins/Level row (`_safeTop + 150*u`)
    final minJarTopScreenY = _safeTop + 150.0 * u;
    final jarTopStageY = jarCenterY - jarHeight * 0.52;
    if (stageCenterY + jarTopStageY < minJarTopScreenY) {
      final bottomBoardRimY = _boardOrigin.y + boardH + _cellSize * 0.34;
      final maxCenterY = size.y - _safeBottom - 216.0 * u - bottomBoardRimY;
      stageCenterY = math.max(
        stageCenterY,
        math.min(minJarTopScreenY - jarTopStageY, maxCenterY),
      );
      if (stageCenterY + jarTopStageY < minJarTopScreenY) {
        jarCenterY = (minJarTopScreenY - stageCenterY) + jarHeight * 0.52;
      }
    }

    _boardStage.position = Vector2(
      size.x * 0.5,
      stageCenterY,
    );

    _rebuildPlayableGrid();

    final board = BoardComponent(
      level: _level,
      cellSize: _cellSize,
      position: _boardOrigin.clone(),
    );
    _boardStage.add(board);

    final targetJarNumber = _level.targetWinNumber;
    final jarStyle = palette.styleFor(
      number: targetJarNumber,
      isFrozen: false,
    );
    winScreenFlashColorNotifier.value = jarStyle.rimHighlight;
    final initialAppear = _hasWon
        ? ((_winSequenceElapsed >= 0 ? _winSequenceElapsed : 0.36) / 0.36)
            .clamp(0.0, 1.0)
        : 0.0;
    _sandJar = MagicSandJarComponent(
      style: jarStyle,
      levelNumber: _level.number,
      centerPosition: Vector2(0.0, jarCenterY),
      jarWidth: jarWidth,
      jarHeight: jarHeight,
      initialAppearProgress: initialAppear,
    );
    _boardStage.add(_sandJar!);

    for (final m in savedModels) {
      final comp = PieceComponent(
        model: m,
        cellSize: _cellSize,
        palette: palette,
        visualSettings: visualSettings,
        boardOrigin: _boardOrigin,
      );
      _pieces.add(comp);
      _boardStage.add(comp);

      if (!m.isDud && !m.isFrozen && m.number != null) {
        final n = m.number!;
        _pendingNumberPrewarms.add((comp, n * 2));
        _pendingNumberPrewarms.add((comp, n * 4));
      }
    }

    _syncOccupancyGrid();

    if (!preserveModels) {
      final framedOrtho = (0.5 * size.y / _cellSize).clamp(2.5, 30.0);
      _introStartZoom = (framedOrtho /
              (framedOrtho + math.max(0.0, visualSettings.cameraIntroSizeOffset)))
          .clamp(0.45, 0.95);
      _introTimer = 0.0;
      _winZoomTimer = -1.0;
      _stageZoom = _introStartZoom;
      _boardStage.scale = Vector2.all(_stageZoom);
    }
    _maybeSpawnTutorialHand();

    _refreshCanLevelUp();
  }

  void _maybeSpawnTutorialHand() {
    if (_level.isBonus || _level.number != 1 || _firstActionTriggered) return;
    final pair = _findLowestMergeablePair();
    if (pair == null) return;
    final hand = _TutorialHandComponent(
      fromPos: pair.$1.worldCenter,
      toPos: pair.$2.worldCenter,
      cellSize: _cellSize,
      isPausedProvider: () => isModalPaused,
    );
    _tutorialHand = hand;
    _boardStage.add(hand);
  }

  void _notifyFirstAction() {
    _startTimerIfNeeded();
    if (_firstActionTriggered) return;
    _firstActionTriggered = true;
    _tutorialHand?.fadeOutAndRemove();
    _tutorialHand = null;
    onFirstAction?.call();
  }

  Vector2 _canvasToStage(Vector2 canvasPos) {
    final z = _stageZoom <= 1e-4 ? 1.0 : _stageZoom;
    return (canvasPos - _boardStage.position) / z;
  }

  /// Exact `BoardView.TryPickPiece` + `TryPickNearbyUnsurroundedPiece`:
  /// 1. Direct O(1) occupied grid cell `(floor(gx), floor(gy))`.
  /// 2. If empty, searches only **unsurrounded** pieces (pieces with at least one
  ///    open cardinal step) within `(0.5 + generosityRadius) * cellSize` (`0.72 * cs`)
  ///    from any cell center of the piece (zero `Set<GridCell>` allocations).
  PieceComponent? _hitTestPiece(Vector2 stagePos) {
    final gx = (stagePos.x - _boardOrigin.x) / _cellSize;
    final gy = (stagePos.y - _boardOrigin.y) / _cellSize;
    final col = gx.floor();
    final row = gy.floor();

    if (col >= 0 && col < _gridCols && row >= 0 && row < _gridRows) {
      final occIdx = _occupancyGrid[row * _gridCols + col];
      if (occIdx >= 0 && occIdx < _pieces.length) {
        final hit = _pieces[occIdx];
        if (!hit.isFlyingOrSwallowed) {
          return hit;
        }
      }
    }

    final maxPickDist = (0.5 + UnityBoardConfig.generosityRadius) * _cellSize;
    double bestDistSq = maxPickDist * maxPickDist;
    PieceComponent? closest;

    for (final p in _pieces) {
      if (p.isFlyingOrSwallowed) continue;
      if (!_isPieceUnsurrounded(p)) continue;

      final baseCol = p.model.col;
      final baseRow = p.model.row;
      for (final (dc, dr) in p.model.localCells) {
        final c = baseCol + dc;
        final r = baseRow + dr;
        final cx = _boardOrigin.x + (c + 0.5) * _cellSize;
        final cy = _boardOrigin.y + (r + 0.5) * _cellSize;
        final dx = stagePos.x - cx;
        final dy = stagePos.y - cy;
        final distSq = dx * dx + dy * dy;
        if (distSq < bestDistSq) {
          bestDistSq = distSq;
          closest = p;
        }
      }
    }
    return closest;
  }

  bool _isPieceUnsurrounded(PieceComponent piece) {
    const dirs = <GridCell>[(1, 0), (-1, 0), (0, 1), (0, -1)];
    for (final (dc, dr) in dirs) {
      if (_canOccupy(piece.model, piece.model.col + dc, piece.model.row + dr)) {
        return true;
      }
    }
    return false;
  }

  bool get _canInteract =>
      _isReady &&
      !isModalPaused &&
      !_hasWon &&
      !_hasLost &&
      _levelUpFlight == null;

  void _triggerBlockedPieceFeedback(PieceComponent piece) {
    if (_lastBlockedFeedbackPiece == piece &&
        (_elapsedGameTime - _lastBlockedFeedbackTime) < 0.12) {
      return;
    }
    _lastBlockedFeedbackPiece = piece;
    _lastBlockedFeedbackTime = _elapsedGameTime;

    piece.triggerBlockedShake();
    audio.hapticBlocked();
    if (piece.model.isFrozen) {
      audio.playIceBreakSmall();
      _boardStage.add(
        IceChipVfx(
          centerPos: piece.worldCenter,
          cellSize: _cellSize,
        ),
      );
    }
  }

  // --- Zero-Slop Unified Drag & Tap Callbacks (`FingerDragInput`) ---
  // By registering ONLY `DragCallbacks` (no competing `TapCallbacks` in Flutter's GestureArena),
  // `MultiDragScaleGestureRecognizer` is the sole arena member and auto-accepts immediately on
  // `PointerDownEvent` with `0.0 px` touch-slop, while still handling blocked-piece shakes on
  // touch-down (`onDragStart`) and quick-tap squishes on finger release (`_releaseDrag`).

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (!_canInteract || _activePointerId != null) return;

    final stagePos = _canvasToStage(event.canvasPosition);
    final hit = _hitTestPiece(stagePos);
    if (hit == null) return;

    if (!hit.model.canBeDragged) {
      _triggerBlockedPieceFeedback(hit);
      return;
    }

    _startTimerIfNeeded();
    _activePointerId = event.pointerId;
    _draggedPiece = hit;
    _activePointerCanvasPos = event.canvasPosition.clone();
    _dragStartCol = hit.model.col;
    _dragStartRow = hit.model.row;
    _grabStagePos = stagePos.clone();
    _grabStartTime = _elapsedGameTime;
    _isTapCandidate = true;
    _lastOverlap = Vector2.zero();

    final pieceGridOrigin =
        hit.targetWorldOriginForGrid(hit.model.col, hit.model.row);
    _grabOffsetFromPieceOrigin = stagePos - pieceGridOrigin;

    hit.beginDragging();
    audio.playGrab();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _activePointerId) return;
    if (!_canInteract || _draggedPiece == null) {
      _cancelDrag(silent: true);
      return;
    }

    final piece = _draggedPiece!;
    _activePointerCanvasPos += event.canvasDelta;
    final stagePos = _canvasToStage(_activePointerCanvasPos);
    _noteTapTravel(stagePos);
    final rawDesiredOrigin = stagePos - _grabOffsetFromPieceOrigin;

    _handleDrag(piece, rawDesiredOrigin);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_activePointerId == null) return;
    _releaseDrag();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _cancelDrag(silent: true);
  }

  void _noteTapTravel(Vector2 stagePos) {
    if (!_isTapCandidate) return;
    final maxTravel = UnityBoardConfig.tapMaxTravel * _cellSize;
    if ((stagePos - _grabStagePos).length2 > maxTravel * maxTravel) {
      _isTapCandidate = false;
    }
  }

  /// Exact `FingerDragInput.ReleaseDrag` + `EndDrag` + `StepOntoMergeContact` + `ComputeDesiredOrigin`:
  /// 1. If an off-corner merge candidate is armed 1 step away (`_mergeContactOrigin`), steps
  ///    `dragged` onto `_mergeContactOrigin` first (`StepOntoMergeContact`).
  /// 2. If `_mergeCandidate != null` and `(dragged.col, dragged.row) == _mergeContactOrigin`,
  ///    commits the merge on finger release!
  /// 3. Otherwise forgets any merge candidate, snaps `dragged` to its grid cell, and if the
  ///    gesture remained within `tapMaxTravel` & `tapMaxDuration`, plays `triggerTapSquish()`.
  void _releaseDrag() {
    final dragged = _draggedPiece;
    final wasTap = _isTapCandidate &&
        (_elapsedGameTime - _grabStartTime) <= UnityBoardConfig.tapMaxDuration;

    if (dragged != null && _mergeCandidate != null) {
      _stepOntoMergeContact(dragged);
    }

    final candidate = _mergeCandidate;
    final pushDir = _mergePushDir;
    final contactOrigin = _mergeContactOrigin;

    if (dragged != null &&
        candidate != null &&
        (dragged.model.col, dragged.model.row) == contactOrigin &&
        _canCompleteMerge(
          dragged: dragged,
          contactCol: contactOrigin.$1,
          contactRow: contactOrigin.$2,
          pushDir: pushDir,
          target: candidate,
        )) {
      _commitMerge(dragged: dragged, target: candidate, pushDir: pushDir);
      return;
    }

    _forgetMergeCandidate();
    _draggedPiece = null;
    _activePointerId = null;
    _isTapCandidate = false;

    if (dragged != null) {
      final moved = dragged.model.col != _dragStartCol ||
          dragged.model.row != _dragStartRow;
      dragged.snapDragTargetToModelGrid();
      if (moved) {
        _notifyFirstAction();
        audio.playPut();
      } else if (wasTap) {
        dragged.triggerTapSquish();
      } else {
        audio.hapticDrop();
      }
    }
  }

  void _stepOntoMergeContact(PieceComponent dragged) {
    final currentOrigin = (dragged.model.col, dragged.model.row);
    if (currentOrigin == _mergeContactOrigin) return;

    final stepC = _mergeContactOrigin.$1 - currentOrigin.$1;
    final stepR = _mergeContactOrigin.$2 - currentOrigin.$2;
    if ((stepC.abs() + stepR.abs()) != 1) return;
    if (!_allowsDirection(dragged.model.movement, (stepC, stepR))) return;

    if (_canOccupy(
      dragged.model,
      _mergeContactOrigin.$1,
      _mergeContactOrigin.$2,
    )) {
      dragged.model.col = _mergeContactOrigin.$1;
      dragged.model.row = _mergeContactOrigin.$2;
      _syncOccupancyGrid();
    }
  }

  void _cancelDrag({required bool silent}) {
    final dragged = _draggedPiece;
    _forgetMergeCandidate();
    _draggedPiece = null;
    _activePointerId = null;
    _isTapCandidate = false;

    if (dragged != null) {
      dragged.snapDragTargetToModelGrid();
      if (!silent) {
        audio.playPut();
      }
    }
  }

  bool _allowsDirection(MovementConstraint movement, GridCell dir) {
    if (dir.$1 != 0) return movement.allowsHorizontal;
    if (dir.$2 != 0) return movement.allowsVertical;
    return false;
  }

  bool _canOccupy(
    PieceModel moving,
    int testCol,
    int testRow, {
    int? ignorePieceId,
  }) {
    final movingId = moving.id;
    final local = moving.localCells;
    for (int i = 0; i < local.length; i++) {
      final cell = local[i];
      final c = testCol + cell.$1;
      final r = testRow + cell.$2;
      if (c < 0 || c >= _gridCols || r < 0 || r >= _gridRows) return false;
      final idx = r * _gridCols + c;
      if (_playableGrid[idx] == 0) return false;
      final occIdx = _occupancyGrid[idx];
      if (occIdx >= 0 && occIdx < _pieces.length) {
        final other = _pieces[occIdx];
        if (!other.isFlyingOrSwallowed) {
          final otherId = other.model.id;
          if (otherId != movingId &&
              (ignorePieceId == null || otherId != ignorePieceId)) {
            return false;
          }
        }
      }
    }
    return true;
  }

  /// Exact `Board.TryFindMergeTarget` + `BlockOrderGame.CanCompleteMerge`:
  /// Stepping `dragged` from `(contactCol, contactRow)` by `pushDir` to `desiredOrigin`
  /// must touch a single matching mergeable `target`, AND every cell of `dragged` at
  /// `desiredOrigin` must be playable and free of any 3rd piece (`CanRelocate` / `IsFootprintPlayable`).
  bool _canCompleteMerge({
    required PieceComponent dragged,
    required int contactCol,
    required int contactRow,
    required GridCell pushDir,
    required PieceComponent target,
  }) {
    if (!dragged.model.canMerge || !target.model.canMerge) return false;
    if (dragged.model.number != target.model.number) return false;
    if (!_allowsDirection(dragged.model.movement, pushDir)) return false;

    final desiredCol = contactCol + pushDir.$1;
    final desiredRow = contactRow + pushDir.$2;
    return _canOccupy(
      dragged.model,
      desiredCol,
      desiredRow,
      ignorePieceId: target.model.id,
    );
  }

  (PieceComponent target, PieceComponent survivor)? _tryGetMergeCandidate({
    required PieceComponent dragged,
    required int originCol,
    required int originRow,
    required GridCell dir,
  }) {
    final draggedModel = dragged.model;
    if (!draggedModel.canMerge || (dir.$1 == 0 && dir.$2 == 0)) return null;
    if (!_allowsDirection(draggedModel.movement, dir)) return null;

    final desiredCol = originCol + dir.$1;
    final desiredRow = originRow + dir.$2;
    final draggedId = draggedModel.id;
    final local = draggedModel.localCells;

    PieceComponent? matched;
    for (int i = 0; i < local.length; i++) {
      final cell = local[i];
      final c = desiredCol + cell.$1;
      final r = desiredRow + cell.$2;
      if (c < 0 || c >= _gridCols || r < 0 || r >= _gridRows) return null;
      final idx = r * _gridCols + c;
      if (_playableGrid[idx] == 0) return null;

      final occIdx = _occupancyGrid[idx];
      if (occIdx < 0 || occIdx >= _pieces.length) continue;
      final other = _pieces[occIdx];
      if (other.isFlyingOrSwallowed || other.model.id == draggedId) continue;

      // Touching two distinct pieces simultaneously at `desiredOrigin` is rejected by `Board.TryFindMergeTarget`!
      if (matched != null && matched.model.id != other.model.id) {
        return null;
      }
      matched = other;
    }

    if (matched == null) return null;
    if (!matched.model.canMerge || matched.model.number != draggedModel.number) {
      return null;
    }

    final draggedSurvives =
        matched.model.localCells.length < draggedModel.localCells.length;
    final survivor = draggedSurvives ? dragged : matched;
    return (matched, survivor);
  }

  // --- Exact `FingerDragInput` Math (`CommitSteps`, `EaseTowardCap`, Straight + Off-Corner Contact) ---

  /// Hyperbolic soft-cap curve `FingerDragInput.EaseTowardCap(raw, freeTravel, cap)`:
  /// `1:1` linear up to `freeTravel`, then smooth C1 hyperbolic asymptote toward `cap`.
  static double _easeTowardCap(double raw, double freeTravel, double cap) {
    if (raw <= 0.0) return 0.0;
    if (raw <= freeTravel) return raw;
    final headroom = cap - freeTravel;
    if (headroom <= 1e-6) return freeTravel;
    final excess = raw - freeTravel;
    return freeTravel + (excess * headroom) / (excess + headroom);
  }

  double _clampOvershootAxis({
    required PieceComponent piece,
    required double rawOffsetPx,
    required GridCell positiveDir,
    required GridCell negativeDir,
  }) {
    if (rawOffsetPx.abs() <= 1e-5) return 0.0;
    final dir = rawOffsetPx > 0 ? positiveDir : negativeDir;
    final sign = rawOffsetPx > 0 ? 1.0 : -1.0;
    final raw = rawOffsetPx.abs();

    if (!_allowsDirection(piece.model.movement, dir)) {
      return 0.0;
    }

    final nextCol = piece.model.col + dir.$1;
    final nextRow = piece.model.row + dir.$2;
    if (_canOccupy(piece.model, nextCol, nextRow)) {
      final stepCap = (0.5 + UnityBoardConfig.stepHysteresis) * _cellSize;
      return sign * math.min(raw, stepCap);
    }

    final mergePair = _tryGetMergeCandidate(
      dragged: piece,
      originCol: piece.model.col,
      originRow: piece.model.row,
      dir: dir,
    );
    if (mergePair != null) {
      final freeTravel = UnityBoardConfig.mergeOverlapThreshold * _cellSize;
      final cap = UnityBoardConfig.mergeOverlapTravel * _cellSize;
      return sign * _easeTowardCap(raw, freeTravel, cap);
    }

    final softWallCap = UnityBoardConfig.softGiveCap * _cellSize;
    return sign * _easeTowardCap(raw, 0.0, softWallCap);
  }

  void _handleDrag(PieceComponent comp, Vector2 rawDesiredOrigin) {
    final model = comp.model;
    final allowsH = model.movement.allowsHorizontal;
    final allowsV = model.movement.allowsVertical;
    final stepThreshold = (0.5 + UnityBoardConfig.stepHysteresis) * _cellSize;

    // 1. `CommitSteps` (up to `maxStepsPerFrame = 8` grid steps at `0.55 * cellSize`)
    bool movedGridCell = false;
    for (int step = 0; step < UnityBoardConfig.maxStepsPerFrame; step++) {
      final gridOrigin = comp.targetWorldOriginForGrid(model.col, model.row);
      final dx = allowsH ? (rawDesiredOrigin.x - gridOrigin.x) : 0.0;
      final dy = allowsV ? (rawDesiredOrigin.y - gridOrigin.y) : 0.0;

      bool advanced = false;
      if (dx.abs() >= dy.abs()) {
        if (allowsH && dx.abs() > stepThreshold) {
          final sc = dx > 0 ? 1 : -1;
          if (_canOccupy(model, model.col + sc, model.row)) {
            model.col += sc;
            advanced = true;
          }
        }
        if (!advanced && allowsV && dy.abs() > stepThreshold) {
          final sr = dy > 0 ? 1 : -1;
          if (_canOccupy(model, model.col, model.row + sr)) {
            model.row += sr;
            advanced = true;
          }
        }
      } else {
        if (allowsV && dy.abs() > stepThreshold) {
          final sr = dy > 0 ? 1 : -1;
          if (_canOccupy(model, model.col, model.row + sr)) {
            model.row += sr;
            advanced = true;
          }
        }
        if (!advanced && allowsH && dx.abs() > stepThreshold) {
          final sc = dx > 0 ? 1 : -1;
          if (_canOccupy(model, model.col + sc, model.row)) {
            model.col += sc;
            advanced = true;
          }
        }
      }

      if (advanced) {
        _syncOccupancyGrid();
        movedGridCell = true;
        _isTapCandidate = false;
      } else {
        break;
      }
    }

    if (movedGridCell) {
      _notifyFirstAction();
    }

    // 2. `ComputeOverlap` (`ClampOvershoot` on X and Y)
    final currentGridOrigin = comp.targetWorldOriginForGrid(model.col, model.row);
    final rawDelta = rawDesiredOrigin - currentGridOrigin;
    final overlapX = _clampOvershootAxis(
      piece: comp,
      rawOffsetPx: rawDelta.x,
      positiveDir: (1, 0),
      negativeDir: (-1, 0),
    );
    final overlapY = _clampOvershootAxis(
      piece: comp,
      rawOffsetPx: rawDelta.y,
      positiveDir: (0, 1),
      negativeDir: (0, -1),
    );
    _lastOverlap = Vector2(overlapX, overlapY);

    comp.setDragTargetWorld(
      Vector2(
        currentGridOrigin.x + overlapX,
        currentGridOrigin.y + overlapY,
      ),
    );

    // 3. `UpdateMergeCandidate` (Hold-to-Preview ONLY; commits on release in `_releaseDrag`!)
    _updateMergeCandidate(comp);
  }

  double _depthAlong(GridCell dir) {
    final proj = _lastOverlap.x * dir.$1 + _lastOverlap.y * dir.$2;
    return proj > 0.0 ? proj : 0.0;
  }

  bool _reachesMergeDepth(PieceComponent candidate, double depth) {
    if (_mergeCandidate != null && candidate.model.id == _mergeCandidate!.model.id) {
      return depth > 0.0;
    }
    return depth >= UnityBoardConfig.mergeArmDepth * _cellSize;
  }

  _MergeContactCandidate? _tryMergeStraight(PieceComponent dragged, GridCell dir) {
    final depth = _depthAlong(dir);
    if (depth <= 0.0) return null;

    final pair = _tryGetMergeCandidate(
      dragged: dragged,
      originCol: dragged.model.col,
      originRow: dragged.model.row,
      dir: dir,
    );
    if (pair == null) return null;
    if (!_reachesMergeDepth(pair.$1, depth)) return null;

    return _MergeContactCandidate(
      target: pair.$1,
      survivor: pair.$2,
      pushDir: dir,
      contactOrigin: (dragged.model.col, dragged.model.row),
      magnitude: depth,
    );
  }

  _MergeContactCandidate? _tryMergeOffCorner(
    PieceComponent dragged,
    GridCell stepDir,
    GridCell pushDir,
  ) {
    final depth = math.min(_depthAlong(stepDir), _depthAlong(pushDir));
    if (depth <= 0.0) return null;
    if (!_allowsDirection(dragged.model.movement, stepDir)) return null;

    final steppedCol = dragged.model.col + stepDir.$1;
    final steppedRow = dragged.model.row + stepDir.$2;
    if (!_canOccupy(dragged.model, steppedCol, steppedRow)) return null;

    final pair = _tryGetMergeCandidate(
      dragged: dragged,
      originCol: steppedCol,
      originRow: steppedRow,
      dir: pushDir,
    );
    if (pair == null) return null;
    if (!_reachesMergeDepth(pair.$1, depth)) return null;

    return _MergeContactCandidate(
      target: pair.$1,
      survivor: pair.$2,
      pushDir: pushDir,
      contactOrigin: (steppedCol, steppedRow),
      magnitude: depth,
    );
  }

  _MergeContactCandidate? _tryFindStraightMergeContact(PieceComponent dragged) {
    final hDir = _lastOverlap.x > 0.0 ? (1, 0) : (-1, 0);
    final vDir = _lastOverlap.y > 0.0 ? (0, 1) : (0, -1);

    final cH = _tryMergeStraight(dragged, hDir);
    final cV = _tryMergeStraight(dragged, vDir);
    if (cH != null && cV != null) {
      return cH.magnitude >= cV.magnitude ? cH : cV;
    }
    return cH ?? cV;
  }

  _MergeContactCandidate? _tryFindCornerMergeContact(PieceComponent dragged) {
    final hDir = _lastOverlap.x > 0.0 ? (1, 0) : (-1, 0);
    final vDir = _lastOverlap.y > 0.0 ? (0, 1) : (0, -1);
    final dH = _depthAlong(hDir);
    final dV = _depthAlong(vDir);

    if (dH >= dV) {
      return _tryMergeOffCorner(dragged, hDir, vDir) ??
          _tryMergeOffCorner(dragged, vDir, hDir);
    } else {
      return _tryMergeOffCorner(dragged, vDir, hDir) ??
          _tryMergeOffCorner(dragged, hDir, vDir);
    }
  }

  _MergeContactCandidate? _tryReachMergeCandidateAlongPush(
    PieceComponent dragged,
    GridCell pushDir,
  ) {
    final straight = _tryMergeStraight(dragged, pushDir);
    if (straight != null) return straight;

    final stepAcross = pushDir.$1 != 0
        ? (_lastOverlap.y > 0.0 ? (0, 1) : (0, -1))
        : (_lastOverlap.x > 0.0 ? (1, 0) : (-1, 0));
    return _tryMergeOffCorner(dragged, stepAcross, pushDir);
  }

  _MergeContactCandidate? _tryFindMergeContact(PieceComponent dragged) {
    var contact = _tryFindStraightMergeContact(dragged) ??
        _tryFindCornerMergeContact(dragged);
    if (contact == null) return null;

    // Sticky push direction: if still touching `_mergeCandidate` from `_mergePushDir`,
    // keep `_mergePushDir` so diagonal thumb micro-wobble never flips seam normal!
    if (_mergeCandidate != null &&
        contact.target.model.id == _mergeCandidate!.model.id &&
        contact.pushDir != _mergePushDir) {
      final sticky = _tryReachMergeCandidateAlongPush(dragged, _mergePushDir);
      if (sticky != null &&
          sticky.target.model.id == _mergeCandidate!.model.id) {
        contact = sticky;
      }
    }
    return contact;
  }

  double _computeMergePush(double magnitude) {
    final threshold = UnityBoardConfig.mergeOverlapThreshold * _cellSize;
    if (_mergeArmMagnitude >= threshold) return 1.0;
    return ((magnitude - _mergeArmMagnitude) / (threshold - _mergeArmMagnitude))
        .clamp(0.0, 1.0);
  }

  void _updateMergeCandidate(PieceComponent dragged) {
    final contact = _tryFindMergeContact(dragged);
    if (contact == null) {
      _forgetMergeCandidate();
      return;
    }

    final isNewCandidate =
        _mergeCandidate == null || _mergeCandidate!.model.id != contact.target.model.id;
    final dirOrOriginChanged =
        contact.pushDir != _mergePushDir || contact.contactOrigin != _mergeContactOrigin;

    if (isNewCandidate) {
      _mergeArmMagnitude = contact.magnitude;
    }

    if (isNewCandidate || dirOrOriginChanged) {
      _setBoardMergeCandidate(
        held: dragged,
        candidate: contact.target,
        survivor: contact.survivor,
        pushDir: contact.pushDir,
        contactOrigin: contact.contactOrigin,
      );
    }

    _mergeCandidate = contact.target;
    _mergeSurvivor = contact.survivor;
    _mergePushDir = contact.pushDir;
    _mergeContactOrigin = contact.contactOrigin;

    final pushAmount = _computeMergePush(contact.magnitude);
    _pushBoardMergeCandidate(
      held: dragged,
      candidate: contact.target,
      survivor: contact.survivor,
      pushAmount: pushAmount,
    );
  }

  /// Exact `BoardView.FindMergeContact`: averages `heldEdgeLocal` (relative to `held.position`)
  /// and `seamWorld` across all local cells of `held` that touch `candidate` when `held`
  /// stands at `contactOrigin` and pushes along `pushDir`.
  _MergeSeamContactGeometry _findMergeSeamGeometry({
    required PieceComponent held,
    required PieceComponent candidate,
    required GridCell pushDir,
    required GridCell contactOrigin,
  }) {
    final candBaseCol = candidate.model.col;
    final candBaseRow = candidate.model.row;
    final candLocal = candidate.model.localCells;
    double sumLocalX = 0.0;
    double sumLocalY = 0.0;
    double sumSeamX = 0.0;
    double sumSeamY = 0.0;
    int count = 0;

    for (final (dc, dr) in held.model.localCells) {
      final adjCol = contactOrigin.$1 + dc + pushDir.$1;
      final adjRow = contactOrigin.$2 + dr + pushDir.$2;
      bool touches = false;
      for (int k = 0; k < candLocal.length; k++) {
        final tc = candLocal[k];
        if (candBaseCol + tc.$1 == adjCol && candBaseRow + tc.$2 == adjRow) {
          touches = true;
          break;
        }
      }
      if (!touches) continue;

      final edgeLocalX = (dc + 0.5 + 0.5 * pushDir.$1) * _cellSize;
      final edgeLocalY = (dr + 0.5 + 0.5 * pushDir.$2) * _cellSize;
      final seamWorldX =
          _boardOrigin.x + (contactOrigin.$1 + dc + 0.5 + 0.5 * pushDir.$1) * _cellSize;
      final seamWorldY =
          _boardOrigin.y + (contactOrigin.$2 + dr + 0.5 + 0.5 * pushDir.$2) * _cellSize;

      sumLocalX += edgeLocalX;
      sumLocalY += edgeLocalY;
      sumSeamX += seamWorldX;
      sumSeamY += seamWorldY;
      count++;
    }

    if (count == 0) {
      final fallbackLocal = Vector2(held.size.x * 0.5, held.size.y * 0.5);
      final fallbackSeam =
          (held.visualCenterWorld + candidate.visualCenterWorld) * 0.5;
      return _MergeSeamContactGeometry(
        heldEdgeLocal: fallbackLocal,
        seamWorld: fallbackSeam,
      );
    }

    return _MergeSeamContactGeometry(
      heldEdgeLocal: Vector2(sumLocalX / count, sumLocalY / count),
      seamWorld: Vector2(sumSeamX / count, sumSeamY / count),
    );
  }

  /// Exact `BoardView.SetMergeCandidate` + `ArmMerge`:
  /// - If same candidate (`_mergeCandidate == candidate`), updates contact seam on `_candidateTransition`
  ///   without re-arming Z-pulse or replaying `playAttract()`.
  /// - If new candidate, clears previous candidate, arms survivor & partner roles, creates a new
  ///   5-stage `_MergeColorTransitionController`, and plays `audio.playAttract()`.
  void _setBoardMergeCandidate({
    required PieceComponent held,
    required PieceComponent candidate,
    required PieceComponent survivor,
    required GridCell pushDir,
    required GridCell contactOrigin,
  }) {
    final seamGeom = _findMergeSeamGeometry(
      held: held,
      candidate: candidate,
      pushDir: pushDir,
      contactOrigin: contactOrigin,
    );
    final pushUnit = Vector2(pushDir.$1.toDouble(), pushDir.$2.toDouble());

    if (_mergeCandidate != null &&
        _mergeCandidate!.model.id == candidate.model.id &&
        _candidateTransition != null) {
      _candidateTransition!.moveContact(
        newHeldEdgeLocal: seamGeom.heldEdgeLocal,
        newSeamWorld: seamGeom.seamWorld,
        newPushUnit: pushUnit,
      );
      return;
    }

    _clearBoardMergeCandidateVisuals(wasCommitted: false);

    final mergedValue = (survivor.model.number ?? 2) * 2;
    final targetStyle = palette.styleFor(number: mergedValue, isFrozen: false);
    final partner = survivor == held ? candidate : held;

    survivor.armMergeCandidateRole(
      asSurvivor: true,
      mergedPreviewValue: mergedValue,
    );
    partner.armMergeCandidateRole(
      asSurvivor: false,
      mergedPreviewValue: null,
    );

    final transition = _MergeColorTransitionController(
      held: held,
      candidate: candidate,
      visualSettings: visualSettings,
      cellSize: _cellSize,
      targetStyle: targetStyle,
      heldEdgeLocal: seamGeom.heldEdgeLocal,
      seamWorld: seamGeom.seamWorld,
      pushUnit: pushUnit,
    );
    _candidateTransition = transition;
    _mergeTransitions.add(transition);

    _isTapCandidate = false;
    _notifyFirstAction();
    audio.playAttract();
  }

  void _pushBoardMergeCandidate({
    required PieceComponent held,
    required PieceComponent candidate,
    required PieceComponent survivor,
    required double pushAmount,
  }) {
    _currentMergePushAmount = pushAmount.clamp(0.0, 1.0);
    _candidateTransition?.setProximity(_currentMergePushAmount);

    final partner = survivor == held ? candidate : held;
    survivor.updateMergePush(
      pushAmount: _currentMergePushAmount,
      isSurvivor: true,
    );
    partner.updateMergePush(
      pushAmount: _currentMergePushAmount,
      isSurvivor: false,
    );

    _syncActiveCandidateOverlapMask(
      survivor: survivor,
      partner: partner,
      pushAmount: _currentMergePushAmount,
    );
  }

  void _syncActiveCandidateOverlapMask({
    required PieceComponent survivor,
    required PieceComponent partner,
    required double pushAmount,
  }) {
    final joinStrength =
        visualSettings.mergeJoinStrength.evaluate(pushAmount).clamp(0.0, 1.0);
    if (joinStrength <= 1e-3) {
      survivor.clearMergeOverlap();
      partner.clearMergeOverlap();
      return;
    }

    final mergedValue = (survivor.model.number ?? 2) * 2;
    final topColor =
        palette.styleFor(number: mergedValue, isFrozen: false).topBright;

    survivor.setMergeOverlap(
      strength: joinStrength,
      partnerLocalPath: partner.localInflatedSilhouette010,
      partnerWorldOrigin: partner.position,
      topTargetColor: topColor,
    );
    partner.setMergeOverlap(
      strength: joinStrength,
      partnerLocalPath: survivor.localInflatedSilhouette010,
      partnerWorldOrigin: survivor.position,
      topTargetColor: topColor,
    );
  }

  void _forgetMergeCandidate() {
    if (_mergeCandidate == null && _candidateTransition == null) return;
    _clearBoardMergeCandidateVisuals(wasCommitted: false);
    _mergeCandidate = null;
    _mergeSurvivor = null;
    _mergePushDir = (0, 0);
    _mergeContactOrigin = (0, 0);
    _mergeArmMagnitude = 0.0;
    _currentMergePushAmount = 0.0;
  }

  void _clearBoardMergeCandidateVisuals({required bool wasCommitted}) {
    if (_mergeCandidate != null) {
      _mergeCandidate!.clearMergeCandidateState(wasCommitted: wasCommitted);
    }
    if (_draggedPiece != null) {
      _draggedPiece!.clearMergeCandidateState(wasCommitted: wasCommitted);
    }
    if (!wasCommitted) {
      _candidateTransition?.release();
      _candidateTransition = null;
    }
  }

  _ResolvedMergeOutcome _resolveMergeOutcome({
    required PieceComponent dragged,
    required PieceComponent target,
    required GridCell pushDir,
  }) {
    final draggedCells = dragged.model.localCells.length;
    final targetCells = target.model.localCells.length;
    final survivor = targetCells < draggedCells ? dragged : target;
    final partner = survivor == dragged ? target : dragged;

    int nextCol = survivor.model.col;
    int nextRow = survivor.model.row;
    bool survivorMoves = false;

    if (survivor == dragged && (pushDir.$1 != 0 || pushDir.$2 != 0)) {
      final candidateCol = survivor.model.col + pushDir.$1;
      final candidateRow = survivor.model.row + pushDir.$2;
      if (_canOccupy(
        survivor.model,
        candidateCol,
        candidateRow,
        ignorePieceId: partner.model.id,
      )) {
        nextCol = candidateCol;
        nextRow = candidateRow;
        survivorMoves = true;
      }
    }

    return _ResolvedMergeOutcome(
      survivor: survivor,
      partner: partner,
      survivorMoves: survivorMoves,
      survivorNextCol: nextCol,
      survivorNextRow: nextRow,
    );
  }

  Vector2 _nearestCellWorldPosition(PieceComponent survivor, Vector2 fromWorld) {
    Vector2 best = survivor.visualCenterWorld;
    double bestDistSq = double.infinity;
    for (final (c, r) in survivor.model.worldCells) {
      final cellCenter = _cellCenterWorld(c, r);
      final dSq = (cellCenter - fromWorld).length2;
      if (dSq < bestDistSq) {
        bestDistSq = dSq;
        best = cellCenter;
      }
    }
    return best;
  }

  /// Exact `BoardView.OutlineEdgesTouching(survivorCells, consumedOldCells)`:
  /// Emits every outer boundary edge of `survivorCells` where either the adjacent exterior
  /// cell OR the survivor cell itself belonged to `consumedOldCells`.
  List<MergeSplashEdge> _outlineEdgesTouching({
    required Set<GridCell> survivorCells,
    required Set<GridCell> consumedOldCells,
  }) {
    const dirs = <GridCell>[(1, 0), (-1, 0), (0, 1), (0, -1)];
    final edges = <MergeSplashEdge>[];
    for (final cell in survivorCells) {
      final cellWasConsumed = consumedOldCells.contains(cell);
      for (final dir in dirs) {
        final neighbor = (cell.$1 + dir.$1, cell.$2 + dir.$2);
        if (survivorCells.contains(neighbor)) continue;
        if (consumedOldCells.contains(neighbor) || cellWasConsumed) {
          final c1 = _cellCenterWorld(cell.$1, cell.$2);
          final c2 = _cellCenterWorld(neighbor.$1, neighbor.$2);
          edges.add(
            MergeSplashEdge(
              center: (c1 + c2) * 0.5,
              outwardDir: Offset(dir.$1.toDouble(), dir.$2.toDouble()),
              cells: 1,
            ),
          );
        }
      }
    }
    return edges;
  }

  /// Exact `BoardMergeResolver.PresentMergeAsync` choreography on finger release:
  /// 1. Commits `_candidateTransition` (`committed` -> `expanding` over `0.30s` `t^2` radial sweep).
  /// 2. Updates `survivor` grid cell (if `survivorMoves`), value (`* 2`), and merged `MovementConstraint`,
  ///    settling `MergeNumberPreview` (`0.50s`) and playing `MergeSurvivorMoves` (`1.12x`) or
  ///    `MergeSurvivorStays` (`1.20x` + `LeanImpulse`) + `1.0 - curve` screw shrink.
  /// 3. Absorbs `consumed` linearly over `0.28s` (`1 -> 0` scale) into `_nearestCellWorldPosition`
  ///    while keeping `_MergeOverlap` seam fusion active until `isAbsorbFinished`.
  /// 4. Spawns `MergeSplashVfx` along `OutlineEdgesTouching` + `0.10s`-delayed `MergeBlockSparksVfx`.
  /// 5. Unlocks ONLY ice blocks whose target `== newNumber` (`0.3833s` badge `Pop` -> shatter -> `1.5x` shake).
  void _commitMerge({
    required PieceComponent dragged,
    required PieceComponent target,
    required GridCell pushDir,
  }) {
    _notifyFirstAction();

    final seamGeom = _findMergeSeamGeometry(
      held: dragged,
      candidate: target,
      pushDir: pushDir,
      contactOrigin: (dragged.model.col, dragged.model.row),
    );
    final outcome = _resolveMergeOutcome(
      dragged: dragged,
      target: target,
      pushDir: pushDir,
    );

    final survivor = outcome.survivor;
    final consumed = outcome.partner;
    final consumedOldCells = consumed.model.worldCells;
    final wasPinnedBeforeMerge = survivor.model.movement.isPinned;

    final committedTransition = _candidateTransition;
    _candidateTransition = null;
    committedTransition?.commit();

    final commitOverlapStrength = math.max(
      0.55,
      visualSettings.mergeJoinStrength
          .evaluate(_currentMergePushAmount)
          .clamp(0.0, 1.0),
    );

    _clearBoardMergeCandidateVisuals(wasCommitted: true);
    _mergeCandidate = null;
    _mergeSurvivor = null;
    _mergePushDir = (0, 0);
    _mergeContactOrigin = (0, 0);
    _mergeArmMagnitude = 0.0;
    _currentMergePushAmount = 0.0;

    _draggedPiece = null;
    _activePointerId = null;
    _isTapCandidate = false;

    final oldStyle = palette.styleFor(
      number: survivor.model.number,
      isFrozen: false,
    );
    final newNumber = (survivor.model.number ?? 2) * 2;
    final newStyle = palette.styleFor(number: newNumber, isFrozen: false);
    final combinedMovement =
        survivor.model.movement.resolveMergedWith(consumed.model.movement);

    if (outcome.survivorMoves) {
      survivor.model.col = outcome.survivorNextCol;
      survivor.model.row = outcome.survivorNextRow;
    }
    survivor.model.number = newNumber;
    survivor.model.movement = combinedMovement;
    survivor.snapDragTargetToModelGrid();

    // Expand `MergeColorTransition` across survivor & consumed (`0.30s`, `t^2` curve)
    if (committedTransition != null) {
      committedTransition.expand(
        survivor: survivor,
        newTargetStyle: newStyle,
      );
    } else {
      survivor.applyMergedAppearance(newStyle);
    }

    // Settle preview number (`0.50s` `SettleAsync`) & trigger survivor pulse / lean impulse / screw shrink
    survivor.commitNumberPreview(fallbackMergedNumber: newNumber);
    final shoveOffset = Offset(pushDir.$1.toDouble(), pushDir.$2.toDouble());
    survivor.triggerSurvivorCommitResponse(
      survivorMoves: outcome.survivorMoves,
      shoveDir: shoveOffset,
      wasPinnedBeforeMerge: wasPinnedBeforeMerge,
      previousStyle: oldStyle,
    );

    // Absorb `consumed` linearly into nearest survivor cell over `0.28s`
    _pieces.remove(consumed);
    _syncOccupancyGrid();
    _pendingNumberPrewarms.add((survivor, newNumber * 2));
    consumed.priority = math.max(2, survivor.priority - 1);
    final absorbDest =
        _nearestCellWorldPosition(survivor, consumed.visualCenterWorld);
    consumed.beginAbsorb(
      worldDestinationCenter: absorbDest,
      duration: _absorbDurationSeconds,
    );
    _absorbingAnims.add(
      _AbsorbingMergeAnim(
        consumed: consumed,
        survivor: survivor,
        transition: committedTransition,
        topTargetColor: newStyle.topBright,
        initialOverlapStrength: commitOverlapStrength,
        duration: _absorbDurationSeconds,
      ),
    );

    // Spawn edge-based `MergeSplashVfx` + `0.10s`-delayed upward `MergeBlockSparksVfx`
    final splashEdges = _outlineEdgesTouching(
      survivorCells: survivor.model.worldCells,
      consumedOldCells: consumedOldCells,
    );
    Vector2 splashCenter = seamGeom.seamWorld;
    if (splashEdges.isNotEmpty) {
      Vector2 sum = Vector2.zero();
      for (final e in splashEdges) {
        sum += e.center;
      }
      splashCenter = sum / splashEdges.length.toDouble();
    }

    _boardStage.add(
      MergeSplashVfx(
        centerPos: splashCenter,
        primaryColor: newStyle.topMid,
        accentColor: newStyle.accent,
        ringColor: newStyle.topBright,
        pushDir: shoveOffset,
        edges: splashEdges,
        cellSize: _cellSize,
      ),
    );
    _boardStage.add(
      MergeBlockSparksVfx(
        cellCentersProvider: () =>
            survivor.isMounted ? survivor.worldCellCenters : const <Vector2>[],
        accentColor: newStyle.accent,
        cellSize: _cellSize,
        delaySeconds: UnityBoardConfig.mergeSparksDelay,
        downOffsetCells: UnityBoardConfig.mergeSparksDownOffset,
        liftCells: UnityBoardConfig.mergeSparksLift,
      ),
    );
    // Exact Unity `GameplayState`: `OnMovementEnded` (`TriggerPieceDrop`) +
    // `OnMovementCompleted` (`PlaySfx("block_put")`) + `<ResolveMovementAsync>d__38` (`PlaySfx("block_merge")`)
    // fire together at `t = 0ms`, followed by `TriggerMerge()` (`hapticMergeImpact`) at `t = 45ms`!
    audio.playPut();
    audio.playMerge();

    _unlockEligibleIceBlocks(newNumber);
    _refreshCanLevelUp();
    _checkWinCondition();
  }

  /// Exact `IceComponent` rule (`target == mergedNumber`, NOT `<=`!):
  /// Clears `model.iceTarget = null` immediately in gameplay state while playing
  /// `IceComponentView.PopThenBreakAsync` (`0.3833s` badge `Pop` -> shatter VFX & SFX -> `1.5x` shake).
  void _unlockEligibleIceBlocks(int mergedNumber) {
    for (final p in _pieces) {
      if (p.isFlyingOrSwallowed) continue;
      final target = p.model.iceTarget;
      if (target != null && target == mergedNumber) {
        p.model.iceTarget = null;
        if (p.model.number != null) {
          _pendingNumberPrewarms.add((p, p.model.number! * 2));
        }
        p.beginIceUnlockSequence(
          onShatter: () {
            if (!p.isMounted) return;
            _boardStage.add(
              IceShatterVfx(
                centerPos: p.worldCenter,
                cellSize: _cellSize,
                worldCellCenters: p.worldCellCenters,
              ),
            );
            audio.playIceBreak();
          },
        );
      }
    }
  }

  /// Exact `LevelUpPowerUp.TrySelectLevelUpPair`:
  /// Finds the lowest `number` with `>= 2` mergeable pieces, sorts ascending by
  /// `localCells.length` (tie-break by board/id order), and selects `candidates[0]` (`spent`)
  /// and `candidates[1]` (`kept`) — BOTH fewest-block pieces!
  (PieceComponent spent, PieceComponent kept)? _findLowestMergeablePair() {
    final groups = <int, List<PieceComponent>>{};
    for (final p in _pieces) {
      if (p.isFlyingOrSwallowed || !p.model.canMerge) continue;
      final n = p.model.number;
      if (n == null) continue;
      groups.putIfAbsent(n, () => <PieceComponent>[]).add(p);
    }

    int? lowestNum;
    for (final entry in groups.entries) {
      if (entry.value.length >= 2) {
        if (lowestNum == null || entry.key < lowestNum) {
          lowestNum = entry.key;
        }
      }
    }
    if (lowestNum == null) return null;

    final candidates = List<PieceComponent>.from(groups[lowestNum]!)
      ..sort((a, b) {
        final cellCmp =
            a.model.localCells.length.compareTo(b.model.localCells.length);
        if (cellCmp != 0) return cellCmp;
        return a.model.id.compareTo(b.model.id);
      });

    return (candidates[0], candidates[1]);
  }

  void _refreshCanLevelUp() {
    canLevelUpNotifier.value = !_hasWon &&
        !_hasLost &&
        _levelUpFlight == null &&
        _findLowestMergeablePair() != null;
  }

  /// Triggers the `Level Up` Power-Up (`LevelUpVisualConfig.json`).
  bool triggerLevelUpPowerUp() {
    if (!_canInteract) return false;
    final pair = _findLowestMergeablePair();
    if (pair == null) return false;
    if (paused) resumeEngine();

    _cancelDrag(silent: true);
    _notifyFirstAction();

    final (spent, kept) = pair;
    _pieces.remove(spent);
    spent.beginFlying();
    _syncOccupancyGrid();
    spent.priority = 130;
    kept.levelUpTargetGlow = 1.0;

    _boardStage.add(
      LevelUpRevealArrowVfx(
        targetCenter: kept.worldCenter,
        cellSize: _cellSize,
      ),
    );

    final style = palette.styleFor(number: spent.model.number, isFrozen: false);
    _levelUpFlight = _LevelUpFlightAnim(
      spent: spent,
      kept: kept,
      startOrigin: spent.position.clone(),
      liftHeight: _cellSize * (visualSettings.levelUpLiftHeight * 0.62),
      liftDur: visualSettings.levelUpLiftDuration,
      travelDur: visualSettings.levelUpTravelDuration,
      sparkColor: style.topBright,
    );
    audio.playLevelUpArrow();
    audio.playLevelUpFly();
    _refreshCanLevelUp();
    return true;
  }

  /// Triggers the `Time Freeze` Power-Up (`20s` icy timer pause).
  /// On normal gameplay (`allowBeforeTimerStarted == false`), requires `canUseTimeFreeze`
  /// (`GameplayTimer.IsStarted && !isTimeFrozen`). During Level 27 FTUE free execution
  /// (`allowBeforeTimerStarted == true`), starts the timer immediately in frozen mode.
  bool triggerTimeFreezePowerUp({bool allowBeforeTimerStarted = false}) {
    if (_hasWon || _hasLost || _level.timerDisabled) return false;
    if (!allowBeforeTimerStarted && !isTimerStartedNotifier.value) {
      return false;
    }
    if (isTimeFrozen) return false;
    if (paused) resumeEngine();
    isTimerStartedNotifier.value = true;
    _setTimeFreezeRemaining(maxTimeFreezeSeconds, forceNotify: true);
    audio.playTimeFreeze();
    return true;
  }

  void _checkWinCondition() {
    if (_hasWon || _hasLost) return;
    int numberedRemaining = 0;
    PieceComponent? finalPiece;
    for (final p in _pieces) {
      if (!p.isFlyingOrSwallowed && !p.model.isDud) {
        numberedRemaining++;
        finalPiece = p;
      }
    }
    if (numberedRemaining <= 1) {
      _hasWon = true;
      _winZoomTimer = 0.0;
      _winSequenceElapsed = 0.0;
      _winSandStreamSpawned = false;
      _winJarOpened = false;
      _winCallbackFired = false;
      _finalWinningPiece = finalPiece;
      isWinSequenceActiveNotifier.value = true;
      _refreshCanLevelUp();

      final winNumber = finalPiece?.model.number ?? _level.targetWinNumber;
      final winStyle = palette.styleFor(
        number: winNumber,
        isFrozen: false,
      );
      _sandJar?.updateStyle(winStyle);
      winScreenFlashColorNotifier.value = winStyle.rimHighlight;

      // Step 1 (`merge thành công số cuối cùng. Tile cuối phát sáng, scale lớn nhẹ và tạo hiệu ứng nổ ánh sáng`):
      finalPiece?.triggerFinalWinHighlight();
      _boardStage.add(
        FinalTileLightExplosionVfx(
          centerPos: finalPiece?.worldCenter ?? Vector2.zero(),
          style: winStyle,
          cellSize: _cellSize,
        ),
      );
      audio.playWinComplete();
    }
  }

  @override
  void update(double dt) {
    PieceComponent.resetFrameBakeBudget(4);
    super.update(dt);
    if (!_isReady) return;
    if (_needsSafeAreaRelayout) {
      _needsSafeAreaRelayout = false;
      if (size.x > 10 && size.y > 10) {
        _buildLevelStage(preserveModels: _pieces.isNotEmpty);
      }
    }
    final clampedDt = dt.clamp(0.0, 0.05);
    _elapsedGameTime += clampedDt;

    // 0. Incremental idle pre-warm of merged 4-layer number sprites (up to 2 per frame)
    if (_draggedPiece == null && _pendingNumberPrewarms.isNotEmpty) {
      int budget = 2;
      while (budget > 0 && _pendingNumberPrewarms.isNotEmpty) {
        final (comp, previewVal) = _pendingNumberPrewarms.removeLast();
        if (comp.isMounted && !comp.isFlyingOrSwallowed) {
          comp.prewarmMergedNumberSprite(previewVal);
          budget--;
        }
      }
    }

    // 1. Camera Intro & Win Zoom (`camera_anim.json`)
    if (_winZoomTimer >= 0) {
      _winZoomTimer += clampedDt;
      final t =
          (_winZoomTimer / visualSettings.cameraWinDuration).clamp(0.0, 1.0);
      final curveVal = visualSettings.cameraWinCurve.evaluate(t);
      final targetWinZoom =
          1.0 / visualSettings.cameraWinZoomFactor.clamp(0.8, 1.0);
      _stageZoom =
          ui.lerpDouble(1.0, targetWinZoom, curveVal.clamp(0.0, 1.25))!;
      _boardStage.scale = Vector2.all(_stageZoom);
    } else if (_introTimer < visualSettings.cameraIntroDuration) {
      _introTimer += clampedDt;
      final t =
          (_introTimer / visualSettings.cameraIntroDuration).clamp(0.0, 1.0);
      final curveVal =
          visualSettings.cameraIntroCurve.evaluate(t).clamp(0.0, 1.2);
      _stageZoom = ui.lerpDouble(_introStartZoom, 1.0, curveVal)!;
      _boardStage.scale = Vector2.all(_stageZoom);
    }

    // 2. 4-Step Magic Sand Jar Win Choreography (with comfortable breathing room before popup):
    // - Step 1 (`0.00s .. 0.42s`): Timer hides (`isWinSequenceActiveNotifier`), Jar materializes (`appearProgress: 0 -> 1`),
    //   and final tile glows, scales up gently (`1.24x`), and bursts light.
    // - Step 2 (`0.42s .. 1.85s`): Colored sand streams upward from board & final tile into the jar.
    // - Step 3 (`0.55s .. 2.58s`): Jar shakes & glows while swirling sand fills (`0.55s .. 1.85s`)
    //   and reveals the hidden crystal emblem & filigree texture, holds briefly (`1.85s .. 2.10s`)
    //   to admire the filled jar, then pops open with a light fountain (`2.10s .. 2.58s`).
    // - Step 4 (`2.30s .. 3.15s`): Radial light wave expands across the full screen and
    //   presents the Next Level pop-up at peak bloom (`2.62s`).
    if (_winSequenceElapsed >= 0) {
      _winSequenceElapsed += clampedDt;

      // Keep the final winning tile luminous during Steps 1 & 2 while sand lifts off the board
      if (_finalWinningPiece != null &&
          _finalWinningPiece!.isMounted &&
          _winSequenceElapsed < 1.80) {
        final glowKeep =
            (1.0 - (_winSequenceElapsed / 1.80) * 0.25).clamp(0.75, 1.0);
        if (_finalWinningPiece!.levelUpTargetGlow < glowKeep) {
          _finalWinningPiece!.levelUpTargetGlow = glowKeep;
        }
      }

      // Step 2: Spawn upward sand stream from board & final tile to jar after Step 1 beat (`0.42s`)
      if (!_winSandStreamSpawned && _winSequenceElapsed >= 0.42) {
        _winSandStreamSpawned = true;
        final winPiece = _finalWinningPiece;
        final winStyle = _sandJar?.style ??
            palette.styleFor(
              number: winPiece?.model.number ?? _level.targetWinNumber,
              isFrozen: false,
            );
        final boardOrigins = <Vector2>[];
        for (int r = 0; r < _gridRows; r++) {
          for (int c = 0; c < _gridCols; c++) {
            if (_playableGrid[r * _gridCols + c] != 0) {
              boardOrigins.add(_cellCenterWorld(c, r));
            }
          }
        }
        final primaryOrigin = winPiece != null && winPiece.isMounted
            ? winPiece.worldCenter
            : Vector2.zero();
        if (boardOrigins.isEmpty) {
          boardOrigins.add(primaryOrigin);
        }
        _boardStage.add(
          BoardSandStreamToJarVfx(
            finalTileCenter: primaryOrigin,
            boardOrigins: boardOrigins,
            targetMouthProvider: () =>
                _sandJar?.mouthWorldPos ?? Vector2(0.0, _boardOrigin.y - _cellSize),
            style: winStyle,
            cellSize: _cellSize,
          ),
        );
      }

      // Step 1 -> Step 3: Jar pop-in (`0..0.36s`), shake, glow, swirling sand fill & hidden object reveal, then jar opening
      final appearP = (_winSequenceElapsed / 0.36).clamp(0.0, 1.0);
      final fillP = ((_winSequenceElapsed - 0.55) / 1.30).clamp(0.0, 1.0);
      final glowP = ((_winSequenceElapsed - 0.46) / 1.15).clamp(0.0, 1.0);
      final shakeP =
          (_winSequenceElapsed >= 0.50 && _winSequenceElapsed < 2.08)
              ? math
                  .sin(((_winSequenceElapsed - 0.50) / 1.58) * math.pi)
                  .clamp(0.0, 1.0)
              : 0.0;
      final openP = ((_winSequenceElapsed - 2.10) / 0.48).clamp(0.0, 1.0);
      _sandJar?.setWinSequenceState(
        appearProgress: appearP,
        fillProgress: fillP,
        glowIntensity: glowP,
        shakeIntensity: shakeP,
        openProgress: openP,
      );

      if (!_winJarOpened && _winSequenceElapsed >= 2.10) {
        _winJarOpened = true;
        final winStyle = _sandJar?.style ??
            palette.styleFor(
              number: _level.targetWinNumber,
              isFrozen: false,
            );
        _jarOpenWaveVfx = JarOpenAndFullscreenLightWaveVfx(
          jarMouthProvider: () =>
              _sandJar?.mouthWorldPos ?? Vector2(0.0, _boardOrigin.y - _cellSize),
          style: winStyle,
          cellSize: _cellSize,
        );
        _boardStage.add(_jarOpenWaveVfx!);
        audio.hapticMergeImpact();
      }

      // Step 4: Fullscreen light wave bloom & Next Level pop-up trigger at `t = 2.62s`
      final waveVfx = _jarOpenWaveVfx;
      if (waveVfx != null && waveVfx.isMounted) {
        final flashVal = waveVfx.currentFullscreenFlashIntensity;
        if ((winScreenFlashNotifier.value - flashVal).abs() > 0.005 ||
            flashVal == 0.0) {
          winScreenFlashNotifier.value = flashVal;
        }
      } else if (winScreenFlashNotifier.value != 0.0) {
        winScreenFlashNotifier.value = 0.0;
      }

      if (!_winCallbackFired && _winSequenceElapsed >= 2.62) {
        _winCallbackFired = true;
        onLevelWon();
      }
    }

    // 3. Keep `_MergeOverlap` seam mask synced to live `PieceFollow` positions while holding a candidate
    if (_draggedPiece != null &&
        _mergeCandidate != null &&
        _mergeSurvivor != null) {
      final survivor = _mergeSurvivor!;
      final partner =
          survivor == _draggedPiece ? _mergeCandidate! : _draggedPiece!;
      _syncActiveCandidateOverlapMask(
        survivor: survivor,
        partner: partner,
        pushAmount: _currentMergePushAmount,
      );
    }

    // 4. Tick `0.28s` linear `AbsorbIntoAsync` pairs & keep `_MergeOverlap` fused until `isAbsorbFinished`
    for (int i = _absorbingAnims.length - 1; i >= 0; i--) {
      final anim = _absorbingAnims[i];
      anim.elapsed += clampedDt;
      if (!anim.mergeImpactHapticFired && anim.elapsed >= 0.045) {
        anim.mergeImpactHapticFired = true;
        audio.hapticMergeImpact();
      }
      if (anim.consumed.isAbsorbFinished || anim.elapsed >= anim.duration + 0.02) {
        if (!anim.mergeImpactHapticFired) {
          anim.mergeImpactHapticFired = true;
          audio.hapticMergeImpact();
        }
        anim.transition?.drop(anim.consumed);
        anim.consumed.clearMergeOverlap();
        if (_mergeCandidate != anim.survivor && _draggedPiece != anim.survivor) {
          anim.survivor.clearMergeOverlap();
        }
        anim.consumed.removeFromParent();
        _absorbingAnims.removeAt(i);
      } else {
        final remFrac =
            (1.0 - (anim.elapsed / anim.duration)).clamp(0.0, 1.0);
        final strength = anim.initialOverlapStrength * remFrac;
        anim.consumed.setMergeOverlap(
          strength: strength,
          partnerLocalPath: anim.survivor.localInflatedSilhouette010,
          partnerWorldOrigin: anim.survivor.position,
          topTargetColor: anim.topTargetColor,
        );
        if (_mergeCandidate != anim.survivor && _draggedPiece != anim.survivor) {
          anim.survivor.setMergeOverlap(
            strength: strength,
            partnerLocalPath: anim.consumed.localInflatedSilhouette010,
            partnerWorldOrigin: anim.consumed.position,
            topTargetColor: anim.topTargetColor,
          );
        }
      }
    }

    // 5. Tick all 5-stage `_MergeColorTransitionController` radial shader wipes
    for (int i = _mergeTransitions.length - 1; i >= 0; i--) {
      final transition = _mergeTransitions[i];
      transition.tick(clampedDt);
      if (transition.isFinished) {
        if (identical(_candidateTransition, transition)) {
          _candidateTransition = null;
        }
        _mergeTransitions.removeAt(i);
      }
    }

    // 6. Cinematic `Level Up` Power-Up flight (`level_up_visual.json` exact curves)
    final flight = _levelUpFlight;
    if (flight != null) {
      flight.elapsed += clampedDt;
      flight.sparkTimer += clampedDt;

      final liftedOrigin = Vector2(
        flight.startOrigin.x,
        flight.startOrigin.y - flight.liftHeight,
      );
      final targetOrigin = flight.kept.worldCenter -
          Vector2(flight.spent.size.x * 0.5, flight.spent.size.y * 0.5);

      if (flight.elapsed <= flight.liftDur) {
        final t =
            (flight.elapsed / math.max(0.01, flight.liftDur)).clamp(0.0, 1.0);
        final liftE = visualSettings.levelUpLiftCurve.evaluate(t);
        final jiggle = visualSettings.levelUpLiftJiggleCurve.evaluate(t);
        flight.spent.position = Vector2(
          ui.lerpDouble(flight.startOrigin.x, liftedOrigin.x, liftE)!,
          ui.lerpDouble(flight.startOrigin.y, liftedOrigin.y, liftE)!,
        );
        flight.spent.visualScale =
            ui.lerpDouble(1.0, 1.14, liftE.clamp(0.0, 1.2))!;
        flight.spent.visualScaleXMultiplier = 1.0 + jiggle * 0.9;
        flight.spent.visualScaleYMultiplier = 1.0 - jiggle * 0.7;
      } else {
        final travelElapsed = flight.elapsed - flight.liftDur;
        final t =
            (travelElapsed / math.max(0.01, flight.travelDur)).clamp(0.0, 1.0);
        final e = visualSettings.levelUpTravelCurve.evaluate(t).clamp(0.0, 1.05);
        final shrink =
            visualSettings.levelUpShrinkCurve.evaluate(t).clamp(0.25, 1.25);

        final midCtrl = Vector2(
          (liftedOrigin.x + targetOrigin.x) * 0.5,
          math.min(liftedOrigin.y, targetOrigin.y) - _cellSize * 0.95,
        );
        final oneMinus = 1.0 - e;
        final bx = oneMinus * oneMinus * liftedOrigin.x +
            2 * oneMinus * e * midCtrl.x +
            e * e * targetOrigin.x;
        final by = oneMinus * oneMinus * liftedOrigin.y +
            2 * oneMinus * e * midCtrl.y +
            e * e * targetOrigin.y;
        flight.spent.position = Vector2(bx, by);
        flight.spent.visualScale = 1.12 * shrink;
        flight.spent.visualScaleXMultiplier = 1.0;
        flight.spent.visualScaleYMultiplier = 1.0;

        // Arm target candidate preview once within `MergeArmDistance` (`1.0` cell)
        final distCells =
            (flight.spent.worldCenter - flight.kept.worldCenter).length /
                _cellSize;
        if (!flight.armedTargetPreview &&
            distCells <= math.max(1.0, visualSettings.levelUpMergeArmDistance)) {
          flight.armedTargetPreview = true;
          final mergedVal = (flight.kept.model.number ?? 2) * 2;
          flight.kept.armMergeCandidateRole(
            asSurvivor: true,
            mergedPreviewValue: mergedVal,
          );
          flight.kept.updateMergePush(
            pushAmount: 0.75,
            isSurvivor: true,
          );
          audio.playAttract();
        }

        if (flight.sparkTimer >= 0.04) {
          flight.sparkTimer = 0.0;
          _boardStage.add(
            LevelUpSparksVfx(
              pos: flight.spent.worldCenter,
              color: flight.sparkColor,
              cellSize: _cellSize,
            ),
          );
        }
      }

      if (flight.elapsed >= flight.totalDuration) {
        _completeLevelUpFlight(flight);
      }
    }

    // 7. Countdown Timer & Time Freeze (`GameplayTimer.IsStarted`)
    if (!isModalPaused &&
        !isTimeFreezeIntroInFlight &&
        !_hasWon &&
        !_hasLost &&
        !_level.timerDisabled) {
      if (_timeFreezeRemaining > 0.0) {
        _setTimeFreezeRemaining(_timeFreezeRemaining - clampedDt);
      } else if (isTimerStartedNotifier.value) {
        _countdownFrac += clampedDt;
        if (_countdownFrac >= 1.0) {
          final wholeSecs = _countdownFrac.floor();
          _countdownFrac -= wholeSecs;
          final nextVal =
              math.max(0, remainingSecondsNotifier.value - wholeSecs);
          remainingSecondsNotifier.value = nextVal;
          if (nextVal <= 0 && !_hasWon && !_hasLost) {
            _hasLost = true;
            _cancelDrag(silent: true);
            _refreshCanLevelUp();
            audio.playOutOfTime();
            onTimeExpired();
          }
        }
      }
    }

    // 8. Smart modal engine sleep: suspend 120Hz game loop ONLY after all camera zooms,
    // piece settles, and particle VFX have completely finished behind an opaque modal.
    if (allowEngineSleepBehindModal && !paused && _isBoardCompletelyAtRest()) {
      pauseEngine();
    }
  }

  void _completeLevelUpFlight(_LevelUpFlightAnim flight) {
    _levelUpFlight = null;
    final spent = flight.spent;
    final kept = flight.kept;
    final wasPinnedBeforeMerge = kept.model.movement.isPinned;
    spent.removeFromParent();
    kept.levelUpTargetGlow = 0.95;
    kept.clearMergeCandidateState(wasCommitted: true);

    final oldStyle = palette.styleFor(
      number: kept.model.number,
      isFrozen: false,
    );
    final newNumber = (kept.model.number ?? 2) * 2;
    final newStyle = palette.styleFor(number: newNumber, isFrozen: false);
    kept.model.number = newNumber;
    kept.model.movement =
        kept.model.movement.resolveMergedWith(spent.model.movement);
    _pendingNumberPrewarms.add((kept, newNumber * 2));

    final center = kept.visualCenterWorld;
    final expandTransition = _MergeColorTransitionController(
      held: kept,
      candidate: kept,
      visualSettings: visualSettings,
      cellSize: _cellSize,
      targetStyle: newStyle,
      heldEdgeLocal: Vector2(kept.size.x * 0.5, kept.size.y * 0.5),
      seamWorld: center,
      pushUnit: Vector2(0, 1),
    )..commit();
    expandTransition.expand(
      survivor: kept,
      newTargetStyle: newStyle,
    );
    _mergeTransitions.add(expandTransition);

    kept.commitNumberPreview(fallbackMergedNumber: newNumber);
    kept.triggerSurvivorCommitResponse(
      survivorMoves: false,
      shoveDir: const Offset(0, 1),
      wasPinnedBeforeMerge: wasPinnedBeforeMerge,
      previousStyle: oldStyle,
    );

    _boardStage.add(
      MergeSplashVfx(
        centerPos: kept.worldCenter,
        primaryColor: newStyle.topMid,
        accentColor: newStyle.accent,
        ringColor: newStyle.topBright,
        cellSize: _cellSize,
      ),
    );
    _boardStage.add(
      MergeBlockSparksVfx(
        cellCentersProvider: () =>
            kept.isMounted ? kept.worldCellCenters : const <Vector2>[],
        accentColor: newStyle.accent,
        cellSize: _cellSize,
        delaySeconds: UnityBoardConfig.mergeSparksDelay,
        downOffsetCells: UnityBoardConfig.mergeSparksDownOffset,
        liftCells: UnityBoardConfig.mergeSparksLift,
      ),
    );
    audio.playLevelUpMerge();

    _unlockEligibleIceBlocks(newNumber);
    _refreshCanLevelUp();
    _checkWinCondition();
  }
}
