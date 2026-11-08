import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame/components.dart' hide Matrix4;
import 'package:flame/flame.dart';
import 'package:flutter/material.dart';
import '../geometry/polyomino_path_builder.dart';
import '../models/level_models.dart';
import '../models/palette.dart';
import '../models/unity_curve.dart';
import 'vfx_components.dart';

enum _FollowState {
  nothing,
  dragging,
  snapping,
  absorbing,
  flying,
}

enum _NumberPreviewMode {
  idle,
  holdingSurvivor,
  holdingPartner,
  shrinkingAway,
  settling,
}

class _ResolvedPieceLabelLayout {
  final NumberLabelLayoutMode mode;
  final Offset labelCenterLocal;
  final double roomWidthPx;
  final double finalTmpFontSize;
  final DigitLayoutMetrics digitMetrics;
  final double arrowOrPinPushPx;
  final MovementArrowLayout? arrowLayout;

  const _ResolvedPieceLabelLayout({
    required this.mode,
    required this.labelCenterLocal,
    required this.roomWidthPx,
    required this.finalTmpFontSize,
    required this.digitMetrics,
    required this.arrowOrPinPushPx,
    required this.arrowLayout,
  });
}

class _BakedGlyphSprite {
  final ui.Image image;
  final Rect srcRect;
  final Rect dstRect;

  const _BakedGlyphSprite({
    required this.image,
    required this.srcRect,
    required this.dstRect,
  });
}

class _SharedPieceGeometry {
  final String key;
  final Path topPath;
  final Path wallPath;
  final Path innerHighlightPath;
  final Path liquidCavityPath;
  final Path inflatedLocalPath010;
  final Path iceSheenPath;
  final Rect localBounds;
  final Offset visualPivotLocal;
  final Offset labelAnchorLocal;
  final List<PinnedScrewAnchor> screwAnchors;
  final double lipDepth;
  final double shadowBakePad;
  final ui.Image? bakedShadowImage;

  const _SharedPieceGeometry({
    required this.key,
    required this.topPath,
    required this.wallPath,
    required this.innerHighlightPath,
    required this.liquidCavityPath,
    required this.inflatedLocalPath010,
    required this.iceSheenPath,
    required this.localBounds,
    required this.visualPivotLocal,
    required this.labelAnchorLocal,
    required this.screwAnchors,
    required this.lipDepth,
    required this.shadowBakePad,
    required this.bakedShadowImage,
  });
}

class _BakedStaticPieceSprite {
  final ui.Image image;
  final Rect srcRect;
  final Rect dstRect;

  const _BakedStaticPieceSprite({
    required this.image,
    required this.srcRect,
    required this.dstRect,
  });
}

class _SandSwarmGrain {
  double worldX;
  double worldY;
  double velX;
  double velY;
  final double homeLocalX;
  final double homeLocalY;
  final double size;
  double life;
  final double maxLife;
  double swirlPhase;
  final double swirlFreq;
  final int colorKind;
  final bool isDiamond;
  final bool isForeground;

  _SandSwarmGrain({
    required this.worldX,
    required this.worldY,
    required this.velX,
    required this.velY,
    required this.homeLocalX,
    required this.homeLocalY,
    required this.size,
    required this.life,
    required this.maxLife,
    required this.swirlPhase,
    required this.swirlFreq,
    required this.colorKind,
    required this.isDiamond,
    required this.isForeground,
  });
}

class PieceComponent extends PositionComponent {
  static const double _tmpUnitToCellRatio = 0.082;
  static const int _pinFitSteps = 12;

  static final Map<String, Size> _metricsTextSizeCache = <String, Size>{};
  static final Map<String, _BakedGlyphSprite> _fourLayerNumberSpriteCache =
      <String, _BakedGlyphSprite>{};
  static final Map<String, _BakedGlyphSprite> _frozenBadgeTextSpriteCache =
      <String, _BakedGlyphSprite>{};
  static final Map<String, _SharedPieceGeometry> _sharedGeometryCache =
      <String, _SharedPieceGeometry>{};
  static final Map<String, _BakedStaticPieceSprite> _sharedStaticPieceCache =
      <String, _BakedStaticPieceSprite>{};

  static int _frameBakeBudget = 3;

  /// Resets the per-frame GPU texture bake budget so static piece caching never
  /// causes a single-frame spike on large boards.
  static void resetFrameBakeBudget([int budget = 3]) {
    _frameBakeBudget = budget;
  }

  // Pure white R8 channel mask: `BlendMode.srcOver` is mathematically 100% identical
  // to `BlendMode.screen` (`out = a + dst * (1 - a)`) without mobile tile-GPU readback.
  static final Paint _iceFrostPaint = Paint()
    ..blendMode = BlendMode.srcOver
    ..colorFilter = UnityChannelMaskFilters.redChannelTint(
      Colors.white,
      opacity: 0.28,
    );
  static final Paint _iceSheenPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.18)
    ..style = PaintingStyle.fill;
  static final Paint _screwBoltPaint = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = const ColorFilter.mode(
      Color(0xFFE4ECFA),
      BlendMode.modulate,
    );
  static final Paint _screwFallbackCirclePaint = Paint()
    ..color = const Color(0xFFD5E0F5);
  static final Paint _arrowTopPaint = Paint()
    ..filterQuality = FilterQuality.medium;

  final PieceModel model;
  final double cellSize;
  final BlockOrderPalette palette;
  final PieceVisualSettings visualSettings;
  final Vector2 boardOrigin;
  final math.Random _rng = math.Random();

  late _SharedPieceGeometry _sharedGeom;
  late Path _topPath;
  late Path _wallPath;
  late Path _innerHighlightPath;
  late Path _liquidCavityPath;
  late Path _inflatedLocalPath010;
  late Rect _localBounds;
  late Offset _visualPivotLocal; // PieceBlockGeometry.FootprintCenterLocal
  late Offset _labelAnchorLocal; // PieceBlockGeometry.LabelAnchorLocal
  late List<PinnedScrewAnchor> _screwAnchors;
  late double _lipDepth;

  ui.Image? _bakedShadowImage;
  double _shadowBakePad = 0.0;
  bool _usedStaticSpriteLastRender = false;
  bool _isBakingGlassShellOnly = false;
  Path? _lastLiquidWaveClipPath;
  Offset _slideStreakVel = Offset.zero;

  _ResolvedPieceLabelLayout? _cachedBaseLabelLayout;
  int? _cachedBaseLayoutNumber;
  MovementConstraint? _cachedBaseLayoutMovement;
  _ResolvedPieceLabelLayout? _cachedPreviewLabelLayout;
  int? _cachedPreviewLayoutNumber;
  MovementConstraint? _cachedPreviewLayoutMovement;

  final Paint _shadowDrawPaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _glyphSpritePaint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _staticPiecePaint = Paint()..filterQuality = FilterQuality.medium;

  // Base displayed appearance (deferred during 0.30s MergeColorTransition expansion!)
  late BlockColorStyle _displayedAppearanceStyle;

  // Exact `PieceBlock` GLSL `_MergeCylinder` & `_MergeOverlap` shader state
  Vector2 _mergeCylinderWorldCenter = Vector2.zero();
  double _mergeCylinderRadius = 0.0;
  double _mergeCylinderSoftness = 1.0;
  BlockColorStyle? _mergeCylinderTargetStyle;

  double _mergeOverlapStrength = 0.0;
  Path? _mergeOverlapPartnerWorldPath;
  Path? _mergeOverlapPartnerLocalPath;
  Vector2? _mergeOverlapPartnerWorldOrigin;
  Color? _mergeOverlapTopTargetColor;

  // Exact `PieceFollow` state
  _FollowState _followState = _FollowState.nothing;
  Vector2 _visualGridPos;
  Vector2 _dragTargetPos;
  Vector2 _railWorldPos = Vector2.zero();
  bool _allowsDragH = true;
  bool _allowsDragV = true;
  bool isDragging = false;
  double _currentZLiftCells = 0.0;

  // Exact `PieceFollow.BeginAbsorb` (`0.28s` linear center + uniform `1 -> 0` scale)
  Vector2 _absorbFromCenter = Vector2.zero();
  Vector2 _absorbToCenter = Vector2.zero();
  double _absorbDuration = 0.28;
  double _absorbElapsed = 0.0;
  bool _areComponentsRemovedForAbsorb = false;

  // Sloshing Water Physics (`FakeWater` / `ANIM_SONG_SANH`) & Deformer state:
  Offset _jellyLean = Offset.zero;
  Offset _jellyVel = Offset.zero;
  Offset _jellyDeformWritten = Offset.zero;
  final List<_SandSwarmGrain> _sandSwarmGrains = <_SandSwarmGrain>[];
  final List<Offset> _sandTrailCentersWorld = <Offset>[];
  Vector2? _prevSandWorldPos;
  Offset _sandTravelDir = const Offset(1.0, 0.0);
  double _waterSloshTilt = 0.0;
  double _waterSloshVel = 0.0;
  double _sandErosionIntensity = 0.0;
  double _sandReformFlash = 0.0;
  double _sandShimmerClock = 0.0;
  double _liquidWavePhase = 0.0;
  double _smoothedWaveEnergy = 0.0;
  int _lastSandGridCol = -999;
  int _lastSandGridRow = -999;
  final Paint _sandErosionPaint = Paint();

  // `PieceFollow.PlayLeanImpulse` (`MergeSurvivorStaysImpulseCurve`)
  Offset _leanImpulseDir = Offset.zero;
  double _leanImpulseDuration = 0.0;
  double _leanImpulseElapsed = -1.0;
  Offset _leanImpulseLag = Offset.zero;

  // `PieceFollow.PulseAsync` (`MergeSurvivorMoves` / `MergeSurvivorStays`)
  double _mergePulseScale = 1.0;
  double _mergePulseElapsed = -1.0;
  double _mergePulseDuration = 0.28;
  double _mergePulsePeakScale = 1.0;
  UnityCurve? _mergePulseCurve;

  // Tap wiggle (`PlayTapBounce`) & Blocked 2D random jitter (`ShakeAsync`)
  double _tapElapsed = -1.0;
  double _tapScaleZ = 1.0;
  double _tapInflate = 0.0;

  double _shakeElapsed = -1.0;
  double _shakeRangeMultiplier = 1.0;
  Offset _shakeOffsetPx = Offset.zero;

  // Exact Hold-to-Merge Candidate Z-Pulse & Push Inflate (`PieceFollow.TickMergeCandidate`)
  bool isSurvivorCandidate = false;
  bool isPartnerCandidate = false;
  double _candidatePulseScaleZ = 1.0;
  double _candidateLiftCells = 0.0;
  double _liftFromCells = 0.0;
  double _liftToCells = 0.0;
  bool _isPulsePlaying = false;
  bool _isPulseReleasing = false;
  double _pulseElapsed = 0.0;
  double _releaseElapsed = 0.0;
  double _pulseStartOffsetZ = 0.0;
  double _releaseStartOffsetZ = 0.0;

  double _candidatePush = 0.0;
  double _candidateInflate = 0.0;
  double _releaseFromInflate = 0.0;
  double _inflateReleaseElapsed = 0.0;
  bool _isInflateReleasing = false;

  // Exact `MergeNumberPreview` (`BeginAsSurvivor`, `BeginAsPartner`, `ShrinkAway`, `Settle`)
  _NumberPreviewMode _numberPreviewMode = _NumberPreviewMode.idle;
  int? _activePreviewNumber;
  double _numberPreviewPush = 0.0;
  double _shrinkAwayStartPush = 0.0;
  double _settleReleaseGap = 0.0;
  double _numberPreviewTimer = 0.0;
  double _normalNumberSizeFactor = 1.0;
  double _previewNumberSizeFactor = 0.0;

  // `ScaleSwapAnimator.ShrinkAsync` (`1.0 - MovementStationaryAnchorShrinkCurve`)
  List<PinnedScrewAnchor>? _shrinkingScrewAnchors;
  double _shrinkingScrewPinPushPx = 0.0;
  BlockColorStyle? _shrinkingScrewStyle;
  double _screwShrinkTimer = -1.0;

  // `IceComponentView` (`FaceCover` + `0.3833s` `"Pop"` clip -> `BreakIce` -> `1.5x` Shake)
  bool _isIceCovered = false;
  int? _displayIceTarget;
  double _icePopTimer = -1.0;
  VoidCallback? _onIceShatterCallback;

  // Level-Up cyan target aura (`LevelUpVisualConfig.json`: `GlowColor: #00BFFF`)
  double levelUpTargetGlow = 0.0;

  // Swallowed / Level-Up flight override
  bool isFlyingOrSwallowed = false;
  double visualScale = 1.0;
  double visualScaleXMultiplier = 1.0;
  double visualScaleYMultiplier = 1.0;
  double visualOpacity = 1.0;

  ui.Image? _iceLockImg;
  ui.Image? _iceBlocksTex;
  ui.Image? _screwFallbackImg;
  ui.Image? _arrowShadowImg;
  ui.Image? _arrowOutlineImg;
  ui.Image? _arrowTopImg;
  ui.Image? _arrowHorizCombinedImg;
  ui.Image? _arrowVertCombinedImg;
  ui.Image? _glowImg;

  // Cached GPU Paints & Shaders (zero per-frame allocations for stationary & dragged pieces!)
  (Color, Color, bool, int)? _cachedBodyStyleKey;
  final Paint _cachedWallPaint = Paint();
  final Paint _cachedBaseStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _cachedTopPaint = Paint();
  final Paint _cachedRimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  (Color, Color, int)? _cachedReflKey;
  final Paint _cachedReflPaint = Paint();

  final Paint _outerContourPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.15;
  final Paint _auraPaint = Paint()..blendMode = BlendMode.plus;
  final Paint _opacityLayerPaint = Paint();
  final Paint _fallbackShadowPaint = Paint();
  final Paint _mergeOverlapPaint = Paint();
  final Paint _cylinderTopPaint = Paint();
  final Paint _screwShadowPaint = Paint();
  final Paint _arrowShadowPaint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _arrowStrokePaint = Paint()..filterQuality = FilterQuality.medium;
  Color? _cachedArrowShadowColor;
  Color? _cachedArrowStrokeColor;

  PieceComponent({
    required this.model,
    required this.cellSize,
    required this.palette,
    required this.visualSettings,
    required this.boardOrigin,
  })  : _visualGridPos = Vector2(model.col.toDouble(), model.row.toDouble()),
        _dragTargetPos = Vector2(
          boardOrigin.x + model.col * cellSize,
          boardOrigin.y + model.row * cellSize,
        ),
        super(
          position: Vector2(
            boardOrigin.x + model.col * cellSize,
            boardOrigin.y + model.row * cellSize,
          ),
          size: Vector2(
            model.widthCols * cellSize,
            model.heightRows * cellSize,
          ),
          priority: 10 + (model.row + model.heightRows - 1) * 2,
        ) {
    _isIceCovered = model.isFrozen;
    _displayIceTarget = model.iceTarget;
    _displayedAppearanceStyle = palette.styleFor(
      number: model.number,
      isFrozen: _isIceCovered,
    );
    _railWorldPos = position.clone();
    _liquidWavePhase = (model.id * 1.93) % (math.pi * 2.0);
    _rebuildCachedGeometry();
    _cacheSprites();
  }

  bool get isMergeCandidate => isSurvivorCandidate || isPartnerCandidate;

  int? get previewMergedNumber =>
      isSurvivorCandidate ? _activePreviewNumber : null;

  bool get isAbsorbFinished =>
      _followState != _FollowState.absorbing && _areComponentsRemovedForAbsorb;

  /// Cached local inflated silhouette (`inflate = 0.10 * cellSize`) so
  /// `_drawMergeOverlapSeamFusion` never allocates `Path.shift` per frame.
  Path get localInflatedSilhouette010 => _inflatedLocalPath010;

  bool get _isAtExactGridTarget =>
      (position.x - (boardOrigin.x + model.col * cellSize)).abs() <= 0.05 &&
      (position.y - (boardOrigin.y + model.row * cellSize)).abs() <= 0.05;

  double _winFractureProgress = 0.0;
  double _winCrumbleProgress = 0.0;

  @visibleForTesting
  double get debugWinCrumbleProgress => _winCrumbleProgress;

  /// True when the piece has zero active physics, jelly lean, lift, pulse,
  /// shader wipe, seam overlap, number preview, screw shrink, or ice pop,
  /// allowing single-quad GPU texture rendering and idle physics bypass.
  bool get isVisuallyAtRest =>
      _followState == _FollowState.nothing &&
      !isDragging &&
      !isFlyingOrSwallowed &&
      !_areComponentsRemovedForAbsorb &&
      !isSurvivorCandidate &&
      !isPartnerCandidate &&
      _isAtExactGridTarget &&
      (visualScale - 1.0).abs() < 1e-4 &&
      (visualScaleXMultiplier - 1.0).abs() < 1e-4 &&
      (visualScaleYMultiplier - 1.0).abs() < 1e-4 &&
      visualOpacity >= 0.999 &&
      _mergePulseElapsed < 0 &&
      (_mergePulseScale - 1.0).abs() < 1e-4 &&
      !_isPulsePlaying &&
      !_isPulseReleasing &&
      (_candidatePulseScaleZ - 1.0).abs() < 1e-4 &&
      _tapElapsed < 0 &&
      (_tapScaleZ - 1.0).abs() < 1e-4 &&
      !_isInflateReleasing &&
      _candidateInflate.abs() < 1e-4 &&
      _tapInflate.abs() < 1e-4 &&
      _currentZLiftCells.abs() < 1e-4 &&
      _candidateLiftCells.abs() < 1e-4 &&
      _jellyDeformWritten.distanceSquared < 1e-7 &&
      _jellyVel.distanceSquared < 1e-6 &&
      _leanImpulseElapsed < 0 &&
      _shakeElapsed < 0 &&
      _shakeOffsetPx.distanceSquared < 1e-4 &&
      levelUpTargetGlow <= 0.005 &&
      (_mergeCylinderRadius <= 0.2 || _mergeCylinderTargetStyle == null) &&
      _mergeOverlapStrength <= 0.005 &&
      _numberPreviewMode == _NumberPreviewMode.idle &&
      _activePreviewNumber == null &&
      (_normalNumberSizeFactor - 1.0).abs() < 1e-4 &&
      _previewNumberSizeFactor <= 0.005 &&
      _screwShrinkTimer < 0 &&
      _icePopTimer < 0 &&
      _waterSloshTilt.abs() < 1e-3 &&
      _waterSloshVel.abs() < 1e-2 &&
      _sandSwarmGrains.isEmpty &&
      _sandErosionIntensity <= 0.005 &&
      _sandReformFlash <= 0.005 &&
      _winFractureProgress <= 0.001 &&
      _winCrumbleProgress <= 0.001;

  @visibleForTesting
  bool get debugHasStaticBakedSprite {
    final baseStyle = _isIceCovered
        ? palette.styleFor(number: model.number, isFrozen: true)
        : _displayedAppearanceStyle;
    return _sharedStaticPieceCache
        .containsKey(_computeStaticPieceCacheKey(baseStyle));
  }

  @visibleForTesting
  bool get debugUsedStaticSpriteLastRender => _usedStaticSpriteLastRender;

  @visibleForTesting
  double get debugMergeCylinderRadius => _mergeCylinderRadius;

  @visibleForTesting
  double get debugMergeOverlapStrength => _mergeOverlapStrength;

  @visibleForTesting
  double get debugNormalNumberScaleFactor => _normalNumberSizeFactor;

  @visibleForTesting
  double get debugPreviewNumberScaleFactor => _previewNumberSizeFactor;

  @visibleForTesting
  bool get debugIsPreviewShrinkingAway =>
      _numberPreviewMode == _NumberPreviewMode.shrinkingAway;

  @visibleForTesting
  bool get debugIsIceCovered => _isIceCovered;

  @visibleForTesting
  double get debugShrinkingScrewScale {
    if (_screwShrinkTimer < 0) return 0.0;
    final dur = math.max(0.01, visualSettings.stationaryAnchorShrinkDuration);
    final t = (_screwShrinkTimer / dur).clamp(0.0, 1.0);
    return (1.0 - visualSettings.stationaryAnchorShrinkCurve.evaluate(t))
        .clamp(0.0, 1.0);
  }

  void _cacheSprites() {
    ui.Image? tryGet(String key) {
      if (!Flame.images.containsKey(key)) return null;
      try {
        return Flame.images.fromCache(key);
      } catch (_) {
        return null;
      }
    }

    _iceLockImg = tryGet('IceLock.png');
    _iceBlocksTex = tryGet('IceBlocks.png');
    _screwFallbackImg = tryGet('Screw_Greyscale_01.png');
    _arrowShadowImg = tryGet('Movement_Single-Horizontal_Shadow.png');
    _arrowOutlineImg = tryGet('Movement_Single-Horizontal_Stroke.png');
    _arrowTopImg = tryGet('Movement_Single-Horizontal_Top.png');
    _arrowHorizCombinedImg = tryGet('Movement_Double_Horizontal.png');
    _arrowVertCombinedImg = tryGet('Movement_Double_Vertical.png');
    _glowImg = tryGet('Glow_02.png');
  }

  @override
  void onRemove() {
    // `_bakedShadowImage` is owned by `_sharedGeometryCache` (LRU-managed).
    _bakedShadowImage = null;
    super.onRemove();
  }

  static String _buildShapeGeometryKey(List<GridCell> localCells, double cs) {
    if (localCells.length == 1) {
      final c = localCells.first;
      return '${c.$1},${c.$2}|${(cs * 20).round()}';
    }
    final sorted = List<GridCell>.from(localCells)
      ..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
    final sb = StringBuffer();
    for (int i = 0; i < sorted.length; i++) {
      if (i > 0) sb.write(';');
      sb
        ..write(sorted[i].$1)
        ..write(',')
        ..write(sorted[i].$2);
    }
    sb
      ..write('|')
      ..write((cs * 20).round());
    return sb.toString();
  }

  _SharedPieceGeometry _getOrBuildSharedGeometry() {
    final key = _buildShapeGeometryKey(model.localCells, cellSize);
    final existing = _sharedGeometryCache.remove(key);
    if (existing != null) {
      _sharedGeometryCache[key] = existing;
      return existing;
    }

    final localSet = model.localCells.toSet();
    final gapInset = cellSize * 0.013;
    final lipDepth = cellSize * 0.235;

    final topPath = PolyominoPathBuilder.buildRoundedPath(
      cells: localSet,
      cellSize: cellSize,
      inset: gapInset,
      cornerRadius: cellSize * 0.148,
      concaveRadius: cellSize * 0.096,
    );

    Path extruded = topPath.shift(Offset(0, lipDepth));
    for (final frac in const [0.22, 0.45, 0.68, 0.86]) {
      extruded = Path.combine(
        PathOperation.union,
        extruded,
        topPath.shift(Offset(0, lipDepth * frac)),
      );
    }
    final wallPath = extruded;

    final bevelInset = gapInset + (cellSize * 0.052).clamp(1.8, 5.2);
    final innerHighlightPath = PolyominoPathBuilder.buildRoundedPath(
      cells: localSet,
      cellSize: cellSize,
      inset: bevelInset,
      cornerRadius: cellSize * 0.115,
      concaveRadius: cellSize * 0.078,
    );

    final glassWallInset = gapInset + (cellSize * 0.028).clamp(1.4, 3.0);
    final liquidCavityPath = PolyominoPathBuilder.buildRoundedPath(
      cells: localSet,
      cellSize: cellSize,
      inset: glassWallInset,
      cornerRadius: cellSize * 0.132,
      concaveRadius: cellSize * 0.084,
    );

    final inflatedLocalPath010 = PolyominoPathBuilder.buildRoundedPath(
      cells: localSet,
      cellSize: cellSize,
      inset: -cellSize * 0.10,
      cornerRadius: cellSize * (0.148 + 0.10 * 0.5),
      concaveRadius: cellSize * 0.08,
    );

    final w = model.widthCols * cellSize;
    final h = model.heightRows * cellSize;
    final localBounds = Rect.fromLTWH(0, 0, w, h);

    final iceSheenPath = Path()
      ..moveTo(-h * 0.28, h)
      ..lineTo(w * 0.46, 0)
      ..lineTo(w * 0.68, 0)
      ..lineTo(-h * 0.06, h)
      ..close()
      ..moveTo(w * 0.36, h)
      ..lineTo(w + h * 0.22, 0)
      ..lineTo(w + h * 0.34, 0)
      ..lineTo(w * 0.48, h)
      ..close();

    final (fcx, fcy) = model.footprintCenterInCells();
    final visualPivotLocal = Offset(fcx * cellSize, fcy * cellSize);

    final (lcx, lcy) = model.computeLabelCenterInCells();
    final labelAnchorLocal = Offset(lcx * cellSize, lcy * cellSize);
    final screwAnchors = PolyominoPathBuilder.computePinnedScrewAnchors(
      cells: localSet,
      cellSize: cellSize,
    );

    final shadowBakePad = (cellSize * 0.24).ceilToDouble();
    final imgW = (localBounds.width + shadowBakePad * 2.0).ceil().clamp(2, 1024);
    final imgH = (localBounds.height + shadowBakePad * 2.0).ceil().clamp(2, 1024);
    ui.Image? shadowImg;
    try {
      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);
      recCanvas.translate(shadowBakePad, shadowBakePad);
      recCanvas.drawPath(
        topPath,
        Paint()
          ..color = const Color(0xFF02071A)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cellSize * 0.065),
      );
      final pic = recorder.endRecording();
      shadowImg = pic.toImageSync(imgW, imgH);
      pic.dispose();
    } catch (_) {
      shadowImg = null;
    }

    final geom = _SharedPieceGeometry(
      key: key,
      topPath: topPath,
      wallPath: wallPath,
      innerHighlightPath: innerHighlightPath,
      liquidCavityPath: liquidCavityPath,
      inflatedLocalPath010: inflatedLocalPath010,
      iceSheenPath: iceSheenPath,
      localBounds: localBounds,
      visualPivotLocal: visualPivotLocal,
      labelAnchorLocal: labelAnchorLocal,
      screwAnchors: screwAnchors,
      lipDepth: lipDepth,
      shadowBakePad: shadowBakePad,
      bakedShadowImage: shadowImg,
    );

    if (_sharedGeometryCache.length >= 64) {
      final oldest =
          _sharedGeometryCache.remove(_sharedGeometryCache.keys.first);
      oldest?.bakedShadowImage?.dispose();
    }
    _sharedGeometryCache[key] = geom;
    return geom;
  }

  void _rebuildCachedGeometry() {
    final geom = _getOrBuildSharedGeometry();
    _sharedGeom = geom;
    _topPath = geom.topPath;
    _wallPath = geom.wallPath;
    _innerHighlightPath = geom.innerHighlightPath;
    _liquidCavityPath = geom.liquidCavityPath;
    _inflatedLocalPath010 = geom.inflatedLocalPath010;
    _localBounds = geom.localBounds;
    _visualPivotLocal = geom.visualPivotLocal;
    _labelAnchorLocal = geom.labelAnchorLocal;
    _screwAnchors = geom.screwAnchors;
    _lipDepth = geom.lipDepth;
    _shadowBakePad = geom.shadowBakePad;
    _bakedShadowImage = geom.bakedShadowImage;

    _cachedBaseLabelLayout = null;
    _cachedPreviewLabelLayout = null;
    _cachedBodyStyleKey = null;
    _cachedReflKey = null;
  }

  void refreshGeometryForMovement() {
    _screwAnchors = _sharedGeom.screwAnchors;
    _cachedBaseLabelLayout = null;
    _cachedPreviewLabelLayout = null;
  }

  /// World-space center of the piece's visual pivot (`PieceView.VisualCenterWorld`).
  Vector2 get visualCenterWorld => Vector2(
        position.x + _visualPivotLocal.dx,
        position.y + _visualPivotLocal.dy,
      );

  /// World-space label anchor (`PieceBlockGeometry.LabelAnchorLocal`).
  Vector2 get worldCenter => Vector2(
        position.x + _labelAnchorLocal.dx,
        position.y + _labelAnchorLocal.dy,
      );

  List<Vector2> get worldCellCenters => model.worldCells
      .map(
        (cell) => Vector2(
          boardOrigin.x + (cell.$1 + 0.5) * cellSize,
          boardOrigin.y + (cell.$2 + 0.5) * cellSize,
        ),
      )
      .toList();

  /// Inflated world-space silhouette (`inflate = 0.10 * cellSize`) used by
  /// `RenderMergeOverlapMaskPass` to fuse overlapping survivor/partner seams.
  Path buildInflatedWorldSilhouette([double inflateCells = 0.10]) {
    if ((inflateCells - 0.10).abs() < 1e-4) {
      return _inflatedLocalPath010.shift(Offset(position.x, position.y));
    }
    return PolyominoPathBuilder.buildRoundedPath(
      cells: model.localCells.toSet(),
      cellSize: cellSize,
      inset: -cellSize * inflateCells,
      cornerRadius: cellSize * (0.148 + inflateCells * 0.5),
      concaveRadius: cellSize * 0.08,
    ).shift(Offset(position.x, position.y));
  }

  /// Exact world-space AABB corners of all occupied blocks (`MergeColorTransition.CoverRadius`).
  List<Vector2> computeWorldBlockCorners() {
    final pts = <Vector2>[];
    for (final (dc, dr) in model.localCells) {
      final x0 = position.x + dc * cellSize;
      final y0 = position.y + dr * cellSize;
      final x1 = x0 + cellSize;
      final y1 = y0 + cellSize + _lipDepth;
      pts
        ..add(Vector2(x0, y0))
        ..add(Vector2(x1, y0))
        ..add(Vector2(x0, y1))
        ..add(Vector2(x1, y1));
    }
    return pts;
  }

  Vector2 targetWorldOriginForGrid(int col, int row) => Vector2(
        boardOrigin.x + col * cellSize,
        boardOrigin.y + row * cellSize,
      );

  // --- PieceFollow Movement & Drag API ---

  void beginDragging() {
    isDragging = true;
    _followState = _FollowState.dragging;
    _allowsDragH = model.movement.allowsHorizontal;
    _allowsDragV = model.movement.allowsVertical;
    _railWorldPos = targetWorldOriginForGrid(model.col, model.row);
    _dragTargetPos = _railWorldPos.clone();
    if (!model.isDud) {
      _sandErosionIntensity = math.max(_sandErosionIntensity, 0.96);
      _waterSloshVel += (_waterSloshTilt >= 0 ? -1.0 : 1.0) * 5.5;
    }
  }

  void setDragTargetWorld(Vector2 worldOrigin) {
    _dragTargetPos = worldOrigin.clone();
  }

  void beginSnapping([Vector2? customWorldOrigin]) {
    isDragging = false;
    _followState = _FollowState.snapping;
    _dragTargetPos =
        customWorldOrigin?.clone() ?? targetWorldOriginForGrid(model.col, model.row);
  }

  void snapDragTargetToModelGrid() {
    beginSnapping(targetWorldOriginForGrid(model.col, model.row));
  }

  void beginFlying() {
    isDragging = false;
    isFlyingOrSwallowed = true;
    _followState = _FollowState.flying;
    _jellyLean = Offset.zero;
    _jellyVel = Offset.zero;
    _jellyDeformWritten = Offset.zero;
  }

  /// Exact match of `PieceView.AbsorbIntoAsync(worldDestination, 0.28f)`:
  /// Hides component overlays (`RemoveComponentPresentersAsync`) and linearly slides
  /// `visualCenterWorld` into `worldDestinationCenter` while shrinking uniform scale `1 -> 0`.
  void beginAbsorb({
    required Vector2 worldDestinationCenter,
    required double duration,
  }) {
    isDragging = false;
    isFlyingOrSwallowed = true;
    _followState = _FollowState.absorbing;
    _absorbFromCenter = visualCenterWorld.clone();
    _absorbToCenter = worldDestinationCenter.clone();
    _absorbDuration = math.max(0.01, duration);
    _absorbElapsed = 0.0;
    _areComponentsRemovedForAbsorb = true;
    _jellyLean = Offset.zero;
    _jellyVel = Offset.zero;
    _jellyDeformWritten = Offset.zero;
    finishNumberPreview();
  }

  // --- Micro-Juice: Tap Bounce & Blocked 2D Random Shake ---

  /// Exact match of `PieceView.PlayTapBounce()` + sloshing water impulse (`ANIM_SONG_SANH`): no-op on Dud blocks!
  void triggerTapSquish() {
    if (model.isDud) return;
    _tapElapsed = 0.0;
    _waterSloshVel += (_waterSloshTilt >= 0 ? -1.0 : 1.0) * 6.5;
    _sandErosionIntensity = math.max(_sandErosionIntensity, 0.94);
  }

  /// Exact match of `PieceFollow.ShakeAsync(rangeMultiplier)`:
  /// `0.20s` of per-frame random 2D XY jitter in `[-r, +r]` (`r = 0.03 * mult * cellSize`).
  void triggerBlockedShake([
    Offset dir = const Offset(1, 0),
    double rangeMultiplier = 1.0,
  ]) {
    _shakeElapsed = 0.0;
    _shakeRangeMultiplier = rangeMultiplier;
    _sampleRandomShakeOffset();
    if (!model.isDud) {
      final sign = dir.dx.abs() > 0.05 ? (dir.dx >= 0 ? -1.0 : 1.0) : 1.0;
      _waterSloshVel += sign * 7.8 * rangeMultiplier;
      _sandErosionIntensity = math.max(_sandErosionIntensity, 0.82);
    }
  }

  void _sampleRandomShakeOffset() {
    final r = visualSettings.shakeRange * _shakeRangeMultiplier * cellSize;
    _shakeOffsetPx = Offset(
      (_rng.nextDouble() * 2.0 - 1.0) * r,
      (_rng.nextDouble() * 2.0 - 1.0) * r,
    );
  }

  // --- Shader Cylinder, Overlap Seam & Appearance Handoff ---

  void setMergeCylinder({
    required Vector2 worldCenter,
    required double worldRadius,
    required double worldSoftness,
    required BlockColorStyle? targetStyle,
  }) {
    _mergeCylinderWorldCenter = worldCenter.clone();
    _mergeCylinderRadius = worldRadius;
    _mergeCylinderSoftness = math.max(1e-3, worldSoftness);
    _mergeCylinderTargetStyle = targetStyle;
  }

  void clearMergeCylinder() {
    _mergeCylinderRadius = 0.0;
    _mergeCylinderTargetStyle = null;
  }

  void setMergeOverlap({
    required double strength,
    Path? partnerWorldPath,
    Path? partnerLocalPath,
    Vector2? partnerWorldOrigin,
    Color? topTargetColor,
  }) {
    _mergeOverlapStrength = strength.clamp(0.0, 1.0);
    _mergeOverlapPartnerWorldPath = partnerWorldPath;
    _mergeOverlapPartnerLocalPath = partnerLocalPath;
    _mergeOverlapPartnerWorldOrigin = partnerWorldOrigin;
    _mergeOverlapTopTargetColor = topTargetColor;
  }

  void clearMergeOverlap() {
    _mergeOverlapStrength = 0.0;
    _mergeOverlapPartnerWorldPath = null;
    _mergeOverlapPartnerLocalPath = null;
    _mergeOverlapPartnerWorldOrigin = null;
    _mergeOverlapTopTargetColor = null;
  }

  void applyMergedAppearance(BlockColorStyle newStyle) {
    _displayedAppearanceStyle = newStyle;
  }

  void syncAppearanceImmediate() {
    _displayedAppearanceStyle = palette.styleFor(
      number: model.number,
      isFrozen: _isIceCovered,
    );
  }

  // --- Hold-to-Merge Candidate & MergeNumberPreview Choreography ---

  void armMergeCandidateRole({
    required bool asSurvivor,
    int? mergedPreviewValue,
  }) {
    final wasAlreadyCandidate = isSurvivorCandidate || isPartnerCandidate;
    isSurvivorCandidate = asSurvivor;
    isPartnerCandidate = !asSurvivor;

    if (!wasAlreadyCandidate) {
      _liftFromCells = _candidateLiftCells;
      _liftToCells = asSurvivor && !isDragging
          ? visualSettings.offsetWhileDragging *
              visualSettings.mergeCandidateSurvivorLift
          : 0.0;
      _pulseStartOffsetZ = _candidatePulseScaleZ -
          visualSettings.mergeCandidatePulseScale.evaluate(0.0);
      _pulseElapsed = 0.0;
      _isPulsePlaying = true;
      _isPulseReleasing = false;
      _isInflateReleasing = false;
      if (!model.isDud) {
        _waterSloshVel += (asSurvivor ? 1.0 : -1.0) * 5.2;
        _sandErosionIntensity = math.max(_sandErosionIntensity, 0.68);
      }
    }

    if (asSurvivor && mergedPreviewValue != null) {
      beginNumberPreviewAsSurvivor(mergedPreviewValue);
    } else {
      beginNumberPreviewAsPartner();
    }
  }

  void updateMergePush({
    required double pushAmount,
    required bool isSurvivor,
  }) {
    final clamped = pushAmount.clamp(0.0, 1.0);
    // In `BoardView.PushMerge`: `survivor.SetMergePush(pushAmount)` inflates survivor walls;
    // `MergeNumberPreview.Push(pushAmount)` runs on BOTH survivor and partner.
    _candidatePush = isSurvivor ? clamped : 0.0;
    if (!_isInflateReleasing) {
      _candidateInflate = isSurvivor
          ? visualSettings.mergeCandidatePushInflate.evaluate(_candidatePush)
          : 0.0;
    }
    if (!model.isDud && clamped > 0.02) {
      _sandErosionIntensity =
          math.max(_sandErosionIntensity, (0.48 + 0.52 * clamped).clamp(0.0, 1.0));
    }
    pushNumberPreview(clamped);
  }

  void clearMergeCandidateState({required bool wasCommitted}) {
    final wasCandidate = isSurvivorCandidate || isPartnerCandidate;
    isSurvivorCandidate = false;
    isPartnerCandidate = false;

    if (!wasCommitted) {
      if (wasCandidate || (_candidatePulseScaleZ - 1.0).abs() > 1e-3) {
        _liftFromCells = _candidateLiftCells;
        _liftToCells = 0.0;
        _releaseStartOffsetZ = _candidatePulseScaleZ -
            visualSettings.mergeCandidateReleaseCurve.evaluate(0.0);
        _releaseElapsed = 0.0;
        _isPulsePlaying = false;
        _isPulseReleasing = true;
      }
      if (_candidateInflate > 1e-4) {
        _releaseFromInflate = _candidateInflate;
        _inflateReleaseElapsed = 0.0;
        _isInflateReleasing = true;
      }
      _candidatePush = 0.0;
      cancelNumberPreview();
      clearMergeOverlap();
    } else {
      _isPulsePlaying = false;
      _isPulseReleasing = false;
      _candidatePulseScaleZ = 1.0;
      _candidateLiftCells = 0.0;
      _isInflateReleasing = false;
      _candidateInflate = 0.0;
      _candidatePush = 0.0;
    }
  }

  void beginNumberPreviewAsSurvivor(int mergedValue) {
    if (_isIceCovered) return;
    _activePreviewNumber = mergedValue;
    _numberPreviewMode = _NumberPreviewMode.holdingSurvivor;
    _applyNumberPreviewPush(0.0);
  }

  void beginNumberPreviewAsPartner() {
    if (_isIceCovered) return;
    _activePreviewNumber = null;
    _numberPreviewMode = _NumberPreviewMode.holdingPartner;
    _applyNumberPreviewPush(0.0);
  }

  void pushNumberPreview(double amount) {
    if (_numberPreviewMode == _NumberPreviewMode.holdingSurvivor ||
        _numberPreviewMode == _NumberPreviewMode.holdingPartner) {
      _applyNumberPreviewPush(amount);
    }
  }

  void _applyNumberPreviewPush(double amount) {
    _numberPreviewPush = amount.clamp(0.0, 1.0);
    if (_activePreviewNumber != null) {
      final t = visualSettings.mergePreviewNumberSize
          .evaluate(_numberPreviewPush)
          .clamp(0.0, 1.35);
      _normalNumberSizeFactor = (1.0 - t).clamp(0.0, 1.0);
      _previewNumberSizeFactor = t;
    } else {
      _normalNumberSizeFactor = visualSettings.mergePartnerNumberSize
          .evaluate(_numberPreviewPush)
          .clamp(0.50, 1.05);
      _previewNumberSizeFactor = 0.0;
    }
  }

  /// Exact `MergeNumberPreview.Cancel()` -> `ShrinkAwayAsync` (`0.20s` linear push -> 0).
  void cancelNumberPreview() {
    if (_numberPreviewMode == _NumberPreviewMode.idle) return;
    if (_numberPreviewMode == _NumberPreviewMode.shrinkingAway) return;
    _shrinkAwayStartPush = _numberPreviewPush;
    _numberPreviewTimer = 0.0;
    _numberPreviewMode = _NumberPreviewMode.shrinkingAway;
  }

  /// Exact `MergeNumberPreview.Commit()` -> `SettleAsync` (`0.50s` with `releaseGap` continuity).
  void commitNumberPreview({int? fallbackMergedNumber}) {
    if (_isIceCovered) {
      finishNumberPreview();
      return;
    }
    if (_activePreviewNumber == null && fallbackMergedNumber != null) {
      _activePreviewNumber = fallbackMergedNumber;
      _numberPreviewPush = 1.0;
    }
    if (_activePreviewNumber == null) {
      finishNumberPreview();
      return;
    }
    final tier =
        mergeEscalationTierForNumber(_activePreviewNumber ?? fallbackMergedNumber ?? 4);
    _settleReleaseGap =
        visualSettings.mergePreviewNumberSize.evaluate(_numberPreviewPush) -
            visualSettings.mergeNumberSettleSize.evaluate(0.0) +
            0.055 * tier;
    _normalNumberSizeFactor = 0.0;
    _numberPreviewTimer = 0.0;
    _numberPreviewMode = _NumberPreviewMode.settling;
  }

  void finishNumberPreview() {
    _numberPreviewMode = _NumberPreviewMode.idle;
    _activePreviewNumber = null;
    _numberPreviewPush = 0.0;
    _normalNumberSizeFactor = 1.0;
    _previewNumberSizeFactor = 0.0;
  }

  // --- Merge Commit Responses on Survivor ---

  /// Exact match of `PieceView.PlayMergeSurvivorMovesAsync()` (`1.12x` peak over `0.28s`)
  /// and `PlayMergeSurvivorStaysAsync(shoveDir)` (`PlayLeanImpulse` + `1.20x` curve over `0.28s`),
  /// plus `ScaleSwapAnimator.ShrinkAsync` (`1 - curve`) when stationary pins unlock!
  /// Also injects a strong sloshing water impulse (`_waterSloshVel`, `_sandErosionIntensity`)
  /// so the newly merged liquid inside the block rocks and sloshes (`nước sóng sánh`)!
  void triggerSurvivorCommitResponse({
    required bool survivorMoves,
    required Offset shoveDir,
    required bool wasPinnedBeforeMerge,
    required BlockColorStyle previousStyle,
    int mergedNumber = 4,
  }) {
    if (wasPinnedBeforeMerge && !model.movement.isPinned) {
      final prevLayout = _resolveLabelAndArrowLayout(
        overrideNumber: model.number,
        overridePinned: true,
      );
      _shrinkingScrewAnchors = List<PinnedScrewAnchor>.from(_screwAnchors);
      _shrinkingScrewPinPushPx = prevLayout.arrowOrPinPushPx;
      _shrinkingScrewStyle = previousStyle;
      _screwShrinkTimer = 0.0;
    }
    refreshGeometryForMovement();

    final tier = mergeEscalationTierForNumber(mergedNumber);
    final extraScale = 0.034 * tier;
    final extraDur = 0.022 * tier;

    if (survivorMoves) {
      _mergePulseDuration = visualSettings.mergeSurvivorMovesDuration + extraDur;
      _mergePulsePeakScale =
          visualSettings.mergeSurvivorMovesPulseScale + extraScale;
      _mergePulseCurve = visualSettings.mergeSurvivorMovesPulseCurve;
      _mergePulseElapsed = 0.0;
      if (tier > 0 && shoveDir.distance > 1e-3) {
        _leanImpulseDir =
            (shoveDir / shoveDir.distance) * (0.45 + 0.12 * tier);
        _leanImpulseDuration =
            visualSettings.mergeSurvivorStaysDuration + extraDur * 0.8;
        _leanImpulseElapsed = 0.0;
      }
    } else {
      _mergePulseDuration = visualSettings.mergeSurvivorStaysDuration + extraDur;
      _mergePulsePeakScale =
          visualSettings.mergeSurvivorStaysPulseScale + extraScale;
      _mergePulseCurve = visualSettings.mergeSurvivorStaysPulseCurve;
      _mergePulseElapsed = 0.0;

      if (shoveDir.distance > 1e-3) {
        _leanImpulseDir =
            (shoveDir / shoveDir.distance) * (1.0 + 0.16 * tier);
        _leanImpulseDuration =
            visualSettings.mergeSurvivorStaysDuration + extraDur * 0.8;
        _leanImpulseElapsed = 0.0;
      }
    }

    if (!model.isDud) {
      final shoveSign = shoveDir.dx.abs() > 0.05
          ? (shoveDir.dx >= 0 ? -1.0 : 1.0)
          : (shoveDir.dy >= 0 ? 1.0 : -1.0);
      _waterSloshVel += shoveSign * (8.5 + 1.2 * tier);
      _sandErosionIntensity =
          math.max(_sandErosionIntensity, (0.86 + 0.04 * tier).clamp(0.0, 1.0));
      _sandReformFlash = math.max(
        _sandReformFlash,
        (0.68 + 0.06 * tier).clamp(0.0, 1.0),
      );
      if (shoveDir.distance > 1e-3) {
        _sandTravelDir = shoveDir / shoveDir.distance;
      }
      if (tier > 0) {
        levelUpTargetGlow = math.max(
          levelUpTargetGlow,
          (0.38 + 0.09 * tier).clamp(0.0, 1.0),
        );
      }
    }
  }

  /// Step 1 of Win Sequence (`Tile cuối phát sáng, scale lớn nhẹ`):
  /// Triggers a bright luminous aura (`levelUpTargetGlow = 1.0`) and a smooth
  /// gentle scale-up pulse (`1.24x` peak over `0.68s`) on the final winning tile.
  void triggerFinalWinHighlight() {
    levelUpTargetGlow = 1.0;
    _mergePulseDuration = 0.68;
    _mergePulsePeakScale = 1.24;
    _mergePulseCurve = visualSettings.mergeSurvivorStaysPulseCurve;
    _mergePulseElapsed = 0.0;
    _winFractureProgress = 0.0;
    _winCrumbleProgress = 0.0;
    _waterSloshVel = 9.5;
    _sandErosionIntensity = 1.0;
  }

  /// Step 1b -> Step 2 of Win Sequence (`nước sóng sánh dâng trào & rút cạn khỏi block lên bình`):
  /// - `fractureProgress` (`0..1`): liquid morphs into crystal-aqua & waves surge smoothly inside the final block.
  /// - `crumbleProgress` (`0..1`): the water column inside the block drains downward smoothly (`fill: 0.72 -> 0.0`)
  ///   inside the clear glass container as the continuous water stream lifts up into the bottle.
  void setWinCrumbleState({
    required double fractureProgress,
    required double crumbleProgress,
  }) {
    _winFractureProgress = fractureProgress.clamp(0.0, 1.0);
    _winCrumbleProgress = crumbleProgress.clamp(0.0, 1.0);
    _shakeOffsetPx = Offset.zero;

    if (_winFractureProgress > 0.01 && _winCrumbleProgress < 0.98) {
      _sandErosionIntensity = (1.0 - _winCrumbleProgress * 0.30).clamp(0.0, 1.0);
      _waterSloshTilt =
          math.sin(_winFractureProgress * 7.5 + _winCrumbleProgress * 11.0) *
              0.40 *
              (1.0 - _winCrumbleProgress * 0.65);
    }

    if (_winCrumbleProgress > 0.005) {
      final easeScale = Curves.easeInOutCubic.transform(_winCrumbleProgress);
      visualScale = (1.0 - easeScale * 0.14).clamp(0.84, 1.0);
      final fadeU = ((_winCrumbleProgress - 0.24) / 0.76).clamp(0.0, 1.0);
      visualOpacity =
          (1.0 - Curves.easeInOutQuad.transform(fadeU)).clamp(0.0, 1.0);
    }
  }

  // --- IceComponentView `PopThenBreakAsync` (`0.3833s` Pop -> BreakIce -> `1.5x` Shake) ---

  void beginIceUnlockSequence({required VoidCallback onShatter}) {
    if (!_isIceCovered) return;
    _onIceShatterCallback = onShatter;
    _icePopTimer = 0.0;
  }

  void _completeIceBreakNow() {
    _icePopTimer = -1.0;
    _isIceCovered = false;
    _displayIceTarget = null;
    syncAppearanceImmediate();
    final cb = _onIceShatterCallback;
    _onIceShatterCallback = null;
    cb?.call();
    triggerBlockedShake(
      const Offset(1, 0),
      UnityComponentVisualConfig.iceDamageShakeRangeMultiplier,
    );
  }

  double get _currentIceBadgePopScale {
    if (_icePopTimer < 0) return 1.0;
    final t = _icePopTimer;
    const peak = UnityComponentVisualConfig.icePopPeakScale; // 1.62907
    if (t <= 0.25) {
      final u = (t / 0.25).clamp(0.0, 1.0);
      final eased = 1.0 - (1.0 - u) * (1.0 - u);
      return ui.lerpDouble(1.0, peak, eased)!;
    }
    if (t <= 0.33333333) {
      return peak;
    }
    final u = ((t - 0.33333333) / 0.05).clamp(0.0, 1.0);
    return ui.lerpDouble(peak, 1.0, u)!;
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Fast-path for completely settled idle pieces: zero spring sub-steps or Vector2 allocations!
    if (isVisuallyAtRest) {
      final idleDt = dt.clamp(0.0, 0.05);
      _sandShimmerClock += idleDt;
      if (_smoothedWaveEnergy > 1e-4) {
        _smoothedWaveEnergy *= math.exp(-3.8 * idleDt);
        if (_smoothedWaveEnergy < 1e-4) _smoothedWaveEnergy = 0.0;
      }
      _liquidWavePhase = (_liquidWavePhase +
              idleDt * (2.55 + 6.4 * _smoothedWaveEnergy)) %
          (math.pi * 200.0);
      _slideStreakVel = Offset.zero;
      final gx = boardOrigin.x + model.col * cellSize;
      final gy = boardOrigin.y + model.row * cellSize;
      if (position.x != gx || position.y != gy) {
        position
          ..x = gx
          ..y = gy;
      }
      final bottomRow = (model.row + model.heightRows - 1).clamp(0, 30);
      final targetPriority = 10 + bottomRow * 2;
      if (priority != targetPriority) {
        priority = targetPriority;
      }
      return;
    }

    final clampedDt = dt.clamp(0.0, 0.05);

    // 1. Tick `PieceFollow` state (`Dragging`, `Snapping`, `Absorbing`, `Flying`)
    if (_followState == _FollowState.absorbing) {
      _absorbElapsed += clampedDt;
      final t = (_absorbElapsed / _absorbDuration).clamp(0.0, 1.0);
      final cx = ui.lerpDouble(_absorbFromCenter.x, _absorbToCenter.x, t)!;
      final cy = ui.lerpDouble(_absorbFromCenter.y, _absorbToCenter.y, t)!;
      position
        ..x = cx - _visualPivotLocal.dx
        ..y = cy - _visualPivotLocal.dy;
      visualScale = (1.0 - t).clamp(0.0, 1.0);
      _currentZLiftCells = ui.lerpDouble(_currentZLiftCells, 0.0, t)!;
      if (t >= 1.0) {
        _followState = _FollowState.nothing;
      }
    } else if (_followState == _FollowState.dragging && !isFlyingOrSwallowed) {
      final alpha =
          (1.0 - math.exp(-visualSettings.followSmoothing * clampedDt))
              .clamp(0.0, 1.0);
      position
        ..x = _allowsDragH
            ? ui.lerpDouble(position.x, _dragTargetPos.x, alpha)!
            : _railWorldPos.x
        ..y = _allowsDragV
            ? ui.lerpDouble(position.y, _dragTargetPos.y, alpha)!
            : _railWorldPos.y;
      _currentZLiftCells = ui.lerpDouble(
        _currentZLiftCells,
        visualSettings.offsetWhileDragging,
        alpha,
      )!;
    } else if (!isFlyingOrSwallowed) {
      final gridTarget = targetWorldOriginForGrid(model.col, model.row);
      _dragTargetPos = gridTarget;
      if (_followState == _FollowState.snapping ||
          (position - gridTarget).length > 0.05 ||
          _currentZLiftCells.abs() > 1e-3) {
        final alpha =
            (1.0 - math.exp(-visualSettings.settleSmoothing * clampedDt))
                .clamp(0.0, 1.0);
        position.lerp(gridTarget, alpha);
        _currentZLiftCells = ui.lerpDouble(_currentZLiftCells, 0.0, alpha)!;
        if ((position - gridTarget).length / cellSize <= 0.001 &&
            _currentZLiftCells.abs() <= 0.001) {
          position.setFrom(gridTarget);
          _currentZLiftCells = 0.0;
          _followState = _FollowState.nothing;
        }
      }
    }

    if (!isFlyingOrSwallowed) {
      _visualGridPos
        ..x = (position.x - boardOrigin.x) / cellSize
        ..y = (position.y - boardOrigin.y) / cellSize;
      final bottomRow =
          (_visualGridPos.y + model.heightRows - 1.0).round().clamp(0, 30);
      if (isDragging) {
        priority = 95;
      } else if (isSurvivorCandidate) {
        priority = 11 + bottomRow * 2;
      } else {
        priority = 10 + bottomRow * 2;
      }
    }

    // 2. Tick `LeanImpulse` (`MergeSurvivorStaysImpulseCurve`)
    if (_leanImpulseElapsed >= 0) {
      _leanImpulseElapsed += clampedDt;
      final t = (_leanImpulseElapsed / math.max(0.01, _leanImpulseDuration))
          .clamp(0.0, 1.0);
      if (t >= 1.0) {
        _leanImpulseElapsed = -1.0;
        _leanImpulseLag = Offset.zero;
      } else {
        final mag = visualSettings.mergeSurvivorStaysImpulseCurve.evaluate(t);
        _leanImpulseLag = _leanImpulseDir * mag;
      }
    }

    // 3. Tick Deformer & Sand Swarm Trail (`Hóa Cát Bay Theo Tay`)
    if (clampedDt > 1e-5) {
      if (model.isDud ||
          _followState == _FollowState.absorbing ||
          _followState == _FollowState.flying) {
        _jellyLean = Offset.zero;
        _jellyVel = Offset.zero;
        _jellyDeformWritten = Offset.zero;
        _waterSloshTilt = 0.0;
        _waterSloshVel = 0.0;
        _sandSwarmGrains.clear();
        _sandTrailCentersWorld.clear();
        _sandErosionIntensity = 0.0;
        _sandReformFlash = 0.0;
      } else {
        final rawLagX = (_followState == _FollowState.dragging && !_allowsDragH)
            ? 0.0
            : (_dragTargetPos.x - position.x) / cellSize;
        final rawLagY = (_followState == _FollowState.dragging && !_allowsDragV)
            ? 0.0
            : (_dragTargetPos.y - position.y) / cellSize;
        final lagCells = Offset(rawLagX, rawLagY) + _leanImpulseLag;

        final gain = visualSettings.jellyLeanPerLagCell; // 1.35
        Offset target = -lagCells * gain;
        final maxLean = visualSettings.jellyLeanMax; // 0.075
        final targetMag = target.distance;
        if (targetMag > maxLean && targetMag > 1e-6) {
          target = target * (maxLean / targetMag);
        }

        final k = visualSettings.jellyStiffness; // 300.0
        final c = 2.0 * visualSettings.jellyDamping * math.sqrt(k); // 6.9282
        final subSteps = (clampedDt / 0.008).ceil().clamp(1, 8);
        final subDt = clampedDt / subSteps;
        for (int step = 0; step < subSteps; step++) {
          final accel = (target - _jellyLean) * k - _jellyVel * c;
          _jellyVel += accel * subDt;
          _jellyLean += _jellyVel * subDt;
        }

        if (_jellyLean.distanceSquared < 2.25e-6 &&
            _jellyVel.distanceSquared < 6.25e-4 &&
            target.distanceSquared < 1e-6) {
          _jellyLean = Offset.zero;
          _jellyVel = Offset.zero;
          _jellyDeformWritten = Offset.zero;
        } else {
          final exp = -visualSettings.jellyLeanSizeFalloff; // -0.5
          final sizeScaleX = math.pow(model.widthCols, exp).toDouble();
          final sizeScaleY = math.pow(model.heightRows, exp).toDouble();
          _jellyDeformWritten = Offset(
            _jellyLean.dx * sizeScaleX,
            _jellyLean.dy * sizeScaleY,
          );
        }

        _tickSandSwarmTrail(clampedDt, lagCells);
      }
    }

    // 4. Tick `MergeCandidate` Z-Pulse, Release Bounce, & Push Inflate Release
    if (_isPulseReleasing) {
      _releaseElapsed += clampedDt;
      final dur = math.max(0.05, visualSettings.mergeCandidateReleaseDuration);
      final t = (_releaseElapsed / dur).clamp(0.0, 1.0);
      _candidatePulseScaleZ =
          visualSettings.mergeCandidateReleaseCurve.evaluate(t) +
              (1.0 - t) * _releaseStartOffsetZ;
      _candidateLiftCells =
          ui.lerpDouble(_liftFromCells, _liftToCells, t)!;
      if (t >= 1.0) {
        _isPulseReleasing = false;
        _candidatePulseScaleZ = 1.0;
        _candidateLiftCells = 0.0;
      }
    } else if (_isPulsePlaying) {
      _pulseElapsed += clampedDt;
      final dur = math.max(0.05, visualSettings.mergeCandidatePulseDuration);
      final t = (_pulseElapsed / dur).clamp(0.0, 1.0);
      _candidatePulseScaleZ =
          visualSettings.mergeCandidatePulseScale.evaluate(t) +
              (1.0 - t) * _pulseStartOffsetZ;
      _candidateLiftCells =
          ui.lerpDouble(_liftFromCells, _liftToCells, t)!;
      if (t >= 1.0) {
        _isPulsePlaying = false;
      }
    }

    if (_isInflateReleasing) {
      _inflateReleaseElapsed += clampedDt;
      final dur =
          math.max(0.04, visualSettings.mergeCandidatePushReleaseDuration);
      final t = (_inflateReleaseElapsed / dur).clamp(0.0, 1.0);
      _candidateInflate = ui.lerpDouble(_releaseFromInflate, 0.0, t)!;
      if (t >= 1.0) {
        _isInflateReleasing = false;
        _candidateInflate = 0.0;
      }
    }

    // 5. Tick `MergeNumberPreview` (`ShrinkAwayAsync` 0.20s / `SettleAsync` 0.50s)
    if (_numberPreviewMode == _NumberPreviewMode.shrinkingAway) {
      _numberPreviewTimer += clampedDt;
      final dur =
          math.max(0.04, visualSettings.mergeCandidatePushReleaseDuration);
      final u = (_numberPreviewTimer / dur).clamp(0.0, 1.0);
      _applyNumberPreviewPush(ui.lerpDouble(_shrinkAwayStartPush, 0.0, u)!);
      if (u >= 1.0) {
        finishNumberPreview();
      }
    } else if (_numberPreviewMode == _NumberPreviewMode.settling) {
      _numberPreviewTimer += clampedDt;
      final dur = math.max(0.05, visualSettings.mergeNumberSettleDuration);
      final t = (_numberPreviewTimer / dur).clamp(0.0, 1.0);
      _normalNumberSizeFactor = 0.0;
      _previewNumberSizeFactor =
          visualSettings.mergeNumberSettleSize.evaluate(t) +
              (1.0 - t) * _settleReleaseGap;
      if (t >= 1.0) {
        finishNumberPreview();
      }
    }

    // 6. Tick Survivor Merge Pulse, Tap Bounce, Blocked Shake, Screw Shrink, Ice Pop, Glow
    if (_mergePulseElapsed >= 0 && _mergePulseCurve != null) {
      _mergePulseElapsed += clampedDt;
      final t =
          (_mergePulseElapsed / math.max(0.01, _mergePulseDuration)).clamp(0.0, 1.0);
      if (t >= 1.0) {
        _mergePulseElapsed = -1.0;
        _mergePulseScale = 1.0;
      } else {
        _mergePulseScale =
            1.0 + (_mergePulsePeakScale - 1.0) * _mergePulseCurve!.evaluate(t);
      }
    }

    if (_tapElapsed >= 0) {
      _tapElapsed += clampedDt;
      final t = (_tapElapsed / math.max(0.05, visualSettings.tapDuration))
          .clamp(0.0, 1.0);
      if (t >= 1.0) {
        _tapElapsed = -1.0;
        _tapScaleZ = 1.0;
        _tapInflate = 0.0;
      } else {
        _tapScaleZ = visualSettings.tapScaleZ.evaluate(t);
        _tapInflate = visualSettings.tapInflate.evaluate(t);
      }
    }

    if (_shakeElapsed >= 0) {
      _shakeElapsed += clampedDt;
      if (_shakeElapsed >= visualSettings.shakeDuration) {
        _shakeElapsed = -1.0;
        _shakeOffsetPx = Offset.zero;
      } else {
        _sampleRandomShakeOffset();
      }
    }

    if (_screwShrinkTimer >= 0) {
      _screwShrinkTimer += clampedDt;
      if (_screwShrinkTimer >= visualSettings.stationaryAnchorShrinkDuration) {
        _screwShrinkTimer = -1.0;
        _shrinkingScrewAnchors = null;
        _shrinkingScrewStyle = null;
      }
    }

    if (_icePopTimer >= 0) {
      _icePopTimer += clampedDt;
      if (_icePopTimer >= UnityComponentVisualConfig.icePopClipDuration) {
        _completeIceBreakNow();
      }
    }

    if (levelUpTargetGlow > 0) {
      final decayRate = visualSettings.levelUpGlowDuration > 0.05
          ? (1.0 / visualSettings.levelUpGlowDuration)
          : 1.0;
      levelUpTargetGlow =
          math.max(0.0, levelUpTargetGlow - clampedDt * decayRate);
    }
  }

  bool get _isLiquidGlassBlock => !_isIceCovered && !model.isDud;

  String _computeStaticPieceCacheKey(BlockColorStyle baseStyle) {
    final numKey = model.isDud ? -1 : (model.number ?? -2);
    final iceKey = _isIceCovered ? (_displayIceTarget ?? model.iceTarget ?? 4) : 0;
    final reflKey = (visualSettings.reflectionAlpha * 1000).round();
    final assetMask = (ScrewTextureCleaner.cleanedScrews.length << 4) |
        (_iceLockImg != null ? 1 : 0) |
        (_iceBlocksTex != null ? 2 : 0) |
        (_arrowTopImg != null ? 4 : 0) |
        (_arrowHorizCombinedImg != null ? 8 : 0);
    return 'glassHalfLiquidV3|${_sharedGeom.key}|${baseStyle.topBright.toARGB32().toRadixString(16)}|${baseStyle.bottomLip.toARGB32().toRadixString(16)}|$numKey|${model.movement.index}|${_isIceCovered ? 1 : 0}|$iceKey|$reflKey|$assetMask';
  }

  _BakedStaticPieceSprite? _getOrBakeStaticPieceSprite(
    BlockColorStyle baseStyle,
  ) {
    final key = _computeStaticPieceCacheKey(baseStyle);
    final existing = _sharedStaticPieceCache.remove(key);
    if (existing != null) {
      _sharedStaticPieceCache[key] = existing;
      return existing;
    }

    if (_frameBakeBudget <= 0) return null;
    _frameBakeBudget--;

    double ss = 2.0;
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        ss = views.first.devicePixelRatio.clamp(2.0, 2.5);
      }
    } catch (_) {
      ss = 2.0;
    }

    final padSide = _shadowBakePad + 4.0;
    final padBottom = (_lipDepth * 1.95 + _shadowBakePad + 6.0).ceilToDouble();
    final logicalW = _localBounds.width + padSide * 2.0;
    final logicalH = _localBounds.height + padSide + padBottom;
    final imgW = (logicalW * ss).ceil().clamp(4, 2048);
    final imgH = (logicalH * ss).ceil().clamp(4, 2048);

    final bakeShellOnly = _isLiquidGlassBlock;
    _isBakingGlassShellOnly = bakeShellOnly;
    try {
      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);
      recCanvas.scale(imgW / logicalW, imgH / logicalH);
      recCanvas.translate(padSide, padSide);
      _renderDynamicPieceContents(recCanvas, baseStyle);

      final pic = recorder.endRecording();
      final img = pic.toImageSync(imgW, imgH);
      pic.dispose();

      final sprite = _BakedStaticPieceSprite(
        image: img,
        srcRect: Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
        dstRect: Rect.fromLTWH(-padSide, -padSide, logicalW, logicalH),
      );
      if (_sharedStaticPieceCache.length >= 96) {
        final oldest =
            _sharedStaticPieceCache.remove(_sharedStaticPieceCache.keys.first);
        oldest?.image.dispose();
      }
      _sharedStaticPieceCache[key] = sprite;
      return sprite;
    } catch (_) {
      return null;
    } finally {
      _isBakingGlassShellOnly = false;
    }
  }

  @override
  void render(Canvas canvas) {
    if (visualOpacity <= 0.01 || visualScale <= 0.005) {
      _usedStaticSpriteLastRender = false;
      return;
    }

    final baseStyle = _isIceCovered
        ? palette.styleFor(number: model.number, isFrozen: true)
        : _displayedAppearanceStyle;

    if (isVisuallyAtRest) {
      final staticSprite = _getOrBakeStaticPieceSprite(baseStyle);
      if (staticSprite != null) {
        _usedStaticSpriteLastRender = true;
        // 1. Pre-baked drop shadow + clear crystal-glass container shell
        canvas.drawImageRect(
          staticSprite.image,
          staticSprite.srcRect,
          staticSprite.dstRect,
          _staticPiecePaint,
        );
        if (_isLiquidGlassBlock) {
          // 2. Live ~75% "lưng lửng" liquid + gentle 3D meniscus wave ("sóng sánh nhẹ") + bubbles
          _drawGlassHalfFullLiquidAndWave(
            canvas,
            baseStyle,
            isIdleAtRest: true,
          );
          // 3. Glossy crystal-glass top shoulder, inner vertical wall streaks & rim
          _drawCrystalGlassForeground(canvas, baseStyle);
          // 4. Crisp pre-baked number / arrows / pins submerged cleanly inside the liquid
          _drawPieceTopFaceRiders(canvas, baseStyle, Offset.zero);
        }
        return;
      }
    }

    _usedStaticSpriteLastRender = false;
    _renderDynamicPieceContents(canvas, baseStyle);
  }

  void _renderDynamicPieceContents(Canvas canvas, BlockColorStyle baseStyle) {
    final isGlassLiquid = _isLiquidGlassBlock;

    final totalBlockInflate = _candidateInflate + _tapInflate;
    final wallInflateScaleX =
        1.0 + (totalBlockInflate * 0.72) / math.max(1, model.widthCols);
    final wallInflateScaleY =
        1.0 + (totalBlockInflate * 0.72) / math.max(1, model.heightRows);

    final sandReformPop = _sandReformFlash > 0.01
        ? (1.0 + math.sin(_sandReformFlash * math.pi) * 0.036)
        : 1.0;
    final sizeDamp = 1.0 / math.sqrt(math.max(1, model.localCells.length));
    final sloshWave = (math.sin(_sandShimmerClock * 15.5) *
                (_sandErosionIntensity * 0.042 + _sandReformFlash * 0.038) +
            _waterSloshTilt * 0.052 +
            (_jellyDeformWritten.dx.abs() - _jellyDeformWritten.dy.abs()) *
                0.40) *
        sizeDamp;
    final clampedSlosh =
        _isBakingGlassShellOnly ? 0.0 : sloshWave.clamp(-0.075, 0.075);
    final sloshScaleX = 1.0 + clampedSlosh;
    final sloshScaleY = 1.0 - clampedSlosh * 0.88;
    final sloshRotRad = _isBakingGlassShellOnly
        ? 0.0
        : (((_waterSloshTilt * 0.048) +
                math.sin(_sandShimmerClock * 15.0) *
                    (_sandErosionIntensity * 0.020 +
                        _sandReformFlash * 0.024)) *
            sizeDamp);

    final finalScaleX = visualScale *
        visualScaleXMultiplier *
        _mergePulseScale *
        wallInflateScaleX *
        sandReformPop *
        sloshScaleX;
    final finalScaleY = visualScale *
        visualScaleYMultiplier *
        _mergePulseScale *
        wallInflateScaleY *
        sandReformPop *
        sloshScaleY;
    final finalScaleZ = _mergePulseScale * _candidatePulseScaleZ * _tapScaleZ;

    final effectiveLipDepth =
        (_lipDepth * finalScaleZ).clamp(2.0, _lipDepth * 1.85);
    final zHeightGrowPx = effectiveLipDepth - _lipDepth;

    final totalLiftCells = _currentZLiftCells + _candidateLiftCells;
    final liftPx = totalLiftCells * cellSize * 1.15 + zHeightGrowPx * 0.55;
    final topJellyShift = _isBakingGlassShellOnly
        ? Offset.zero
        : (_jellyDeformWritten * cellSize * 1.05 +
            Offset(
              _waterSloshTilt * cellSize * 0.085 +
                  math.sin(_sandShimmerClock * 15.0) *
                      _sandErosionIntensity *
                      cellSize *
                      0.028,
              math.cos(_sandShimmerClock * 13.0) *
                  _sandErosionIntensity *
                  cellSize *
                  0.024,
            ));

    canvas.save();
    if (visualOpacity < 0.999) {
      _opacityLayerPaint.color = Colors.white.withValues(alpha: visualOpacity);
      canvas.saveLayer(
        _localBounds.inflate(cellSize * 0.9),
        _opacityLayerPaint,
      );
    }

    canvas.translate(
      _visualPivotLocal.dx + _shakeOffsetPx.dx,
      _visualPivotLocal.dy + _shakeOffsetPx.dy,
    );
    if (sloshRotRad.abs() > 1e-4) {
      canvas.rotate(sloshRotRad);
    }
    canvas.scale(finalScaleX, finalScaleY);
    canvas.translate(-_visualPivotLocal.dx, -_visualPivotLocal.dy);

    // 0a. Cyan `LevelUpVisualConfig` Target Aura
    if (levelUpTargetGlow > 0.01 && _glowImg != null) {
      final glowProgress = (1.0 - levelUpTargetGlow).clamp(0.0, 1.0);
      final curveVal =
          visualSettings.levelUpGlowIntensity.evaluate(glowProgress);
      final auraAlpha = (curveVal * 0.80).clamp(0.0, 1.0);
      if (auraAlpha > 0.01) {
        final auraRect = _localBounds.inflate(cellSize * 0.55);
        _auraPaint.colorFilter = ColorFilter.mode(
          const Color(0xFF00BFFF).withValues(alpha: auraAlpha),
          BlendMode.modulate,
        );
        canvas.drawImageRect(
          _glowImg!,
          Rect.fromLTWH(
            0,
            0,
            _glowImg!.width.toDouble(),
            _glowImg!.height.toDouble(),
          ),
          auraRect,
          _auraPaint,
        );
      }
    }

    // 0b. Subtle Glass Motion-Streak Trail when sliding fast (matches block `64` in `media_1794051081001.png`!)
    if (isGlassLiquid &&
        !_isBakingGlassShellOnly &&
        _slideStreakVel.distance > cellSize * 2.0) {
      _drawGlassSlideMotionStreaks(canvas, baseStyle, liftPx);
    }

    // 1. Pre-Baked Drop Shadow (compact offset for sleek glass containers so rows never overlap!)
    final clampedLiftCells = math.max(0.0, totalLiftCells);
    final shadowBaseDy =
        isGlassLiquid ? (cellSize * 0.055) : (_lipDepth + cellSize * 0.055);
    final shadowShift = Offset(
      -0.20 * clampedLiftCells * cellSize,
      shadowBaseDy + 0.42 * clampedLiftCells * cellSize,
    );
    final shadowAlpha = isGlassLiquid
        ? (0.30 + clampedLiftCells * 1.35).clamp(0.0, 0.50)
        : (0.36 + clampedLiftCells * 1.4).clamp(0.0, 0.54);
    final shadowImg = _bakedShadowImage;
    if (shadowImg != null) {
      final liftSpread = clampedLiftCells * 0.14 * cellSize;
      final dstShadowRect = Rect.fromLTWH(
        -_shadowBakePad + shadowShift.dx - liftSpread,
        -_shadowBakePad + shadowShift.dy - liftSpread,
        _localBounds.width + _shadowBakePad * 2.0 + liftSpread * 2.0,
        _localBounds.height + _shadowBakePad * 2.0 + liftSpread * 2.0,
      );
      _shadowDrawPaint.color = Color.fromRGBO(255, 255, 255, shadowAlpha);
      canvas.drawImageRect(
        shadowImg,
        Rect.fromLTWH(
          0,
          0,
          shadowImg.width.toDouble(),
          shadowImg.height.toDouble(),
        ),
        dstShadowRect,
        _shadowDrawPaint,
      );
    } else {
      _fallbackShadowPaint.color = Color.fromRGBO(2, 7, 26, shadowAlpha);
      canvas.save();
      canvas.translate(shadowShift.dx, shadowShift.dy);
      canvas.drawPath(_topPath, _fallbackShadowPaint);
      canvas.restore();
    }

    if (!isGlassLiquid &&
        clampedLiftCells < 0.05 &&
        !_areComponentsRemovedForAbsorb) {
      final reflFade = (1.0 - clampedLiftCells / 0.05).clamp(0.0, 1.0);
      final reflAlpha =
          (visualSettings.reflectionAlpha * 1.08 * reflFade).clamp(0.0, 0.28);
      final reflAlphaKey = (reflAlpha * 255).round();
      final nextReflKey = (baseStyle.topMid, baseStyle.bottomLip, reflAlphaKey);
      if (_cachedReflKey != nextReflKey) {
        _cachedReflKey = nextReflKey;
        final reflTopLocal = _localBounds.bottom - _lipDepth * 0.65;
        final reflBottomLocal = _localBounds.bottom + _lipDepth * 0.40;
        _cachedReflPaint.shader = ui.Gradient.linear(
          Offset(_visualPivotLocal.dx, reflTopLocal),
          Offset(_visualPivotLocal.dx, reflBottomLocal),
          [
            baseStyle.topMid.withValues(alpha: reflAlpha),
            baseStyle.bottomLip.withValues(alpha: 0.0),
          ],
        );
      }
      canvas.save();
      canvas.translate(0, _lipDepth * 1.55);
      canvas.drawPath(_topPath, _cachedReflPaint);
      canvas.restore();
    }

    // Shift piece upward by Z-lift (`position.z = -OffsetWhileDragging`)
    canvas.translate(0, -liftPx);

    if (isGlassLiquid) {
      // --- CLEAR CRYSTAL-GLASS CONTAINER + ~70% "LƯNG LỬNG" LIQUID PIPELINE ---
      BlockColorStyle renderLiquidStyle = baseStyle;
      if (_winFractureProgress > 0.005 && !_isBakingGlassShellOnly) {
        final winAquaT =
            Curves.easeOutCubic.transform(_winFractureProgress.clamp(0.0, 1.0));
        renderLiquidStyle = BlockColorStyle(
          number: baseStyle.number,
          topBright:
              Color.lerp(baseStyle.topBright, const Color(0xFF42F2FF), winAquaT)!,
          topMid:
              Color.lerp(baseStyle.topMid, const Color(0xFF08BFE8), winAquaT)!,
          bottomLip:
              Color.lerp(baseStyle.bottomLip, const Color(0xFF027BA8), winAquaT)!,
          rimHighlight: Color.lerp(
            baseStyle.rimHighlight,
            const Color(0xFFB8FFFF),
            winAquaT,
          )!,
          accent:
              Color.lerp(baseStyle.accent, const Color(0xFF2CEBFF), winAquaT)!,
          numberStrokeOuter: Color.lerp(
            baseStyle.numberStrokeOuter,
            const Color(0xFF03385E),
            winAquaT,
          )!,
          numberStrokeMid: Color.lerp(
            baseStyle.numberStrokeMid,
            const Color(0xFF027BA8),
            winAquaT,
          )!,
          numberStrokeInner: Color.lerp(
            baseStyle.numberStrokeInner,
            const Color(0xFF2CEBFF),
            winAquaT,
          )!,
          screwBright: baseStyle.screwBright,
          screwDark: baseStyle.screwDark,
          arrowStroke: baseStyle.arrowStroke,
          arrowShadow: baseStyle.arrowShadow,
        );

        // Luminous crystal-aqua outer silhouette halo hugging the winning glass block (`media_1794007349252.png` Panel 2)
        final haloAlpha =
            (winAquaT * (1.0 - _winCrumbleProgress * 0.72) * 0.68).clamp(0.0, 0.75);
        if (haloAlpha > 0.01) {
          canvas.save();
          if (topJellyShift != Offset.zero) {
            canvas.translate(topJellyShift.dx, topJellyShift.dy);
          }
          canvas.drawPath(
            _topPath,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = (cellSize * 0.16).clamp(5.0, 16.0)
              ..color = const Color(0xFF38EEFF).withValues(alpha: haloAlpha)
              ..maskFilter = MaskFilter.blur(
                BlurStyle.normal,
                (cellSize * 0.14).clamp(4.0, 14.0),
              ),
          );
          canvas.restore();
        }
      }

      // 2a. Translucent clear-glass container back wall (allows dark board grid to show through top ~30%!)
      _drawCrystalGlassBackShell(canvas, renderLiquidStyle, topJellyShift);

      if (_isBakingGlassShellOnly) {
        if (visualOpacity < 0.999) {
          canvas.restore();
        }
        canvas.restore();
        return;
      }

      // 2b. ~70% "Lưng Lửng" Colored Liquid + 3D Glowing Meniscus Wave + Effervescent Bubbles
      _drawGlassHalfFullLiquidAndWave(
        canvas,
        renderLiquidStyle,
        isIdleAtRest: isVisuallyAtRest,
        topJellyShift: topJellyShift,
      );

      // 3. `_MergeCylinder` Smoothstep Color Wipe clipped to the ~70% liquid region (top glass stays clear!)
      if (_mergeCylinderRadius > 0.2 && _mergeCylinderTargetStyle != null) {
        _drawMergeCylinderShaderOverlay(
          canvas,
          targetStyle: _mergeCylinderTargetStyle!,
          topJellyShift: topJellyShift,
          effectiveLipDepth: effectiveLipDepth,
          liftPx: liftPx,
          finalScaleX: finalScaleX,
          finalScaleY: finalScaleY,
        );
      }

      // 4. `_MergeOverlap` Seam Fusion clipped to the liquid region
      if (_mergeOverlapStrength > 0.01 &&
          (_mergeOverlapPartnerLocalPath != null ||
              _mergeOverlapPartnerWorldPath != null) &&
          _mergeOverlapTopTargetColor != null) {
        _drawMergeOverlapSeamFusion(
          canvas,
          topJellyShift: topJellyShift,
          liftPx: liftPx,
        );
      }

      // 5. Glossy 3D Crystal-Glass Foreground Rim, Top Shoulder Gleam & Vertical Wall Streaks
      final activeGlassStyle = (_mergeCylinderRadius > cellSize * 0.85 &&
              _mergeCylinderTargetStyle != null)
          ? _mergeCylinderTargetStyle!
          : renderLiquidStyle;
      _drawCrystalGlassForeground(
        canvas,
        activeGlassStyle,
        topJellyShift: topJellyShift,
      );

      // 6. Top-Face Riders (Pins, Arrows, 4-Layer Number submerged inside the ~70% liquid)
      if (!_areComponentsRemovedForAbsorb) {
        _drawPieceTopFaceRiders(canvas, renderLiquidStyle, topJellyShift);
      }
    } else {
      // --- SOLID OBSTACLE PIPELINE (Dud & Ice-Covered Pieces) ---
      _drawBodySurface(
        canvas,
        baseStyle,
        topJellyShift: topJellyShift,
        effectiveLipDepth: effectiveLipDepth,
      );

      if (_isIceCovered) {
        _drawIceFrostAndSheen(canvas, topJellyShift);
      }

      final outerContourColor = _isIceCovered
          ? const Color(0xFF2882ED)
          : Color.lerp(baseStyle.topMid, baseStyle.bottomLip, 0.58)!;
      _outerContourPaint.color = outerContourColor.withValues(alpha: 0.88);
      canvas.save();
      canvas.translate(topJellyShift.dx, topJellyShift.dy);
      canvas.drawPath(_topPath, _outerContourPaint);
      canvas.restore();

      if (!_areComponentsRemovedForAbsorb) {
        _drawPieceTopFaceRiders(canvas, baseStyle, topJellyShift);
      }
    }

    if (visualOpacity < 0.999) {
      canvas.restore();
    }
    canvas.restore();
  }

  /// Draws pins, directional movement arrows, and 4-layer number on the piece.
  /// For half-full liquid glass blocks, gently shifts the number/horizontal-arrows downward so they
  /// sit squarely inside the ~75% colored liquid body below the meniscus (`media_1794051081001.png`).
  void _drawPieceTopFaceRiders(
    Canvas canvas,
    BlockColorStyle baseStyle,
    Offset topJellyShift,
  ) {
    canvas.save();
    canvas.translate(topJellyShift.dx, topJellyShift.dy);

    if (_isIceCovered) {
      _drawFrozenLockBadge(canvas, _displayIceTarget ?? model.iceTarget ?? 4);
      canvas.restore();
      return;
    }

    final layoutStyle = (_mergeCylinderTargetStyle != null &&
            _mergeCylinderRadius > cellSize * 0.65)
        ? _mergeCylinderTargetStyle!
        : baseStyle;
    final resolvedLayout = _getBaseLabelAndArrowLayout();

    // Stationary Corner Pins stay anchored at the 4 corners of the glass container
    if (model.movement.isPinned) {
      _drawPinnedScrews(
        canvas,
        layoutStyle,
        _screwAnchors,
        pinPushPx: resolvedLayout.arrowOrPinPushPx,
        extraScaleMultiplier: 1.0,
      );
    } else if (_screwShrinkTimer >= 0 &&
        _shrinkingScrewAnchors != null &&
        _shrinkingScrewStyle != null) {
      final shrinkScale = debugShrinkingScrewScale;
      if (shrinkScale > 0.01) {
        _drawPinnedScrews(
          canvas,
          _shrinkingScrewStyle!,
          _shrinkingScrewAnchors!,
          pinPushPx: _shrinkingScrewPinPushPx,
          extraScaleMultiplier: shrinkScale,
        );
      }
    }

    // Compute vertical liquid-submersion offset so numbers & arrows sit comfortably inside the ~70% liquid!
    double liquidSubmergeDy = 0.0;
    if (_isLiquidGlassBlock) {
      final arrowLayout = resolvedLayout.arrowLayout;
      final isSingleCellPinned = model.movement.isPinned &&
          model.heightRows == 1 &&
          model.widthCols == 1;
      if (isSingleCellPinned) {
        liquidSubmergeDy = cellSize * 0.045;
      } else if (model.heightRows == 1) {
        liquidSubmergeDy = (arrowLayout != null && !arrowLayout.isHorizontal)
            ? cellSize * 0.065
            : cellSize * 0.098;
      } else {
        // Multi-row pieces: if label is in top row (`dy < 0.75 * cellSize`), nudge below meniscus;
        // otherwise keep right in the heart of the liquid (`+0.030 * cellSize`).
        liquidSubmergeDy = resolvedLayout.labelCenterLocal.dy < cellSize * 0.75
            ? cellSize * 0.105
            : cellSize * 0.030;
      }
    }

    canvas.save();
    if (liquidSubmergeDy != 0.0) {
      canvas.translate(0.0, liquidSubmergeDy);
    }

    if (resolvedLayout.arrowLayout != null) {
      _drawMovementArrows(
        canvas,
        layoutStyle,
        resolvedLayout.arrowLayout!,
        arrowPushPx: resolvedLayout.arrowOrPinPushPx,
      );
    }

    if (!model.isDud && model.number != null) {
      _drawBlockNumbersWithPreview(canvas, baseStyle, resolvedLayout);
    }
    canvas.restore();

    if (_winFractureProgress > 0.01 && _winCrumbleProgress < 0.85) {
      _drawWinFractureCracks(canvas, baseStyle);
    }

    canvas.restore();
  }

  /// Soft translucent glass motion-streak trail behind fast-sliding pieces (`64` in `media_1794051081001.png`).
  void _drawGlassSlideMotionStreaks(
    Canvas canvas,
    BlockColorStyle style,
    double liftPx,
  ) {
    final speed = _slideStreakVel.distance;
    final strength =
        ((speed - cellSize * 2.0) / (cellSize * 9.0)).clamp(0.0, 1.0);
    if (strength <= 0.02) return;

    final dir = _slideStreakVel / speed;
    final trailUnit = -dir;
    final streakLen = cellSize * (0.22 + 0.42 * strength);

    canvas.save();
    canvas.translate(0, -liftPx);
    for (int i = 1; i <= 3; i++) {
      final frac = i / 3.0;
      final shift = trailUnit * (streakLen * frac);
      final alpha = (0.14 * (1.0 - frac * 0.72) * strength).clamp(0.0, 0.16);
      canvas.save();
      canvas.translate(shift.dx, shift.dy);
      canvas.drawPath(
        _topPath,
        Paint()
          ..color =
              Color.lerp(style.rimHighlight, const Color(0xFFA8E4FF), 0.55)!
                  .withValues(alpha: alpha),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  /// Clear Crystal-Glass Container Back Shell:
  /// Keeps the top ~25% of the block genuinely transparent so the dark navy board grid shows through
  /// as rich crystal-tinted glass (`#204088` in `media_1794051081001.png`), with subtle glass sheen.
  void _drawCrystalGlassBackShell(
    Canvas canvas,
    BlockColorStyle style,
    Offset topJellyShift,
  ) {
    canvas.save();
    if (topJellyShift != Offset.zero) {
      canvas.translate(topJellyShift.dx, topJellyShift.dy);
    }

    canvas.drawPath(
      _topPath,
      Paint()
        ..shader = ui.Gradient.linear(
          _localBounds.topLeft,
          _localBounds.bottomLeft,
          [
            Colors.white.withValues(alpha: 0.17),
            const Color(0xFF9AD4FF).withValues(alpha: 0.09),
            const Color(0xFF4A8EE8).withValues(alpha: 0.06),
            style.bottomLip.withValues(alpha: 0.16),
          ],
          const [0.0, 0.16, 0.38, 1.0],
        ),
    );

    canvas.restore();
  }

  /// Renders the ~75% "Lưng Lửng" Colored Liquid + 3D Elliptical/S-Wave Meniscus + Internal Bounce Glow + Bubbles:
  /// - At rest (`isIdleAtRest == true`): gentle calm 3D meniscus wave ("sóng sánh nhẹ khi chưa di chuyển hoặc click").
  /// - Clicked / Dragged / Moving (`isIdleAtRest == false`): strong surging S-wave ("khi di chuyển hoặc click thì sóng mạnh hơn")!
  void _drawGlassHalfFullLiquidAndWave(
    Canvas canvas,
    BlockColorStyle style, {
    required bool isIdleAtRest,
    Offset topJellyShift = Offset.zero,
    double alphaMultiplier = 1.0,
  }) {
    final x0 = _localBounds.left;
    final y0 = _localBounds.top;
    final x1 = _localBounds.right;
    final y1 = _localBounds.bottom;
    final w = _localBounds.width;

    // Empty crystal-glass headspace at top: front meniscus sits at ~31% of 1 cell on 1-row pieces
    // and ~34% of 1 cell on 2+-row pieces (`back meniscus` sits `meniscusDepth` higher around ~22%–25%),
    // matching `16`, `256`, `2048`, `128`, `1024`, `512`, `8`, `64`, `32`, `4` in `media_1794051081001.png`!
    final headspacePx =
        cellSize * (model.heightRows == 1 ? 0.308 : 0.338);
    final restSurfaceY = y0 + headspacePx;
    final drainT =
        Curves.easeInOutCubic.transform(_winCrumbleProgress.clamp(0.0, 1.0));
    final baseWaveY = ui.lerpDouble(
      restSurfaceY,
      y1 + 2.0,
      drainT,
    )!;

    // Deterministic per-piece phase offset so resting blocks breathe organically out-of-sync
    final pieceSeed = (model.id * 1.93) % (math.pi * 2.0);
    final isWideBlock = model.widthCols >= 2;
    final idleTiltDy = math.sin(_sandShimmerClock * 1.95 + pieceSeed) *
        cellSize *
        (isWideBlock ? 0.030 : 0.014);

    final energy = _smoothedWaveEnergy.clamp(0.0, 1.0);
    final restAmp = isWideBlock ? 0.034 : 0.016;
    final waveAmp =
        cellSize * (restAmp + 0.095 * energy) * (1.0 - 0.65 * drainT);
    final phase = _liquidWavePhase;
    final activeTiltDy = isIdleAtRest
        ? idleTiltDy
        : (_waterSloshTilt * w * 0.27).clamp(-cellSize * 0.23, cellSize * 0.23);
    final tiltSpanDy = ui.lerpDouble(idleTiltDy, activeTiltDy, energy)!;

    // 3D Elliptical Meniscus Geometry (`media_1794051081001.png`):
    // Back rim sits higher (`meniscusDepth`) and arches UPWARD (`-backLensArch`),
    // while Front rim arches DOWNWARD (`+frontLensArch`), creating the unmistakable
    // plump 3D glowing oval liquid cap on `1x2` blocks (`16`, `256`, `1024`, `4`) AND
    // lush 3D undulating S-wave water surface on `2x1` blocks (`2048`, `128`, `512`, `8`, `64`)!
    final meniscusDepth =
        cellSize * (0.078 + 0.020 * energy) * (1.0 - 0.75 * drainT);
    final lensRoundness = (isWideBlock ? 0.65 : 1.0) * (1.0 - 0.45 * energy);
    final backLensArch = cellSize * 0.034 * lensRoundness;
    final frontLensArch = cellSize * 0.028 * lensRoundness;

    final minClampY = y0 + cellSize * 0.085;
    final minCtrlY = y0 - cellSize * 0.14;
    final maxClampY = ui.lerpDouble(y1 - cellSize * 0.08, y1 + 3.0, drainT)!;

    // Cubic Bezier control points attenuate peak S-wave height by ~0.42x (`27/64`),
    // so scale `sWaveFront`/`sWaveBack` accordingly for lush gentle waves at rest & bold waves on click/drag!
    final sWaveScale = isWideBlock ? 3.45 : 1.75;
    final sWaveFront = math.sin(phase) * waveAmp * sWaveScale;
    final sWaveBack = math.sin(phase + 0.35) * waveAmp * (sWaveScale * 0.88);

    final bLeftY = (baseWaveY -
            meniscusDepth * 0.72 +
            tiltSpanDy * 0.65 +
            sWaveBack * 0.25)
        .clamp(minClampY, maxClampY);
    final bRightY = (baseWaveY -
            meniscusDepth * 0.72 -
            tiltSpanDy * 0.65 -
            sWaveBack * 0.25)
        .clamp(minClampY, maxClampY);
    final bCtrl1Y = (baseWaveY -
            meniscusDepth -
            backLensArch +
            tiltSpanDy * 0.42 -
            sWaveBack)
        .clamp(minCtrlY, maxClampY);
    final bCtrl2Y = (baseWaveY -
            meniscusDepth -
            backLensArch -
            tiltSpanDy * 0.42 +
            sWaveBack)
        .clamp(minCtrlY, maxClampY);

    final fLeftY =
        (baseWaveY + tiltSpanDy * 0.72 + sWaveFront * 0.28)
            .clamp(minClampY + cellSize * 0.025, maxClampY);
    final fRightY =
        (baseWaveY - tiltSpanDy * 0.72 - sWaveFront * 0.28)
            .clamp(minClampY + cellSize * 0.025, maxClampY);
    final fCtrl1Y = (baseWaveY +
            frontLensArch +
            tiltSpanDy * 0.45 -
            sWaveFront)
        .clamp(minCtrlY + cellSize * 0.02, maxClampY);
    final fCtrl2Y = (baseWaveY +
            frontLensArch -
            tiltSpanDy * 0.45 +
            sWaveFront)
        .clamp(minCtrlY + cellSize * 0.02, maxClampY);

    final backWavePath = Path()
      ..moveTo(x0 - 2.0, bLeftY)
      ..cubicTo(
        x0 + w * 0.32,
        bCtrl1Y,
        x0 + w * 0.68,
        bCtrl2Y,
        x1 + 2.0,
        bRightY,
      )
      ..lineTo(x1 + 2.0, y1 + 2.0)
      ..lineTo(x0 - 2.0, y1 + 2.0)
      ..close();

    final frontWaterPath = Path()
      ..moveTo(x0 - 2.0, fLeftY)
      ..cubicTo(
        x0 + w * 0.33,
        fCtrl1Y,
        x0 + w * 0.67,
        fCtrl2Y,
        x1 + 2.0,
        fRightY,
      )
      ..lineTo(x1 + 2.0, y1 + 2.0)
      ..lineTo(x0 - 2.0, y1 + 2.0)
      ..close();

    // Cache union of meniscus + liquid body for `_MergeCylinder` & `_MergeOverlap` clipping
    _lastLiquidWaveClipPath = backWavePath;

    canvas.save();
    if (topJellyShift != Offset.zero) {
      canvas.translate(topJellyShift.dx, topJellyShift.dy);
    }
    canvas.clipPath(_liquidCavityPath);

    // 1. Bright Glowing 3D Top Meniscus Surface (`backWavePath`)
    final meniscusBright = Color.lerp(style.topBright, Colors.white, 0.50)!;
    final meniscusMid = Color.lerp(style.topBright, Colors.white, 0.28)!;
    canvas.drawPath(
      backWavePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x0, baseWaveY - meniscusDepth),
          Offset(x1, baseWaveY + cellSize * 0.04),
          [
            meniscusBright.withValues(alpha: 0.95 * alphaMultiplier),
            meniscusMid.withValues(alpha: 0.94 * alphaMultiplier),
          ],
        ),
    );

    // 2. Rich Jewel-Tone Liquid Body + Glowing Bottom Glass Floor Refraction (`media_1794051081001.png`)
    final upperBodyCol = Color.lerp(style.topMid, style.bottomLip, 0.30)!;
    final deepCoreCol = Color.lerp(style.topMid, style.bottomLip, 0.45)!;
    final floorGlowCol = Color.lerp(style.topBright, Colors.white, 0.24)!;

    _sandErosionPaint.shader = ui.Gradient.linear(
      Offset(x0 + w * 0.5, baseWaveY),
      Offset(x0 + w * 0.5, y1),
      [
        upperBodyCol.withValues(alpha: 0.93 * alphaMultiplier),
        deepCoreCol.withValues(alpha: 0.95 * alphaMultiplier),
        style.topMid.withValues(alpha: 0.95 * alphaMultiplier),
        style.topBright.withValues(alpha: 0.96 * alphaMultiplier),
        floorGlowCol.withValues(alpha: 0.97 * alphaMultiplier),
      ],
      const [0.0, 0.46, 0.76, 0.91, 1.0],
    );
    canvas.drawPath(frontWaterPath, _sandErosionPaint);

    // Subtle internal side-wall bounce glow inside the liquid along left & right glass edges
    canvas.drawPath(
      frontWaterPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x0, baseWaveY),
          Offset(x1, baseWaveY),
          [
            style.topBright.withValues(alpha: 0.42 * alphaMultiplier),
            style.topBright.withValues(alpha: 0.0),
            style.topBright.withValues(alpha: 0.0),
            style.topBright.withValues(alpha: 0.38 * alphaMultiplier),
          ],
          const [0.0, 0.14, 0.86, 1.0],
        ),
    );

    // 3. Crisp Specular Front Meniscus Rim Curve (`#FFFFFF` / pastel gleam)
    final frontRimCurve = Path()
      ..moveTo(x0, fLeftY)
      ..cubicTo(
        x0 + w * 0.34,
        fCtrl1Y,
        x0 + w * 0.66,
        fCtrl2Y,
        x1,
        fRightY,
      );
    canvas.drawPath(
      frontRimCurve,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeWidth = (cellSize * 0.025).clamp(1.3, 2.4)
        ..color = Color.lerp(style.topBright, Colors.white, 0.78)!
            .withValues(alpha: (0.86 + 0.10 * energy).clamp(0.0, 1.0) * alphaMultiplier),
    );

    // Active wave frothy crest highlight when clicked / dragged (`energy > 0.18`, like block `64`)
    if (energy > 0.18) {
      final crestBandH = cellSize * (0.055 * energy);
      final crestGlowPath = Path()
        ..moveTo(x0, fLeftY)
        ..cubicTo(x0 + w * 0.34, fCtrl1Y, x0 + w * 0.66, fCtrl2Y, x1, fRightY)
        ..lineTo(x1, fRightY + crestBandH)
        ..cubicTo(
          x0 + w * 0.66,
          fCtrl2Y + crestBandH * 1.15,
          x0 + w * 0.34,
          fCtrl1Y + crestBandH * 1.15,
          x0,
          fLeftY + crestBandH,
        )
        ..close();
      canvas.drawPath(
        crestGlowPath,
        Paint()
          ..color = Colors.white
              .withValues(alpha: (0.34 * energy * alphaMultiplier).clamp(0.0, 0.45)),
      );
    }

    // 4. Delicate Rising Effervescent Glass Bubbles in the lower half of the liquid (`media_1794051081001.png`)
    final bubbleCount = energy > 0.25 ? 7 : 5;
    final bubbleSpeed = 0.22 + 0.55 * energy;
    final liquidSpanH = math.max(cellSize * 0.25, y1 - baseWaveY);
    for (int k = 0; k < bubbleCount; k++) {
      final bPhase =
          (_sandShimmerClock * bubbleSpeed + k * 0.29 + pieceSeed * 0.15) % 1.0;
      // Cluster bubbles naturally toward lower-left & lower-right glass corners like `media_1794051081001.png`
      final xSlot = (k.isEven)
          ? (0.12 + 0.18 * ((k * 0.37) % 1.0))
          : (0.70 + 0.18 * ((k * 0.43) % 1.0));
      final bx = x0 +
          w * xSlot +
          math.sin(_sandShimmerClock * 2.4 + k * 1.7) * cellSize * 0.015;
      final by = y1 -
          cellSize * 0.075 -
          bPhase * (liquidSpanH * (0.48 + 0.28 * energy));
      if (by <= baseWaveY + cellSize * 0.05) continue;

      final br =
          (cellSize * (0.022 + 0.010 * (k % 3)) * (1.0 - 0.20 * bPhase))
              .clamp(1.1, 3.2);
      final bAlpha =
          ((1.0 - bPhase * 0.75) * (0.42 + 0.28 * energy) * alphaMultiplier)
              .clamp(0.0, 0.80);
      if (bAlpha <= 0.02) continue;

      canvas.drawCircle(
        Offset(bx, by),
        br,
        Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 0.95
          ..color = Colors.white.withValues(alpha: bAlpha),
      );
      canvas.drawCircle(
        Offset(bx - br * 0.32, by - br * 0.32),
        br * 0.35,
        Paint()..color = Colors.white.withValues(alpha: (bAlpha * 1.35).clamp(0.0, 0.92)),
      );
    }

    canvas.restore();
  }

  /// Glossy 3D Crystal-Glass Container Rim, Top Shoulder Specular Gleam & Thin Vertical Inner Wall Streaks:
  /// Drawn OVER the liquid so the colored liquid clearly sits inside a clear glass vial (`media_1794051081001.png`).
  void _drawCrystalGlassForeground(
    Canvas canvas,
    BlockColorStyle style, {
    Offset topJellyShift = Offset.zero,
  }) {
    final x0 = _localBounds.left;
    final y0 = _localBounds.top;
    final x1 = _localBounds.right;
    final y1 = _localBounds.bottom;

    canvas.save();
    if (topJellyShift != Offset.zero) {
      canvas.translate(topJellyShift.dx, topJellyShift.dy);
    }

    // 1. Inner Glass Specular Reflections (clipped to `_topPath`)
    canvas.save();
    canvas.clipPath(_topPath);

    // 1a. Bright glossy white top glass shoulder rim (`y0 .. y0 + 0.16 * cellSize`)
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(x0, y0, x1, y0 + cellSize * 0.17));
    canvas.drawPath(
      _liquidCavityPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (cellSize * 0.036).clamp(1.6, 3.2)
        ..shader = ui.Gradient.linear(
          Offset(x0, y0),
          Offset(x0, y0 + cellSize * 0.17),
          [
            Colors.white.withValues(alpha: 0.86),
            const Color(0xFFD8F2FF).withValues(alpha: 0.35),
            Colors.white.withValues(alpha: 0.0),
          ],
          const [0.0, 0.52, 1.0],
        ),
    );
    canvas.restore();

    // 1b. Thin vertical inner glass wall specular streaks along left & right walls
    canvas.drawPath(
      _innerHighlightPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (cellSize * 0.022).clamp(1.0, 2.0)
        ..shader = ui.Gradient.linear(
          Offset(x0, y0),
          Offset(x0, y1),
          [
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.24),
            Color.lerp(style.topBright, Colors.white, 0.55)!
                .withValues(alpha: 0.45),
          ],
          const [0.0, 0.38, 1.0],
        ),
    );

    // 1c. Thick rounded glass base refraction highlight along the bottom floor (`y1 - 0.12 * cellSize .. y1`)
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(x0, y1 - cellSize * 0.12, x1, y1));
    canvas.drawPath(
      _liquidCavityPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = (cellSize * 0.038).clamp(1.6, 3.4)
        ..color = Color.lerp(style.topBright, Colors.white, 0.65)!
            .withValues(alpha: 0.72),
    );
    canvas.restore();

    canvas.restore();

    // 2. Crisp Outer Crystal-Glass Contour (`_topPath`) — icy blue-white around empty top, jewel-tinted around liquid!
    final outerGlassStrokeW = (cellSize * 0.026).clamp(1.3, 2.3);
    canvas.drawPath(
      _topPath,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = outerGlassStrokeW
        ..strokeJoin = ui.StrokeJoin.round
        ..shader = ui.Gradient.linear(
          Offset(x0, y0),
          Offset(x0, y1),
          [
            const Color(0xFFD8EEFF).withValues(alpha: 0.82),
            const Color(0xFF90C8FF).withValues(alpha: 0.62),
            Color.lerp(style.rimHighlight, Colors.white, 0.38)!
                .withValues(alpha: 0.86),
            Color.lerp(style.topBright, Colors.white, 0.48)!
                .withValues(alpha: 0.90),
          ],
          const [0.0, 0.26, 0.68, 1.0],
        ),
    );

    canvas.restore();
  }

  void _drawWinFractureCracks(Canvas canvas, BlockColorStyle style) {
    final reach = _winFractureProgress.clamp(0.0, 1.0);
    final fade = (1.0 - (_winCrumbleProgress / 0.85)).clamp(0.0, 1.0);
    final alpha = (reach * fade).clamp(0.0, 1.0);
    if (alpha <= 0.02) return;

    final diag = math.sqrt(
      _localBounds.width * _localBounds.width +
          _localBounds.height * _localBounds.height,
    );
    final radius = math.max(16.0, diag * 0.65);
    final sloshShift = Offset(
      math.sin(_sandShimmerClock * 14.0) * cellSize * 0.18,
      math.cos(_sandShimmerClock * 11.5) * cellSize * 0.14,
    );
    final glowCenter = _visualPivotLocal + sloshShift;
    final crestColor = Color.lerp(style.rimHighlight, Colors.white, 0.72)!;

    _sandErosionPaint.shader = ui.Gradient.radial(
      glowCenter,
      radius,
      [
        Colors.white.withValues(alpha: (0.58 * alpha).clamp(0.0, 1.0)),
        crestColor.withValues(alpha: (0.36 * alpha).clamp(0.0, 1.0)),
        style.topBright.withValues(alpha: 0.0),
      ],
      const [0.0, 0.52, 1.0],
    );
    canvas.save();
    if (_lastLiquidWaveClipPath != null) {
      canvas.clipPath(_lastLiquidWaveClipPath!);
    }
    canvas.drawPath(_liquidCavityPath, _sandErosionPaint);
    canvas.restore();
  }

  void _drawExtrudedOpaqueWall(
    Canvas canvas,
    Paint opaqueWallPaint,
    Offset topJellyShift,
    double effectiveLipDepth,
  ) {
    if (topJellyShift.distance <= 0.35 &&
        (effectiveLipDepth - _lipDepth).abs() <= 0.35) {
      canvas.drawPath(_wallPath, opaqueWallPaint);
      return;
    }
    for (final h in const [0.0, 0.14, 0.28, 0.42, 0.56, 0.70, 0.84, 0.94]) {
      canvas.save();
      canvas.translate(
        topJellyShift.dx * h,
        effectiveLipDepth * (1.0 - h) + topJellyShift.dy * h,
      );
      canvas.drawPath(_topPath, opaqueWallPaint);
      canvas.restore();
    }
  }

  /// Solid surface renderer used ONLY for Dud (`model.isDud`) and Ice-Covered (`_isIceCovered`) obstacles.
  void _drawBodySurface(
    Canvas canvas,
    BlockColorStyle style, {
    required Offset topJellyShift,
    required double effectiveLipDepth,
  }) {
    final lipKey = (effectiveLipDepth * 16.0).round();
    final nextBodyKey = (style.topBright, style.bottomLip, _isIceCovered, lipKey);
    if (_cachedBodyStyleKey != nextBodyKey) {
      _cachedBodyStyleKey = nextBodyKey;
      final topCrease = Color.lerp(style.bottomLip, Colors.black, 0.08)!;
      final baseShade = Color.lerp(style.bottomLip, Colors.black, 0.16)!;
      _cachedWallPaint.shader = ui.Gradient.linear(
        Offset(_localBounds.left, _localBounds.bottom - cellSize * 0.15),
        Offset(_localBounds.left, _localBounds.bottom + effectiveLipDepth),
        _isIceCovered
            ? const [Color(0xFF2B8CFA), Color(0xFF1876EE), Color(0xFF105EC8)]
            : [topCrease, style.bottomLip, baseShade],
        const [0.0, 0.45, 1.0],
      );
      _cachedBaseStrokePaint.color = baseShade.withValues(alpha: 0.72);
      _cachedTopPaint.shader = ui.Gradient.linear(
        _localBounds.topLeft,
        Offset(_localBounds.left + _localBounds.width * 0.75, _localBounds.bottom),
        [
          Color.lerp(style.topBright, Colors.white, 0.18)!,
          style.topBright,
          style.topMid,
        ],
        const [0.0, 0.36, 1.0],
      );
      final rimStrokeW = (cellSize * 0.048).clamp(1.8, 3.8);
      final softRimEnd = Color.lerp(style.topBright, style.rimHighlight, 0.55)!;
      _cachedRimPaint
        ..strokeWidth = rimStrokeW
        ..shader = ui.Gradient.linear(
          _localBounds.topLeft,
          _localBounds.bottomRight,
          [
            Colors.white.withValues(alpha: _isIceCovered ? 0.90 : 0.84),
            style.rimHighlight.withValues(alpha: _isIceCovered ? 0.75 : 0.64),
            softRimEnd.withValues(alpha: _isIceCovered ? 0.62 : 0.44),
          ],
          const [0.0, 0.42, 1.0],
        );
    }

    _drawExtrudedOpaqueWall(
      canvas,
      _cachedWallPaint,
      topJellyShift,
      effectiveLipDepth,
    );

    canvas.save();
    canvas.translate(0, effectiveLipDepth);
    canvas.drawPath(_topPath, _cachedBaseStrokePaint);
    canvas.restore();

    canvas.save();
    canvas.translate(topJellyShift.dx, topJellyShift.dy);
    canvas.drawPath(_topPath, _cachedTopPaint);
    canvas.drawPath(_innerHighlightPath, _cachedRimPaint);
    canvas.restore();
  }

  /// Ticks the Sloshing Water Physics (`ANIM_SONG_SANH` / `FakeWater`) inside the glass block.
  void _tickSandSwarmTrail(double clampedDt, Offset lagCells) {
    _sandShimmerClock += clampedDt;
    final prevPos = _prevSandWorldPos ?? position.clone();
    final dx = position.x - prevPos.x;
    final dy = position.y - prevPos.y;
    _prevSandWorldPos = position.clone();

    final frameMoveDist = math.sqrt(dx * dx + dy * dy);
    final lagMag = lagCells.distance;

    // Smooth slide velocity for horizontal/vertical glass motion streak (`64` in `media_1794051081001.png`)
    final instVel = clampedDt > 1e-4
        ? Offset(dx / clampedDt, dy / clampedDt)
        : Offset.zero;
    final velBlend = (clampedDt * 18.0).clamp(0.0, 1.0);
    _slideStreakVel = Offset.lerp(_slideStreakVel, instVel, velBlend)!;

    if (frameMoveDist > 0.35) {
      _sandTravelDir = Offset(dx / frameMoveDist, dy / frameMoveDist);
    } else if (lagMag > 0.012) {
      _sandTravelDir = Offset(lagCells.dx / lagMag, lagCells.dy / lagMag);
    }

    if (_lastSandGridCol == -999) {
      _lastSandGridCol = model.col;
      _lastSandGridRow = model.row;
    } else if (model.col != _lastSandGridCol || model.row != _lastSandGridRow) {
      final stepDc = (model.col - _lastSandGridCol).toDouble();
      final stepDr = (model.row - _lastSandGridRow).toDouble();
      _lastSandGridCol = model.col;
      _lastSandGridRow = model.row;
      if (isDragging || _followState == _FollowState.dragging) {
        _sandReformFlash = math.max(_sandReformFlash, 0.78);
        _sandErosionIntensity = math.max(_sandErosionIntensity, 0.94);
        final impulseSign = stepDc.abs() > 0.1
            ? (stepDc >= 0 ? -1.0 : 1.0)
            : (stepDr >= 0 ? 1.0 : -1.0);
        _waterSloshVel += impulseSign * 7.2;
      }
    }

    final activelyDragging =
        isDragging || _followState == _FollowState.dragging;
    final activelyMerging = isSurvivorCandidate ||
        isPartnerCandidate ||
        _mergePulseElapsed >= 0 ||
        _numberPreviewMode == _NumberPreviewMode.settling;
    final isMoving = frameMoveDist > 0.20 || lagMag > 0.010;

    double targetTilt = 0.0;
    if (activelyDragging || activelyMerging) {
      final vxNorm = (dx / math.max(1.0, cellSize * 0.14)).clamp(-1.0, 1.0);
      final vyNorm = (dy / math.max(1.0, cellSize * 0.16)).clamp(-1.0, 1.0);
      final oscWave = math.sin(_sandShimmerClock * 15.0) *
          (activelyMerging ? 0.48 : (isMoving ? 0.42 : 0.28));
      targetTilt = (-vxNorm * 0.62 -
              lagCells.dx * 1.95 +
              vyNorm * 0.42 -
              lagCells.dy * 0.85 +
              oscWave)
          .clamp(-0.78, 0.78);
    }

    const sloshK = 280.0;
    final sloshC = 2.0 * 0.22 * math.sqrt(sloshK);
    final subSteps = (clampedDt / 0.008).ceil().clamp(1, 6);
    final subDt = clampedDt / subSteps;
    for (int s = 0; s < subSteps; s++) {
      final accel =
          (targetTilt - _waterSloshTilt) * sloshK - _waterSloshVel * sloshC;
      _waterSloshVel += accel * subDt;
      _waterSloshTilt += _waterSloshVel * subDt;
    }
    if (_waterSloshTilt.abs() < 8e-3 &&
        _waterSloshVel.abs() < 0.12 &&
        targetTilt.abs() < 1e-4) {
      _waterSloshTilt = 0.0;
      _waterSloshVel = 0.0;
    }

    if (activelyDragging || activelyMerging) {
      final targetErosion = activelyMerging
          ? 0.92
          : (0.62 +
                  (frameMoveDist / (cellSize * 0.14)) * 0.45 +
                  (lagMag / 0.14) * 0.42)
              .clamp(0.60, 1.0);
      _sandErosionIntensity = ui.lerpDouble(
        _sandErosionIntensity,
        targetErosion,
        (clampedDt * 16.0).clamp(0.0, 1.0),
      )!;
    } else {
      if (_sandErosionIntensity > 0.55 && _sandReformFlash <= 0.01) {
        _sandReformFlash = 0.85;
        final recoilSign = _sandTravelDir.dx.abs() > 0.1
            ? (_sandTravelDir.dx >= 0 ? 1.0 : -1.0)
            : 1.0;
        _waterSloshVel += recoilSign * 6.5;
      }
      _sandErosionIntensity =
          math.max(0.0, _sandErosionIntensity - clampedDt * 1.45);
    }

    if (_sandReformFlash > 0.0) {
      _sandReformFlash = math.max(0.0, _sandReformFlash - clampedDt * 2.65);
    }

    // Smooth C1-continuous wave energy & phase integration (zero phase jumps on click/drag!)
    final tapBoost = _tapElapsed >= 0
        ? (1.0 -
                (_tapElapsed / math.max(0.05, visualSettings.tapDuration))
                    .clamp(0.0, 1.0)) *
            0.94
        : 0.0;
    final shakeBoost = _shakeElapsed >= 0 ? 0.88 : 0.0;
    final targetWaveEnergy = math
        .max(
          _sandErosionIntensity,
          math.max(
            _sandReformFlash * 0.92,
            math.max(
              _waterSloshTilt.abs() * 1.38,
              math.max(
                tapBoost,
                math.max(shakeBoost, _winFractureProgress * 0.92),
              ),
            ),
          ),
        )
        .clamp(0.0, 1.0);
    final energyRate = targetWaveEnergy > _smoothedWaveEnergy ? 18.0 : 3.8;
    final energyAlpha = 1.0 - math.exp(-clampedDt * energyRate);
    _smoothedWaveEnergy =
        ui.lerpDouble(_smoothedWaveEnergy, targetWaveEnergy, energyAlpha)!;
    if (_smoothedWaveEnergy < 4e-3 && targetWaveEnergy <= 1e-4) {
      _smoothedWaveEnergy = 0.0;
    }
    _liquidWavePhase = (_liquidWavePhase +
            clampedDt * (2.55 + 6.4 * _smoothedWaveEnergy)) %
        (math.pi * 200.0);

    if (_sandSwarmGrains.isNotEmpty) {
      _sandSwarmGrains.clear();
    }
    if (_sandTrailCentersWorld.isNotEmpty) {
      _sandTrailCentersWorld.clear();
    }
  }

  /// `_MergeCylinder` Smoothstep Color Wipe clipped strictly to the ~75% liquid & meniscus region
  /// so the top ~25% crystal-glass headspace remains 100% transparent during hold-to-merge & commit!
  void _drawMergeCylinderShaderOverlay(
    Canvas canvas, {
    required BlockColorStyle targetStyle,
    required Offset topJellyShift,
    required double effectiveLipDepth,
    required double liftPx,
    required double finalScaleX,
    required double finalScaleY,
  }) {
    final sx = finalScaleX.abs() < 1e-3 ? 1.0 : finalScaleX;
    final sy = finalScaleY.abs() < 1e-3 ? 1.0 : finalScaleY;
    final dxWorld = _mergeCylinderWorldCenter.x -
        (position.x + _visualPivotLocal.dx + _shakeOffsetPx.dx);
    final dyWorld = _mergeCylinderWorldCenter.y -
        (position.y + _visualPivotLocal.dy + _shakeOffsetPx.dy);
    final localCenter = Offset(
      _visualPivotLocal.dx + dxWorld / sx,
      _visualPivotLocal.dy + dyWorld / sy + liftPx,
    );

    final avgScale = (sx + sy) * 0.5;
    final r = _mergeCylinderRadius / avgScale;
    final s = math.max(1e-3, _mergeCylinderSoftness / avgScale);
    if (r <= 0.2) return;

    final innerEdge = r - s;
    final alphas = <double>[];
    final stops = <double>[];

    double smoothBlend(double u) {
      final c = u.clamp(0.0, 1.0);
      return 1.0 - c * c * (3.0 - 2.0 * c);
    }

    if (innerEdge >= 0.0) {
      final s0 = (innerEdge / r).clamp(0.0, 1.0);
      alphas.add(1.0);
      stops.add(0.0);
      for (final f in const [0.0, 0.25, 0.50, 0.75, 1.0]) {
        final stop = (s0 + (1.0 - s0) * f).clamp(0.0, 1.0);
        if (stops.isNotEmpty && (stop - stops.last).abs() < 1e-4) continue;
        alphas.add(smoothBlend(f));
        stops.add(stop);
      }
    } else {
      final u0 = (1.0 - r / s).clamp(0.0, 1.0);
      for (final f in const [0.0, 0.25, 0.50, 0.75, 1.0]) {
        final u = u0 + (1.0 - u0) * f;
        alphas.add(smoothBlend(u));
        stops.add(f);
      }
    }

    if (alphas.length < 2) return;

    final topColors = <Color>[
      for (int i = 0; i < alphas.length; i++)
        Color.lerp(targetStyle.topMid, targetStyle.topBright, 1.0 - stops[i] * 0.55)!
            .withValues(alpha: 0.94 * alphas[i]),
    ];

    final topCenter = localCenter - topJellyShift;
    _cylinderTopPaint.shader =
        ui.Gradient.radial(topCenter, r, topColors, stops);

    canvas.save();
    canvas.translate(topJellyShift.dx, topJellyShift.dy);
    canvas.clipPath(_liquidCavityPath);
    if (_lastLiquidWaveClipPath != null) {
      canvas.clipPath(_lastLiquidWaveClipPath!);
    }
    canvas.drawRect(_localBounds, _cylinderTopPaint);
    canvas.restore();

    final cylAlpha = (r / math.max(1.0, cellSize * 0.90)).clamp(0.0, 1.0);
    if (cylAlpha > 0.05) {
      _drawGlassHalfFullLiquidAndWave(
        canvas,
        targetStyle,
        isIdleAtRest: false,
        topJellyShift: topJellyShift,
        alphaMultiplier: cylAlpha,
      );
    }
  }

  /// `_MergeOverlap` Seam Fusion clipped to the ~75% liquid region so the empty top glass stays clear!
  void _drawMergeOverlapSeamFusion(
    Canvas canvas, {
    required Offset topJellyShift,
    required double liftPx,
  }) {
    final targetCol = _mergeOverlapTopTargetColor;
    if (targetCol == null) return;

    _mergeOverlapPaint.color = targetCol.withValues(
      alpha: (0.76 * _mergeOverlapStrength).clamp(0.0, 0.88),
    );

    final partnerLocal = _mergeOverlapPartnerLocalPath;
    final partnerOrigin = _mergeOverlapPartnerWorldOrigin;
    if (partnerLocal != null && partnerOrigin != null) {
      canvas.save();
      canvas.translate(topJellyShift.dx, topJellyShift.dy);
      canvas.clipPath(_liquidCavityPath);
      if (_lastLiquidWaveClipPath != null) {
        canvas.clipPath(_lastLiquidWaveClipPath!);
      }
      canvas.translate(
        partnerOrigin.x - position.x - topJellyShift.dx,
        partnerOrigin.y - position.y + liftPx - topJellyShift.dy,
      );
      canvas.drawPath(partnerLocal, _mergeOverlapPaint);
      canvas.restore();
      return;
    }

    final partnerWorld = _mergeOverlapPartnerWorldPath;
    if (partnerWorld == null) return;
    canvas.save();
    canvas.translate(topJellyShift.dx, topJellyShift.dy);
    canvas.clipPath(_liquidCavityPath);
    if (_lastLiquidWaveClipPath != null) {
      canvas.clipPath(_lastLiquidWaveClipPath!);
    }
    canvas.translate(
      -position.x - topJellyShift.dx,
      -position.y + liftPx - topJellyShift.dy,
    );
    canvas.drawPath(partnerWorld, _mergeOverlapPaint);
    canvas.restore();
  }

  void _drawIceFrostAndSheen(Canvas canvas, Offset topJellyShift) {
    canvas.save();
    canvas.translate(topJellyShift.dx, topJellyShift.dy);
    canvas.clipPath(_topPath);

    if (_iceBlocksTex != null) {
      canvas.drawImageRect(
        _iceBlocksTex!,
        Rect.fromLTWH(
          0,
          0,
          _iceBlocksTex!.width.toDouble(),
          _iceBlocksTex!.height.toDouble(),
        ),
        _localBounds.inflate(cellSize * 0.1),
        _iceFrostPaint,
      );
    }

    canvas.drawPath(_sharedGeom.iceSheenPath, _iceSheenPaint);
    canvas.restore();
  }

  // --- Exact `NumberComponentView` & `MovementComponentView` Layout Engine ---

  DigitLayoutMetrics _metricsForDigits(int digitCount) {
    const list = UnityComponentVisualConfig.metricsByDigitCount;
    final idx = (digitCount - 1).clamp(0, list.length - 1);
    return list[idx];
  }

  Size _measureUnscaledNumberAtMetrics(String text, DigitLayoutMetrics m) {
    final cacheKey = '$text|${m.fontSize}|${(cellSize * 4).round()}';
    final cached = _metricsTextSizeCache[cacheKey];
    if (cached != null) return cached;

    final pxFont = m.fontSize * _tmpUnitToCellRatio * cellSize;
    final letterSp = (m.characterSpacing * 0.0115) * pxFont;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: pxFont,
          letterSpacing: letterSp,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final measured = Size(tp.width * m.horizontalScale, tp.height);
    if (_metricsTextSizeCache.length >= 128) {
      _metricsTextSizeCache.remove(_metricsTextSizeCache.keys.first);
    }
    _metricsTextSizeCache[cacheKey] = measured;
    return measured;
  }

  double _growIntoRoom({
    required String text,
    required DigitLayoutMetrics m,
    required double fontScale,
    required double roomWidthPx,
  }) {
    final baseSize = m.fontSize * fontScale;
    if (roomWidthPx <= cellSize * 1.001) {
      return baseSize;
    }
    final availWidth =
        roomWidthPx - 2.0 * UnityComponentVisualConfig.roomSideMargin * cellSize;
    final curWidth = _measureUnscaledNumberAtMetrics(text, m).width * fontScale;
    if (curWidth <= 1e-3) return baseSize;
    return (curWidth < availWidth) ? (baseSize * availWidth / curWidth) : baseSize;
  }

  _ResolvedPieceLabelLayout _getBaseLabelAndArrowLayout() {
    if (_cachedBaseLabelLayout != null &&
        _cachedBaseLayoutNumber == model.number &&
        _cachedBaseLayoutMovement == model.movement) {
      return _cachedBaseLabelLayout!;
    }
    final resolved = _resolveLabelAndArrowLayout();
    _cachedBaseLabelLayout = resolved;
    _cachedBaseLayoutNumber = model.number;
    _cachedBaseLayoutMovement = model.movement;
    return resolved;
  }

  _ResolvedPieceLabelLayout _getPreviewLabelAndArrowLayout(int previewVal) {
    if (_cachedPreviewLabelLayout != null &&
        _cachedPreviewLayoutNumber == previewVal &&
        _cachedPreviewLayoutMovement == model.movement) {
      return _cachedPreviewLabelLayout!;
    }
    final resolved = _resolveLabelAndArrowLayout(overrideNumber: previewVal);
    _cachedPreviewLabelLayout = resolved;
    _cachedPreviewLayoutNumber = previewVal;
    _cachedPreviewLayoutMovement = model.movement;
    return resolved;
  }

  _ResolvedPieceLabelLayout _resolveLabelAndArrowLayout({
    int? overrideNumber,
    bool? overridePinned,
  }) {
    final numVal = overrideNumber ?? model.number;
    final text = numVal != null ? '$numVal' : '2';
    final m = _metricsForDigits(text.length);
    final isPinned = overridePinned ?? model.movement.isPinned;

    final arrowLayout = isPinned
        ? null
        : PolyominoPathBuilder.resolveMovementArrows(
            model: model,
            cellSize: cellSize,
          );

    NumberLabelLayoutMode mode = NumberLabelLayoutMode.full;
    Offset labelCenter = _labelAnchorLocal;

    double arrowInnerGapBasePx = 0.0;
    double arrowMaxPushPx = 0.0;

    if (isPinned && _screwAnchors.isNotEmpty) {
      mode = NumberLabelLayoutMode.betweenPins;
      labelCenter = _labelAnchorLocal;
    } else if (arrowLayout != null) {
      if (arrowLayout.isCompact) {
        mode = arrowLayout.isHorizontal
            ? NumberLabelLayoutMode.compactBetweenSideArrows
            : NumberLabelLayoutMode.compactCentre;
        labelCenter = _labelAnchorLocal;
      } else if (arrowLayout.hasArrowGap) {
        mode = NumberLabelLayoutMode.betweenArrows;
        // `NumberComponentView.SetLayout`: `BetweenArrows => arrowGap.Center`!
        labelCenter = (arrowLayout.negRestPos + arrowLayout.posRestPos) * 0.5;

        final arrowHalfSpanAlong = _arrowHalfReachAlongPx(
          isHorizontal: arrowLayout.isHorizontal,
          arrowScale: arrowLayout.arrowScale,
          includeShadow: false,
        );
        final arrowOuterHalfReach = _arrowHalfReachAlongPx(
          isHorizontal: arrowLayout.isHorizontal,
          arrowScale: arrowLayout.arrowScale,
          includeShadow: true,
        );
        final negCoord = arrowLayout.isHorizontal
            ? arrowLayout.negRestPos.dx
            : arrowLayout.negRestPos.dy;
        final posCoord = arrowLayout.isHorizontal
            ? arrowLayout.posRestPos.dx
            : arrowLayout.posRestPos.dy;
        final negInner = negCoord + arrowHalfSpanAlong;
        final posInner = posCoord - arrowHalfSpanAlong;
        arrowInnerGapBasePx = math.max(0.05 * cellSize, posInner - negInner);

        final negOuter = negCoord - arrowOuterHalfReach;
        final posOuter = posCoord + arrowOuterHalfReach;
        final edgeMargin =
            UnityComponentVisualConfig.pushedArrowEdgeMargin * cellSize;
        arrowMaxPushPx = math.max(
          0.0,
          math.min(
            negOuter - (arrowLayout.negativeCellLimit + edgeMargin),
            (arrowLayout.positiveCellLimit - edgeMargin) - posOuter,
          ),
        );
      }
    }

    final roomWidthPx = model.computeLabelRoomWidthInCells(
          labelCenter.dx / cellSize,
          labelCenter.dy / cellSize,
        ) *
        cellSize;

    final fontScale = (mode == NumberLabelLayoutMode.compactCentre ||
            mode == NumberLabelLayoutMode.compactBetweenSideArrows)
        ? UnityComponentVisualConfig.compactScale
        : 1.0;

    double rawTmpFontSize;
    double pushPx = 0.0;

    switch (mode) {
      case NumberLabelLayoutMode.compactCentre:
        rawTmpFontSize = m.fontSize * fontScale;
        break;

      case NumberLabelLayoutMode.compactBetweenSideArrows:
        // `BetweenSideArrowsFit(text)` against `WidestFittingNumber = "88"`
        final refW =
            _measureUnscaledNumberAtMetrics('88', _metricsForDigits(2)).width;
        final curW = _measureUnscaledNumberAtMetrics(text, m).width;
        final fit = curW > 1e-3 ? math.min(1.0, refW / curW) : 1.0;
        rawTmpFontSize = m.fontSize * fontScale * fit;
        break;

      case NumberLabelLayoutMode.betweenArrows:
        final isH = arrowLayout!.isHorizontal;
        final prefSize = _measureUnscaledNumberAtMetrics(text, m);
        final along = math.max(1e-3, isH ? prefSize.width : prefSize.height);
        final capRatio =
            math.min(1.0, UnityComponentVisualConfig.maxFontSize / m.fontSize);
        final marginPx = UnityComponentVisualConfig.arrowMargin * cellSize;
        final needed = along * capRatio + 2.0 * marginPx;
        pushPx = ((needed - arrowInnerGapBasePx) * 0.5)
            .clamp(0.0, arrowMaxPushPx);

        final usableGap =
            math.max(0.05 * cellSize, arrowInnerGapBasePx + 2.0 * pushPx - 2.0 * marginPx);
        double fitted = m.fontSize * usableGap / along;
        if (!isH) {
          fitted = math.min(
            fitted,
            _growIntoRoom(
              text: text,
              m: m,
              fontScale: 1.0,
              roomWidthPx: roomWidthPx,
            ),
          );
        }
        rawTmpFontSize = fitted;
        break;

      case NumberLabelLayoutMode.betweenPins:
        final hi = math.min(
          _growIntoRoom(
            text: text,
            m: m,
            fontScale: 1.0,
            roomWidthPx: roomWidthPx,
          ),
          UnityComponentVisualConfig.maxFontSize,
        );
        final prefSize = _measureUnscaledNumberAtMetrics(text, m);
        final unitW = prefSize.width / m.fontSize;
        final unitH = prefSize.height / m.fontSize;
        final pinMaxPushPx = UnityComponentVisualConfig.maxPinPush * cellSize;

        (bool ok, double reqPush) tryPushPinsFor(double testTmpFont) {
          final margin = UnityComponentVisualConfig.arrowMargin * cellSize;
          final halfW = unitW * testTmpFont * 0.5 + margin;
          final halfH = unitH * testTmpFont * 0.5 + margin;
          if (2.0 * halfW > roomWidthPx * 1.001) return (false, 0.0);

          bool clearsAt(double push) {
            final nRect = Rect.fromCenter(
              center: labelCenter,
              width: halfW * 2.0,
              height: halfH * 2.0,
            );
            for (final anchor in _screwAnchors) {
              final screwDiam = cellSize * 0.375 * anchor.baseScale;
              final pt = anchor.positionWithPinPush(push);
              final pRect = Rect.fromCenter(
                center: pt,
                width: screwDiam,
                height: screwDiam,
              );
              if (nRect.overlaps(pRect)) return false;
            }
            return true;
          }

          if (!clearsAt(pinMaxPushPx)) return (false, pinMaxPushPx);
          if (clearsAt(0.0)) return (true, 0.0);

          double lo = 0.0, hiP = pinMaxPushPx;
          for (int i = 0; i < _pinFitSteps; i++) {
            final mid = (lo + hiP) * 0.5;
            if (clearsAt(mid)) {
              hiP = mid;
            } else {
              lo = mid;
            }
          }
          return (true, hiP);
        }

        final hiAttempt = tryPushPinsFor(hi);
        if (hiAttempt.$1) {
          rawTmpFontSize = hi;
          pushPx = hiAttempt.$2;
        } else {
          double loF = 0.0, hiF = hi;
          for (int i = 0; i < _pinFitSteps; i++) {
            final midF = (loF + hiF) * 0.5;
            if (tryPushPinsFor(midF).$1) {
              loF = midF;
            } else {
              hiF = midF;
            }
          }
          rawTmpFontSize = loF;
          pushPx = tryPushPinsFor(loF).$2;
        }
        break;

      case NumberLabelLayoutMode.full:
        rawTmpFontSize = _growIntoRoom(
          text: text,
          m: m,
          fontScale: fontScale,
          roomWidthPx: roomWidthPx,
        );
        break;
    }

    final finalTmpFont = math.min(
      math.max(1.2, rawTmpFontSize),
      UnityComponentVisualConfig.maxFontSize,
    );

    return _ResolvedPieceLabelLayout(
      mode: mode,
      labelCenterLocal: labelCenter,
      roomWidthPx: roomWidthPx,
      finalTmpFontSize: finalTmpFont,
      digitMetrics: m,
      arrowOrPinPushPx: pushPx,
      arrowLayout: arrowLayout,
    );
  }

  double _arrowHalfReachAlongPx({
    required bool isHorizontal,
    required double arrowScale,
    required bool includeShadow,
  }) {
    final topImg = _arrowTopImg;
    final strokeImg = _arrowOutlineImg;
    // Exact Unity `MovementMechanicView`: `Movement_Single-Horizontal_Top.png` (`120x195`, `PPU=100`)
    // at parent `sc = 0.220` -> `1.95 * 0.220 = 0.429 * cellSize` height (`0.236 * cs` compact).
    final topTargetH = cellSize * 0.429 * arrowScale;
    if (topImg == null || strokeImg == null) {
      return topTargetH * 0.40;
    }
    final pxScale = topTargetH / topImg.height;
    final w = strokeImg.width * pxScale * 0.974;
    final shadowExtra = includeShadow ? cellSize * 0.036 * arrowScale : 0.0;
    return w * 0.5 + shadowExtra;
  }

  void _drawPinnedScrews(
    Canvas canvas,
    BlockColorStyle style,
    List<PinnedScrewAnchor> anchors, {
    required double pinPushPx,
    required double extraScaleMultiplier,
  }) {
    if (extraScaleMultiplier <= 0.01) return;
    // Proportional to `cellSize` with NO `20px` upper clamp (`0.42 * 0.65 = 0.273 * cellSize`
    // on `1x1`, matching `Icon_Mechanic_Cage.png` `68/252 = 0.270 * cellSize` 1:1!).
    final baseUnitDiam = math.max(8.0, cellSize * 0.42);
    final cleanedList = ScrewTextureCleaner.cleanedScrews;
    _screwShadowPaint.color =
        Color.lerp(style.screwDark, Colors.black, 0.12)!.withValues(alpha: 0.82);

    for (int i = 0; i < anchors.length; i++) {
      final anchor = anchors[i];
      final screwDiam =
          baseUnitDiam * anchor.baseScale * extraScaleMultiplier;
      if (screwDiam <= 0.5) continue;
      final r = screwDiam * 0.445;
      final pt = anchor.positionWithPinPush(pinPushPx);

      // Block-colored drop shadow underneath the hexagonal steel bolt
      canvas.drawCircle(
        pt + Offset(0, r * 0.24),
        r * 0.98,
        _screwShadowPaint,
      );

      final screwImg = cleanedList.isNotEmpty
          ? cleanedList[i % cleanedList.length]
          : _screwFallbackImg;

      if (screwImg != null && cleanedList.isNotEmpty) {
        // Cool silver-lavender steel bolt head (`Icon_Mechanic_Cage.png`) — never tinted green/pink!
        canvas.drawImageRect(
          screwImg,
          Rect.fromLTWH(
            0,
            0,
            screwImg.width.toDouble(),
            screwImg.height.toDouble(),
          ),
          Rect.fromCenter(center: pt, width: screwDiam, height: screwDiam),
          _screwBoltPaint,
        );
      } else {
        canvas.drawCircle(
          pt,
          r * 0.92,
          _screwFallbackCirclePaint,
        );
      }
    }
  }

  /// Exact `MovementComponentView` (`MovementMechanicView.prefab`, `PPU = 100`, `sc = 0.220`):
  /// - `Top` (`120x195`): `0.429 * cellSize * arrowScale` height (`0.236 * cs` compact on `1x1`).
  /// - `Stroke` (`160x238`): local `sc = 0.974` colored with `style.arrowStroke`.
  /// - `Shadow` (`137x192`): local `sc = 1.490` colored with `style.arrowShadow` and drop offset.
  /// - `Movement_Double_Horizontal/Vertical` (`168x129`): `sc = 0.500` -> `0.84 * cellSize` span.
  void _drawMovementArrows(
    Canvas canvas,
    BlockColorStyle style,
    MovementArrowLayout layout, {
    required double arrowPushPx,
  }) {
    if (layout.isCombined) {
      final comb =
          layout.isHorizontal ? _arrowHorizCombinedImg : _arrowVertCombinedImg;
      if (comb != null) {
        final targetSpan = cellSize * 0.84;
        final dst = layout.isHorizontal
            ? Rect.fromCenter(
                center: layout.negRestPos,
                width: targetSpan,
                height: targetSpan * (comb.height / comb.width),
              )
            : Rect.fromCenter(
                center: layout.negRestPos,
                width: targetSpan * (comb.width / comb.height),
                height: targetSpan,
              );
        canvas.drawImageRect(
          comb,
          Rect.fromLTWH(0, 0, comb.width.toDouble(), comb.height.toDouble()),
          dst,
          _arrowTopPaint,
        );
        return;
      }
    }

    final pushVec = layout.hasArrowGap
        ? (layout.isHorizontal
            ? Offset(arrowPushPx, 0.0)
            : Offset(0.0, arrowPushPx))
        : Offset.zero;
    final negPos = layout.negRestPos - pushVec;
    final posPos = layout.posRestPos + pushVec;

    if (_arrowShadowImg != null &&
        _arrowOutlineImg != null &&
        _arrowTopImg != null) {
      final topImg = _arrowTopImg!;
      final strokeImg = _arrowOutlineImg!;
      final shadowImg = _arrowShadowImg!;

      final topTargetH = cellSize * 0.429 * layout.arrowScale;
      final pxScale = topTargetH / topImg.height;
      final strokeScale = pxScale * 0.974;
      final shadowScale = pxScale * 1.490;

      final topSrc = Rect.fromLTWH(
        0,
        0,
        topImg.width.toDouble(),
        topImg.height.toDouble(),
      );
      final strokeSrc = Rect.fromLTWH(
        0,
        0,
        strokeImg.width.toDouble(),
        strokeImg.height.toDouble(),
      );
      final shadowSrc = Rect.fromLTWH(
        0,
        0,
        shadowImg.width.toDouble(),
        shadowImg.height.toDouble(),
      );

      final topDst = Rect.fromCenter(
        center: Offset.zero,
        width: topImg.width * pxScale,
        height: topImg.height * pxScale,
      );
      final strokeDst = Rect.fromCenter(
        center: Offset.zero,
        width: strokeImg.width * strokeScale,
        height: strokeImg.height * strokeScale,
      );
      final shadowDst = Rect.fromCenter(
        center: Offset.zero,
        width: shadowImg.width * shadowScale,
        height: shadowImg.height * shadowScale,
      );

      final worldDropY = cellSize * 0.034 * layout.arrowScale;
      if (_cachedArrowShadowColor != style.arrowShadow) {
        _cachedArrowShadowColor = style.arrowShadow;
        _arrowShadowPaint.colorFilter = ColorFilter.mode(
          style.arrowShadow.withValues(alpha: 0.72),
          BlendMode.modulate,
        );
      }
      if (_cachedArrowStrokeColor != style.arrowStroke) {
        _cachedArrowStrokeColor = style.arrowStroke;
        _arrowStrokePaint.colorFilter =
            ColorFilter.mode(style.arrowStroke, BlendMode.modulate);
      }

      void drawSingleArrowHead({
        required Offset pos,
        required double rotationRad,
        bool flipX = false,
      }) {
        canvas.save();
        canvas.translate(pos.dx, pos.dy + worldDropY);
        if (flipX) canvas.scale(-1.0, 1.0);
        if (rotationRad != 0.0) canvas.rotate(rotationRad);
        canvas.drawImageRect(
          shadowImg,
          shadowSrc,
          shadowDst,
          _arrowShadowPaint,
        );
        canvas.restore();

        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        if (flipX) canvas.scale(-1.0, 1.0);
        if (rotationRad != 0.0) canvas.rotate(rotationRad);
        canvas.drawImageRect(
          strokeImg,
          strokeSrc,
          strokeDst,
          _arrowStrokePaint,
        );
        canvas.drawImageRect(topImg, topSrc, topDst, _arrowTopPaint);
        canvas.restore();
      }

      if (layout.isHorizontal) {
        drawSingleArrowHead(pos: negPos, rotationRad: 0.0, flipX: true);
        drawSingleArrowHead(pos: posPos, rotationRad: 0.0);
      } else {
        drawSingleArrowHead(pos: negPos, rotationRad: -math.pi * 0.5);
        drawSingleArrowHead(pos: posPos, rotationRad: math.pi * 0.5);
      }
    }
  }

  /// Authentic `IceCountBadge` (`IceMechanicView.prefab` & `Icon_Mechanic_Ice.png`):
  /// True ~1:1 aspect `IceLock.png` (`220x222`) + crisp solid `#122E7A` `PoetsenOne` digits,
  /// animated by the 23-frame `0.3833s` `"Pop"` clip (`1.0 -> 1.62907 -> 1.0`) before shattering!
  void _drawFrozenLockBadge(Canvas canvas, int targetNum) {
    final (spanCx, spanCy) = model.spanCenterInCells();
    final badgeCenter = model.coversLabel(spanCx, spanCy)
        ? Offset(spanCx * cellSize, spanCy * cellSize)
        : _labelAnchorLocal;

    final lockImg = _iceLockImg;
    final aspect =
        lockImg != null ? (lockImg.width / lockImg.height) : (220.0 / 222.0);
    final badgeH = cellSize * 0.70;
    final badgeW = badgeH * aspect;
    final dst = Rect.fromCenter(
      center: badgeCenter,
      width: badgeW,
      height: badgeH,
    );

    if (lockImg != null) {
      canvas.drawImageRect(
        lockImg,
        Rect.fromLTWH(
          0,
          0,
          lockImg.width.toDouble(),
          lockImg.height.toDouble(),
        ),
        dst,
        _glyphSpritePaint,
      );
    }

    final textStr = '$targetNum';
    final digits = textStr.length;
    final fontSize = cellSize *
        (digits <= 2
            ? 0.242
            : digits == 3
                ? 0.195
                : 0.158);

    final popScale = _currentIceBadgePopScale;
    final textCenter = Offset(badgeCenter.dx, badgeCenter.dy + badgeH * 0.115);

    canvas.save();
    canvas.translate(textCenter.dx, textCenter.dy);
    canvas.scale(popScale, popScale);

    final baked = _getOrBakeFrozenBadgeGlyphSprite(textStr, fontSize);
    if (baked != null) {
      canvas.drawImageRect(
        baked.image,
        baked.srcRect,
        baked.dstRect,
        _glyphSpritePaint,
      );
    } else {
      _paintFrozenBadgeGlyphDirect(canvas, textStr, fontSize);
    }
    canvas.restore();
  }

  _BakedGlyphSprite? _getOrBakeFrozenBadgeGlyphSprite(
    String textStr,
    double fontSize,
  ) {
    final key = 'v2|$textStr|${(fontSize * 10).round()}';
    final cached = _frozenBadgeTextSpriteCache[key];
    if (cached != null) return cached;

    try {
      final fillTp = TextPainter(
        text: TextSpan(
          text: textStr,
          style: TextStyle(
            fontFamily: 'PoetsenOne',
            fontSize: fontSize,
            color: const Color(0xFF122E7A),
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const pad = 4.0;
      final logicalW = fillTp.width + pad * 2.0;
      final logicalH = fillTp.height + pad * 2.0;
      const ss = 2.0;
      final imgW = (logicalW * ss).ceil().clamp(4, 512);
      final imgH = (logicalH * ss).ceil().clamp(4, 512);

      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);
      recCanvas.scale(imgW / logicalW, imgH / logicalH);
      recCanvas.translate(logicalW * 0.5, logicalH * 0.5);

      final textOffset = Offset(-fillTp.width * 0.5, -fillTp.height * 0.5);
      fillTp.paint(recCanvas, textOffset);

      final pic = recorder.endRecording();
      final img = pic.toImageSync(imgW, imgH);
      pic.dispose();

      final sprite = _BakedGlyphSprite(
        image: img,
        srcRect: Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
        dstRect: Rect.fromLTWH(
          -logicalW * 0.5,
          -logicalH * 0.5,
          logicalW,
          logicalH,
        ),
      );
      if (_frozenBadgeTextSpriteCache.length >= 48) {
        final oldest =
            _frozenBadgeTextSpriteCache.remove(_frozenBadgeTextSpriteCache.keys.first);
        oldest?.image.dispose();
      }
      _frozenBadgeTextSpriteCache[key] = sprite;
      return sprite;
    } catch (_) {
      return null;
    }
  }

  void _paintFrozenBadgeGlyphDirect(
    Canvas canvas,
    String textStr,
    double fontSize,
  ) {
    final fillTp = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: fontSize,
          color: const Color(0xFF122E7A),
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = Offset(-fillTp.width * 0.5, -fillTp.height * 0.5);
    fillTp.paint(canvas, textOffset);
  }

  /// Coordinates `NumberComponentView` (`_normalNumberSizeFactor`) and floating
  /// `MergeNumberPreview` (`_previewNumberSizeFactor`, `MergePreviewNumberDepth = 0.05`).
  void _drawBlockNumbersWithPreview(
    Canvas canvas,
    BlockColorStyle baseStyle,
    _ResolvedPieceLabelLayout baseLayout,
  ) {
    final baseNum = model.number!;

    // 1. Underlying normal `NumberComponentView` (`scale = 1 - t` on survivor, `1 - 0.25*push` on partner, `0` while settling)
    if (_normalNumberSizeFactor > 0.015) {
      _paintFourLayerStyledNumber(
        canvas: canvas,
        numberValue: baseNum,
        style: baseStyle,
        layout: baseLayout,
        sizeFactor: _normalNumberSizeFactor,
        yElevationPx: 0.0,
      );
    }

    // 2. Floating `MergeNumberPreview` (`DrawAbove`, `MergePreviewNumberDepth = 0.05 * cellSize`)
    if (_activePreviewNumber != null && _previewNumberSizeFactor > 0.015) {
      final previewVal = _activePreviewNumber!;
      final previewStyle = palette.styleFor(
        number: previewVal,
        isFrozen: false,
      );
      final previewLayout = _getPreviewLabelAndArrowLayout(previewVal);
      final depthLiftPx = visualSettings.mergePreviewNumberDepth * cellSize;
      _paintFourLayerStyledNumber(
        canvas: canvas,
        numberValue: previewVal,
        style: previewStyle,
        layout: previewLayout,
        sizeFactor: _previewNumberSizeFactor,
        yElevationPx: depthLiftPx,
      );
    }
  }

  /// Exact 4-layer back-to-front 3D `NumberComponentView` (`PoetsenOne-Regular SDF`),
  /// pre-baked once into a crisp `2x` supersampled GPU texture sprite so per-frame
  /// `TextPainter.layout()` and `MaskFilter.blur` cost is ZERO:
  /// 1. `Stroke3` (`+0.0743` Y drop, `_OutlineSoftness = 1.0` soft outer shadow/rim in `numberStrokeInner`)
  /// 2. `Stroke2` (`+0.0406` Y drop, thick 3D extruded bottom bevel in `numberStrokeMid`)
  /// 3. `Stroke1` (`+0.0111` Y drop, thick crisp dark contour in `numberStrokeOuter`)
  /// 4. `Fill` (`(0, 0)`, pure white `#FFFFFF`)
  void _paintFourLayerStyledNumber({
    required Canvas canvas,
    required int numberValue,
    required BlockColorStyle style,
    required _ResolvedPieceLabelLayout layout,
    required double sizeFactor,
    required double yElevationPx,
  }) {
    if (sizeFactor <= 0.015) return;
    final m = layout.digitMetrics;
    final baseFontPx =
        layout.finalTmpFontSize * _tmpUnitToCellRatio * cellSize;
    final letterSp = (m.characterSpacing * 0.0115) * baseFontPx;
    final yDropScale = (layout.finalTmpFontSize / 4.875).clamp(0.55, 1.05);

    canvas.save();
    canvas.translate(
      layout.labelCenterLocal.dx,
      layout.labelCenterLocal.dy - yElevationPx,
    );
    canvas.scale(sizeFactor * m.horizontalScale, sizeFactor);

    final baked = _getOrBakeFourLayerNumberSprite(
      numberValue: numberValue,
      baseFontPx: baseFontPx,
      letterSp: letterSp,
      yDropScale: yDropScale,
      style: style,
    );
    if (baked != null) {
      canvas.drawImageRect(
        baked.image,
        baked.srcRect,
        baked.dstRect,
        _glyphSpritePaint,
      );
    } else {
      _paintFourLayerNumberDirect(
        canvas: canvas,
        textStr: '$numberValue',
        baseFontPx: baseFontPx,
        letterSp: letterSp,
        yDropScale: yDropScale,
        style: style,
      );
    }

    canvas.restore();
  }

  /// Pre-bakes the 4-layer 3D merged number sprite (`n * 2`, `n * 4`) during idle
  /// frames so first hold-to-merge contact has 0.0ms `TextPainter` / `MaskFilter` stall.
  void prewarmMergedNumberSprite(int previewVal) {
    if (model.isDud || _isIceCovered || previewVal <= 0) return;
    final layout = _getPreviewLabelAndArrowLayout(previewVal);
    final m = layout.digitMetrics;
    final baseFontPx =
        layout.finalTmpFontSize * _tmpUnitToCellRatio * cellSize;
    final letterSp = (m.characterSpacing * 0.0115) * baseFontPx;
    final yDropScale = (layout.finalTmpFontSize / 4.875).clamp(0.55, 1.05);
    final style = palette.styleFor(number: previewVal, isFrozen: false);
    _getOrBakeFourLayerNumberSprite(
      numberValue: previewVal,
      baseFontPx: baseFontPx,
      letterSp: letterSp,
      yDropScale: yDropScale,
      style: style,
    );
  }

  _BakedGlyphSprite? _getOrBakeFourLayerNumberSprite({
    required int numberValue,
    required double baseFontPx,
    required double letterSp,
    required double yDropScale,
    required BlockColorStyle style,
  }) {
    final key =
        'glassv2|$numberValue|${(baseFontPx * 10).round()}|${(cellSize * 4).round()}|${style.numberStrokeOuter.toARGB32().toRadixString(16)}|${style.numberStrokeMid.toARGB32().toRadixString(16)}';
    final cached = _fourLayerNumberSpriteCache[key];
    if (cached != null) return cached;

    try {
      final textStr = '$numberValue';
      final crispStroke1W = (baseFontPx * 0.088).clamp(1.2, 3.2);
      final dropStroke2W = (baseFontPx * 0.135).clamp(1.8, 4.6);
      final softStroke3W = (baseFontPx * 0.185).clamp(2.2, 6.2);
      final blurSigma = (cellSize * 0.024).clamp(0.9, 2.8);

      final stroke3Tp = TextPainter(
        text: TextSpan(
          text: textStr,
          style: TextStyle(
            fontFamily: 'PoetsenOne',
            fontSize: baseFontPx,
            letterSpacing: letterSp,
            height: 1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = softStroke3W
              ..strokeJoin = StrokeJoin.round
              ..color = style.numberStrokeOuter.withValues(alpha: 0.44)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final stroke2Tp = TextPainter(
        text: TextSpan(
          text: textStr,
          style: TextStyle(
            fontFamily: 'PoetsenOne',
            fontSize: baseFontPx,
            letterSpacing: letterSp,
            height: 1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = dropStroke2W
              ..strokeJoin = StrokeJoin.round
              ..color = style.numberStrokeMid.withValues(alpha: 0.56)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma * 0.45),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final stroke1Tp = TextPainter(
        text: TextSpan(
          text: textStr,
          style: TextStyle(
            fontFamily: 'PoetsenOne',
            fontSize: baseFontPx,
            letterSpacing: letterSp,
            height: 1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = crispStroke1W
              ..strokeJoin = StrokeJoin.round
              ..color = style.numberStrokeOuter.withValues(alpha: 0.68),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final fillTp = TextPainter(
        text: TextSpan(
          text: textStr,
          style: TextStyle(
            fontFamily: 'PoetsenOne',
            fontSize: baseFontPx,
            letterSpacing: letterSp,
            height: 1.0,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final padX = softStroke3W + blurSigma * 3.5 + 6.0;
      final padTop = softStroke3W + blurSigma * 3.5 + 6.0;
      final padBottom =
          softStroke3W + blurSigma * 3.5 + 0.085 * cellSize * yDropScale + 8.0;

      final logicalW = stroke3Tp.width + padX * 2.0;
      final logicalH = stroke3Tp.height + padTop + padBottom;
      final originX = logicalW * 0.5;
      final originY = padTop + stroke3Tp.height * 0.5;

      const ss = 2.0;
      final imgW = (logicalW * ss).ceil().clamp(4, 1024);
      final imgH = (logicalH * ss).ceil().clamp(4, 1024);

      final recorder = ui.PictureRecorder();
      final recCanvas = Canvas(recorder);
      recCanvas.scale(imgW / logicalW, imgH / logicalH);
      recCanvas.translate(originX, originY);

      final baseOffset = Offset(-stroke3Tp.width * 0.5, -stroke3Tp.height * 0.5);
      stroke3Tp.paint(
        recCanvas,
        baseOffset + Offset(0, 0.064 * cellSize * yDropScale),
      );
      stroke2Tp.paint(
        recCanvas,
        baseOffset + Offset(0, 0.036 * cellSize * yDropScale),
      );
      stroke1Tp.paint(
        recCanvas,
        baseOffset + Offset(0, 0.010 * cellSize * yDropScale),
      );
      fillTp.paint(recCanvas, baseOffset);

      final pic = recorder.endRecording();
      final img = pic.toImageSync(imgW, imgH);
      pic.dispose();

      final sprite = _BakedGlyphSprite(
        image: img,
        srcRect: Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
        dstRect: Rect.fromLTWH(-originX, -originY, logicalW, logicalH),
      );
      if (_fourLayerNumberSpriteCache.length >= 192) {
        final oldest =
            _fourLayerNumberSpriteCache.remove(_fourLayerNumberSpriteCache.keys.first);
        oldest?.image.dispose();
      }
      _fourLayerNumberSpriteCache[key] = sprite;
      return sprite;
    } catch (_) {
      return null;
    }
  }

  void _paintFourLayerNumberDirect({
    required Canvas canvas,
    required String textStr,
    required double baseFontPx,
    required double letterSp,
    required double yDropScale,
    required BlockColorStyle style,
  }) {
    final crispStroke1W = (baseFontPx * 0.088).clamp(1.2, 3.2);
    final dropStroke2W = (baseFontPx * 0.135).clamp(1.8, 4.6);
    final softStroke3W = (baseFontPx * 0.185).clamp(2.2, 6.2);

    final stroke3Tp = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: baseFontPx,
          letterSpacing: letterSp,
          height: 1.0,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = softStroke3W
            ..strokeJoin = StrokeJoin.round
            ..color = style.numberStrokeOuter.withValues(alpha: 0.44),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final baseOffset = Offset(-stroke3Tp.width * 0.5, -stroke3Tp.height * 0.5);
    stroke3Tp.paint(
      canvas,
      baseOffset + Offset(0, 0.064 * cellSize * yDropScale),
    );

    final stroke2Tp = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: baseFontPx,
          letterSpacing: letterSp,
          height: 1.0,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = dropStroke2W
            ..strokeJoin = StrokeJoin.round
            ..color = style.numberStrokeMid.withValues(alpha: 0.56),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    stroke2Tp.paint(
      canvas,
      baseOffset + Offset(0, 0.036 * cellSize * yDropScale),
    );

    final stroke1Tp = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: baseFontPx,
          letterSpacing: letterSp,
          height: 1.0,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = crispStroke1W
            ..strokeJoin = StrokeJoin.round
            ..color = style.numberStrokeOuter.withValues(alpha: 0.68),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    stroke1Tp.paint(
      canvas,
      baseOffset + Offset(0, 0.0111 * cellSize * yDropScale),
    );

    final fillTp = TextPainter(
      text: TextSpan(
        text: textStr,
        style: TextStyle(
          fontFamily: 'PoetsenOne',
          fontSize: baseFontPx,
          letterSpacing: letterSp,
          height: 1.0,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    fillTp.paint(canvas, baseOffset);
  }
}
