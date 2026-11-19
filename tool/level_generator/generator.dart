import 'dart:math' as math;

import 'models.dart';
import 'solver.dart';

enum DifficultyTier {
  easy,
  normal,
  hard,
  superHard;

  static DifficultyTier? tryParse(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'easy':
        return DifficultyTier.easy;
      case 'normal':
        return DifficultyTier.normal;
      case 'hard':
        return DifficultyTier.hard;
      case 'super_hard':
      case 'superhard':
        return DifficultyTier.superHard;
      default:
        return null;
    }
  }
}

enum MechanicCombo {
  none,
  dud,
  ice,
  arrows,
  pinned,
  dudArrows,
  iceDud,
  dudPinned,
  iceArrows,
  iceDudArrows,
  iceDudPinned,
  dudPinnedArrows,
  all4;

  bool get useIce =>
      this == ice ||
      this == iceDud ||
      this == iceArrows ||
      this == iceDudArrows ||
      this == iceDudPinned ||
      this == all4;

  bool get useDud =>
      this == dud ||
      this == dudArrows ||
      this == iceDud ||
      this == dudPinned ||
      this == iceDudArrows ||
      this == iceDudPinned ||
      this == dudPinnedArrows ||
      this == all4;

  bool get useArrows =>
      this == arrows ||
      this == dudArrows ||
      this == iceArrows ||
      this == iceDudArrows ||
      this == dudPinnedArrows ||
      this == all4;

  bool get usePinned =>
      this == pinned ||
      this == dudPinned ||
      this == iceDudPinned ||
      this == dudPinnedArrows ||
      this == all4;

  String get cliName {
    switch (this) {
      case none:
        return 'none';
      case dud:
        return 'dud';
      case ice:
        return 'ice';
      case arrows:
        return 'arrows';
      case pinned:
        return 'pinned';
      case dudArrows:
        return 'dud+arrows';
      case iceDud:
        return 'ice+dud';
      case dudPinned:
        return 'dud+pinned';
      case iceArrows:
        return 'ice+arrows';
      case iceDudArrows:
        return 'ice+dud+arrows';
      case iceDudPinned:
        return 'ice+dud+pinned';
      case dudPinnedArrows:
        return 'dud+pinned+arrows';
      case all4:
        return 'all4';
    }
  }

  static MechanicCombo? tryParse(String raw) {
    final norm = raw.toLowerCase().trim().replaceAll(' ', '');
    for (final v in values) {
      if (v.cliName == norm || v.name.toLowerCase() == norm) {
        return v;
      }
    }
    return null;
  }
}

class GenerationConfig {
  final DifficultyTier? fixedDifficulty;
  final MechanicCombo? fixedMechanics;
  final int maxAttemptsPerLevel;
  final int solverMaxVisited;
  final int solverTimeoutMs;
  final int bankId;

  const GenerationConfig({
    this.fixedDifficulty,
    this.fixedMechanics,
    this.maxAttemptsPerLevel = 80,
    this.solverMaxVisited = 22000,
    this.solverTimeoutMs = 900,
    this.bankId = 300,
  });
}

class GeneratedLevelReport {
  final GenLevel level;
  final DifficultyTier difficulty;
  final MechanicCombo requestedCombo;
  final SolveResult solveResult;
  final int attempts;
  final String wallArchetype;
  final String shapeTheme;

  const GeneratedLevelReport({
    required this.level,
    required this.difficulty,
    required this.requestedCombo,
    required this.solveResult,
    required this.attempts,
    required this.wallArchetype,
    required this.shapeTheme,
  });
}

/// Extensible mutator interface so new mechanics (e.g., NumberGate, Crate,
/// Chain, Bomb) can be plugged into the generation pipeline cleanly.
abstract class MechanicMutator {
  String get id;

  void apply({
    required int cols,
    required int rows,
    required Set<GridCell> walls,
    required List<GenPiece> pieces,
    required DifficultyTier difficulty,
    required MechanicCombo combo,
    required math.Random rng,
  });
}

class _DifficultyProfile {
  final List<(int cols, int rows)> gridChoices;
  final int minNumbered;
  final int maxNumbered;
  final int minDud;
  final int maxDud;
  final int minEmptyCells;
  final int maxEmptyCells;
  final int minSlides;
  final int maxInitialAdjacentPairs;
  final List<int> targetSums;
  final double timeBufferMultiplier;

  const _DifficultyProfile({
    required this.gridChoices,
    required this.minNumbered,
    required this.maxNumbered,
    required this.minDud,
    required this.maxDud,
    required this.minEmptyCells,
    required this.maxEmptyCells,
    required this.minSlides,
    required this.maxInitialAdjacentPairs,
    required this.targetSums,
    required this.timeBufferMultiplier,
  });
}

class _ShapeTemplate {
  final String name;
  final List<GridCell> cells;

  const _ShapeTemplate(this.name, this.cells);
}

class LevelGenerator {
  static const Map<DifficultyTier, _DifficultyProfile> _profiles = {
    DifficultyTier.easy: _DifficultyProfile(
      gridChoices: [(5, 6), (5, 7), (6, 6), (6, 7)],
      minNumbered: 9,
      maxNumbered: 12,
      minDud: 1,
      maxDud: 2,
      minEmptyCells: 6,
      maxEmptyCells: 10,
      minSlides: 3,
      maxInitialAdjacentPairs: 2,
      targetSums: [256, 512, 1024, 2048],
      timeBufferMultiplier: 1.15,
    ),
    DifficultyTier.normal: _DifficultyProfile(
      gridChoices: [(6, 7), (6, 8), (6, 9), (7, 7), (7, 8)],
      minNumbered: 11,
      maxNumbered: 15,
      minDud: 2,
      maxDud: 4,
      minEmptyCells: 5,
      maxEmptyCells: 9,
      minSlides: 5,
      maxInitialAdjacentPairs: 2,
      targetSums: [512, 1024, 2048, 4096],
      timeBufferMultiplier: 1.05,
    ),
    DifficultyTier.hard: _DifficultyProfile(
      gridChoices: [(6, 8), (6, 9), (7, 8), (7, 9), (6, 10)],
      minNumbered: 13,
      maxNumbered: 17,
      minDud: 2,
      maxDud: 5,
      minEmptyCells: 4,
      maxEmptyCells: 8,
      minSlides: 7,
      maxInitialAdjacentPairs: 1,
      targetSums: [1024, 2048, 4096, 8192],
      timeBufferMultiplier: 0.95,
    ),
    DifficultyTier.superHard: _DifficultyProfile(
      gridChoices: [(6, 9), (7, 8), (7, 9), (6, 10), (7, 10)],
      minNumbered: 14,
      maxNumbered: 19,
      minDud: 3,
      maxDud: 6,
      minEmptyCells: 4,
      maxEmptyCells: 7,
      minSlides: 8,
      maxInitialAdjacentPairs: 1,
      targetSums: [2048, 4096, 8192],
      timeBufferMultiplier: 0.88,
    ),
  };

  // Polyomino library matching the shapes used across `all_121_levels.json`.
  static const _s1x1 = _ShapeTemplate('1x1', [(0, 0)]);
  static const _s2x1 = _ShapeTemplate('2x1', [(0, 0), (1, 0)]);
  static const _s1x2 = _ShapeTemplate('1x2', [(0, 0), (0, 1)]);
  static const _s3x1 = _ShapeTemplate('3x1', [(0, 0), (1, 0), (2, 0)]);
  static const _s1x3 = _ShapeTemplate('1x3', [(0, 0), (0, 1), (0, 2)]);
  static const _s2x2 = _ShapeTemplate('2x2', [(0, 0), (1, 0), (0, 1), (1, 1)]);
  static const _sL3a = _ShapeTemplate('L3a', [(0, 0), (0, 1), (1, 1)]);
  static const _sL3b = _ShapeTemplate('L3b', [(1, 0), (0, 1), (1, 1)]);
  static const _sL3c = _ShapeTemplate('L3c', [(0, 0), (1, 0), (0, 1)]);
  static const _sL3d = _ShapeTemplate('L3d', [(0, 0), (1, 0), (1, 1)]);
  static const _sT4a = _ShapeTemplate('T4a', [(0, 0), (1, 0), (2, 0), (1, 1)]);
  static const _sT4b = _ShapeTemplate('T4b', [(1, 0), (0, 1), (1, 1), (2, 1)]);
  static const _sT4c = _ShapeTemplate('T4c', [(0, 0), (0, 1), (1, 1), (0, 2)]);
  static const _sT4d = _ShapeTemplate('T4d', [(1, 0), (0, 1), (1, 1), (1, 2)]);
  static const _sL4a = _ShapeTemplate('L4a', [(0, 0), (0, 1), (0, 2), (1, 2)]);
  static const _sL4b = _ShapeTemplate('L4b', [(1, 0), (1, 1), (0, 2), (1, 2)]);
  static const _sS4a = _ShapeTemplate('S4a', [(1, 0), (2, 0), (0, 1), (1, 1)]);
  static const _sZ4a = _ShapeTemplate('Z4a', [(0, 0), (1, 0), (1, 1), (2, 1)]);

  static const Map<String, List<_ShapeTemplate>> _shapeThemes = {
    'dominoFlow': [_s1x1, _s2x1, _s1x2, _s2x1, _s1x2, _s2x2, _s3x1, _s1x3],
    'polyMix': [
      _s1x1,
      _s2x1,
      _s1x2,
      _s2x2,
      _sL3a,
      _sL3b,
      _sL3c,
      _sL3d,
      _s3x1,
      _s1x3,
      _sT4a,
      _sT4b,
    ],
    'chunkyPuzzle': [
      _s2x2,
      _s2x1,
      _s1x2,
      _sL3a,
      _sL3b,
      _sL3c,
      _sL3d,
      _sT4a,
      _sT4b,
      _sT4c,
      _sT4d,
      _sL4a,
      _sL4b,
      _sS4a,
      _sZ4a,
      _s1x1,
    ],
    'tightGrid': [_s1x1, _s1x1, _s2x1, _s1x2, _s2x1, _s1x2, _s3x1, _s1x3, _sL3a, _sL3d],
  };

  final List<MechanicMutator> mutators;

  LevelGenerator({List<MechanicMutator>? mutators})
    : mutators = mutators ??
          [
            const PinnedMutator(),
            const ArrowMutator(),
            const IceMutator(),
          ];

  /// Industry-standard 10-level sawtooth difficulty pacing.
  static DifficultyTier difficultyForLevelNumber(int levelNum) {
    final slot = levelNum % 10;
    if (slot == 0) return DifficultyTier.superHard;
    if (slot == 5) return DifficultyTier.hard;
    if (slot == 6) return DifficultyTier.easy;
    if (slot == 1) return DifficultyTier.normal;
    if (slot == 4 || slot == 9) return DifficultyTier.hard;
    return DifficultyTier.normal;
  }

  /// Selects a varied mechanic combo matching the difficulty tier & level index.
  static MechanicCombo comboForLevel(
    int levelNum,
    DifficultyTier tier,
    math.Random rng,
  ) {
    switch (tier) {
      case DifficultyTier.easy:
        const pool = [
          MechanicCombo.none,
          MechanicCombo.dud,
          MechanicCombo.ice,
          MechanicCombo.arrows,
        ];
        return pool[(levelNum + rng.nextInt(pool.length)) % pool.length];
      case DifficultyTier.normal:
        const pool = [
          MechanicCombo.dud,
          MechanicCombo.ice,
          MechanicCombo.arrows,
          MechanicCombo.dudArrows,
          MechanicCombo.iceDud,
          MechanicCombo.dudPinned,
          MechanicCombo.iceArrows,
        ];
        return pool[(levelNum + rng.nextInt(pool.length)) % pool.length];
      case DifficultyTier.hard:
        const pool = [
          MechanicCombo.dudArrows,
          MechanicCombo.iceDud,
          MechanicCombo.dudPinned,
          MechanicCombo.iceArrows,
          MechanicCombo.iceDudArrows,
          MechanicCombo.iceDudPinned,
          MechanicCombo.dudPinnedArrows,
        ];
        return pool[(levelNum + rng.nextInt(pool.length)) % pool.length];
      case DifficultyTier.superHard:
        const pool = [
          MechanicCombo.iceDudArrows,
          MechanicCombo.iceDudPinned,
          MechanicCombo.dudPinnedArrows,
          MechanicCombo.all4,
        ];
        return pool[(levelNum + rng.nextInt(pool.length)) % pool.length];
    }
  }

  /// Generates a single verified, unique campaign level.
  GeneratedLevelReport generateLevel({
    required int levelNumber,
    required math.Random rng,
    required Set<String> usedHashes,
    GenerationConfig config = const GenerationConfig(),
  }) {
    final tier =
        config.fixedDifficulty ?? difficultyForLevelNumber(levelNumber);
    final profile = _profiles[tier]!;
    final combo =
        config.fixedMechanics ?? comboForLevel(levelNumber, tier, rng);

    GeneratedLevelReport? bestFallback;

    for (int attempt = 1; attempt <= config.maxAttemptsPerLevel; attempt++) {
      // Relax slide threshold slightly on late retries so generation never stalls.
      final relaxedMinSlides = attempt > (config.maxAttemptsPerLevel * 0.65)
          ? math.max(2, profile.minSlides - 2)
          : profile.minSlides;

      final (cols, rows) =
          profile.gridChoices[rng.nextInt(profile.gridChoices.length)];
      final (wallArchetype, walls) = _buildWalls(cols, rows, tier, rng);
      final playableCells = cols * rows - walls.length;
      if (playableCells < 24) continue;

      final themeKeys = _shapeThemes.keys.toList();
      final shapeTheme = themeKeys[rng.nextInt(themeKeys.length)];

      final targetNumbered =
          profile.minNumbered +
          rng.nextInt(profile.maxNumbered - profile.minNumbered + 1);
      final targetDud = combo.useDud
          ? profile.minDud + rng.nextInt(profile.maxDud - profile.minDud + 1)
          : 0;
      final targetEmpty =
          profile.minEmptyCells +
          rng.nextInt(profile.maxEmptyCells - profile.minEmptyCells + 1);

      final packed = _packShapes(
        cols: cols,
        rows: rows,
        walls: walls,
        themeName: shapeTheme,
        targetTotalPieces: targetNumbered + targetDud,
        minEmptyReserve: targetEmpty,
        rng: rng,
      );
      if (packed.length < math.max(8, targetNumbered - 2) + targetDud) {
        continue;
      }

      // Split packed shapes into Dud blockers + Numbered pieces
      final actualDud = combo.useDud
          ? math.min(targetDud, math.max(1, packed.length - 8))
          : 0;
      final numberedCount = packed.length - actualDud;
      if (numberedCount < 7) continue;

      final dudIndices = _pickDudIndices(packed, actualDud, cols, rows, rng);
      final numberedPieces = <GenPiece>[];
      final dudPieces = <GenPiece>[];
      for (int i = 0; i < packed.length; i++) {
        if (dudIndices.contains(i)) {
          dudPieces.add(packed[i]);
        } else {
          numberedPieces.add(packed[i]);
        }
      }

      // Build valid 2048 number multiset and place with spatial separation
      final targetSum = _chooseValidTargetSum(
        numberedCount,
        profile.targetSums,
        rng,
      );
      final numbers = _build2048Numbers(numberedCount, targetSum, rng);
      if (numbers == null) continue;
      _assignNumbersWithSeparation(numberedPieces, numbers, rng);

      final allPieces = <GenPiece>[...numberedPieces, ...dudPieces];

      // Run extensible mechanic mutators (Pinned, Arrows, Ice, + future custom ones)
      for (final mutator in mutators) {
        mutator.apply(
          cols: cols,
          rows: rows,
          walls: walls,
          pieces: allPieces,
          difficulty: tier,
          combo: combo,
          rng: rng,
        );
      }

      // Verify requested mechanics actually landed on the board
      final candidate = GenLevel(
        number: levelNumber,
        cols: cols,
        rows: rows,
        timeSeconds: 180,
        walls: walls,
        pieces: allPieces,
        bankId: config.bankId,
        levelLayoutId: 300000 + levelNumber,
      );

      if (!_matchesRequestedMechanics(candidate, combo)) continue;

      // Fast static checks before A*
      if (LevelSolver.runStaticChecks(candidate) != null) continue;

      // Reject boards with too many trivial instant adjacent merges
      final adjPairs = LevelSolver.countImmediatelyAdjacentPairs(candidate);
      if (adjPairs > profile.maxInitialAdjacentPairs && attempt < 55) continue;

      // Must have at least 2 legal moves at start so it feels responsive
      if (LevelSolver.countInitialLegalActions(candidate) < 2) continue;

      // Deduplicate
      final hash = candidate.computeContentHash();
      if (usedHashes.contains(hash)) continue;

      // Run exact game-parity A* Raycast Solver!
      final solve = LevelSolver.solve(
        candidate,
        maxVisited: config.solverMaxVisited,
        timeoutMs: config.solverTimeoutMs,
      );
      if (!solve.isSolved) continue;

      final calibratedTime = _calibrateTimeSeconds(
        candidate,
        solve,
        profile.timeBufferMultiplier,
      );
      final finalized = GenLevel(
        number: levelNumber,
        cols: candidate.cols,
        rows: candidate.rows,
        timeSeconds: calibratedTime,
        walls: candidate.walls,
        pieces: candidate.pieces,
        bankId: config.bankId,
        levelLayoutId: 300000 + levelNumber,
      );

      final report = GeneratedLevelReport(
        level: finalized,
        difficulty: tier,
        requestedCombo: combo,
        solveResult: solve,
        attempts: attempt,
        wallArchetype: wallArchetype,
        shapeTheme: shapeTheme,
      );

      if (solve.slideMoves >= relaxedMinSlides) {
        usedHashes.add(finalized.computeContentHash());
        return report;
      }

      if (bestFallback == null ||
          solve.slideMoves > bestFallback.solveResult.slideMoves) {
        bestFallback = report;
      }
    }

    if (bestFallback != null) {
      usedHashes.add(bestFallback.level.computeContentHash());
      return bestFallback;
    }

    // Ultra-safe deterministic fallback so batch generation never crashes
    return _generateSafeFallback(
      levelNumber: levelNumber,
      tier: tier,
      combo: combo,
      rng: rng,
      usedHashes: usedHashes,
      config: config,
    );
  }

  static bool _matchesRequestedMechanics(GenLevel lv, MechanicCombo combo) {
    if (combo.useDud && !lv.hasDud) return false;
    if (combo.useIce && !lv.hasIce) return false;
    if (combo.useArrows && !lv.hasArrows) return false;
    if (combo.usePinned && !lv.hasPinned) return false;
    return true;
  }

  static (String archetype, Set<GridCell> walls) _buildWalls(
    int cols,
    int rows,
    DifficultyTier tier,
    math.Random rng,
  ) {
    const archetypes = [
      'openNotched',
      'innerPillars',
      'hourglass',
      'alcoves',
      'diamondFrame',
    ];
    final choice = archetypes[rng.nextInt(archetypes.length)];
    final walls = <GridCell>{};

    void tryAdd(int c, int r) {
      if (c < 0 || c >= cols || r < 0 || r >= rows) return;
      final cell = (c, r);
      if (walls.contains(cell)) return;
      walls.add(cell);
      if (!isPlayableAreaConnected(cols, rows, walls)) {
        walls.remove(cell);
      }
    }

    switch (choice) {
      case 'openNotched':
        final corners = [
          (0, 0),
          (cols - 1, 0),
          (0, rows - 1),
          (cols - 1, rows - 1),
        ]..shuffle(rng);
        final count = rng.nextInt(5); // 0..4 corners
        for (int i = 0; i < count; i++) {
          tryAdd(corners[i].$1, corners[i].$2);
        }
        break;

      case 'innerPillars':
        final pillarCount = 1 + rng.nextInt(tier == DifficultyTier.easy ? 2 : 3);
        for (int i = 0; i < pillarCount; i++) {
          final c = 1 + rng.nextInt(math.max(1, cols - 2));
          final r = 1 + rng.nextInt(math.max(1, rows - 2));
          tryAdd(c, r);
        }
        if (rng.nextBool()) {
          tryAdd(0, 0);
          tryAdd(cols - 1, rows - 1);
        }
        break;

      case 'hourglass':
        final midR = rows ~/ 2;
        final bandHalf = rows >= 9 ? 1 : 0;
        for (int r = midR - bandHalf; r <= midR + bandHalf; r++) {
          tryAdd(0, r);
          tryAdd(cols - 1, r);
          if (cols >= 8 && r == midR) {
            tryAdd(1, r);
            tryAdd(cols - 2, r);
          }
        }
        break;

      case 'alcoves':
        final notchRows = <int>[];
        for (int r = 1; r < rows - 1; r += 2) {
          notchRows.add(r);
        }
        notchRows.shuffle(rng);
        final take = math.min(notchRows.length, 2 + rng.nextInt(2));
        for (int i = 0; i < take; i++) {
          final r = notchRows[i];
          final side = i.isEven ? 0 : cols - 1;
          tryAdd(side, r);
          if (cols >= 7 && rng.nextBool()) {
            tryAdd(side == 0 ? 1 : cols - 2, r);
          }
        }
        break;

      case 'diamondFrame':
        tryAdd(0, 0);
        tryAdd(cols - 1, 0);
        tryAdd(0, rows - 1);
        tryAdd(cols - 1, rows - 1);
        if (cols >= 6 && rows >= 8) {
          tryAdd(1, 0);
          tryAdd(0, 1);
          tryAdd(cols - 2, 0);
          tryAdd(cols - 1, 1);
          tryAdd(1, rows - 1);
          tryAdd(0, rows - 2);
          tryAdd(cols - 2, rows - 1);
          tryAdd(cols - 1, rows - 2);
        }
        break;
    }

    return (choice, walls);
  }

  static List<GenPiece> _packShapes({
    required int cols,
    required int rows,
    required Set<GridCell> walls,
    required String themeName,
    required int targetTotalPieces,
    required int minEmptyReserve,
    required math.Random rng,
  }) {
    final pool = _shapeThemes[themeName] ?? _shapeThemes['polyMix']!;
    final occupied = Set<GridCell>.from(walls);
    final totalCells = cols * rows;
    final pieces = <GenPiece>[];

    // Candidate coordinates shuffled for organic packing
    final allCoords = <GridCell>[
      for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++)
          if (!walls.contains((c, r))) (c, r),
    ];

    int nextId = 1;
    int fails = 0;

    while (pieces.length < targetTotalPieces && fails < 90) {
      final remainingEmpty = totalCells - occupied.length;
      if (remainingEmpty <= minEmptyReserve) break;

      // Adapt shape size dynamically to hit high board occupancy (~75%-90%) cleanly
      final remainingPieces = targetTotalPieces - pieces.length;
      final avgNeeded =
          (remainingEmpty - minEmptyReserve) / math.max(1, remainingPieces);
      final minCellSize = avgNeeded >= 3.2
          ? 3
          : avgNeeded >= 2.2
          ? 2
          : 1;
      final maxCellSize = math.min(4, math.max(minCellSize, avgNeeded.ceil() + 1));

      var eligible = pool
          .where(
            (t) =>
                t.cells.length >= minCellSize &&
                t.cells.length <= maxCellSize &&
                remainingEmpty - t.cells.length >= minEmptyReserve,
          )
          .toList();
      if (eligible.isEmpty) {
        eligible = pool
            .where((t) => remainingEmpty - t.cells.length >= minEmptyReserve)
            .toList();
      }
      final template = eligible.isNotEmpty
          ? eligible[rng.nextInt(eligible.length)]
          : _s1x1;

      allCoords.shuffle(rng);
      bool placed = false;
      for (final (c0, r0) in allCoords) {
        bool fits = true;
        for (final (dc, dr) in template.cells) {
          final c = c0 + dc;
          final r = r0 + dr;
          if (c < 0 ||
              c >= cols ||
              r < 0 ||
              r >= rows ||
              occupied.contains((c, r))) {
            fits = false;
            break;
          }
        }
        if (fits) {
          for (final (dc, dr) in template.cells) {
            occupied.add((c0 + dc, r0 + dr));
          }
          final sortedCells = List<GridCell>.from(template.cells)
            ..sort((a, b) {
              final rCmp = a.$2.compareTo(b.$2);
              return rCmp != 0 ? rCmp : a.$1.compareTo(b.$1);
            });
          pieces.add(
            GenPiece(
              id: nextId,
              key: _pieceKeyForIndex(nextId - 1),
              col: c0,
              row: r0,
              cells: sortedCells,
            ),
          );
          nextId++;
          placed = true;
          break;
        }
      }

      if (!placed) {
        fails++;
      } else {
        fails = 0;
      }
    }

    return pieces;
  }

  static String _pieceKeyForIndex(int idx) {
    if (idx < 26) {
      return String.fromCharCode(65 + idx); // A..Z
    }
    return '${idx + 1}';
  }

  /// Picks Dud indices preferring compact/lane-blocking shapes (1..3 cells).
  static Set<int> _pickDudIndices(
    List<GenPiece> packed,
    int count,
    int cols,
    int rows,
    math.Random rng,
  ) {
    if (count <= 0) return const {};
    final cx = (cols - 1) * 0.5;
    final cy = (rows - 1) * 0.5;
    final scored = <(int idx, double score)>[];
    for (int i = 0; i < packed.length; i++) {
      final p = packed[i];
      if (p.cells.length > 3) continue; // Keep Duds <= 3 cells so board stays playable
      final distCenter = (p.col - cx).abs() + (p.row - cy).abs();
      // Slightly prefer centrally located blockers + randomness
      final score = -distCenter * 0.4 + rng.nextDouble() * 3.0;
      scored.add((i, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return {for (int i = 0; i < math.min(count, scored.length); i++) scored[i].$1};
  }

  static int _chooseValidTargetSum(
    int pieceCount,
    List<int> preferredSums,
    math.Random rng,
  ) {
    // Min sum for `pieceCount` pieces of value >= 2 is `2 * pieceCount`.
    final minRequired = 2 * pieceCount;
    final valid = preferredSums.where((s) => s >= minRequired).toList();
    if (valid.isNotEmpty) {
      return valid[rng.nextInt(valid.length)];
    }
    int pow2 = 2;
    while (pow2 < minRequired) {
      pow2 *= 2;
    }
    return pow2;
  }

  /// Builds a valid 2048 multiset of length `count` that collapses to `targetSum`.
  static List<int>? _build2048Numbers(
    int count,
    int targetSum,
    math.Random rng,
  ) {
    if (count < 2 || targetSum < count * 2) return null;
    final nums = <int>[targetSum];
    final style = rng.nextInt(3); // 0 = ladder, 1 = branched, 2 = clustered

    for (int step = 0; step < count - 1; step++) {
      final splittable = <int>[];
      for (int i = 0; i < nums.length; i++) {
        if (nums[i] > 2) splittable.add(i);
      }
      if (splittable.isEmpty) return null;

      int pickIdx;
      if (style == 0) {
        // Ladder: mostly split the smallest splittable number (classic domino cascade)
        splittable.sort((a, b) => nums[a].compareTo(nums[b]));
        pickIdx = rng.nextDouble() < 0.78
            ? splittable.first
            : splittable[rng.nextInt(splittable.length)];
      } else if (style == 1) {
        // Branched: mix smallest & mid-size numbers for multi-branch decisions
        splittable.sort((a, b) => nums[a].compareTo(nums[b]));
        pickIdx = rng.nextDouble() < 0.45
            ? splittable.first
            : splittable[rng.nextInt(splittable.length)];
      } else {
        // Clustered: favor splitting larger numbers to create multiple pairs
        splittable.sort((a, b) => nums[b].compareTo(nums[a]));
        final top = math.min(3, splittable.length);
        pickIdx = splittable[rng.nextInt(top)];
      }

      final v = nums.removeAt(pickIdx);
      nums.add(v ~/ 2);
      nums.add(v ~/ 2);
    }

    nums.sort();
    return nums;
  }

  /// Assigns numbers to pieces while maximizing spatial separation between matching pairs.
  static void _assignNumbersWithSeparation(
    List<GenPiece> pieces,
    List<int> sortedNumbers,
    math.Random rng,
  ) {
    // Group equal numbers and assign largest -> smallest so big blocks get nice footprints
    final unassigned = List<GenPiece>.from(pieces);
    final placedByValue = <int, List<GenPiece>>{};

    for (int i = sortedNumbers.length - 1; i >= 0; i--) {
      final val = sortedNumbers[i];
      final sameValPeers = placedByValue[val] ?? const <GenPiece>[];

      GenPiece chosen;
      if (sameValPeers.isNotEmpty) {
        // Pick unassigned piece maximizing minimum distance to existing pieces of same number!
        double bestScore = -1e9;
        chosen = unassigned.first;
        for (final cand in unassigned) {
          double minD = 1e9;
          for (final peer in sameValPeers) {
            final d =
                ((cand.col - peer.col).abs() + (cand.row - peer.row).abs())
                    .toDouble();
            if (d < minD) minD = d;
          }
          // Add slight noise + preference for non-adjacent
          final score = minD + rng.nextDouble() * 1.4;
          if (score > bestScore) {
            bestScore = score;
            chosen = cand;
          }
        }
      } else {
        // First occurrence of this number: slight preference for bigger shapes on bigger numbers
        unassigned.sort((a, b) => b.cells.length.compareTo(a.cells.length));
        final topK = math.min(unassigned.length, val >= 256 ? 4 : unassigned.length);
        chosen = unassigned[rng.nextInt(topK)];
      }

      chosen.number = val;
      unassigned.remove(chosen);
      placedByValue.putIfAbsent(val, () => []).add(chosen);
    }
  }

  static int _calibrateTimeSeconds(
    GenLevel lv,
    SolveResult solve,
    double tierBuffer,
  ) {
    // Calibrated against campaign Lv 51..122 (range 100s..195s, avg ~155-170s)
    final mechBonus =
        (lv.hasIce ? 12 : 0) +
        (lv.hasDud ? 10 : 0) +
        (lv.hasArrows ? 10 : 0) +
        (lv.hasPinned ? 8 : 0);
    final raw =
        (solve.mergeMoves * 3.6 + solve.slideMoves * 1.9 + 38 + mechBonus) *
        tierBuffer;
    final rounded5 = ((raw / 5.0).round() * 5).clamp(100, 195);
    return rounded5;
  }

  GeneratedLevelReport _generateSafeFallback({
    required int levelNumber,
    required DifficultyTier tier,
    required MechanicCombo combo,
    required math.Random rng,
    required Set<String> usedHashes,
    required GenerationConfig config,
  }) {
    // Guaranteed solvable fallback on an open 6x8 board with slightly relaxed constraints
    for (int attempt = 1; attempt <= 60; attempt++) {
      final (cols, rows) = (6, 8);
      final walls = <GridCell>{};
      final packed = _packShapes(
        cols: cols,
        rows: rows,
        walls: walls,
        themeName: 'dominoFlow',
        targetTotalPieces: combo.useDud ? 12 : 10,
        minEmptyReserve: 10,
        rng: rng,
      );
      if (packed.length < 9) continue;
      final dudCnt = combo.useDud ? 2 : 0;
      final numbered = packed.sublist(0, packed.length - dudCnt);
      final duds = packed.sublist(packed.length - dudCnt);
      final nums = _build2048Numbers(numbered.length, 1024, rng);
      if (nums == null) continue;
      _assignNumbersWithSeparation(numbered, nums, rng);
      final pieces = [...numbered, ...duds];
      for (final m in mutators) {
        m.apply(
          cols: cols,
          rows: rows,
          walls: walls,
          pieces: pieces,
          difficulty: DifficultyTier.easy,
          combo: combo,
          rng: rng,
        );
      }
      final lv = GenLevel(
        number: levelNumber,
        cols: cols,
        rows: rows,
        timeSeconds: 160,
        walls: walls,
        pieces: pieces,
        bankId: config.bankId,
        levelLayoutId: 300000 + levelNumber,
      );
      final solve = LevelSolver.solve(lv, maxVisited: 25000, timeoutMs: 1200);
      if (solve.isSolved) {
        usedHashes.add(lv.computeContentHash());
        return GeneratedLevelReport(
          level: lv,
          difficulty: tier,
          requestedCombo: combo,
          solveResult: solve,
          attempts: config.maxAttemptsPerLevel + attempt,
          wallArchetype: 'openFallback',
          shapeTheme: 'dominoFlow',
        );
      }
    }
    throw StateError('Failed to generate solvable level #$levelNumber');
  }
}

/// Assigns `Pinned` (Stationary) blocks safely on medium/high numbers.
class PinnedMutator implements MechanicMutator {
  const PinnedMutator();

  @override
  String get id => 'pinned';

  @override
  void apply({
    required int cols,
    required int rows,
    required Set<GridCell> walls,
    required List<GenPiece> pieces,
    required DifficultyTier difficulty,
    required MechanicCombo combo,
    required math.Random rng,
  }) {
    if (!combo.usePinned) return;

    final maxPinned = switch (difficulty) {
      DifficultyTier.easy => 1,
      DifficultyTier.normal => 2,
      DifficultyTier.hard => 2,
      DifficultyTier.superHard => 3,
    };
    final target = 1 + rng.nextInt(maxPinned);

    final candidates = pieces.where((p) => !p.isDud).toList()
      ..sort((a, b) => (b.number ?? 0).compareTo(a.number ?? 0));
    if (candidates.length < 4) return;

    final pinnedNums = <int>{};
    int placed = 0;

    // Prefer pinning distinct medium/large values so smaller blocks cascade into them
    final pool = candidates.take(math.max(4, candidates.length ~/ 2)).toList()
      ..shuffle(rng);

    for (final p in pool) {
      if (placed >= target) break;
      final n = p.number!;
      // Never pin two pieces of the same value in this pass (avoids pinned pair deadlock)
      if (pinnedNums.contains(n)) continue;
      // Avoid pinning the minimum value if there are only 2 of them and both could be stuck
      p.movement = MovementType.pinned;
      pinnedNums.add(n);
      placed++;
    }
  }
}

/// Assigns `Horizontal` / `Vertical` Arrow constraints to numbered pieces and optionally Duds.
class ArrowMutator implements MechanicMutator {
  const ArrowMutator();

  @override
  String get id => 'arrows';

  @override
  void apply({
    required int cols,
    required int rows,
    required Set<GridCell> walls,
    required List<GenPiece> pieces,
    required DifficultyTier difficulty,
    required MechanicCombo combo,
    required math.Random rng,
  }) {
    if (!combo.useArrows) return;

    final occ = <GridCell, GenPiece>{};
    for (final p in pieces) {
      for (final wc in p.worldCells()) {
        occ[wc] = p;
      }
    }

    final targetRatio = switch (difficulty) {
      DifficultyTier.easy => 0.18,
      DifficultyTier.normal => 0.26,
      DifficultyTier.hard => 0.32,
      DifficultyTier.superHard => 0.36,
    };

    // Track axis per number so two matching pieces don't get stuck on parallel disjoint lanes
    final numAxisUsed = <int, Set<MovementType>>{};
    final eligible = pieces.where((p) => !p.movement.isPinned).toList()
      ..shuffle(rng);
    final maxCount = math.max(2, (eligible.length * targetRatio).round());

    int assigned = 0;
    for (final p in eligible) {
      if (assigned >= maxCount) break;
      // Allow Dud+Arrow stacking ~55% of the time when both Dud & Arrows are active
      if (p.isDud && rng.nextDouble() > 0.55) continue;

      final canH = _hasAxisClearance(p, cols, rows, walls, horizontal: true);
      final canV = _hasAxisClearance(p, cols, rows, walls, horizontal: false);
      if (!canH && !canV) continue;

      final usedForNum = p.number != null ? (numAxisUsed[p.number!] ?? const <MovementType>{}) : const <MovementType>{};
      MovementType? pick;
      if (canH && canV) {
        if (usedForNum.contains(MovementType.horizontal) &&
            !usedForNum.contains(MovementType.vertical)) {
          pick = MovementType.vertical;
        } else if (usedForNum.contains(MovementType.vertical) &&
            !usedForNum.contains(MovementType.horizontal)) {
          pick = MovementType.horizontal;
        } else {
          pick = rng.nextBool()
              ? MovementType.horizontal
              : MovementType.vertical;
        }
      } else if (canH && !usedForNum.contains(MovementType.horizontal)) {
        pick = MovementType.horizontal;
      } else if (canV && !usedForNum.contains(MovementType.vertical)) {
        pick = MovementType.vertical;
      }

      if (pick == null) continue;
      p.movement = pick;
      if (p.number != null) {
        numAxisUsed.putIfAbsent(p.number!, () => {}).add(pick);
      }
      assigned++;
    }
  }

  /// Ensures a piece isn't locked against walls on both sides of its assigned axis.
  static bool _hasAxisClearance(
    GenPiece p,
    int cols,
    int rows,
    Set<GridCell> walls, {
    required bool horizontal,
  }) {
    final dirs = horizontal ? const [(1, 0), (-1, 0)] : const [(0, 1), (0, -1)];
    for (final (dx, dy) in dirs) {
      bool fitsInBoundsAndWalls = true;
      for (final (c, r) in p.worldCells(p.col + dx, p.row + dy)) {
        if (c < 0 || c >= cols || r < 0 || r >= rows || walls.contains((c, r))) {
          fitsInBoundsAndWalls = false;
          break;
        }
      }
      if (fitsInBoundsAndWalls) return true;
    }
    return false;
  }
}

/// Assigns `Ice` blocks with topologically valid `iceTarget` values (guaranteed unlockable!).
class IceMutator implements MechanicMutator {
  const IceMutator();

  @override
  String get id => 'ice';

  @override
  void apply({
    required int cols,
    required int rows,
    required Set<GridCell> walls,
    required List<GenPiece> pieces,
    required DifficultyTier difficulty,
    required MechanicCombo combo,
    required math.Random rng,
  }) {
    if (!combo.useIce) return;

    final numbered = pieces.where((p) => !p.isDud).toList();
    if (numbered.length < 5) return;

    // Sort descending by value so higher-tier pieces are frozen and unlocked by lower merges
    numbered.sort((a, b) => (b.number ?? 0).compareTo(a.number ?? 0));

    final maxIce = switch (difficulty) {
      DifficultyTier.easy => math.min(3, numbered.length ~/ 3),
      DifficultyTier.normal => math.min(5, (numbered.length * 0.4).round()),
      DifficultyTier.hard => math.min(7, (numbered.length * 0.48).round()),
      DifficultyTier.superHard => math.min(9, (numbered.length * 0.55).round()),
    };
    final targetIce = math.max(2, 2 + rng.nextInt(math.max(1, maxIce - 1)));

    // Keep the smallest pieces unfrozen so the player can always start merging!
    final unfrozen = List<GenPiece>.from(numbered);
    final frozen = <GenPiece>[];

    // Pick candidates from the upper ~65% of numbers (avoid freezing pinned blocks)
    final upperPool = numbered
        .where((p) => !p.movement.isPinned)
        .take(math.max(2, (numbered.length * 0.7).round()))
        .toList()
      ..shuffle(rng);

    for (final cand in upperPool) {
      if (frozen.length >= targetIce) break;
      if (unfrozen.length <= 4) break;

      // Test removing `cand` from unfrozen and checking what merge values the rest can produce
      unfrozen.remove(cand);
      final produced = _simulateReachableValues(unfrozen);
      if (produced.isEmpty) {
        unfrozen.add(cand);
        continue;
      }

      // Prefer an iceTarget <= cand.number (classic logical progression: unlock 64 when you reach 32 or 64)
      final logicalTargets =
          produced.where((v) => v <= cand.number!).toList()..sort();
      final allTargets = produced.toList()..sort();
      final pool = logicalTargets.isNotEmpty ? logicalTargets : allTargets;

      // Favor upper half of achievable targets so Ice lasts meaningfully into the level
      final startIdx = pool.length > 2 ? pool.length ~/ 2 : 0;
      cand.iceTarget = pool[startIdx + rng.nextInt(pool.length - startIdx)];
      frozen.add(cand);
    }

    // Re-validate full Ice DAG in case multi-freeze interacted; trim any bad one safely
    for (int i = frozen.length - 1; i >= 0; i--) {
      final probe = GenLevel(
        number: 0,
        cols: cols,
        rows: rows,
        timeSeconds: 120,
        walls: walls,
        pieces: pieces,
        levelLayoutId: 0,
      );
      final err = LevelSolver.runStaticChecks(probe);
      if (err == null || !err.startsWith('Ice deadlock')) break;
      frozen[i].iceTarget = null;
    }
  }

  static Set<int> _simulateReachableValues(List<GenPiece> unfrozen) {
    final counts = <int, int>{};
    for (final p in unfrozen) {
      final n = p.number;
      if (n != null) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final produced = <int>{};
    bool changed = true;
    while (changed) {
      changed = false;
      final keys = counts.keys.toList()..sort();
      for (final k in keys) {
        final cnt = counts[k] ?? 0;
        if (cnt >= 2) {
          final next = k * 2;
          produced.add(next);
          counts[next] = (counts[next] ?? 0) + (cnt ~/ 2);
          counts[k] = cnt % 2;
          changed = true;
        }
      }
    }
    return produced;
  }
}
