import 'dart:convert';
import 'dart:math' as math;

typedef GridCell = (int col, int row);

enum MovementType {
  free,
  horizontal,
  vertical,
  pinned;

  bool get allowsHorizontal =>
      this == MovementType.free || this == MovementType.horizontal;

  bool get allowsVertical =>
      this == MovementType.free || this == MovementType.vertical;

  bool get canMove => allowsHorizontal || allowsVertical;

  bool get isPinned => this == MovementType.pinned;

  MovementType resolveMergedWith(MovementType other) {
    final h = allowsHorizontal || other.allowsHorizontal;
    final v = allowsVertical || other.allowsVertical;
    if (h && v) return MovementType.free;
    if (h) return MovementType.horizontal;
    if (v) return MovementType.vertical;
    return MovementType.pinned;
  }

  static MovementType fromJson(Map<String, dynamic> json) {
    if (json['pinned'] == true) return MovementType.pinned;
    final mv = (json['movement'] as String?)?.toLowerCase();
    if (mv == 'horizontal') return MovementType.horizontal;
    if (mv == 'vertical') return MovementType.vertical;
    if (mv == 'none') return MovementType.pinned;
    return MovementType.free;
  }
}

class GenPiece {
  final int id;
  final String key;
  int col;
  int row;

  /// Normalized local cells (min col == 0, min row == 0), sorted by (row, col).
  final List<GridCell> cells;

  /// `null` means Dud blocker.
  int? number;

  /// Non-null means frozen until a merge produces `mergedNumber == iceTarget`.
  int? iceTarget;

  MovementType movement;

  GenPiece({
    required this.id,
    required this.key,
    required this.col,
    required this.row,
    required this.cells,
    this.number,
    this.iceTarget,
    this.movement = MovementType.free,
  });

  bool get isDud => number == null;
  bool get isFrozen => iceTarget != null;
  bool get canMove => !isFrozen && movement.canMove;
  bool get canMerge => !isDud && !isFrozen;

  List<GridCell> worldCells([int? originCol, int? originRow]) {
    final c0 = originCol ?? col;
    final r0 = originRow ?? row;
    return [for (final (dc, dr) in cells) (c0 + dc, r0 + dr)];
  }

  GenPiece copyWith({
    int? id,
    String? key,
    int? col,
    int? row,
    List<GridCell>? cells,
    int? number,
    bool clearNumber = false,
    int? iceTarget,
    bool clearIce = false,
    MovementType? movement,
  }) {
    return GenPiece(
      id: id ?? this.id,
      key: key ?? this.key,
      col: col ?? this.col,
      row: row ?? this.row,
      cells: cells ?? List<GridCell>.from(this.cells),
      number: clearNumber ? null : (number ?? this.number),
      iceTarget: clearIce ? null : (iceTarget ?? this.iceTarget),
      movement: movement ?? this.movement,
    );
  }

  Map<String, dynamic> toShapeJson() {
    final map = <String, dynamic>{
      'col': col,
      'key': key,
      'row': row,
      'cells': [
        for (final (dc, dr) in cells) [dc, dr],
      ],
    };
    if (number != null) {
      map['number'] = number;
    }
    if (movement == MovementType.pinned) {
      map['pinned'] = true;
    } else if (movement == MovementType.horizontal) {
      map['movement'] = 'horizontal';
    } else if (movement == MovementType.vertical) {
      map['movement'] = 'vertical';
    }
    if (iceTarget != null) {
      map['iceTarget'] = iceTarget;
    }
    return map;
  }

  static GenPiece fromShapeJson(Map<String, dynamic> s, int id) {
    final c0 = (s['col'] as num?)?.toInt() ?? 0;
    final r0 = (s['row'] as num?)?.toInt() ?? 0;
    final raw = <GridCell>[];
    for (final ce in (s['cells'] as List<dynamic>? ?? const [])) {
      if (ce is List && ce.length >= 2) {
        raw.add(((ce[0] as num).toInt(), (ce[1] as num).toInt()));
      }
    }
    if (raw.isEmpty) raw.add((0, 0));

    int minC = raw.first.$1;
    int minR = raw.first.$2;
    for (final (dc, dr) in raw) {
      if (dc < minC) minC = dc;
      if (dr < minR) minR = dr;
    }
    final norm = [for (final (dc, dr) in raw) (dc - minC, dr - minR)]
      ..sort((a, b) {
        final rCmp = a.$2.compareTo(b.$2);
        return rCmp != 0 ? rCmp : a.$1.compareTo(b.$1);
      });

    final rawNum = (s['number'] as num?)?.toInt();
    final rawIce = (s['iceTarget'] as num?)?.toInt();

    return GenPiece(
      id: id,
      key: (s['key'] as String?) ?? 'P$id',
      col: c0 + minC,
      row: r0 + minR,
      cells: norm,
      number: (rawNum != null && rawNum > 0) ? rawNum : null,
      iceTarget: (rawIce != null && rawIce > 0) ? rawIce : null,
      movement: MovementType.fromJson(s),
    );
  }
}

class GenLevel {
  final int number;
  final int cols;
  final int rows;
  final int timeSeconds;
  final bool timerDisabled;
  final Set<GridCell> walls;
  final List<GenPiece> pieces;
  final int bankId;
  final int levelLayoutId;

  const GenLevel({
    required this.number,
    required this.cols,
    required this.rows,
    required this.timeSeconds,
    this.timerDisabled = false,
    required this.walls,
    required this.pieces,
    this.bankId = 300,
    required this.levelLayoutId,
  });

  bool get hasIce => pieces.any((p) => p.iceTarget != null);
  bool get hasDud => pieces.any((p) => p.isDud);
  bool get hasPinned => pieces.any((p) => p.movement.isPinned);
  bool get hasArrows => pieces.any(
    (p) =>
        p.movement == MovementType.horizontal ||
        p.movement == MovementType.vertical,
  );

  int get playableCellCount => cols * rows - walls.length;

  int get occupiedCellCount {
    int total = 0;
    for (final p in pieces) {
      total += p.cells.length;
    }
    return total;
  }

  double get occupancyRatio =>
      playableCellCount <= 0 ? 0.0 : occupiedCellCount / playableCellCount;

  int get targetWinNumber {
    int sum = 0;
    int maxInit = 2;
    for (final p in pieces) {
      final n = p.number;
      if (n != null && n > 0) {
        sum += n;
        if (n > maxInit) maxInit = n;
      }
    }
    if (sum <= 2) return 2;
    int pow2 = 2;
    while (pow2 * 2 <= sum) {
      pow2 *= 2;
    }
    return math.max(maxInit, pow2);
  }

  List<String> get activeMechanicNames => [
    if (hasIce) 'Ice',
    if (hasDud) 'Dud',
    if (hasPinned) 'Pinned',
    if (hasArrows) 'Arrows',
  ];

  Map<String, dynamic> toLayoutJson() {
    final sortedWalls = walls.toList()
      ..sort((a, b) {
        final rCmp = a.$2.compareTo(b.$2);
        return rCmp != 0 ? rCmp : a.$1.compareTo(b.$1);
      });
    return <String, dynamic>{
      'cols': cols,
      'rows': rows,
      'time': timeSeconds,
      'walls': [
        for (final (c, r) in sortedWalls) [c, r],
      ],
      'shapes': [for (final p in pieces) p.toShapeJson()],
      'timerDisabled': timerDisabled,
    };
  }

  /// Deterministic 8-hex-char content hash (FNV-1a 32-bit over canonical layout JSON).
  String computeContentHash() {
    final canonical = jsonEncode(toLayoutJson());
    int hash = 0x811c9dc5;
    for (int i = 0; i < canonical.length; i++) {
      hash ^= canonical.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Exact entry format matching `assets/levels/all_121_levels.json`.
  Map<String, dynamic> toCampaignEntryJson() {
    return <String, dynamic>{
      'data': <String, dynamic>{
        'layout_text_json': toLayoutJson(),
      },
      'content_hash': computeContentHash(),
      'level_layout_id': levelLayoutId,
      'bank_id': bankId,
      'number': number,
      'rewards': const <dynamic>[],
    };
  }

  static GenLevel fromCampaignJson(Map<String, dynamic> root, int fallbackNum) {
    final numVal = (root['number'] as num?)?.toInt() ?? fallbackNum;
    dynamic lay = root['data']?['layout_text_json'] ?? root;
    if (lay is String) {
      lay = jsonDecode(lay);
    }
    final map = lay as Map<String, dynamic>;
    final cols = (map['cols'] as num?)?.toInt() ?? 6;
    final rows = (map['rows'] as num?)?.toInt() ?? 8;
    final timeSeconds = (map['time'] as num?)?.toInt() ?? 120;
    final timerDisabled = map['timerDisabled'] == true;

    final walls = <GridCell>{};
    for (final w in (map['walls'] as List<dynamic>? ?? const [])) {
      if (w is List && w.length >= 2) {
        walls.add(((w[0] as num).toInt(), (w[1] as num).toInt()));
      }
    }

    final pieces = <GenPiece>[];
    int nextId = 1;
    for (final s in (map['shapes'] as List<dynamic>? ?? const [])) {
      if (s is Map<String, dynamic>) {
        pieces.add(GenPiece.fromShapeJson(s, nextId++));
      }
    }

    return GenLevel(
      number: numVal,
      cols: cols,
      rows: rows,
      timeSeconds: timeSeconds,
      timerDisabled: timerDisabled,
      walls: walls,
      pieces: pieces,
      bankId: (root['bank_id'] as num?)?.toInt() ?? 204,
      levelLayoutId:
          (root['level_layout_id'] as num?)?.toInt() ?? (200000 + numVal),
    );
  }

  /// Renders a readable ASCII preview of the board for CLI inspection.
  String renderAscii() {
    final grid = List<List<String>>.generate(
      rows,
      (_) => List<String>.filled(cols, '  .   '),
    );

    for (final (c, r) in walls) {
      if (c >= 0 && c < cols && r >= 0 && r < rows) {
        grid[r][c] = ' #### ';
      }
    }

    for (final p in pieces) {
      final tag = _pieceTag(p);
      for (final (c, r) in p.worldCells()) {
        if (c >= 0 && c < cols && r >= 0 && r < rows) {
          grid[r][c] = tag;
        }
      }
    }

    final buf = StringBuffer();
    final border = '+${List.filled(cols, '------').join('+')}+';
    buf.writeln(border);
    for (int r = 0; r < rows; r++) {
      buf.writeln('|${grid[r].join('|')}|');
      buf.writeln(border);
    }

    // Legend for Ice / Pinned / Arrows
    final details = <String>[];
    for (final p in pieces) {
      final tags = <String>[];
      if (p.isDud) tags.add('Dud');
      if (p.iceTarget != null) tags.add('Ice(${p.iceTarget})');
      if (p.movement == MovementType.pinned) tags.add('Pinned');
      if (p.movement == MovementType.horizontal) tags.add('ArrowH');
      if (p.movement == MovementType.vertical) tags.add('ArrowV');
      if (tags.isNotEmpty) {
        details.add(
          '${p.key}:${p.number?.toString() ?? "DUD"}[${tags.join("+")}]',
        );
      }
    }
    if (details.isNotEmpty) {
      buf.writeln('Mechanics: ${details.join(', ')}');
    }
    return buf.toString();
  }

  static String _pieceTag(GenPiece p) {
    final mod = p.isFrozen
        ? '*'
        : p.movement == MovementType.pinned
        ? 'X'
        : p.movement == MovementType.horizontal
        ? '-'
        : p.movement == MovementType.vertical
        ? '|'
        : ' ';
    final label = p.isDud ? '${p.key}D' : '${p.key}${p.number}';
    final compact = label.length > 5 ? label.substring(0, 5) : label;
    return '$mod$compact'.padRight(6);
  }
}

/// Checks if all playable (non-wall) cells form a single 4-connected component.
bool isPlayableAreaConnected(int cols, int rows, Set<GridCell> walls) {
  GridCell? start;
  int playableCount = 0;
  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      if (!walls.contains((c, r))) {
        start ??= (c, r);
        playableCount++;
      }
    }
  }
  if (start == null) return false;

  final visited = <GridCell>{start};
  final queue = <GridCell>[start];
  int head = 0;
  const dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  while (head < queue.length) {
    final (cx, cy) = queue[head++];
    for (final (dx, dy) in dirs) {
      final nx = cx + dx;
      final ny = cy + dy;
      if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
      final cell = (nx, ny);
      if (!walls.contains(cell) && visited.add(cell)) {
        queue.add(cell);
      }
    }
  }
  return visited.length == playableCount;
}
