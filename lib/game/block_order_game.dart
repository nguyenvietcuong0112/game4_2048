import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Canvas, Color, Paint, Rect;
import '../models/level_models.dart';
import '../models/palette.dart';
import '../models/unity_curve.dart';
import '../services/audio_haptics_service.dart';
import 'board_component.dart';
import 'piece_component.dart';
import 'vfx_components.dart';

class _SwallowedPieceAnim {
  final PieceComponent piece;
  final Vector2 startPos;
  final Vector2 endPos;
  double elapsed = 0.0;
  static const double duration = 0.15;

  _SwallowedPieceAnim({
    required this.piece,
    required this.startPos,
    required this.endPos,
  });
}

class _LevelUpFlightAnim {
  final PieceComponent spent;
  final PieceComponent kept;
  final Vector2 startOrigin;
  final double liftHeight;
  double elapsed = 0.0;
  double sparkTimer = 0.0;
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

class _TutorialHandComponent extends PositionComponent {
  final Vector2 fromPos;
  final Vector2 toPos;
  final double cellSize;
  ui.Image? _handImg;
  double _t = 0.0;

  _TutorialHandComponent({
    required this.fromPos,
    required this.toPos,
    required this.cellSize,
  }) : super(priority: 250) {
    if (Flame.images.containsKey('Hand_01.png')) {
      try {
        _handImg = Flame.images.fromCache('Hand_01.png');
      } catch (_) {}
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t = (_t + dt * 0.72) % 1.0;
    final moveT = CurvesHelper.smoothStep((_t / 0.78).clamp(0.0, 1.0));
    position = Vector2(
      ui.lerpDouble(fromPos.x, toPos.x, moveT)!,
      ui.lerpDouble(fromPos.y, toPos.y, moveT)!,
    );
  }

  @override
  void render(Canvas canvas) {
    final img = _handImg;
    if (img == null) return;
    double alpha = 1.0;
    if (_t < 0.12) {
      alpha = (_t / 0.12).clamp(0.0, 1.0);
    } else if (_t > 0.82) {
      alpha = ((1.0 - _t) / 0.18).clamp(0.0, 1.0);
    }
    final handSize = cellSize * 0.95;
    final pressScale = _t < 0.18 ? 0.92 : 1.0;
    canvas.save();
    canvas.scale(pressScale, pressScale);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(
        -handSize * 0.22,
        -handSize * 0.12,
        handSize,
        handSize * (img.height / img.width),
      ),
      Paint()..color = Color.fromRGBO(255, 255, 255, alpha * 0.95),
    );
    canvas.restore();
  }
}

class CurvesHelper {
  static double smoothStep(double x) {
    final t = x.clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }
}

class BlockOrderGame extends FlameGame with DragCallbacks, TapCallbacks {
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
  final ValueNotifier<bool> canLevelUpNotifier = ValueNotifier<bool>(false);

  bool isModalPaused = false;
  bool _isReady = false;
  bool _hasWon = false;
  bool _hasLost = false;
  bool _firstActionTriggered = false;
  double _winCallbackDelay = -1.0;

  // Countdown timer accumulators
  double _countdownFrac = 0.0;
  static const double maxTimeFreezeSeconds = 20.0;

  // Stage & board layout
  final PositionComponent _boardStage = PositionComponent(priority: 5);
  BoardComponent? _boardComponent;
  final List<PieceComponent> _pieces = [];
  _TutorialHandComponent? _tutorialHand;

  double _cellSize = 40.0;
  Vector2 _boardOrigin = Vector2.zero();
  Vector2 _lastLayoutSize = Vector2.zero();

  // Camera Intro & Win Zoom
  double _introTimer = 0.0;
  double _winZoomTimer = -1.0;
  double _stageZoom = 1.0;

  // Active Drag State
  int? _activePointerId;
  PieceComponent? _draggedPiece;
  Vector2 _grabOffsetFromPieceOrigin = Vector2.zero();
  int _dragStartCol = 0;
  int _dragStartRow = 0;
  PieceComponent? _mergeCandidate;
  GridCell _mergePushDir = (0, 0);

  // Active Merge Swallow & LevelUp Animations
  final List<_SwallowedPieceAnim> _swallowedAnims = [];
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

  bool get isBusyWithPowerUp => _levelUpFlight != null;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    const spritesToLoad = [
      'IceLock.png',
      'IceBlocks.png',
      'Ice_Shards.png',
      'Screw_Greyscale_01.png',
      'Movement_Single-Horizontal_Shadow.png',
      'Movement_Single-Horizontal_Stroke.png',
      'Movement_Single-Horizontal_Top.png',
      'Movement_Double_Horizontal.png',
      'Movement_Double_Vertical.png',
      'Sparkle_01.png',
      'ParticleFlare.png',
      'Explosion_Halo.png',
      'Glow_02.png',
      'Hand_01.png',
    ];
    for (final s in spritesToLoad) {
      try {
        await Flame.images.load(s);
      } catch (e) {
        debugPrint('Flame image preload warning for $s: $e');
      }
    }
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
      _buildLevelStage(preserveModels: _pieces.isNotEmpty);
    }
  }

  void loadLevel(LevelDefinition newLevel) {
    _level = newLevel;
    _hasWon = false;
    _hasLost = false;
    _winCallbackDelay = -1.0;
    _firstActionTriggered = false;
    _countdownFrac = 0.0;
    remainingSecondsNotifier.value = newLevel.timeSeconds;
    timeFreezeNotifier.value = 0.0;
    _cancelDrag(silent: true);
    _swallowedAnims.clear();
    _levelUpFlight = null;
    if (_isReady && size.x > 10 && size.y > 10) {
      _buildLevelStage(preserveModels: false);
    }
  }

  void restartLevel() {
    loadLevel(_level);
  }

  void addExtraTime(int extraSeconds) {
    if (_hasWon) return;
    _hasLost = false;
    _countdownFrac = 0.0;
    remainingSecondsNotifier.value += extraSeconds;
  }

  void _buildLevelStage({required bool preserveModels}) {
    _lastLayoutSize = size.clone();

    final savedModels = preserveModels
        ? _pieces.map((p) => p.model.clone()).toList()
        : _level.initialPieces.map((p) => p.clone()).toList();

    _boardStage.removeAll(_boardStage.children.toList());
    _pieces.clear();
    _tutorialHand = null;

    // Exact Unity ortho camera framing matching `ref_gameplay.png` (`7x8` centered at ~58% width)
    final widthRatio = _level.cols <= 5
        ? 0.56
        : _level.cols <= 7
            ? 0.585
            : 0.68;
    final topReserved = (size.y * 0.22).clamp(135.0, 235.0);
    final bottomReserved = (size.y * 0.24).clamp(155.0, 250.0);

    final availW = (size.x * widthRatio).clamp(120.0, 1000.0);
    final availH = (size.y - topReserved - bottomReserved).clamp(160.0, 1400.0);
    final maxCellByScreen = (size.x * 0.118).clamp(32.0, 62.0);

    _cellSize = math
        .min(availW / _level.cols, availH / _level.rows)
        .clamp(24.0, maxCellByScreen);

    final boardW = _level.cols * _cellSize;
    final boardH = _level.rows * _cellSize;

    _boardStage.position = Vector2(
      size.x * 0.5,
      topReserved + availH * 0.50,
    );
    _boardOrigin = Vector2(-boardW * 0.5, -boardH * 0.5);

    final board = BoardComponent(
      level: _level,
      cellSize: _cellSize,
      position: _boardOrigin.clone(),
    );
    _boardComponent = board;
    _boardStage.add(board);

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
    }

    if (!preserveModels) {
      _introTimer = 0.0;
      _winZoomTimer = -1.0;
      _stageZoom = 0.92;
      _boardStage.scale = Vector2.all(_stageZoom);
      _maybeSpawnTutorialHand();
    }

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
    );
    _tutorialHand = hand;
    _boardStage.add(hand);
  }

  void _notifyFirstAction() {
    if (_firstActionTriggered) return;
    _firstActionTriggered = true;
    _tutorialHand?.removeFromParent();
    _tutorialHand = null;
    onFirstAction?.call();
  }

  Vector2 _canvasToStage(Vector2 canvasPos) {
    final z = _stageZoom <= 1e-4 ? 1.0 : _stageZoom;
    return (canvasPos - _boardStage.position) / z;
  }

  PieceComponent? _hitTestPiece(Vector2 stagePos) {
    final gx = (stagePos.x - _boardOrigin.x) / _cellSize;
    final gy = (stagePos.y - _boardOrigin.y) / _cellSize;
    final col = gx.floor();
    final row = gy.floor();

    // 1. Exact grid cell match
    for (final p in _pieces) {
      if (p.isFlyingOrSwallowed) continue;
      if (p.model.worldCells.contains((col, row))) {
        return p;
      }
    }

    // 2. Generous 0.24-cell bevel tolerance for comfortable thumb play
    PieceComponent? closest;
    double bestDist = _cellSize * 0.24;
    for (final p in _pieces) {
      if (p.isFlyingOrSwallowed) continue;
      for (final (c, r) in p.model.worldCells) {
        final rect = Rect.fromLTWH(
          _boardOrigin.x + c * _cellSize,
          _boardOrigin.y + r * _cellSize,
          _cellSize,
          _cellSize,
        );
        final clampedX = stagePos.x.clamp(rect.left, rect.right);
        final clampedY = stagePos.y.clamp(rect.top, rect.bottom);
        final d = math.sqrt(
          math.pow(stagePos.x - clampedX, 2) +
              math.pow(stagePos.y - clampedY, 2),
        );
        if (d < bestDist) {
          bestDist = d;
          closest = p;
        }
      }
    }
    return closest;
  }

  bool get _canInteract =>
      _isReady &&
      !isModalPaused &&
      !_hasWon &&
      !_hasLost &&
      _levelUpFlight == null;

  @override
  void onTapDown(TapDownEvent event) {
    if (!_canInteract) return;
    final stagePos = _canvasToStage(event.canvasPosition);
    final hit = _hitTestPiece(stagePos);
    if (hit == null) return;

    if (!hit.model.canBeDragged) {
      hit.triggerBlockedShake();
      audio.hapticBlocked();
    } else {
      hit.triggerTapSquish();
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (!_canInteract || _activePointerId != null) return;

    final stagePos = _canvasToStage(event.canvasPosition);
    final hit = _hitTestPiece(stagePos);
    if (hit == null) return;

    if (!hit.model.canBeDragged) {
      hit.triggerBlockedShake();
      audio.hapticBlocked();
      return;
    }

    _activePointerId = event.pointerId;
    _draggedPiece = hit;
    _dragStartCol = hit.model.col;
    _dragStartRow = hit.model.row;
    final pieceGridOrigin =
        hit.targetWorldOriginForGrid(hit.model.col, hit.model.row);
    _grabOffsetFromPieceOrigin = stagePos - pieceGridOrigin;

    hit.isDragging = true;
    hit.setDragTargetWorld(pieceGridOrigin);
    hit.triggerTapSquish();
    audio.playGrab();

    _updateBoardHighlight(hit);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _activePointerId) return;
    if (!_canInteract || _draggedPiece == null) {
      _cancelDrag(silent: true);
      return;
    }

    final piece = _draggedPiece!;
    final stagePos = _canvasToStage(event.canvasEndPosition);
    final rawDesiredOrigin = stagePos - _grabOffsetFromPieceOrigin;

    _stepSlideAndEvaluateMerge(piece, rawDesiredOrigin);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_activePointerId == null) return;
    _finishDrag();
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    _cancelDrag(silent: true);
  }

  void _finishDrag() {
    final dragged = _draggedPiece;
    final candidate = _mergeCandidate;
    final pushDir = _mergePushDir;

    if (dragged != null && candidate != null) {
      _commitMerge(dragged: dragged, target: candidate, pushDir: pushDir);
      return;
    }

    if (dragged != null) {
      final moved = dragged.model.col != _dragStartCol ||
          dragged.model.row != _dragStartRow;
      dragged.isDragging = false;
      dragged.snapDragTargetToModelGrid();
      if (moved) {
        _notifyFirstAction();
        audio.playPut();
      }
    }
    _clearMergeCandidate();
    _boardComponent?.highlightedCells = null;
    _draggedPiece = null;
    _activePointerId = null;
  }

  void _cancelDrag({required bool silent}) {
    if (_draggedPiece != null) {
      _draggedPiece!.isDragging = false;
      _draggedPiece!.snapDragTargetToModelGrid();
      if (!silent) audio.playPut();
    }
    _clearMergeCandidate();
    _boardComponent?.highlightedCells = null;
    _draggedPiece = null;
    _activePointerId = null;
  }

  void _updateBoardHighlight(PieceComponent piece) {
    final style = palette.styleFor(
      number: piece.model.number,
      isFrozen: piece.model.isFrozen,
    );
    _boardComponent
      ?..highlightedCells = piece.model.worldCells
      ..highlightColor = style.topBright;
  }

  bool _canOccupy(PieceModel moving, int testCol, int testRow) {
    final testCells = moving.worldCellsAt(testCol, testRow);
    for (final (c, r) in testCells) {
      if (!_level.isPlayableCell(c, r)) return false;
    }
    for (final other in _pieces) {
      if (other.isFlyingOrSwallowed || other.model.id == moving.id) continue;
      final otherCells = other.model.worldCells;
      for (final cell in testCells) {
        if (otherCells.contains(cell)) return false;
      }
    }
    return true;
  }

  PieceComponent? _findAdjacentMergeTarget(
    PieceModel moving,
    int dirC,
    int dirR,
  ) {
    if (!moving.canMerge || (dirC == 0 && dirR == 0)) return null;
    final shiftedCells = moving.worldCellsAt(moving.col + dirC, moving.row + dirR);

    PieceComponent? matched;
    for (final other in _pieces) {
      if (other.isFlyingOrSwallowed || other.model.id == moving.id) continue;
      if (!other.model.canMerge || other.model.number != moving.number) continue;

      final otherCells = other.model.worldCells;
      bool touches = false;
      for (final c in shiftedCells) {
        if (otherCells.contains(c)) {
          touches = true;
          break;
        }
      }
      if (touches) {
        matched = other;
        break;
      }
    }
    return matched;
  }

  void _clearMergeCandidate() {
    if (_mergeCandidate != null) {
      _mergeCandidate!.isMergeCandidate = false;
      _mergeCandidate!.previewMergedNumber = null;
      _mergeCandidate = null;
    }
    _mergePushDir = (0, 0);
  }

  void _setMergeCandidate(
    PieceComponent target,
    int mergedPreview,
    GridCell dir,
  ) {
    if (_mergeCandidate != target) {
      _clearMergeCandidate();
      _mergeCandidate = target;
      target.isMergeCandidate = true;
      target.previewMergedNumber = mergedPreview;
      _mergePushDir = dir;
      audio.playAttract();
    } else {
      target.previewMergedNumber = mergedPreview;
      _mergePushDir = dir;
    }
  }

  void _stepSlideAndEvaluateMerge(
    PieceComponent comp,
    Vector2 rawDesiredOrigin,
  ) {
    final model = comp.model;
    final allowsH = model.movement.allowsHorizontal;
    final allowsV = model.movement.allowsVertical;

    double desiredColF = allowsH
        ? (rawDesiredOrigin.x - _boardOrigin.x) / _cellSize
        : model.col.toDouble();
    double desiredRowF = allowsV
        ? (rawDesiredOrigin.y - _boardOrigin.y) / _cellSize
        : model.row.toDouble();

    bool movedGridCell = false;
    for (int step = 0; step < 16; step++) {
      final dx = desiredColF - model.col;
      final dy = desiredRowF - model.row;
      if (dx.abs() < 0.50 && dy.abs() < 0.50) break;

      bool advanced = false;
      final preferX = dx.abs() >= dy.abs();

      if (preferX) {
        if (allowsH && dx.abs() >= 0.50) {
          final sc = dx > 0 ? 1 : -1;
          if (_canOccupy(model, model.col + sc, model.row)) {
            model.col += sc;
            advanced = true;
          }
        }
        if (!advanced && allowsV && dy.abs() >= 0.50) {
          final sr = dy > 0 ? 1 : -1;
          if (_canOccupy(model, model.col, model.row + sr)) {
            model.row += sr;
            advanced = true;
          }
        }
      } else {
        if (allowsV && dy.abs() >= 0.50) {
          final sr = dy > 0 ? 1 : -1;
          if (_canOccupy(model, model.col, model.row + sr)) {
            model.row += sr;
            advanced = true;
          }
        }
        if (!advanced && allowsH && dx.abs() >= 0.50) {
          final sc = dx > 0 ? 1 : -1;
          if (_canOccupy(model, model.col + sc, model.row)) {
            model.col += sc;
            advanced = true;
          }
        }
      }

      if (advanced) {
        movedGridCell = true;
      } else {
        break;
      }
    }

    if (movedGridCell) {
      _notifyFirstAction();
      _updateBoardHighlight(comp);
    }

    final remX = allowsH ? (desiredColF - model.col) : 0.0;
    final remY = allowsV ? (desiredRowF - model.row) : 0.0;

    double visualOffsetX = 0.0;
    double visualOffsetY = 0.0;

    PieceComponent? bestCandidate;
    double bestPushStrength = 0.0;
    GridCell bestDir = (0, 0);

    if (remX.abs() > 0.005) {
      final dirX = remX > 0 ? 1 : -1;
      if (_canOccupy(model, model.col + dirX, model.row)) {
        visualOffsetX = remX.clamp(-0.50, 0.50);
      } else {
        final adj = _findAdjacentMergeTarget(model, dirX, 0);
        if (adj != null) {
          final push = remX.abs();
          visualOffsetX = dirX * math.min(push * 0.55, 0.34);
          if (push > bestPushStrength) {
            bestPushStrength = push;
            bestCandidate = adj;
            bestDir = (dirX, 0);
          }
        } else {
          visualOffsetX = dirX * math.min(remX.abs() * 0.08, 0.055);
        }
      }
    }

    if (remY.abs() > 0.005) {
      final dirY = remY > 0 ? 1 : -1;
      if (_canOccupy(model, model.col, model.row + dirY)) {
        visualOffsetY = remY.clamp(-0.50, 0.50);
      } else {
        final adj = _findAdjacentMergeTarget(model, 0, dirY);
        if (adj != null) {
          final push = remY.abs();
          visualOffsetY = dirY * math.min(push * 0.55, 0.34);
          if (push > bestPushStrength) {
            bestPushStrength = push;
            bestCandidate = adj;
            bestDir = (0, dirY);
          }
        } else {
          visualOffsetY = dirY * math.min(remY.abs() * 0.08, 0.055);
        }
      }
    }

    if (visualOffsetX.abs() > 0.08 && visualOffsetY.abs() > 0.08) {
      final sx = visualOffsetX > 0 ? 1 : -1;
      final sy = visualOffsetY > 0 ? 1 : -1;
      if (!_canOccupy(model, model.col + sx, model.row + sy)) {
        if (visualOffsetX.abs() >= visualOffsetY.abs()) {
          visualOffsetY = 0.0;
        } else {
          visualOffsetX = 0.0;
        }
      }
    }

    comp.setDragTargetWorld(
      Vector2(
        _boardOrigin.x + (model.col + visualOffsetX) * _cellSize,
        _boardOrigin.y + (model.row + visualOffsetY) * _cellSize,
      ),
    );

    if (bestCandidate != null && bestPushStrength >= 0.18) {
      final previewVal = (model.number ?? 2) * 2;
      _setMergeCandidate(bestCandidate, previewVal, bestDir);
      if (bestPushStrength >= 0.46) {
        _commitMerge(dragged: comp, target: bestCandidate, pushDir: bestDir);
      }
    } else {
      _clearMergeCandidate();
    }
  }

  void _commitMerge({
    required PieceComponent dragged,
    required PieceComponent target,
    required GridCell pushDir,
  }) {
    _notifyFirstAction();

    dragged.isDragging = false;
    dragged.snapDragTargetToModelGrid();
    _clearMergeCandidate();
    _boardComponent?.highlightedCells = null;
    _draggedPiece = null;
    _activePointerId = null;

    final draggedCells = dragged.model.localCells.length;
    final targetCells = target.model.localCells.length;
    final PieceComponent survivor =
        draggedCells > targetCells ? dragged : target;
    final PieceComponent consumed = survivor == dragged ? target : dragged;

    final oldStyle = palette.styleFor(
      number: survivor.model.number,
      isFrozen: false,
    );
    final newNumber = (survivor.model.number ?? 2) * 2;
    final combinedMovement =
        survivor.model.movement.resolveMergedWith(consumed.model.movement);

    survivor.model.number = newNumber;
    survivor.model.movement = combinedMovement;
    survivor.snapDragTargetToModelGrid();

    _pieces.remove(consumed);
    consumed.isFlyingOrSwallowed = true;
    consumed.priority = 98;

    final contactWorld = (survivor.worldCenter + consumed.worldCenter) * 0.5;
    final swallowEndOrigin = survivor.worldCenter -
        Vector2(
          consumed.size.x * 0.5,
          consumed.size.y * 0.5,
        );
    _swallowedAnims.add(
      _SwallowedPieceAnim(
        piece: consumed,
        startPos: consumed.position.clone(),
        endPos: swallowEndOrigin,
      ),
    );

    survivor.triggerMergeAbsorb(
      oldStyle: oldStyle,
      worldContactPoint: contactWorld,
    );

    final newStyle = palette.styleFor(number: newNumber, isFrozen: false);
    _boardStage.add(
      MergeSplashVfx(
        centerPos: contactWorld,
        primaryColor: newStyle.topMid,
        accentColor: newStyle.topBright,
        cellSize: _cellSize,
      ),
    );
    audio.playMerge();

    _unlockEligibleIceBlocks(newNumber);
    _refreshCanLevelUp();
    _checkWinCondition();
  }

  void _unlockEligibleIceBlocks(int mergedNumber) {
    bool anyShattered = false;
    for (final p in _pieces) {
      if (p.isFlyingOrSwallowed) continue;
      final target = p.model.iceTarget;
      if (target != null && target <= mergedNumber) {
        p.model.iceTarget = null;
        p.triggerIceUnfroze();
        _boardStage.add(
          IceShatterVfx(
            centerPos: p.worldCenter,
            cellSize: _cellSize,
          ),
        );
        anyShattered = true;
      }
    }
    if (anyShattered) {
      audio.playIceBreak();
    }
  }

  (PieceComponent spent, PieceComponent kept)? _findLowestMergeablePair() {
    final groups = <int, List<PieceComponent>>{};
    for (final p in _pieces) {
      if (p.isFlyingOrSwallowed || !p.model.canMerge) continue;
      final n = p.model.number;
      if (n == null) continue;
      groups.putIfAbsent(n, () => []).add(p);
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
        if (a.model.movement.isPinned != b.model.movement.isPinned) {
          return a.model.movement.isPinned ? 1 : -1;
        }
        return a.model.id.compareTo(b.model.id);
      });

    final spent = candidates.first;
    final kept = candidates.last;
    return (spent, kept);
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

    _cancelDrag(silent: true);
    _notifyFirstAction();

    final (spent, kept) = pair;
    _pieces.remove(spent);
    spent.isFlyingOrSwallowed = true;
    spent.priority = 130;
    kept.levelUpTargetGlow = 1.0;

    final style = palette.styleFor(number: spent.model.number, isFrozen: false);
    _levelUpFlight = _LevelUpFlightAnim(
      spent: spent,
      kept: kept,
      startOrigin: spent.position.clone(),
      liftHeight: _cellSize * 1.15,
      liftDur: 0.35,
      travelDur: 0.50,
      sparkColor: style.topBright,
    );
    audio.playLevelUpArrow();
    audio.playLevelUpFly();
    _refreshCanLevelUp();
    return true;
  }

  /// Triggers the `Time Freeze` Power-Up (`20s` icy timer pause).
  bool triggerTimeFreezePowerUp() {
    if (!_canInteract || _level.timerDisabled) return false;
    if (timeFreezeNotifier.value > 1.0) return false;
    timeFreezeNotifier.value = maxTimeFreezeSeconds;
    audio.playTimeFreeze();
    return true;
  }

  void _checkWinCondition() {
    if (_hasWon || _hasLost) return;
    int numberedRemaining = 0;
    for (final p in _pieces) {
      if (!p.isFlyingOrSwallowed && !p.model.isDud) {
        numberedRemaining++;
      }
    }
    if (numberedRemaining <= 1) {
      _hasWon = true;
      _winZoomTimer = 0.0;
      _winCallbackDelay = 0.44;
      _refreshCanLevelUp();
      audio.playWinComplete();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_isReady) return;
    final clampedDt = dt.clamp(0.0, 0.05);

    // 1. Camera Intro & Win Zoom
    if (_winZoomTimer >= 0) {
      _winZoomTimer += clampedDt;
      final t =
          (_winZoomTimer / visualSettings.cameraWinDuration).clamp(0.0, 1.0);
      final curveVal = visualSettings.cameraWinCurve.evaluate(t);
      _stageZoom = ui.lerpDouble(1.0, 1.075, curveVal.clamp(0.0, 1.2))!;
      _boardStage.scale = Vector2.all(_stageZoom);
    } else if (_introTimer < visualSettings.cameraIntroDuration) {
      _introTimer += clampedDt;
      final t =
          (_introTimer / visualSettings.cameraIntroDuration).clamp(0.0, 1.0);
      final eased = CurvesHelper.smoothStep(t);
      _stageZoom = ui.lerpDouble(0.92, 1.0, eased)!;
      _boardStage.scale = Vector2.all(_stageZoom);
    }

    // 2. Win overlay trigger delay
    if (_winCallbackDelay >= 0) {
      _winCallbackDelay -= clampedDt;
      if (_winCallbackDelay < 0) {
        onLevelWon();
      }
    }

    // 3. Swallowed consumed pieces animation
    for (int i = _swallowedAnims.length - 1; i >= 0; i--) {
      final anim = _swallowedAnims[i];
      anim.elapsed += clampedDt;
      final t = (anim.elapsed / _SwallowedPieceAnim.duration).clamp(0.0, 1.0);
      final eased = CurvesHelper.smoothStep(t);
      anim.piece.position = Vector2(
        ui.lerpDouble(anim.startPos.x, anim.endPos.x, eased)!,
        ui.lerpDouble(anim.startPos.y, anim.endPos.y, eased)!,
      );
      anim.piece.visualScale = ui.lerpDouble(1.0, 0.38, eased)!;
      anim.piece.visualOpacity = (1.0 - t * 0.85).clamp(0.0, 1.0);
      if (t >= 1.0) {
        anim.piece.removeFromParent();
        _swallowedAnims.removeAt(i);
      }
    }

    // 4. Cinematic `Level Up` Power-Up flight (`LevelUpVisualConfig.json`)
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
        final t = (flight.elapsed / flight.liftDur).clamp(0.0, 1.0);
        final e = CurvesHelper.smoothStep(t);
        flight.spent.position = Vector2(
          ui.lerpDouble(flight.startOrigin.x, liftedOrigin.x, e)!,
          ui.lerpDouble(flight.startOrigin.y, liftedOrigin.y, e)!,
        );
        flight.spent.visualScale = ui.lerpDouble(1.0, 1.15, e)!;
      } else {
        final travelElapsed = flight.elapsed - flight.liftDur;
        final t = (travelElapsed / flight.travelDur).clamp(0.0, 1.0);
        final e = t * t * (2.2 - 1.2 * t); // Accelerates smoothly into merge

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
        flight.spent.visualScale = ui.lerpDouble(1.15, 0.68, e)!;

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

    // 5. Countdown Timer & Time Freeze
    if (!isModalPaused && !_hasWon && !_hasLost && !_level.timerDisabled) {
      if (timeFreezeNotifier.value > 0) {
        timeFreezeNotifier.value =
            math.max(0.0, timeFreezeNotifier.value - clampedDt);
      } else if (_firstActionTriggered || _level.number > 3) {
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
  }

  void _completeLevelUpFlight(_LevelUpFlightAnim flight) {
    _levelUpFlight = null;
    final spent = flight.spent;
    final kept = flight.kept;
    spent.removeFromParent();
    kept.levelUpTargetGlow = 0.85;

    final oldStyle = palette.styleFor(
      number: kept.model.number,
      isFrozen: false,
    );
    final newNumber = (kept.model.number ?? 2) * 2;
    kept.model.number = newNumber;
    kept.model.movement =
        kept.model.movement.resolveMergedWith(spent.model.movement);

    final center = kept.worldCenter;
    kept.triggerMergeAbsorb(
      oldStyle: oldStyle,
      worldContactPoint: center,
    );
    final newStyle = palette.styleFor(number: newNumber, isFrozen: false);
    _boardStage.add(
      MergeSplashVfx(
        centerPos: center,
        primaryColor: newStyle.topMid,
        accentColor: newStyle.topBright,
        cellSize: _cellSize,
      ),
    );
    audio.playLevelUpMerge();

    _unlockEligibleIceBlocks(newNumber);
    _refreshCanLevelUp();
    _checkWinCondition();
  }
}
