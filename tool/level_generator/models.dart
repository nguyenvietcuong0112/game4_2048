import 'dart:convert';
import 'dart:math' as math;

typedef GridCell = (int col, int row);

enum MovementType {
  free,
  horizontal,
  vertical,
  pinned,
  left,
  right,
  up,
  down;

  bool get allowsLeft =>
      this == MovementType.free ||
      this == MovementType.horizontal ||
      this == MovementType.left;

  bool get allowsRight =>
      this == MovementType.free ||
      this == MovementType.horizontal ||
      this == MovementType.right;

  bool get allowsUp =>
      this == MovementType.free ||
      this == MovementType.vertical ||
      this == MovementType.up;

  bool get allowsDown =>
      this == MovementType.free ||
      this == MovementType.vertical ||
      this == MovementType.down;

  bool get allowsHorizontal => allowsLeft || allowsRight;

  bool get allowsVertical => allowsUp || allowsDown;

  bool get canMove => allowsHorizontal || allowsVertical;

  bool get isPinned => this == MovementType.pinned;

  bool get isOneWay =>
      this == MovementType.left ||
      this == MovementType.right ||
      this == MovementType.up ||
      this == MovementType.down;

  MovementType resolveMergedWith(MovementType other) {
    final l = allowsLeft || other.allowsLeft;
    final r = allowsRight || other.allowsRight;
    final u = allowsUp || other.allowsUp;
    final d = allowsDown || other.allowsDown;
    final h = l || r;
    final v = u || d;
    if (h && v) return MovementType.free;
    if (l && r) return MovementType.horizontal;
    if (u && d) return MovementType.vertical;
    if (l) return MovementType.left;
    if (r) return MovementType.right;
    if (u) return MovementType.up;
    if (d) return MovementType.down;
    return MovementType.pinned;
  }

  static MovementType fromJson(Map<String, dynamic> json) {
    if (json['pinned'] == true) return MovementType.pinned;
    final mv = (json['movement'] as String?)?.toLowerCase();
    if (mv == 'horizontal') return MovementType.horizontal;
    if (mv == 'vertical') return MovementType.vertical;
    if (mv == 'left') return MovementType.left;
    if (mv == 'right') return MovementType.right;
    if (mv == 'up') return MovementType.up;
    if (mv == 'down') return MovementType.down;
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

  /// Wave 1 mechanics:
  int? clockBonusSeconds;
  bool isMystery;
  String? keyColor;
  String? lockColor;

  /// Wave 3 mechanics:
  int swapUses;
  int? movesLeft;

  GenPiece({
    required this.id,
    required this.key,
    required this.col,
    required this.row,
    required this.cells,
    this.number,
    this.iceTarget,
    this.movement = MovementType.free,
    this.clockBonusSeconds,
    this.isMystery = false,
    this.keyColor,
    this.lockColor,
    this.swapUses = 0,
    this.movesLeft,
  });

  bool get isDud => number == null;
  bool get isFrozen => iceTarget != null;
  bool get isLocked => lockColor != null;
  bool get hasKey => keyColor != null;
  bool get hasClockBonus => (clockBonusSeconds ?? 0) > 0;
  bool get hasSwap => swapUses > 0;
  bool get hasLimitedMoves => (movesLeft ?? 0) > 0;
  bool get canMove => !isFrozen && !isLocked && movement.canMove;
  bool get canMerge => !isDud && !isFrozen && !isLocked && !isMystery;

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
    int? clockBonusSeconds,
    bool clearClockBonus = false,
    bool? isMystery,
    String? keyColor,
    bool clearKeyColor = false,
    String? lockColor,
    bool clearLockColor = false,
    int? swapUses,
    int? movesLeft,
    bool clearMovesLeft = false,
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
      clockBonusSeconds: clearClockBonus
          ? null
          : (clockBonusSeconds ?? this.clockBonusSeconds),
      isMystery: isMystery ?? this.isMystery,
      keyColor: clearKeyColor ? null : (keyColor ?? this.keyColor),
      lockColor: clearLockColor ? null : (lockColor ?? this.lockColor),
      swapUses: swapUses ?? this.swapUses,
      movesLeft: clearMovesLeft ? null : (movesLeft ?? this.movesLeft),
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
    } else if (movement == MovementType.left) {
      map['movement'] = 'left';
    } else if (movement == MovementType.right) {
      map['movement'] = 'right';
    } else if (movement == MovementType.up) {
      map['movement'] = 'up';
    } else if (movement == MovementType.down) {
      map['movement'] = 'down';
    }
    if (iceTarget != null) {
      map['iceTarget'] = iceTarget;
    }
    if (clockBonusSeconds != null && clockBonusSeconds! > 0) {
      map['clockBonus'] = clockBonusSeconds;
    }
    if (isMystery) {
      map['mystery'] = true;
    }
    if (keyColor != null && keyColor!.isNotEmpty) {
      map['keyColor'] = keyColor;
    }
    if (lockColor != null && lockColor!.isNotEmpty) {
      map['lockColor'] = lockColor;
    }
    if (swapUses > 0) {
      map['swapUses'] = swapUses;
    }
    if (movesLeft != null && movesLeft! > 0) {
      map['movesLeft'] = movesLeft;
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
    final rawClock = (s['clockBonus'] as num?)?.toInt();
    final number = (rawNum != null && rawNum > 0) ? rawNum : null;
    final rawKeyColor = (s['keyColor'] as String?)?.trim().toLowerCase();
    final rawLockColor = (s['lockColor'] as String?)?.trim().toLowerCase();

    return GenPiece(
      id: id,
      key: (s['key'] as String?) ?? 'P$id',
      col: c0 + minC,
      row: r0 + minR,
      cells: norm,
      number: number,
      iceTarget: (rawIce != null && rawIce > 0) ? rawIce : null,
      movement: MovementType.fromJson(s),
      clockBonusSeconds:
          (rawClock != null && rawClock > 0 && number != null) ? rawClock : null,
      isMystery: s['mystery'] == true && number != null,
      keyColor: (rawKeyColor != null && rawKeyColor.isNotEmpty && number != null)
          ? rawKeyColor
          : null,
      lockColor: (rawLockColor != null && rawLockColor.isNotEmpty)
          ? rawLockColor
          : null,
      swapUses: ((s['swapUses'] as num?)?.toInt() ??
                  (s['swap'] == true ? 1 : 0))
              .clamp(0, 99),
      movesLeft: ((s['movesLeft'] as num?)?.toInt() ?? 0) > 0
          ? (s['movesLeft'] as num).toInt()
          : null,
    );
  }
}

class GenDispenser {
  final int col;
  final int row;
  final GridCell dir;
  final List<int> queue;

  const GenDispenser({
    required this.col,
    required this.row,
    required this.dir,
    required this.queue,
  });

  GridCell get cell => (col, row);
  GridCell get mouthCell => (col + dir.$1, row + dir.$2);

  String get dirName {
    if (dir == (0, 1)) return 'down';
    if (dir == (0, -1)) return 'up';
    if (dir == (1, 0)) return 'right';
    return 'left';
  }

  static GridCell parseDir(String? raw) {
    switch ((raw ?? 'down').trim().toLowerCase()) {
      case 'up':
        return (0, -1);
      case 'left':
        return (-1, 0);
      case 'right':
        return (1, 0);
      case 'down':
      default:
        return (0, 1);
    }
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'col': col,
    'row': row,
    'dir': dirName,
    'queue': List<int>.from(queue),
  };

  static GenDispenser? fromJson(Map<String, dynamic> d) {
    final c = (d['col'] as num?)?.toInt();
    final r = (d['row'] as num?)?.toInt();
    if (c == null || r == null) return null;
    final q = <int>[
      for (final v in (d['queue'] as List<dynamic>? ?? const []))
        if (v is num && v.toInt() > 0) v.toInt(),
    ];
    if (q.isEmpty) return null;
    return GenDispenser(
      col: c,
      row: r,
      dir: parseDir(d['dir'] as String?),
      queue: q,
    );
  }
}

class GenLevel {
  final int number;
  final int cols;
  final int rows;
  final int timeSeconds;
  final bool timerDisabled;
  final bool isSpecial;
  final Set<GridCell> walls;
  final Set<GridCell> redWalls;
  final Set<GridCell> blueWalls;
  final List<GenDispenser> dispensers;
  final List<GenPiece> pieces;
  final int bankId;
  final int levelLayoutId;

  const GenLevel({
    required this.number,
    required this.cols,
    required this.rows,
    required this.timeSeconds,
    this.timerDisabled = false,
    this.isSpecial = false,
    required this.walls,
    this.redWalls = const {},
    this.blueWalls = const {},
    this.dispensers = const [],
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
  bool get hasClockBonus => pieces.any((p) => p.hasClockBonus);
  bool get hasMystery => pieces.any((p) => p.isMystery);
  bool get hasKeyLock => pieces.any((p) => p.hasKey || p.isLocked);
  bool get hasToggleWalls => redWalls.isNotEmpty || blueWalls.isNotEmpty;
  bool get hasDispensers => dispensers.any((d) => d.queue.isNotEmpty);
  bool get hasSwap => pieces.any((p) => p.hasSwap);
  bool get hasOneWayArrow => pieces.any((p) => p.movement.isOneWay);
  bool get hasLimitedMove => pieces.any((p) => p.hasLimitedMoves);

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
    for (final d in dispensers) {
      for (final n in d.queue) {
        if (n > 0) {
          sum += n;
          if (n > maxInit) maxInit = n;
        }
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
    if (hasClockBonus) 'Clock',
    if (hasMystery) 'Mystery',
    if (hasKeyLock) 'KeyLock',
    if (hasToggleWalls) 'ToggleWalls',
    if (hasDispensers) 'Dispenser',
    if (hasSwap) 'Swap',
    if (hasOneWayArrow) 'OneWay',
    if (hasLimitedMove) 'LimitedMove',
  ];

  Map<String, dynamic> toLayoutJson() {
    List<List<int>> sortCells(Set<GridCell> set) {
      final list = set.toList()
        ..sort((a, b) {
          final rCmp = a.$2.compareTo(b.$2);
          return rCmp != 0 ? rCmp : a.$1.compareTo(b.$1);
        });
      return [for (final (c, r) in list) [c, r]];
    }

    final map = <String, dynamic>{
      'cols': cols,
      'rows': rows,
      'time': timeSeconds,
      'walls': sortCells(walls),
      'shapes': [for (final p in pieces) p.toShapeJson()],
      'timerDisabled': timerDisabled,
    };
    if (isSpecial) {
      map['isSpecial'] = true;
    }
    if (redWalls.isNotEmpty) {
      map['redWalls'] = sortCells(redWalls);
    }
    if (blueWalls.isNotEmpty) {
      map['blueWalls'] = sortCells(blueWalls);
    }
    if (dispensers.isNotEmpty) {
      map['dispensers'] = [for (final d in dispensers) d.toJson()];
    }
    return map;
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
    final isSpecial = map['isSpecial'] == true;

    final walls = <GridCell>{};
    for (final w in (map['walls'] as List<dynamic>? ?? const [])) {
      if (w is List && w.length >= 2) {
        walls.add(((w[0] as num).toInt(), (w[1] as num).toInt()));
      }
    }
    final redWalls = <GridCell>{};
    for (final w in (map['redWalls'] as List<dynamic>? ?? const [])) {
      if (w is List && w.length >= 2) {
        redWalls.add(((w[0] as num).toInt(), (w[1] as num).toInt()));
      }
    }
    final blueWalls = <GridCell>{};
    for (final w in (map['blueWalls'] as List<dynamic>? ?? const [])) {
      if (w is List && w.length >= 2) {
        blueWalls.add(((w[0] as num).toInt(), (w[1] as num).toInt()));
      }
    }
    final dispensers = <GenDispenser>[];
    for (final d in (map['dispensers'] as List<dynamic>? ?? const [])) {
      if (d is Map<String, dynamic>) {
        final parsed = GenDispenser.fromJson(d);
        if (parsed != null) {
          dispensers.add(parsed);
          walls.add(parsed.cell);
        }
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
      isSpecial: isSpecial,
      walls: walls,
      redWalls: redWalls,
      blueWalls: blueWalls,
      dispensers: dispensers,
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
