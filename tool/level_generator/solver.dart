import 'dart:math' as math;
import 'dart:typed_data';

import 'models.dart';

enum SolveStatus {
  solved,
  unsolvable,
  searchLimit,
  timeout,
}

class SolveResult {
  final SolveStatus status;
  final String reason;
  final int totalMoves;
  final int mergeMoves;
  final int slideMoves;
  final int visitedStates;
  final int elapsedMs;
  final List<String> steps;

  const SolveResult({
    required this.status,
    required this.reason,
    this.totalMoves = 0,
    this.mergeMoves = 0,
    this.slideMoves = 0,
    this.visitedStates = 0,
    this.elapsedMs = 0,
    this.steps = const [],
  });

  bool get isSolved => status == SolveStatus.solved;
}

class _SimPiece {
  final int id;
  final String key;
  final int col;
  final int row;
  final List<GridCell> cells;
  final int? number;
  final int? iceTarget;
  final MovementType movement;
  final bool isMystery;
  final String? keyColor;
  final String? lockColor;
  final int swapUses;
  final int? movesLeft;

  const _SimPiece({
    required this.id,
    required this.key,
    required this.col,
    required this.row,
    required this.cells,
    required this.number,
    required this.iceTarget,
    required this.movement,
    this.isMystery = false,
    this.keyColor,
    this.lockColor,
    this.swapUses = 0,
    this.movesLeft,
  });

  bool get isDud => number == null;
  bool get isFrozen => iceTarget != null;
  bool get isLocked => lockColor != null;
  bool get canMove => !isFrozen && !isLocked && movement.canMove;
  bool get canMerge => !isDud && !isFrozen && !isLocked && !isMystery;

  /// Compact signature used for canonical state hashing.
  String signature() {
    final buf = StringBuffer()
      ..write(col)
      ..write(',')
      ..write(row)
      ..write(',')
      ..write(number ?? 0)
      ..write(',')
      ..write(iceTarget ?? 0)
      ..write(',')
      ..write(movement.index)
      ..write(',')
      ..write(isMystery ? 1 : 0)
      ..write(',')
      ..write(keyColor ?? '')
      ..write(',')
      ..write(lockColor ?? '')
      ..write(',')
      ..write(swapUses)
      ..write(',')
      ..write(movesLeft ?? 0)
      ..write(':');
    for (int i = 0; i < cells.length; i++) {
      final (dc, dr) = cells[i];
      if (i > 0) buf.write(';');
      buf
        ..write(dc)
        ..write('.')
        ..write(dr);
    }
    return buf.toString();
  }
}

class _SearchNode {
  final int priority;
  final int moves;
  final int merges;
  final int tieBreaker;
  final List<_SimPiece> pieces;
  final int wallPhase;
  final List<int> dispenserOffsets;
  final _SearchNode? parent;
  final String? moveDesc;

  const _SearchNode({
    required this.priority,
    required this.moves,
    required this.merges,
    required this.tieBreaker,
    required this.pieces,
    this.wallPhase = 0,
    this.dispenserOffsets = const [],
    this.parent,
    this.moveDesc,
  });
}

class _MinHeap {
  final List<_SearchNode> _data = [];

  bool get isEmpty => _data.isEmpty;
  int get length => _data.length;

  void push(_SearchNode node) {
    _data.add(node);
    _siftUp(_data.length - 1);
  }

  _SearchNode pop() {
    final top = _data.first;
    final last = _data.removeLast();
    if (_data.isNotEmpty) {
      _data[0] = last;
      _siftDown(0);
    }
    return top;
  }

  bool _less(_SearchNode a, _SearchNode b) {
    if (a.priority != b.priority) return a.priority < b.priority;
    if (a.moves != b.moves) return a.moves < b.moves;
    return a.tieBreaker < b.tieBreaker;
  }

  void _siftUp(int i) {
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_less(_data[i], _data[parent])) {
        final tmp = _data[i];
        _data[i] = _data[parent];
        _data[parent] = tmp;
        i = parent;
      } else {
        break;
      }
    }
  }

  void _siftDown(int i) {
    final n = _data.length;
    while (true) {
      final left = (i << 1) + 1;
      final right = left + 1;
      int smallest = i;
      if (left < n && _less(_data[left], _data[smallest])) {
        smallest = left;
      }
      if (right < n && _less(_data[right], _data[smallest])) {
        smallest = right;
      }
      if (smallest != i) {
        final tmp = _data[i];
        _data[i] = _data[smallest];
        _data[smallest] = tmp;
        i = smallest;
      } else {
        break;
      }
    }
  }
}

class LevelSolver {
  static const List<GridCell> _dirsAll = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  static const List<GridCell> _dirsHoriz = [(1, 0), (-1, 0)];
  static const List<GridCell> _dirsVert = [(0, 1), (0, -1)];
  static const List<GridCell> _dirLeft = [(-1, 0)];
  static const List<GridCell> _dirRight = [(1, 0)];
  static const List<GridCell> _dirUp = [(0, -1)];
  static const List<GridCell> _dirDown = [(0, 1)];

  static List<GridCell> _allowedDirs(MovementType mv) {
    switch (mv) {
      case MovementType.free:
        return _dirsAll;
      case MovementType.horizontal:
        return _dirsHoriz;
      case MovementType.vertical:
        return _dirsVert;
      case MovementType.left:
        return _dirLeft;
      case MovementType.right:
        return _dirRight;
      case MovementType.up:
        return _dirUp;
      case MovementType.down:
        return _dirDown;
      case MovementType.pinned:
        return const [];
    }
  }

  /// Fast static validation checks that reject provably unsolvable boards in < 0.1ms.
  static String? runStaticChecks(GenLevel level) {
    // 1. Bounds, wall overlap, piece overlap
    final occ = <GridCell>{};
    for (final p in level.pieces) {
      for (final (c, r) in p.worldCells()) {
        if (c < 0 || c >= level.cols || r < 0 || r >= level.rows) {
          return 'Piece ${p.key} out of bounds at ($c,$r)';
        }
        if (level.walls.contains((c, r))) {
          return 'Piece ${p.key} overlaps wall at ($c,$r)';
        }
        if (!occ.add((c, r))) {
          return 'Piece ${p.key} overlaps another piece at ($c,$r)';
        }
      }
    }

    // 2. Multiset parity check (board pieces + dispenser queues must collapse to single power of 2)
    final counts = <int, int>{};
    for (final p in level.pieces) {
      final n = p.number;
      if (n != null) {
        if (n < 2 || (n & (n - 1)) != 0) {
          return 'Non-power-of-2 piece number: $n';
        }
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    for (final d in level.dispensers) {
      final (mc, mr) = d.mouthCell;
      if (mc < 0 || mc >= level.cols || mr < 0 || mr >= level.rows) {
        return 'Dispenser at ${d.cell} mouth $mc,$mr out of bounds';
      }
      if (level.walls.contains((mc, mr))) {
        return 'Dispenser at ${d.cell} mouth ($mc,$mr) is a wall';
      }
      for (final n in d.queue) {
        if (n < 2 || (n & (n - 1)) != 0) {
          return 'Non-power-of-2 dispenser number: $n';
        }
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) {
      return 'No numbered pieces on board';
    }
    while (counts.length > 1 ||
        (counts.length == 1 && counts.values.first > 1)) {
      int minKey = counts.keys.first;
      for (final k in counts.keys) {
        if (k < minKey) minKey = k;
      }
      final cnt = counts.remove(minKey)!;
      if (cnt.isOdd) {
        return 'Parity error: odd count ($cnt) of minimum number $minKey';
      }
      counts[minKey * 2] = (counts[minKey * 2] ?? 0) + (cnt ~/ 2);
    }

    // 3. Ice topological unlock check (no circular/unreachable ice targets)
    final avail = <int, int>{};
    final frozen = <GenPiece>[];
    for (final p in level.pieces) {
      if (p.isFrozen) {
        frozen.add(p);
      } else if (p.number != null) {
        avail[p.number!] = (avail[p.number!] ?? 0) + 1;
      }
    }
    for (final d in level.dispensers) {
      for (final n in d.queue) {
        avail[n] = (avail[n] ?? 0) + 1;
      }
    }
    if (frozen.isNotEmpty) {
      final unlockedTargets = <int>{};
      bool progressed = true;
      while (progressed && frozen.isNotEmpty) {
        progressed = false;
        final produced = _reachableMergedValues(avail);
        for (int i = frozen.length - 1; i >= 0; i--) {
          final fp = frozen[i];
          final t = fp.iceTarget!;
          if (produced.contains(t) || unlockedTargets.contains(t)) {
            unlockedTargets.add(t);
            if (fp.number != null) {
              avail[fp.number!] = (avail[fp.number!] ?? 0) + 1;
            }
            frozen.removeAt(i);
            progressed = true;
          }
        }
      }
      if (frozen.isNotEmpty) {
        final stuck = frozen.map((p) => '${p.key}(ice:${p.iceTarget})').join(', ');
        return 'Ice deadlock: unreachable targets $stuck';
      }
    }

    // 4. Pinned pair check
    final pinnedByNum = <int, List<GenPiece>>{};
    for (final p in level.pieces) {
      if (p.number != null && p.movement.isPinned) {
        pinnedByNum.putIfAbsent(p.number!, () => []).add(p);
      }
    }
    for (final entry in pinnedByNum.entries) {
      if (entry.value.length >= 2) {
        final numVal = entry.key;
        int otherSum = 0;
        for (final p in level.pieces) {
          if (p.number != null &&
              p.number! <= numVal &&
              !entry.value.contains(p)) {
            otherSum += p.number!;
          }
        }
        if (otherSum < numVal) {
          return 'Pinned pair deadlock on number $numVal';
        }
      }
    }

    // 5. Key & Lock consistency check (every lock color must have an existing key)
    final presentKeyColors = <String>{
      for (final p in level.pieces)
        if (p.keyColor != null) p.keyColor!,
    };
    for (final p in level.pieces) {
      if (p.lockColor != null && !presentKeyColors.contains(p.lockColor)) {
        return 'Orphan lock color "${p.lockColor}" on piece ${p.key} with no matching key';
      }
      if (p.keyColor != null && p.lockColor == p.keyColor) {
        return 'Self-locked key "${p.keyColor}" on piece ${p.key}';
      }
    }

    return null;
  }

  /// Computes all merged values reachable from a multiset `avail`.
  static Set<int> _reachableMergedValues(Map<int, int> avail) {
    final c = Map<int, int>.from(avail);
    final produced = <int>{};
    bool changed = true;
    while (changed) {
      changed = false;
      final keys = c.keys.toList()..sort();
      for (final k in keys) {
        final cnt = c[k] ?? 0;
        if (cnt >= 2) {
          final next = k * 2;
          produced.add(next);
          c[next] = (c[next] ?? 0) + (cnt ~/ 2);
          c[k] = cnt % 2;
          changed = true;
        }
      }
    }
    return produced;
  }

  /// Runs exact-parity A* Raycast Solver matching `BlockOrderGame` mechanics.
  static SolveResult solve(
    GenLevel level, {
    int maxVisited = 30000,
    int timeoutMs = 1800,
    bool recordSteps = false,
    bool strictWallBlocking = true,
  }) {
    final sw = Stopwatch()..start();

    final staticErr = runStaticChecks(level);
    if (staticErr != null) {
      return SolveResult(
        status: SolveStatus.unsolvable,
        reason: staticErr,
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    final cols = level.cols;
    final rows = level.rows;
    final gridSize = cols * rows;
    final playable = Uint8List(gridSize)..fillRange(0, gridSize, 1);
    for (final (c, r) in level.walls) {
      if (c >= 0 && c < cols && r >= 0 && r < rows) {
        playable[r * cols + c] = 0;
      }
    }
    final redWallMask = Uint8List(gridSize);
    for (final (c, r) in level.redWalls) {
      if (c >= 0 && c < cols && r >= 0 && r < rows) {
        redWallMask[r * cols + c] = 1;
      }
    }
    final blueWallMask = Uint8List(gridSize);
    for (final (c, r) in level.blueWalls) {
      if (c >= 0 && c < cols && r >= 0 && r < rows) {
        blueWallMask[r * cols + c] = 1;
      }
    }
    final hasToggle = level.hasToggleWalls;
    final dispensers = level.dispensers;
    int nextSpawnId = level.pieces.length + 100;

    (List<_SimPiece>, List<int>) applyDispense(
      List<_SimPiece> pieces,
      List<int> offsets,
      int wallPhase,
    ) {
      if (dispensers.isEmpty) return (pieces, offsets);
      final activeToggle = wallPhase == 0 ? redWallMask : blueWallMask;
      final occSet = <int>{};
      for (final p in pieces) {
        for (final (dc, dr) in p.cells) {
          occSet.add((p.row + dr) * cols + (p.col + dc));
        }
      }
      List<_SimPiece>? nextPieces;
      List<int>? nextOffsets;
      for (int di = 0; di < dispensers.length; di++) {
        final d = dispensers[di];
        final off = (nextOffsets ?? offsets)[di];
        if (off >= d.queue.length) continue;
        final (mc, mr) = d.mouthCell;
        if (mc < 0 || mc >= cols || mr < 0 || mr >= rows) continue;
        final mIdx = mr * cols + mc;
        if (playable[mIdx] == 0) continue;
        if (hasToggle && activeToggle[mIdx] == 1) continue;
        if (occSet.contains(mIdx)) continue;

        nextPieces ??= List<_SimPiece>.of(pieces);
        nextOffsets ??= List<int>.of(offsets);
        final numVal = d.queue[off];
        nextOffsets[di] = off + 1;
        final sid = nextSpawnId++;
        nextPieces.add(
          _SimPiece(
            id: sid,
            key: 'D${di}_$off',
            col: mc,
            row: mr,
            cells: const [(0, 0)],
            number: numVal,
            iceTarget: null,
            movement: MovementType.free,
          ),
        );
        occSet.add(mIdx);
      }
      return (nextPieces ?? pieces, nextOffsets ?? offsets);
    }

    int countRemainingDispensed(List<int> offsets) {
      int rem = 0;
      for (int di = 0; di < dispensers.length; di++) {
        rem += dispensers[di].queue.length - offsets[di];
      }
      return rem;
    }

    final rawInitial = [
      for (final p in level.pieces)
        _SimPiece(
          id: p.id,
          key: p.key,
          col: p.col,
          row: p.row,
          cells: p.cells,
          number: p.number,
          iceTarget: p.iceTarget,
          movement: p.movement,
          isMystery: p.isMystery,
          keyColor: p.keyColor,
          lockColor: p.lockColor,
          swapUses: p.swapUses,
          movesLeft: p.movesLeft,
        ),
    ];
    final initOffsetsRaw = List<int>.filled(dispensers.length, 0);
    final (initial, initOffsets) = applyDispense(rawInitial, initOffsetsRaw, 0);

    final initNumbered = initial.where((p) => !p.isDud).length;
    if (initNumbered <= 1 && countRemainingDispensed(initOffsets) == 0) {
      return SolveResult(
        status: SolveStatus.solved,
        reason: 'Already won',
        elapsedMs: sw.elapsedMilliseconds,
      );
    }

    final visited = <String>{
      _canonicalKey(initial, wallPhase: hasToggle ? 0 : -1, dispenserOffsets: initOffsets),
    };
    final heap = _MinHeap();
    int stateCounter = 0;
    heap.push(
      _SearchNode(
        priority: _heuristic(
          initial,
          remainingDispenserBlocks: countRemainingDispensed(initOffsets),
        ),
        moves: 0,
        merges: 0,
        tieBreaker: stateCounter++,
        pieces: initial,
        wallPhase: 0,
        dispenserOffsets: initOffsets,
      ),
    );

    final occ = Int16List(gridSize);
    int checkCounter = 0;

    while (!heap.isEmpty) {
      if (visited.length > maxVisited) {
        return SolveResult(
          status: SolveStatus.searchLimit,
          reason: 'Exceeded maxVisited ($maxVisited)',
          visitedStates: visited.length,
          elapsedMs: sw.elapsedMilliseconds,
        );
      }
      if ((++checkCounter & 0xFF) == 0 && sw.elapsedMilliseconds > timeoutMs) {
        return SolveResult(
          status: SolveStatus.timeout,
          reason: 'Timed out (${timeoutMs}ms)',
          visitedStates: visited.length,
          elapsedMs: sw.elapsedMilliseconds,
        );
      }

      final cur = heap.pop();
      final curPieces = cur.pieces;

      int numLeft = 0;
      for (final p in curPieces) {
        if (!p.isDud) numLeft++;
      }
      if (numLeft <= 1 && countRemainingDispensed(cur.dispenserOffsets) == 0) {
        final steps = <String>[];
        if (recordSteps) {
          _SearchNode? cursor = cur;
          while (cursor != null && cursor.moveDesc != null) {
            steps.add(cursor.moveDesc!);
            cursor = cursor.parent;
          }
          for (int l = 0, r = steps.length - 1; l < r; l++, r--) {
            final tmp = steps[l];
            steps[l] = steps[r];
            steps[r] = tmp;
          }
        }
        return SolveResult(
          status: SolveStatus.solved,
          reason: 'SOLVED',
          totalMoves: cur.moves,
          mergeMoves: cur.merges,
          slideMoves: cur.moves - cur.merges,
          visitedStates: visited.length,
          elapsedMs: sw.elapsedMilliseconds,
          steps: steps,
        );
      }

      // Build occupancy grid: cell -> index in curPieces (-1 if empty)
      occ.fillRange(0, gridSize, -1);
      for (int idx = 0; idx < curPieces.length; idx++) {
        final p = curPieces[idx];
        for (final (dc, dr) in p.cells) {
          occ[(p.row + dr) * cols + (p.col + dc)] = idx;
        }
      }
      final activeToggle = cur.wallPhase == 0 ? redWallMask : blueWallMask;

      // Expand moves for each movable piece
      for (int i = 0; i < curPieces.length; i++) {
        final p = curPieces[i];
        if (!p.canMove) continue;

        for (final (dx, dy) in _allowedDirs(p.movement)) {
          int contactCol = p.col;
          int contactRow = p.row;
          int step = 1;

          while (true) {
            final nextCol = p.col + step * dx;
            final nextRow = p.row + step * dy;

            bool hitsWallOrBound = false;
            int hitPieceIdx = -1;
            bool multiHit = false;

            for (final (dc, dr) in p.cells) {
              final c = nextCol + dc;
              final r = nextRow + dr;
              if (c < 0 || c >= cols || r < 0 || r >= rows) {
                hitsWallOrBound = true;
                continue;
              }
              final gIdx = r * cols + c;
              if (playable[gIdx] == 0) {
                hitsWallOrBound = true;
              } else if (hasToggle &&
                  activeToggle[gIdx] == 1 &&
                  occ[gIdx] != i) {
                // Raised toggle wall blocks unless piece `i` itself is already holding it down
                hitsWallOrBound = true;
              }
              final otherIdx = occ[gIdx];
              if (otherIdx >= 0 && otherIdx != i) {
                if (hitPieceIdx == -1) {
                  hitPieceIdx = otherIdx;
                } else if (hitPieceIdx != otherIdx) {
                  multiHit = true;
                }
              }
            }

            // Case 1: Pure empty slide step
            if (!hitsWallOrBound && hitPieceIdx == -1) {
              int? nextMovesLeft = p.movesLeft;
              MovementType nextMv = p.movement;
              if (nextMovesLeft != null && nextMovesLeft > 0) {
                nextMovesLeft = nextMovesLeft - 1;
                if (nextMovesLeft <= 0) {
                  nextMovesLeft = null;
                  nextMv = MovementType.pinned;
                }
              }
              final moved = _SimPiece(
                id: p.id,
                key: p.key,
                col: nextCol,
                row: nextRow,
                cells: p.cells,
                number: p.number,
                iceTarget: p.iceTarget,
                movement: nextMv,
                isMystery: p.isMystery,
                keyColor: p.keyColor,
                lockColor: p.lockColor,
                swapUses: p.swapUses,
                movesLeft: nextMovesLeft,
              );
              final rawNext = List<_SimPiece>.of(curPieces)..[i] = moved;
              final (nextPieces, nextOffsets) = applyDispense(
                rawNext,
                cur.dispenserOffsets,
                cur.wallPhase,
              );
              final key = _canonicalKey(
                nextPieces,
                wallPhase: hasToggle ? cur.wallPhase : -1,
                dispenserOffsets: nextOffsets,
              );
              if (visited.add(key)) {
                final nextMoves = cur.moves + 1;
                final h = _heuristic(
                  nextPieces,
                  remainingDispenserBlocks: countRemainingDispensed(nextOffsets),
                );
                heap.push(
                  _SearchNode(
                    priority: h + nextMoves * 2,
                    moves: nextMoves,
                    merges: cur.merges,
                    tieBreaker: stateCounter++,
                    pieces: nextPieces,
                    wallPhase: cur.wallPhase,
                    dispenserOffsets: nextOffsets,
                    parent: recordSteps ? cur : null,
                    moveDesc: recordSteps
                        ? 'Slide ${p.key}(${p.number ?? "DUD"}) -> ($nextCol,$nextRow)'
                        : null,
                  ),
                );
              }
              contactCol = nextCol;
              contactRow = nextRow;
              step++;
              continue;
            }

            // Case 2: Exact game-parity merge check when hitting exactly 1 piece
            if (!multiHit && hitPieceIdx >= 0 && (!strictWallBlocking || !hitsWallOrBound)) {
              final target = curPieces[hitPieceIdx];
              if (p.canMerge &&
                  target.canMerge &&
                  p.number == target.number) {
                final draggedSurvives = p.cells.length > target.cells.length;
                final canMerge = strictWallBlocking
                    ? !hitsWallOrBound
                    : (!draggedSurvives || !hitsWallOrBound);
                if (canMerge) {
                  final newNumber = p.number! * 2;
                  final combinedMv = p.movement.resolveMergedWith(
                    target.movement,
                  );
                  final survivor = draggedSurvives
                      ? _SimPiece(
                          id: p.id,
                          key: p.key,
                          col: contactCol + dx,
                          row: contactRow + dy,
                          cells: p.cells,
                          number: newNumber,
                          iceTarget: null,
                          movement: combinedMv,
                        )
                      : _SimPiece(
                          id: target.id,
                          key: target.key,
                          col: target.col,
                          row: target.row,
                          cells: target.cells,
                          number: newNumber,
                          iceTarget: null,
                          movement: combinedMv,
                        );

                  final triggeredKeyColors = <String>{
                    if (p.keyColor != null) p.keyColor!,
                    if (target.keyColor != null) target.keyColor!,
                  };
                  final mergeCells = <GridCell>{
                    for (final (dc, dr) in survivor.cells)
                      (survivor.col + dc, survivor.row + dr),
                    for (final (dc, dr) in (draggedSurvives ? target.cells : p.cells))
                      ((draggedSurvives ? target.col : contactCol) + dc,
                          (draggedSurvives ? target.row : contactRow) + dr),
                  };

                  final nextPieces = <_SimPiece>[];
                  int iceUnlocked = 0;
                  int locksUnlocked = 0;
                  int mysteriesRevealed = 0;
                  for (int k = 0; k < curPieces.length; k++) {
                    if (k == i || k == hitPieceIdx) continue;
                    final op = curPieces[k];
                    final unlockIce = op.iceTarget == newNumber;
                    final unlockLock = op.lockColor != null &&
                        triggeredKeyColors.contains(op.lockColor);
                    bool revealMystery = false;
                    if (op.isMystery) {
                      for (final (dc, dr) in op.cells) {
                        final oc = op.col + dc;
                        final or = op.row + dr;
                        if (mergeCells.contains((oc + 1, or)) ||
                            mergeCells.contains((oc - 1, or)) ||
                            mergeCells.contains((oc, or + 1)) ||
                            mergeCells.contains((oc, or - 1))) {
                          revealMystery = true;
                          break;
                        }
                      }
                    }

                    if (unlockIce || unlockLock || revealMystery) {
                      if (unlockIce) iceUnlocked++;
                      if (unlockLock) locksUnlocked++;
                      if (revealMystery) mysteriesRevealed++;
                      nextPieces.add(
                        _SimPiece(
                          id: op.id,
                          key: op.key,
                          col: op.col,
                          row: op.row,
                          cells: op.cells,
                          number: op.number,
                          iceTarget: unlockIce ? null : op.iceTarget,
                          movement: op.movement,
                          isMystery: revealMystery ? false : op.isMystery,
                          keyColor: op.keyColor,
                          lockColor: unlockLock ? null : op.lockColor,
                          swapUses: op.swapUses,
                          movesLeft: op.movesLeft,
                        ),
                      );
                    } else {
                      nextPieces.add(op);
                    }
                  }
                  nextPieces.add(survivor);
                  final nextWallPhase = hasToggle ? (cur.wallPhase ^ 1) : 0;
                  final (finalPieces, nextOffsets) = applyDispense(
                    nextPieces,
                    cur.dispenserOffsets,
                    nextWallPhase,
                  );

                  final key = _canonicalKey(
                    finalPieces,
                    wallPhase: hasToggle ? nextWallPhase : -1,
                    dispenserOffsets: nextOffsets,
                  );
                  if (visited.add(key)) {
                    final nextMoves = cur.moves + 1;
                    final nextMerges = cur.merges + 1;
                    final h = _heuristic(
                      finalPieces,
                      remainingDispenserBlocks:
                          countRemainingDispensed(nextOffsets),
                    );
                    heap.push(
                      _SearchNode(
                        // Strong reward for merges, ice/key unlocks & mystery reveals
                        priority: h +
                            nextMoves * 2 -
                            220 -
                            iceUnlocked * 80 -
                            locksUnlocked * 90 -
                            mysteriesRevealed * 70,
                        moves: nextMoves,
                        merges: nextMerges,
                        tieBreaker: stateCounter++,
                        pieces: finalPieces,
                        wallPhase: nextWallPhase,
                        dispenserOffsets: nextOffsets,
                        parent: recordSteps ? cur : null,
                        moveDesc: recordSteps
                            ? 'Merge ${p.key}(${p.number}) + ${target.key}(${target.number}) -> $newNumber'
                            : null,
                      ),
                    );
                  }
                }
              } else if (p.swapUses > 0 &&
                  p.canMerge &&
                  target.canMerge &&
                  p.number != target.number) {
                // Case 2b: One-time Number Swap when pushing a Swap Block into a different-number block
                final movedBeforeSwap = contactCol != p.col || contactRow != p.row;
                int? nextMovesLeft = p.movesLeft;
                MovementType nextMv = p.movement;
                if (movedBeforeSwap && nextMovesLeft != null && nextMovesLeft > 0) {
                  nextMovesLeft = nextMovesLeft - 1;
                  if (nextMovesLeft <= 0) {
                    nextMovesLeft = null;
                    nextMv = MovementType.pinned;
                  }
                }
                final swappedP = _SimPiece(
                  id: p.id,
                  key: p.key,
                  col: contactCol,
                  row: contactRow,
                  cells: p.cells,
                  number: target.number,
                  iceTarget: p.iceTarget,
                  movement: nextMv,
                  isMystery: p.isMystery,
                  keyColor: p.keyColor,
                  lockColor: p.lockColor,
                  swapUses: p.swapUses - 1,
                  movesLeft: nextMovesLeft,
                );
                final swappedTarget = _SimPiece(
                  id: target.id,
                  key: target.key,
                  col: target.col,
                  row: target.row,
                  cells: target.cells,
                  number: p.number,
                  iceTarget: target.iceTarget,
                  movement: target.movement,
                  isMystery: target.isMystery,
                  keyColor: target.keyColor,
                  lockColor: target.lockColor,
                  swapUses: target.swapUses,
                  movesLeft: target.movesLeft,
                );
                final rawNext = List<_SimPiece>.of(curPieces)
                  ..[i] = swappedP
                  ..[hitPieceIdx] = swappedTarget;
                final (nextPieces, nextOffsets) = applyDispense(
                  rawNext,
                  cur.dispenserOffsets,
                  cur.wallPhase,
                );
                final key = _canonicalKey(
                  nextPieces,
                  wallPhase: hasToggle ? cur.wallPhase : -1,
                  dispenserOffsets: nextOffsets,
                );
                if (visited.add(key)) {
                  final nextMoves = cur.moves + 1;
                  final h = _heuristic(
                    nextPieces,
                    remainingDispenserBlocks: countRemainingDispensed(nextOffsets),
                  );
                  heap.push(
                    _SearchNode(
                      priority: h + nextMoves * 2 - 40,
                      moves: nextMoves,
                      merges: cur.merges,
                      tieBreaker: stateCounter++,
                      pieces: nextPieces,
                      wallPhase: cur.wallPhase,
                      dispenserOffsets: nextOffsets,
                      parent: recordSteps ? cur : null,
                      moveDesc: recordSteps
                          ? 'Swap ${p.key}(${p.number}) <-> ${target.key}(${target.number})'
                          : null,
                    ),
                  );
                }
              }
            }

            // Cannot raycast past a wall or piece
            break;
          }
        }
      }
    }

    return SolveResult(
      status: SolveStatus.unsolvable,
      reason: 'Deadlock: exhausted all reachable states without winning',
      visitedStates: visited.length,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  static int _heuristic(
    List<_SimPiece> pieces, {
    int remainingDispenserBlocks = 0,
  }) {
    int numberedCount = 0;
    int frozenCount = 0;
    int lockedCount = 0;
    int mysteryCount = 0;
    int pinnedCount = 0;
    final byNum = <int, List<_SimPiece>>{};

    for (final p in pieces) {
      if (p.isFrozen) frozenCount++;
      if (p.isLocked) lockedCount++;
      if (p.isMystery) mysteryCount++;
      if (p.movement.isPinned) pinnedCount++;
      final n = p.number;
      if (n != null) {
        numberedCount++;
        if (p.canMerge) {
          byNum.putIfAbsent(n, () => []).add(p);
        }
      }
    }

    int distSum = 0;
    for (final list in byNum.values) {
      if (list.length >= 2) {
        int minD = 999;
        for (int a = 0; a < list.length; a++) {
          final pa = list[a];
          for (int b = a + 1; b < list.length; b++) {
            final pb = list[b];
            final d = (pa.col - pb.col).abs() + (pa.row - pb.row).abs();
            if (d < minD) minD = d;
          }
        }
        distSum += minD;
      }
    }

    return (numberedCount + remainingDispenserBlocks) * 260 +
        frozenCount * 45 +
        lockedCount * 55 +
        mysteryCount * 40 +
        pinnedCount * 20 +
        distSum * 4;
  }

  static String _canonicalKey(
    List<_SimPiece> pieces, {
    int wallPhase = -1,
    List<int> dispenserOffsets = const [],
  }) {
    final sigs = [for (final p in pieces) p.signature()]..sort();
    final base = sigs.join('|');
    if (wallPhase < 0 && dispenserOffsets.isEmpty) return base;
    final buf = StringBuffer(base);
    if (wallPhase >= 0) {
      buf
        ..write('#W')
        ..write(wallPhase);
    }
    if (dispenserOffsets.isNotEmpty) {
      buf.write('#D');
      for (int i = 0; i < dispenserOffsets.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(dispenserOffsets[i]);
      }
    }
    return buf.toString();
  }

  /// Counts how many distinct immediate legal actions exist from the starting board.
  static int countInitialLegalActions(GenLevel level) {
    final cols = level.cols;
    final rows = level.rows;
    final occ = <GridCell, GenPiece>{};
    for (final p in level.pieces) {
      for (final wc in p.worldCells()) {
        occ[wc] = p;
      }
    }
    int actions = 0;
    for (final p in level.pieces) {
      if (!p.canMove) continue;
      for (final (dx, dy) in _allowedDirs(p.movement)) {
        bool blockedWall = false;
        final hits = <GenPiece>{};
        for (final (c, r) in p.worldCells(p.col + dx, p.row + dy)) {
          if (c < 0 || c >= cols || r < 0 || r >= rows || level.walls.contains((c, r))) {
            blockedWall = true;
            continue;
          }
          final other = occ[(c, r)];
          if (other != null && other.id != p.id) {
            hits.add(other);
          }
        }
        if (!blockedWall && hits.isEmpty) {
          actions++;
        } else if (hits.length == 1) {
          final target = hits.first;
          if (p.canMerge && target.canMerge && p.number == target.number) {
            final draggedSurvives = p.cells.length > target.cells.length;
            if (!draggedSurvives || !blockedWall) {
              actions++;
            }
          }
        }
      }
    }
    return actions;
  }

  /// Counts how many pairs of matching mergeable pieces start immediately adjacent (touching).
  static int countImmediatelyAdjacentPairs(GenLevel level) {
    final occ = <GridCell, GenPiece>{};
    for (final p in level.pieces) {
      for (final wc in p.worldCells()) {
        occ[wc] = p;
      }
    }
    final seenPairs = <(int, int)>{};
    for (final p in level.pieces) {
      if (!p.canMerge) continue;
      for (final (c, r) in p.worldCells()) {
        for (final (dx, dy) in _dirsAll) {
          final other = occ[(c + dx, r + dy)];
          if (other != null &&
              other.id != p.id &&
              other.canMerge &&
              other.number == p.number) {
            final pair = (math.min(p.id, other.id), math.max(p.id, other.id));
            seenPairs.add(pair);
          }
        }
      }
    }
    return seenPairs.length;
  }
}
