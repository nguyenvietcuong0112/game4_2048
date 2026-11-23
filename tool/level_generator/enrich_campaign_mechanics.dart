import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'models.dart';
import 'solver.dart';

const String _campaignPath = 'assets/levels/all_121_levels.json';

/// Exact Special Hard boss levels matching the rearranged progression plan
/// (Lv.28, 76, 101, 124, 153, 173 + periodic bosses through Lv.300).
const Set<int> kSpecialHardLevels = {
  28,
  76,
  101,
  124,
  153,
  173,
  193,
  213,
  233,
  253,
  273,
  293,
  300,
};

/// Exact Remix combo showcase levels from the progression plan.
const Map<int, List<String>> kRemixLevels = {
  64: ['keyLock', 'oneWayArrow'],
  89: ['swap', 'limitedMove'],
  115: ['dispenser', 'mystery'],
  143: ['toggleWalls', 'arrows'],
  163: ['dispenser', 'keyLock'],
};

/// Exact first-unlock milestone levels for all 8 Wave 1-3 mechanics:
/// - Lv.33  : Mystery Block (?)
/// - Lv.50  : One-Way Arrow (single-direction slide)
/// - Lv.58  : Key & Lock Block (gold / ruby / emerald)
/// - Lv.70  : Swap Block (one-time number swap)
/// - Lv.83  : Limited-Move / Fragile Block (nails to Pinned after N moves)
/// - Lv.95  : Clock Bonus Block (+15s / +12s)
/// - Lv.108 : Pipe Dispenser (water pipe block queue)
/// - Lv.133 : Toggle Walls (Red / Blue alternating gates)
///
/// Classic mechanics stay on their exact original unlock levels:
/// - Lv.7   : Ice
/// - Lv.14  : Dud
/// - Lv.22  : Arrows
/// - Lv.42  : Pinned
///
/// Enriches Campaign Levels 28..300 while keeping Levels 1..27 completely untouched!
void main() {
  final file = File(_campaignPath);
  if (!file.existsSync()) {
    stderr.writeln('Error: $_campaignPath not found');
    exitCode = 1;
    return;
  }

  final rawList = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  final rng = math.Random(20261123);

  final counts = <String, int>{
    'special': 0,
    'mystery': 0,
    'oneWayArrow': 0,
    'keyLock': 0,
    'swap': 0,
    'limitedMove': 0,
    'clockBonus': 0,
    'dispenser': 0,
    'toggleWalls': 0,
  };
  final firstSeen = <String, int>{};
  int mutatedLevels = 0;

  final sw = Stopwatch()..start();

  for (int i = 0; i < rawList.length; i++) {
    final entry = rawList[i] as Map<String, dynamic>;
    final baseLevel = GenLevel.fromCampaignJson(entry, i + 1);
    final lvNum = baseLevel.number;

    // Strictly preserve Levels 1..27 untouched (Lv 1..27 classic + our tuned Lv 6)!
    // Also preserve Lv 42 clean Pinned debut spotlight!
    if (lvNum < 28) continue;

    final strippedBase = _stripNewMechanics(baseLevel);
    final hadOldNewMechs = _hasAnyNewMechanic(baseLevel) || baseLevel.isSpecial;

    void writeEntry(GenLevel levelToWrite) {
      final updatedEntry = Map<String, dynamic>.from(entry);
      final dataMap = Map<String, dynamic>.from(
        (entry['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{},
      );
      dataMap['layout_text_json'] = levelToWrite.toLayoutJson();
      updatedEntry['data'] = dataMap;
      updatedEntry['content_hash'] = levelToWrite.computeContentHash();
      rawList[i] = updatedEntry;
    }

    if (lvNum == 42) {
      if (hadOldNewMechs) writeEntry(strippedBase);
      continue;
    }

    final isSpecial = kSpecialHardLevels.contains(lvNum);
    final isRemix = kRemixLevels.containsKey(lvNum);
    final wanted = _pickMechanicsForLevel(lvNum, rng);

    if (wanted.isEmpty && !isSpecial) {
      if (hadOldNewMechs) {
        writeEntry(strippedBase);
      }
      continue;
    }

    var current = strippedBase;
    bool changed = false;

    for (final mech in wanted) {
      final isKeyBeat = _isMilestoneLevel(lvNum, mech) || isRemix || isSpecial;
      final maxTries = isKeyBeat ? 22 : 6;
      final maxVisited = isKeyBeat ? 20000 : 7500;
      final timeoutMs = isKeyBeat ? 900 : 280;
      final mutated = _tryApplyMechanic(
        current,
        mech,
        rng,
        maxTries: maxTries,
        maxVisited: maxVisited,
        timeoutMs: timeoutMs,
        allowEdgeWallForDispenser: isKeyBeat,
      );
      if (mutated != null) {
        current = mutated;
        changed = true;
      } else if (isKeyBeat) {
        stderr.writeln('[WARN] Key beat Lv $lvNum could not apply $mech directly!');
      }
    }

    if (isSpecial) {
      // Tighten timer slightly (~12%) on Special Hard boss levels for extra tension
      final tightenedTime = current.timerDisabled
          ? current.timeSeconds
          : math.max(55, (current.timeSeconds * 0.88).round());
      current = _copyLevel(
        current,
        isSpecial: true,
        timeSeconds: tightenedTime,
      );
      changed = true;
    }

    if (!changed) {
      if (hadOldNewMechs) {
        writeEntry(strippedBase);
      }
      continue;
    }

    // Verify combined topological mechanics when >= 2 constraint mechanics were added together
    final constraintCount = [
      current.hasMystery,
      current.hasKeyLock,
      current.hasToggleWalls,
      current.hasDispensers,
      current.hasOneWayArrow,
      current.hasLimitedMove,
    ].where((b) => b).length;

    SolveResult? finalSolve;
    if (constraintCount >= 2) {
      finalSolve = LevelSolver.solve(
        current,
        maxVisited: (isRemix || isSpecial) ? 26000 : 10000,
        timeoutMs: (isRemix || isSpecial) ? 1200 : 400,
      );
      if (!finalSolve.isSolved && !isRemix && !isSpecial) {
        stderr.writeln(
          '[SKIP] Lv $lvNum combined verification failed (${finalSolve.reason}), keeping clean base.',
        );
        if (hadOldNewMechs) {
          writeEntry(strippedBase);
        }
        continue;
      }
    }

    writeEntry(current);
    mutatedLevels++;

    void record(String key, bool present) {
      if (!present) return;
      counts[key] = (counts[key] ?? 0) + 1;
      firstSeen.putIfAbsent(key, () => lvNum);
    }

    record('special', current.isSpecial);
    record('mystery', current.hasMystery);
    record('oneWayArrow', current.hasOneWayArrow);
    record('keyLock', current.hasKeyLock);
    record('swap', current.hasSwap);
    record('limitedMove', current.hasLimitedMove);
    record('clockBonus', current.hasClockBonus);
    record('dispenser', current.hasDispensers);
    record('toggleWalls', current.hasToggleWalls);

    if (_isAnyMilestone(lvNum) || isRemix || isSpecial || lvNum % 30 == 0) {
      final tag = isSpecial
          ? 'SPECIAL'
          : isRemix
              ? 'REMIX  '
              : _isAnyMilestone(lvNum)
                  ? 'UNLOCK '
                  : 'OK     ';
      stdout.writeln(
        '[$tag] Lv ${lvNum.toString().padLeft(3)} | '
        '${current.activeMechanicNames.join("+").padRight(42)} | '
        'time:${current.timeSeconds}s',
      );
    }
  }

  file.writeAsStringSync('${jsonEncode(rawList)}\n');

  stdout.writeln(
    '\n=== Enriched $mutatedLevels levels in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(2)}s (Total: ${rawList.length} levels) ===',
  );
  stdout.writeln('Mechanic coverage & first unlock level:');
  for (final k in counts.keys) {
    stdout.writeln(
      '  - ${k.padRight(14)}: ${counts[k].toString().padLeft(3)} levels (first: Lv.${firstSeen[k] ?? "-"})',
    );
  }
}

bool _hasAnyNewMechanic(GenLevel lv) =>
    lv.hasClockBonus ||
    lv.hasMystery ||
    lv.hasKeyLock ||
    lv.hasToggleWalls ||
    lv.hasDispensers ||
    lv.hasSwap ||
    lv.hasOneWayArrow ||
    lv.hasLimitedMove;

bool _isMilestoneLevel(int lv, String mech) {
  return switch (mech) {
    'mystery' => lv == 33,
    'oneWayArrow' => lv == 50,
    'keyLock' => lv == 58,
    'swap' => lv == 70,
    'limitedMove' => lv == 83,
    'clockBonus' => lv == 95,
    'dispenser' => lv == 108,
    'toggleWalls' => lv == 133,
    _ => false,
  };
}

bool _isAnyMilestone(int lv) =>
    lv == 33 ||
    lv == 50 ||
    lv == 58 ||
    lv == 70 ||
    lv == 83 ||
    lv == 95 ||
    lv == 108 ||
    lv == 133;

List<String> _pickMechanicsForLevel(int lv, math.Random rng) {
  // 1. Exact single-mechanic spotlight unlocks
  if (lv == 33) return const ['mystery'];
  if (lv == 50) return const ['oneWayArrow'];
  if (lv == 58) return const ['keyLock'];
  if (lv == 70) return const ['swap'];
  if (lv == 83) return const ['limitedMove'];
  if (lv == 95) return const ['clockBonus'];
  if (lv == 108) return const ['dispenser'];
  if (lv == 133) return const ['toggleWalls'];

  // 2. Exact Remix showcase levels
  final remix = kRemixLevels[lv];
  if (remix != null) return remix;

  // 3. Special Hard boss levels — rich multi-mechanic challenges using ONLY unlocked mechanics
  if (lv == 28) {
    // First Special Hard level (classic era: Ice + Dud + Arrows unlocked)
    return const ['ice', 'arrows'];
  }
  if (lv == 76) return const ['keyLock', 'oneWayArrow'];
  if (lv == 101) return const ['clockBonus', 'limitedMove'];
  if (lv == 124) return const ['dispenser', 'swap'];
  if (lv == 153) return const ['toggleWalls', 'keyLock'];
  if (lv == 173) return const ['toggleWalls', 'dispenser', 'clockBonus'];
  if (kSpecialHardLevels.contains(lv)) {
    final pool = [
      'mystery',
      'oneWayArrow',
      'keyLock',
      'swap',
      'limitedMove',
      'clockBonus',
      'dispenser',
      'toggleWalls',
    ]..shuffle(rng);
    return pool.take(2).toList();
  }

  // 4. Keep Lv 29..32 clean classic (Mystery hasn't unlocked yet until Lv 33!)
  if (lv < 33) return const [];

  // 5. Follow-up practice levels immediately after each unlock so players master it
  if (lv == 34 || lv == 36 || lv == 39) return const ['mystery'];
  if (lv == 51 || lv == 53) return const ['oneWayArrow'];
  if (lv == 59 || lv == 61) return const ['keyLock'];
  if (lv == 71 || lv == 73) return const ['swap'];
  if (lv == 84 || lv == 86) return const ['limitedMove'];
  if (lv == 96 || lv == 98) return const ['clockBonus'];
  if (lv == 109 || lv == 111) return const ['dispenser'];
  if (lv == 134 || lv == 136) return const ['toggleWalls'];

  // 6. Between Lv 33..49 only Mystery is unlocked; sprinkle it gently (~every 3rd level)
  if (lv < 50) {
    return (lv == 40 || lv == 45 || lv == 48) ? const ['mystery'] : const [];
  }

  final unlocked = <String>[
    if (lv >= 33) 'mystery',
    if (lv >= 50) 'oneWayArrow',
    if (lv >= 58) 'keyLock',
    if (lv >= 70) 'swap',
    if (lv >= 83) 'limitedMove',
    if (lv >= 95) 'clockBonus',
    if (lv >= 108) 'dispenser',
    if (lv >= 133) 'toggleWalls',
  ];
  if (unlocked.isEmpty) return const [];

  // Every ~7th level stays clean classic for breathing room
  if (lv % 7 == 0) return const [];

  final shuffled = List<String>.from(unlocked)..shuffle(rng);
  final latest = unlocked.last;
  if (rng.nextDouble() < 0.45) {
    shuffled
      ..remove(latest)
      ..insert(0, latest);
  }

  final wantTwo = lv >= 110 && (lv % 5 == 0 || lv % 5 == 4);
  return shuffled.take(wantTwo ? 2 : 1).toList();
}

GenLevel _stripNewMechanics(GenLevel lv) {
  final pieces = [
    for (final p in lv.pieces)
      p.copyWith(
        clearClockBonus: true,
        isMystery: false,
        clearKeyColor: true,
        clearLockColor: true,
        swapUses: 0,
        clearMovesLeft: true,
        movement: p.movement.isOneWay ? MovementType.free : p.movement,
      ),
  ];

  // Restore any timer adjustments made by previous Clock Bonus / Dispenser enrichment
  int timeAdj = lv.timeSeconds;
  for (final p in lv.pieces) {
    if (p.clockBonusSeconds != null) {
      timeAdj += (p.clockBonusSeconds! - 5);
    }
  }

  // Reverse any previous Dispenser splits (`origNum -> half` on board + `queue` summing to `half`)
  for (final d in lv.dispensers) {
    final qSum = d.queue.fold<int>(0, (a, b) => a + b);
    timeAdj = math.max(45, timeAdj - 10);
    final matchingIdx = <int>[
      for (int i = 0; i < pieces.length; i++)
        if (!pieces[i].isDud && !pieces[i].isFrozen && pieces[i].number == qSum)
          i,
    ];
    if (matchingIdx.isEmpty) {
      for (int i = 0; i < pieces.length; i++) {
        if (!pieces[i].isDud && pieces[i].number == qSum) {
          matchingIdx.add(i);
        }
      }
    }
    int chosen = matchingIdx.isNotEmpty ? matchingIdx.first : -1;
    if (matchingIdx.length > 1) {
      for (final idx in matchingIdx) {
        final testPieces = [for (final p in pieces) p.copyWith()];
        testPieces[idx] = testPieces[idx].copyWith(number: qSum * 2);
        final testLv = GenLevel(
          number: lv.number,
          cols: lv.cols,
          rows: lv.rows,
          timeSeconds: timeAdj,
          timerDisabled: lv.timerDisabled,
          walls: Set<GridCell>.from(lv.walls),
          pieces: testPieces,
          bankId: lv.bankId,
          levelLayoutId: lv.levelLayoutId,
        );
        if (LevelSolver.runStaticChecks(testLv) == null &&
            LevelSolver.solve(testLv, maxVisited: 14000, timeoutMs: 600)
                .isSolved) {
          chosen = idx;
          break;
        }
      }
    }
    if (chosen >= 0) {
      pieces[chosen] = pieces[chosen].copyWith(number: qSum * 2);
    }
  }

  return GenLevel(
    number: lv.number,
    cols: lv.cols,
    rows: lv.rows,
    timeSeconds: timeAdj,
    timerDisabled: lv.timerDisabled,
    isSpecial: false,
    walls: Set<GridCell>.from(lv.walls),
    pieces: pieces,
    bankId: lv.bankId,
    levelLayoutId: lv.levelLayoutId,
  );
}

GenLevel? _tryApplyMechanic(
  GenLevel level,
  String mech,
  math.Random rng, {
  required int maxTries,
  required int maxVisited,
  required int timeoutMs,
  bool allowEdgeWallForDispenser = false,
}) {
  return switch (mech) {
    'clockBonus' => _applyClockBonus(level, rng),
    'mystery' => _applyMystery(
        level,
        rng,
        maxTries: maxTries,
        maxVisited: maxVisited,
        timeoutMs: timeoutMs,
      ),
    'keyLock' => _applyKeyLock(
        level,
        rng,
        maxTries: maxTries,
        maxVisited: maxVisited,
        timeoutMs: timeoutMs,
      ),
    'toggleWalls' => _applyToggleWalls(
        level,
        rng,
        maxTries: maxTries,
        maxVisited: maxVisited,
        timeoutMs: timeoutMs,
      ),
    'dispenser' => _applyDispenser(
        level,
        rng,
        maxTries: maxTries,
        maxVisited: maxVisited,
        timeoutMs: timeoutMs,
        allowEdgeWall: allowEdgeWallForDispenser,
      ),
    'swap' => _applySwap(level, rng),
    'oneWayArrow' => _applyOneWayArrow(
        level,
        rng,
        maxTries: maxTries,
        maxVisited: maxVisited,
        timeoutMs: timeoutMs,
      ),
    'limitedMove' => _applyLimitedMove(
        level,
        rng,
        maxTries: maxTries,
        maxVisited: maxVisited,
        timeoutMs: timeoutMs,
      ),
    'ice' => _applyClassicIce(
        level,
        rng,
        maxTries: maxTries,
        maxVisited: maxVisited,
        timeoutMs: timeoutMs,
      ),
    'arrows' => _applyClassicArrows(
        level,
        rng,
        maxTries: maxTries,
        maxVisited: maxVisited,
        timeoutMs: timeoutMs,
      ),
    _ => null,
  };
}

/// 1. Clock Bonus: strictly non-restrictive (+15s / +12s on merge).
GenLevel? _applyClockBonus(GenLevel level, math.Random rng) {
  if (level.timerDisabled) return null;
  final candidates = [
    for (int i = 0; i < level.pieces.length; i++)
      if (!level.pieces[i].isDud &&
          !level.pieces[i].isFrozen &&
          !level.pieces[i].isLocked &&
          !level.pieces[i].isMystery &&
          !level.pieces[i].hasClockBonus)
        i,
  ];
  if (candidates.isEmpty) return null;
  candidates.shuffle(rng);

  final bonusCount = (candidates.length >= 8 && rng.nextBool()) ? 2 : 1;
  final bonusSec = rng.nextBool() ? 15 : 12;
  final nextPieces = [for (final p in level.pieces) p.copyWith()];
  for (int k = 0; k < bonusCount; k++) {
    nextPieces[candidates[k]] =
        nextPieces[candidates[k]].copyWith(clockBonusSeconds: bonusSec);
  }
  final trim = bonusCount * (bonusSec - 5);
  final nextTime = math.max(45, level.timeSeconds - trim);

  return _copyLevel(level, timeSeconds: nextTime, pieces: nextPieces);
}

/// 2. Mystery Block: hides 1-2 unlocked pieces as '?' and verifies adjacent reveal via A*.
GenLevel? _applyMystery(
  GenLevel level,
  math.Random rng, {
  required int maxTries,
  required int maxVisited,
  required int timeoutMs,
}) {
  final eligible = [
    for (int i = 0; i < level.pieces.length; i++)
      if (!level.pieces[i].isDud &&
          !level.pieces[i].isFrozen &&
          !level.pieces[i].isLocked &&
          !level.pieces[i].hasKey &&
          !level.pieces[i].hasClockBonus &&
          !level.pieces[i].isMystery &&
          (level.pieces[i].number ?? 0) >= 4)
        i,
  ];
  if (eligible.isEmpty) return null;

  for (int attempt = 0; attempt < maxTries; attempt++) {
    eligible.shuffle(rng);
    final wantCount = (eligible.length >= 6 && attempt < maxTries ~/ 2) ? 2 : 1;
    final chosen = eligible.take(wantCount).toList();
    final nextPieces = [for (final p in level.pieces) p.copyWith()];
    for (final idx in chosen) {
      nextPieces[idx] = nextPieces[idx].copyWith(isMystery: true);
    }
    final candidate = _copyLevel(level, pieces: nextPieces);
    final res = LevelSolver.solve(
      candidate,
      maxVisited: maxVisited,
      timeoutMs: timeoutMs,
    );
    if (res.isSolved) return candidate;
  }
  return null;
}

/// 3. Key & Lock: colored Key on low-value piece + matching Lock on high-value piece, A*-verified.
GenLevel? _applyKeyLock(
  GenLevel level,
  math.Random rng, {
  required int maxTries,
  required int maxVisited,
  required int timeoutMs,
}) {
  final numberedIdx = [
    for (int i = 0; i < level.pieces.length; i++)
      if (!level.pieces[i].isDud &&
          !level.pieces[i].isFrozen &&
          !level.pieces[i].isLocked &&
          !level.pieces[i].hasKey &&
          !level.pieces[i].isMystery)
        i,
  ];
  if (numberedIdx.length < 4) return null;
  numberedIdx.sort(
    (a, b) =>
        (level.pieces[a].number ?? 0).compareTo(level.pieces[b].number ?? 0),
  );

  const colors = ['gold', 'ruby', 'emerald'];
  final lowPool = numberedIdx.take(math.max(2, numberedIdx.length ~/ 2)).toList();
  final highPool =
      numberedIdx.skip(math.max(2, numberedIdx.length ~/ 2)).toList();
  if (lowPool.isEmpty || highPool.isEmpty) return null;

  for (int attempt = 0; attempt < maxTries; attempt++) {
    final keyIdx = lowPool[rng.nextInt(lowPool.length)];
    final lockIdx = highPool[rng.nextInt(highPool.length)];
    if (keyIdx == lockIdx) continue;
    if (level.pieces[keyIdx].number == level.pieces[lockIdx].number) continue;

    final color = colors[(level.number + attempt) % colors.length];
    final nextPieces = [for (final p in level.pieces) p.copyWith()];
    nextPieces[keyIdx] = nextPieces[keyIdx].copyWith(keyColor: color);
    nextPieces[lockIdx] = nextPieces[lockIdx].copyWith(lockColor: color);

    final candidate = _copyLevel(level, pieces: nextPieces);
    final res = LevelSolver.solve(
      candidate,
      maxVisited: maxVisited,
      timeoutMs: timeoutMs,
    );
    if (res.isSolved) return candidate;
  }
  return null;
}

/// 4. Toggle Walls: 1-2 Red & 1-2 Blue alternating walls on empty floor cells, A*-verified.
GenLevel? _applyToggleWalls(
  GenLevel level,
  math.Random rng, {
  required int maxTries,
  required int maxVisited,
  required int timeoutMs,
}) {
  if (level.hasToggleWalls) return level;
  final occupied = <GridCell>{};
  for (final p in level.pieces) {
    occupied.addAll(p.worldCells());
  }
  final dispenserMouths = <GridCell>{
    for (final d in level.dispensers) d.mouthCell,
  };
  final emptyCells = <GridCell>[];
  for (int r = 0; r < level.rows; r++) {
    for (int c = 0; c < level.cols; c++) {
      final cell = (c, r);
      if (!level.walls.contains(cell) &&
          !occupied.contains(cell) &&
          !dispenserMouths.contains(cell)) {
        emptyCells.add(cell);
      }
    }
  }
  if (emptyCells.length < 2) return null;

  for (int attempt = 0; attempt < maxTries; attempt++) {
    emptyCells.shuffle(rng);
    final redCount = (emptyCells.length >= 6 && attempt < maxTries ~/ 2) ? 2 : 1;
    final blueCount = (emptyCells.length >= 6 && attempt < maxTries ~/ 2) ? 2 : 1;
    if (emptyCells.length < redCount + blueCount) continue;

    final reds = emptyCells.take(redCount).toSet();
    final blues = emptyCells.skip(redCount).take(blueCount).toSet();

    final candidate = _copyLevel(level, redWalls: reds, blueWalls: blues);
    final res = LevelSolver.solve(
      candidate,
      maxVisited: maxVisited,
      timeoutMs: timeoutMs,
    );
    if (res.isSolved) return candidate;
  }
  return null;
}

/// 5. Pipe Dispenser: mounts pipe on a wall (or empty edge cell if `allowEdgeWall`),
/// splitting an unlocked piece `N >= 4` conserving exact power-of-2 sum, A*-verified.
GenLevel? _applyDispenser(
  GenLevel level,
  math.Random rng, {
  required int maxTries,
  required int maxVisited,
  required int timeoutMs,
  bool allowEdgeWall = false,
}) {
  if (level.hasDispensers) return level;

  final occupied = <GridCell>{};
  for (final p in level.pieces) {
    occupied.addAll(p.worldCells());
  }

  final anchors = <(GridCell wallCell, GridCell dir, bool addWall)>[];
  const dirs = <GridCell>[(0, 1), (0, -1), (1, 0), (-1, 0)];
  for (final w in level.walls) {
    for (final d in dirs) {
      final m = (w.$1 + d.$1, w.$2 + d.$2);
      if (m.$1 >= 0 &&
          m.$1 < level.cols &&
          m.$2 >= 0 &&
          m.$2 < level.rows &&
          !level.walls.contains(m) &&
          !level.redWalls.contains(m) &&
          !level.blueWalls.contains(m)) {
        anchors.add((w, d, false));
      }
    }
  }

  if (anchors.isEmpty && allowEdgeWall) {
    for (int r = 0; r < level.rows; r++) {
      for (int c = 0; c < level.cols; c++) {
        final isEdge = r == 0 || r == level.rows - 1 || c == 0 || c == level.cols - 1;
        final cell = (c, r);
        if (!isEdge || occupied.contains(cell) || level.walls.contains(cell)) {
          continue;
        }
        for (final d in dirs) {
          final m = (c + d.$1, r + d.$2);
          if (m.$1 >= 0 &&
              m.$1 < level.cols &&
              m.$2 >= 0 &&
              m.$2 < level.rows &&
              !level.walls.contains(m) &&
              !level.redWalls.contains(m) &&
              !level.blueWalls.contains(m)) {
            anchors.add((cell, d, true));
          }
        }
      }
    }
  }
  if (anchors.isEmpty) return null;

  final splittable = [
    for (int i = 0; i < level.pieces.length; i++)
      if (!level.pieces[i].isDud &&
          !level.pieces[i].isFrozen &&
          !level.pieces[i].isLocked &&
          !level.pieces[i].isMystery &&
          (level.pieces[i].number ?? 0) >= 4)
        i,
  ];
  if (splittable.isEmpty) return null;

  for (int attempt = 0; attempt < maxTries; attempt++) {
    final anchor = anchors[rng.nextInt(anchors.length)];
    final pIdx = splittable[rng.nextInt(splittable.length)];
    final origNum = level.pieces[pIdx].number!;
    final half = origNum ~/ 2;
    final List<int> queue = (origNum >= 16 && attempt < maxTries * 2 ~/ 3)
        ? [origNum ~/ 4, origNum ~/ 4]
        : [half];

    final nextPieces = [for (final p in level.pieces) p.copyWith()];
    nextPieces[pIdx] = nextPieces[pIdx].copyWith(number: half);
    final nextWalls = Set<GridCell>.from(level.walls);
    if (anchor.$3) nextWalls.add(anchor.$1);

    final candidate = _copyLevel(
      level,
      timeSeconds: level.timeSeconds + 10,
      walls: nextWalls,
      dispensers: [
        ...level.dispensers,
        GenDispenser(
          col: anchor.$1.$1,
          row: anchor.$1.$2,
          dir: anchor.$2,
          queue: queue,
        ),
      ],
      pieces: nextPieces,
    );
    final res = LevelSolver.solve(
      candidate,
      maxVisited: maxVisited,
      timeoutMs: timeoutMs,
    );
    if (res.isSolved) return candidate;
  }
  return null;
}

/// 6. Swap Block: strictly non-restrictive one-time swap on a movable unlocked block.
GenLevel? _applySwap(GenLevel level, math.Random rng) {
  final eligible = [
    for (int i = 0; i < level.pieces.length; i++)
      if (!level.pieces[i].isDud &&
          !level.pieces[i].isFrozen &&
          !level.pieces[i].isLocked &&
          !level.pieces[i].isMystery &&
          !level.pieces[i].hasSwap &&
          level.pieces[i].movement.canMove)
        i,
  ];
  if (eligible.isEmpty) return null;
  eligible.shuffle(rng);
  final nextPieces = [for (final p in level.pieces) p.copyWith()];
  nextPieces[eligible.first] = nextPieces[eligible.first].copyWith(swapUses: 1);
  final candidate = _copyLevel(level, pieces: nextPieces);
  return LevelSolver.runStaticChecks(candidate) == null ? candidate : null;
}

/// 7. One-Way Arrow: constrains 1 movable block to a single direction, A*-verified.
GenLevel? _applyOneWayArrow(
  GenLevel level,
  math.Random rng, {
  required int maxTries,
  required int maxVisited,
  required int timeoutMs,
}) {
  final eligible = [
    for (int i = 0; i < level.pieces.length; i++)
      if (!level.pieces[i].isDud &&
          !level.pieces[i].isFrozen &&
          !level.pieces[i].isLocked &&
          !level.pieces[i].hasLimitedMoves &&
          level.pieces[i].movement.canMove &&
          !level.pieces[i].movement.isOneWay)
        i,
  ];
  if (eligible.isEmpty) return null;

  const oneWays = [
    MovementType.left,
    MovementType.right,
    MovementType.up,
    MovementType.down,
  ];

  for (int attempt = 0; attempt < maxTries; attempt++) {
    final idx = eligible[rng.nextInt(eligible.length)];
    final mv = oneWays[rng.nextInt(oneWays.length)];
    final nextPieces = [for (final p in level.pieces) p.copyWith()];
    nextPieces[idx] = nextPieces[idx].copyWith(movement: mv);

    final candidate = _copyLevel(level, pieces: nextPieces);
    final res = LevelSolver.solve(
      candidate,
      maxVisited: maxVisited,
      timeoutMs: timeoutMs,
    );
    if (res.isSolved) return candidate;
  }
  return null;
}

/// 8. Limited-Move / Fragile Block: sets `movesLeft: 2` or `3` on a movable piece, A*-verified.
GenLevel? _applyLimitedMove(
  GenLevel level,
  math.Random rng, {
  required int maxTries,
  required int maxVisited,
  required int timeoutMs,
}) {
  final eligible = [
    for (int i = 0; i < level.pieces.length; i++)
      if (!level.pieces[i].isDud &&
          !level.pieces[i].isFrozen &&
          !level.pieces[i].isLocked &&
          !level.pieces[i].hasLimitedMoves &&
          level.pieces[i].movement == MovementType.free)
        i,
  ];
  if (eligible.isEmpty) return null;

  for (int attempt = 0; attempt < maxTries; attempt++) {
    final idx = eligible[rng.nextInt(eligible.length)];
    final limit = attempt < maxTries ~/ 2 ? 2 : 3;
    final nextPieces = [for (final p in level.pieces) p.copyWith()];
    nextPieces[idx] = nextPieces[idx].copyWith(movesLeft: limit);

    final candidate = _copyLevel(level, pieces: nextPieces);
    final res = LevelSolver.solve(
      candidate,
      maxVisited: maxVisited,
      timeoutMs: timeoutMs,
    );
    if (res.isSolved) return candidate;
  }
  return null;
}

/// Classic helper for Special Lv 28 (adds Ice to a mid/high block if level has no Ice yet).
GenLevel? _applyClassicIce(
  GenLevel level,
  math.Random rng, {
  required int maxTries,
  required int maxVisited,
  required int timeoutMs,
}) {
  if (level.hasIce) return level;
  final eligible = [
    for (int i = 0; i < level.pieces.length; i++)
      if (!level.pieces[i].isDud &&
          !level.pieces[i].isFrozen &&
          (level.pieces[i].number ?? 0) >= 8)
        i,
  ]..sort((a, b) => (level.pieces[b].number ?? 0).compareTo(level.pieces[a].number ?? 0));
  if (eligible.isEmpty) return null;

  for (int attempt = 0; attempt < math.min(maxTries, eligible.length); attempt++) {
    final idx = eligible[attempt];
    final numVal = level.pieces[idx].number!;
    final target = math.max(4, numVal ~/ 2);
    final nextPieces = [for (final p in level.pieces) p.copyWith()];
    nextPieces[idx] = nextPieces[idx].copyWith(iceTarget: target);
    final candidate = _copyLevel(level, pieces: nextPieces);
    final res = LevelSolver.solve(
      candidate,
      maxVisited: maxVisited,
      timeoutMs: timeoutMs,
    );
    if (res.isSolved) return candidate;
  }
  return null;
}

/// Classic helper for Special Lv 28 / Remix Lv 143 (ensures level has at least 1 H/V Arrow block).
GenLevel? _applyClassicArrows(
  GenLevel level,
  math.Random rng, {
  required int maxTries,
  required int maxVisited,
  required int timeoutMs,
}) {
  if (level.hasArrows) return level;
  final eligible = [
    for (int i = 0; i < level.pieces.length; i++)
      if (!level.pieces[i].isDud &&
          !level.pieces[i].isFrozen &&
          level.pieces[i].movement == MovementType.free)
        i,
  ];
  if (eligible.isEmpty) return null;
  for (int attempt = 0; attempt < maxTries; attempt++) {
    final idx = eligible[rng.nextInt(eligible.length)];
    final mv = rng.nextBool() ? MovementType.horizontal : MovementType.vertical;
    final nextPieces = [for (final p in level.pieces) p.copyWith()];
    nextPieces[idx] = nextPieces[idx].copyWith(movement: mv);
    final candidate = _copyLevel(level, pieces: nextPieces);
    final res = LevelSolver.solve(
      candidate,
      maxVisited: maxVisited,
      timeoutMs: timeoutMs,
    );
    if (res.isSolved) return candidate;
  }
  return null;
}

GenLevel _copyLevel(
  GenLevel base, {
  int? timeSeconds,
  bool? isSpecial,
  Set<GridCell>? walls,
  Set<GridCell>? redWalls,
  Set<GridCell>? blueWalls,
  List<GenDispenser>? dispensers,
  List<GenPiece>? pieces,
}) {
  return GenLevel(
    number: base.number,
    cols: base.cols,
    rows: base.rows,
    timeSeconds: timeSeconds ?? base.timeSeconds,
    timerDisabled: base.timerDisabled,
    isSpecial: isSpecial ?? base.isSpecial,
    walls: walls ?? base.walls,
    redWalls: redWalls ?? base.redWalls,
    blueWalls: blueWalls ?? base.blueWalls,
    dispensers: dispensers ?? base.dispensers,
    pieces: pieces ?? base.pieces,
    bankId: base.bankId,
    levelLayoutId: base.levelLayoutId,
  );
}
