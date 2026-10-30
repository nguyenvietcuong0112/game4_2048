import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';

typedef GridCell = (int col, int row);

enum MovementConstraint {
  free,
  horizontalOnly,
  verticalOnly,
  pinned;

  bool get allowsHorizontal =>
      this == MovementConstraint.free || this == MovementConstraint.horizontalOnly;

  bool get allowsVertical =>
      this == MovementConstraint.free || this == MovementConstraint.verticalOnly;

  bool get canMove => allowsHorizontal || allowsVertical;

  bool get isPinned => this == MovementConstraint.pinned;

  /// Exact match of `MovementComponent.ResolveMergedWith`:
  /// Combines allowed movement axes of both merged pieces.
  MovementConstraint resolveMergedWith(MovementConstraint other) {
    final h = allowsHorizontal || other.allowsHorizontal;
    final v = allowsVertical || other.allowsVertical;
    if (h && v) return MovementConstraint.free;
    if (h) return MovementConstraint.horizontalOnly;
    if (v) return MovementConstraint.verticalOnly;
    return MovementConstraint.pinned;
  }

  static MovementConstraint fromShapeJson(Map<String, dynamic> json) {
    if (json['pinned'] == true) return MovementConstraint.pinned;
    final mov = (json['movement'] as String?)?.toLowerCase();
    if (mov == 'horizontal') return MovementConstraint.horizontalOnly;
    if (mov == 'vertical') return MovementConstraint.verticalOnly;
    if (mov == 'none') return MovementConstraint.pinned;
    return MovementConstraint.free;
  }
}

class PieceModel {
  final int id;
  final String key;
  int col;
  int row;
  final List<GridCell> localCells;
  int? number; // null => Dud blocker
  int? iceTarget; // non-null => frozen until any merge reaches >= iceTarget
  MovementConstraint movement;

  PieceModel({
    required this.id,
    required this.key,
    required this.col,
    required this.row,
    required this.localCells,
    this.number,
    this.iceTarget,
    this.movement = MovementConstraint.free,
  });

  bool get isDud => number == null;
  bool get isFrozen => iceTarget != null;
  bool get canBeDragged => !isFrozen && movement.canMove;
  bool get canMerge => !isDud && !isFrozen;

  Set<GridCell> worldCellsAt(int originCol, int originRow) {
    return {
      for (final (dc, dr) in localCells) (originCol + dc, originRow + dr),
    };
  }

  Set<GridCell> get worldCells => worldCellsAt(col, row);

  int get widthCols {
    int minC = 999, maxC = -999;
    for (final (c, _) in localCells) {
      if (c < minC) minC = c;
      if (c > maxC) maxC = c;
    }
    return maxC - minC + 1;
  }

  int get heightRows {
    int minR = 999, maxR = -999;
    for (final (_, r) in localCells) {
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
    }
    return maxR - minR + 1;
  }

  /// Computes the local coordinates (in cell units, e.g. `(1.5, 1.0)` for a 3x2 rectangle,
  /// or `(cx + 0.5, cy + 0.5)` of the elbow cell for an L/T polyomino) for placing numbers/locks.
  (double cx, double cy) computeLabelCenterInCells() {
    if (localCells.isEmpty) return (0.5, 0.5);
    int minC = 999, maxC = -999, minR = 999, maxR = -999;
    final cellSet = localCells.toSet();
    double sumC = 0, sumR = 0;
    for (final (c, r) in cellSet) {
      if (c < minC) minC = c;
      if (c > maxC) maxC = c;
      if (r < minR) minR = r;
      if (r > maxR) maxR = r;
      sumC += c + 0.5;
      sumR += r + 0.5;
    }
    final w = maxC - minC + 1;
    final h = maxR - minR + 1;
    // Filled rectangle: exact geometric center of the rectangle
    if (cellSet.length == w * h) {
      return (minC + w * 0.5, minR + h * 0.5);
    }

    // Non-rectangular polyomino (L, T, U, Plus, Z): pick cell with highest neighbor degree
    // closest to the shape's centroid so the label never floats outside the L!
    final avgC = sumC / cellSet.length;
    final avgR = sumR / cellSet.length;

    GridCell best = localCells.first;
    double bestScore = -1e9;
    for (final (c, r) in cellSet) {
      int deg = 0;
      if (cellSet.contains((c - 1, r))) deg++;
      if (cellSet.contains((c + 1, r))) deg++;
      if (cellSet.contains((c, r - 1))) deg++;
      if (cellSet.contains((c, r + 1))) deg++;
      final dist = math.sqrt(
        math.pow((c + 0.5) - avgC, 2) + math.pow((r + 0.5) - avgR, 2),
      );
      final score = deg * 10.0 - dist;
      if (score > bestScore) {
        bestScore = score;
        best = (c, r);
      }
    }
    return (best.$1 + 0.5, best.$2 + 0.5);
  }

  PieceModel clone() {
    return PieceModel(
      id: id,
      key: key,
      col: col,
      row: row,
      localCells: List<GridCell>.from(localCells),
      number: number,
      iceTarget: iceTarget,
      movement: movement,
    );
  }
}

class LevelDefinition {
  final int number;
  final String title;
  final bool isBonus;
  final int cols;
  final int rows;
  final int timeSeconds;
  final bool timerDisabled;
  final Set<GridCell> walls;
  final List<PieceModel> initialPieces;
  final int coinReward;

  const LevelDefinition({
    required this.number,
    required this.title,
    this.isBonus = false,
    required this.cols,
    required this.rows,
    required this.timeSeconds,
    required this.timerDisabled,
    required this.walls,
    required this.initialPieces,
    this.coinReward = 25,
  });

  bool get hasIce => initialPieces.any((p) => p.iceTarget != null);
  bool get hasDud => initialPieces.any((p) => p.isDud);
  bool get hasPinned => initialPieces.any((p) => p.movement.isPinned);
  bool get hasArrows => initialPieces.any(
        (p) =>
            p.movement == MovementConstraint.horizontalOnly ||
            p.movement == MovementConstraint.verticalOnly,
      );

  bool isPlayableCell(int c, int r) {
    if (c < 0 || c >= cols || r < 0 || r >= rows) return false;
    return !walls.contains((c, r));
  }

  Set<GridCell> get playableCells {
    final res = <GridCell>{};
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if (!walls.contains((c, r))) {
          res.add((c, r));
        }
      }
    }
    return res;
  }

  factory LevelDefinition.fromCampaignJson(Map<String, dynamic> root, int fallbackNum) {
    final numVal = (root['number'] as num?)?.toInt() ?? fallbackNum;
    dynamic lay = root['data']?['layout_text_json'] ?? root;
    if (lay is String) {
      lay = jsonDecode(lay);
    }
    final map = lay as Map<String, dynamic>;
    return LevelDefinition._parseLayout(
      map,
      number: numVal,
      title: 'Level $numVal',
      isBonus: false,
    );
  }

  factory LevelDefinition.fromBonusJson(Map<String, dynamic> root, int index) {
    final name = (root['name'] as String?) ?? 'Bonus $index';
    dynamic lay = root['data']?['layout_text_json'] ?? root;
    if (lay is String) {
      lay = jsonDecode(lay);
    }
    return LevelDefinition._parseLayout(
      lay as Map<String, dynamic>,
      number: 1000 + index,
      title: name,
      isBonus: true,
    );
  }

  static LevelDefinition _parseLayout(
    Map<String, dynamic> map, {
    required int number,
    required String title,
    required bool isBonus,
  }) {
    final cols = (map['cols'] as num?)?.toInt() ?? 6;
    final rows = (map['rows'] as num?)?.toInt() ?? 8;
    final timeSeconds = (map['time'] as num?)?.toInt() ?? 120;
    final timerDisabled = map['timerDisabled'] == true;

    final walls = <GridCell>{};
    for (final w in (map['walls'] as List<dynamic>? ?? [])) {
      if (w is List && w.length >= 2) {
        walls.add(((w[0] as num).toInt(), (w[1] as num).toInt()));
      }
    }

    final pieces = <PieceModel>[];
    int nextId = 1;
    for (final s in (map['shapes'] as List<dynamic>? ?? [])) {
      if (s is! Map<String, dynamic>) continue;
      final c0 = (s['col'] as num?)?.toInt() ?? 0;
      final r0 = (s['row'] as num?)?.toInt() ?? 0;
      final rawCells = <GridCell>[];
      for (final ce in (s['cells'] as List<dynamic>? ?? [])) {
        if (ce is List && ce.length >= 2) {
          rawCells.add(((ce[0] as num).toInt(), (ce[1] as num).toInt()));
        }
      }
      if (rawCells.isEmpty) rawCells.add((0, 0));

      // Normalize localCells so min local col/row is 0
      int minDc = rawCells.first.$1;
      int minDr = rawCells.first.$2;
      for (final (dc, dr) in rawCells) {
        if (dc < minDc) minDc = dc;
        if (dr < minDr) minDr = dr;
      }
      final normCells = [
        for (final (dc, dr) in rawCells) (dc - minDc, dr - minDr),
      ];

      final rawNumber = (s['number'] as num?)?.toInt();
      final number = (rawNumber != null && rawNumber > 0) ? rawNumber : null;
      final rawIce = (s['iceTarget'] as num?)?.toInt();
      final iceTarget = (rawIce != null && rawIce > 0) ? rawIce : null;

      pieces.add(
        PieceModel(
          id: nextId++,
          key: (s['key'] as String?) ?? 'P$nextId',
          col: c0 + minDc,
          row: r0 + minDr,
          localCells: normCells,
          number: number,
          iceTarget: iceTarget,
          movement: MovementConstraint.fromShapeJson(s),
        ),
      );
    }

    return LevelDefinition(
      number: number,
      title: title,
      isBonus: isBonus,
      cols: cols,
      rows: rows,
      timeSeconds: timeSeconds,
      timerDisabled: timerDisabled,
      walls: walls,
      initialPieces: pieces,
    );
  }
}

class LevelRepository {
  final List<LevelDefinition> campaignLevels;
  final List<LevelDefinition> bonusLevels;
  final Map<int, String> tutorialHints;

  const LevelRepository({
    required this.campaignLevels,
    required this.bonusLevels,
    required this.tutorialHints,
  });

  static Future<LevelRepository> loadFromAssets() async {
    final campStr = await rootBundle.loadString('assets/levels/all_121_levels.json');
    final bonusStr = await rootBundle.loadString('assets/levels/bonus_levels.json');
    final tutStr = await rootBundle.loadString('assets/configs/tutorial_levels.json');

    final campJson = jsonDecode(campStr) as List<dynamic>;
    final campaign = <LevelDefinition>[];
    for (int i = 0; i < campJson.length; i++) {
      campaign.add(
        LevelDefinition.fromCampaignJson(
          campJson[i] as Map<String, dynamic>,
          i + 1,
        ),
      );
    }

    final bonusJson = jsonDecode(bonusStr) as List<dynamic>;
    final bonus = <LevelDefinition>[];
    for (int i = 0; i < bonusJson.length; i++) {
      bonus.add(
        LevelDefinition.fromBonusJson(
          bonusJson[i] as Map<String, dynamic>,
          i + 1,
        ),
      );
    }

    final tutMap = <int, String>{};
    final tutEntries =
        (jsonDecode(tutStr)['data']?['_entries'] as List<dynamic>?) ?? [];
    for (final e in tutEntries) {
      if (e is Map<String, dynamic>) {
        final lv = (e['_levelNumber'] as num?)?.toInt();
        final txt = e['_tutorialText'] as String?;
        if (lv != null && txt != null && txt.isNotEmpty) {
          tutMap[lv] = txt;
        }
      }
    }

    return LevelRepository(
      campaignLevels: campaign,
      bonusLevels: bonus,
      tutorialHints: tutMap,
    );
  }

  /// Mirrors live chapter_set 150 behavior:
  /// Levels 1..121 play directly; Level 122+ loops Chapter 2 (Levels 11..121).
  LevelDefinition getCampaignLevel(int displayLevelNumber) {
    if (campaignLevels.isEmpty) {
      throw StateError('No campaign levels loaded');
    }
    if (displayLevelNumber <= campaignLevels.length) {
      final idx = (displayLevelNumber - 1).clamp(0, campaignLevels.length - 1);
      return campaignLevels[idx];
    }
    // Loop levels 11..121 (indices 10..120, length 111)
    if (campaignLevels.length > 10) {
      final loopLen = campaignLevels.length - 10;
      final loopIdx = 10 + ((displayLevelNumber - 11) % loopLen);
      final base = campaignLevels[loopIdx];
      return LevelDefinition(
        number: displayLevelNumber,
        title: 'Level $displayLevelNumber',
        cols: base.cols,
        rows: base.rows,
        timeSeconds: base.timeSeconds,
        timerDisabled: base.timerDisabled,
        walls: base.walls,
        initialPieces: base.initialPieces.map((p) => p.clone()).toList(),
      );
    }
    return campaignLevels[(displayLevelNumber - 1) % campaignLevels.length];
  }
}
