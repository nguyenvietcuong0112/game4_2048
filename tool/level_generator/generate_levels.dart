import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'generator.dart';
import 'models.dart';
import 'solver.dart';

const String _defaultCampaignPath = 'assets/levels/all_121_levels.json';
const String _defaultOutputPath = 'assets/levels/generated_levels.json';

void main(List<String> args) {
  final parsed = _parseArgs(args);
  if (parsed.showHelp) {
    _printUsage();
    return;
  }

  if (parsed.verifyPath != null) {
    _runVerifyMode(
      parsed.verifyPath!,
      maxVisited: parsed.solverMaxVisited,
      timeoutMs: parsed.solverTimeoutMs,
      showSteps: parsed.showSteps,
    );
    return;
  }

  _runGenerateMode(parsed);
}

void _runVerifyMode(
  String path, {
  required int maxVisited,
  required int timeoutMs,
  required bool showSteps,
}) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Error: file not found: $path');
    exitCode = 1;
    return;
  }

  final rawList = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  stdout.writeln('Verifying ${rawList.length} levels in $path ...');
  final totalSw = Stopwatch()..start();

  int solved = 0;
  int unsolvable = 0;
  int inconclusive = 0;

  for (int i = 0; i < rawList.length; i++) {
    final entry = rawList[i] as Map<String, dynamic>;
    final level = GenLevel.fromCampaignJson(entry, i + 1);
    final res = LevelSolver.solve(
      level,
      maxVisited: maxVisited,
      timeoutMs: timeoutMs,
      recordSteps: showSteps,
    );
    final mechs = level.activeMechanicNames.isEmpty
        ? 'None'
        : level.activeMechanicNames.join('+');

    if (res.isSolved) {
      solved++;
      stdout.writeln(
        '[OK]   Lv ${level.number.toString().padLeft(3)} '
        '(${level.cols}x${level.rows}, ${level.pieces.length} pcs, $mechs) '
        '-> ${res.totalMoves} moves (${res.mergeMoves} merges, ${res.slideMoves} slides) '
        'in ${res.elapsedMs}ms',
      );
      if (showSteps && res.steps.isNotEmpty) {
        for (int s = 0; s < res.steps.length; s++) {
          stdout.writeln('       ${s + 1}. ${res.steps[s]}');
        }
      }
    } else if (res.status == SolveStatus.unsolvable) {
      unsolvable++;
      stdout.writeln(
        '[FAIL] Lv ${level.number.toString().padLeft(3)} ($mechs) -> ${res.reason}',
      );
    } else {
      inconclusive++;
      stdout.writeln(
        '[WARN] Lv ${level.number.toString().padLeft(3)} ($mechs) -> ${res.reason} '
        '(${res.visitedStates} states, ${res.elapsedMs}ms)',
      );
    }
  }

  stdout.writeln('\nSummary (${(totalSw.elapsedMilliseconds / 1000).toStringAsFixed(2)}s):');
  stdout.writeln('  Total       : ${rawList.length}');
  stdout.writeln('  Solved      : $solved');
  stdout.writeln('  Unsolvable  : $unsolvable');
  stdout.writeln('  SearchLimit : $inconclusive');

  if (unsolvable > 0) {
    exitCode = 2;
  }
}

void _runGenerateMode(_CliOptions opts) {
  // Load existing campaign levels (if present) for auto start-level & hash deduplication
  final campaignFile = File(opts.campaignPath);
  final existingRaw = <Map<String, dynamic>>[];
  final usedHashes = <String>{};
  int highestExistingNumber = 0;

  if (campaignFile.existsSync()) {
    final decoded = jsonDecode(campaignFile.readAsStringSync()) as List<dynamic>;
    for (int i = 0; i < decoded.length; i++) {
      final entry = decoded[i] as Map<String, dynamic>;
      existingRaw.add(entry);
      final lv = GenLevel.fromCampaignJson(entry, i + 1);
      if (lv.number > highestExistingNumber) {
        highestExistingNumber = lv.number;
      }
      usedHashes.add(lv.computeContentHash());
      final storedHash = entry['content_hash'] as String?;
      if (storedHash != null && storedHash.isNotEmpty) {
        usedHashes.add(storedHash);
      }
    }
  }

  final startLevel = opts.startLevel ?? (highestExistingNumber + 1);
  final rng = math.Random(opts.seed);
  final generator = LevelGenerator();
  final config = GenerationConfig(
    fixedDifficulty: opts.difficulty,
    fixedMechanics: opts.mechanics,
    maxAttemptsPerLevel: opts.maxAttempts,
    solverMaxVisited: opts.solverMaxVisited,
    solverTimeoutMs: opts.solverTimeoutMs,
  );

  stdout.writeln('=== Block Order 2048 Level Generator ===');
  stdout.writeln(
    'Count: ${opts.count} | Range: Lv $startLevel -> ${startLevel + opts.count - 1} '
    '| Seed: ${opts.seed}',
  );
  stdout.writeln(
    'Difficulty: ${opts.difficulty?.name ?? "auto (sawtooth)"} '
    '| Mechanics: ${opts.mechanics?.cliName ?? "auto"}',
  );
  stdout.writeln('');

  final totalSw = Stopwatch()..start();
  final generatedReports = <GeneratedLevelReport>[];

  for (int i = 0; i < opts.count; i++) {
    final lvNum = startLevel + i;
    final report = generator.generateLevel(
      levelNumber: lvNum,
      rng: rng,
      usedHashes: usedHashes,
      config: config,
    );
    generatedReports.add(report);

    final lv = report.level;
    final mechs = lv.activeMechanicNames.isEmpty
        ? 'None'
        : lv.activeMechanicNames.join('+');
    final occPct = (lv.occupancyRatio * 100).toStringAsFixed(1);

    stdout.writeln(
      '[OK] Lv ${lv.number.toString().padLeft(3)} | '
      '${report.difficulty.name.padRight(9)} | '
      '${lv.cols}x${lv.rows} (${occPct.padLeft(4)}%) | '
      '${lv.pieces.length.toString().padLeft(2)} pcs -> ${lv.targetWinNumber.toString().padLeft(4)} | '
      '${lv.timeSeconds.toString().padLeft(3)}s | '
      '${mechs.padRight(22)} | '
      'moves:${report.solveResult.totalMoves} '
      '(slides:${report.solveResult.slideMoves}, try:${report.attempts})',
    );

    if (opts.preview) {
      stdout.writeln(lv.renderAscii());
    }
  }

  final generatedEntries = [
    for (final r in generatedReports) r.level.toCampaignEntryJson(),
  ];

  // Write output
  if (opts.appendToCampaign) {
    if (campaignFile.existsSync()) {
      final backupPath = '${campaignFile.path}.bak';
      campaignFile.copySync(backupPath);
      stdout.writeln('\nBackup created: $backupPath');
    }
    final combined = [...existingRaw, ...generatedEntries];
    _writeJsonList(campaignFile, combined, pretty: opts.pretty);
    stdout.writeln(
      'Appended ${generatedEntries.length} levels -> ${campaignFile.path} '
      '(total: ${combined.length} levels)',
    );
  } else {
    final outFile = File(opts.outputPath);
    outFile.parent.createSync(recursive: true);
    _writeJsonList(outFile, generatedEntries, pretty: opts.pretty);
    stdout.writeln(
      '\nSaved ${generatedEntries.length} generated levels -> ${outFile.path}',
    );
  }

  // Compact distribution summary
  final comboCounts = <String, int>{};
  int sumMoves = 0;
  int sumSlides = 0;
  for (final r in generatedReports) {
    final k = r.level.activeMechanicNames.isEmpty
        ? 'None'
        : r.level.activeMechanicNames.join(' + ');
    comboCounts[k] = (comboCounts[k] ?? 0) + 1;
    sumMoves += r.solveResult.totalMoves;
    sumSlides += r.solveResult.slideMoves;
  }

  final avgMoves = (sumMoves / generatedReports.length).toStringAsFixed(1);
  final avgSlides = (sumSlides / generatedReports.length).toStringAsFixed(1);
  final elapsedSec = (totalSw.elapsedMilliseconds / 1000).toStringAsFixed(2);
  stdout.writeln(
    'Done in ${elapsedSec}s | 100% solver-verified | Avg moves: $avgMoves (avg slides: $avgSlides)',
  );
  stdout.writeln('Mechanic distribution:');
  final sortedCombos = comboCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in sortedCombos) {
    stdout.writeln('  - ${e.key}: ${e.value}');
  }
}

void _writeJsonList(
  File file,
  List<Map<String, dynamic>> items, {
  required bool pretty,
}) {
  final encoder = pretty
      ? const JsonEncoder.withIndent('  ')
      : const JsonEncoder();
  file.writeAsStringSync('${encoder.convert(items)}\n');
}

class _CliOptions {
  final int count;
  final int? startLevel;
  final int seed;
  final DifficultyTier? difficulty;
  final MechanicCombo? mechanics;
  final String outputPath;
  final String campaignPath;
  final bool appendToCampaign;
  final bool preview;
  final bool pretty;
  final bool showHelp;
  final String? verifyPath;
  final bool showSteps;
  final int maxAttempts;
  final int solverMaxVisited;
  final int solverTimeoutMs;

  const _CliOptions({
    required this.count,
    required this.startLevel,
    required this.seed,
    required this.difficulty,
    required this.mechanics,
    required this.outputPath,
    required this.campaignPath,
    required this.appendToCampaign,
    required this.preview,
    required this.pretty,
    required this.showHelp,
    required this.verifyPath,
    required this.showSteps,
    required this.maxAttempts,
    required this.solverMaxVisited,
    required this.solverTimeoutMs,
  });
}

_CliOptions _parseArgs(List<String> args) {
  int count = 20;
  int? startLevel;
  int seed = 20261119;
  DifficultyTier? difficulty;
  MechanicCombo? mechanics;
  String outputPath = _defaultOutputPath;
  String campaignPath = _defaultCampaignPath;
  bool appendToCampaign = false;
  bool preview = false;
  bool pretty = false;
  bool showHelp = false;
  String? verifyPath;
  bool showSteps = false;
  int maxAttempts = 80;
  int solverMaxVisited = 22000;
  int solverTimeoutMs = 900;

  String nextValue(int idx, String flag) {
    if (idx + 1 >= args.length) {
      stderr.writeln('Missing value for $flag');
      exit(64);
    }
    return args[idx + 1];
  }

  for (int i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '-h':
      case '--help':
        showHelp = true;
        break;
      case '-n':
      case '--count':
        count = int.parse(nextValue(i++, arg));
        break;
      case '--start-level':
        startLevel = int.parse(nextValue(i++, arg));
        break;
      case '--seed':
        seed = int.parse(nextValue(i++, arg));
        break;
      case '--difficulty':
        final v = nextValue(i++, arg);
        if (v.toLowerCase() != 'auto') {
          difficulty = DifficultyTier.tryParse(v);
          if (difficulty == null) {
            stderr.writeln(
              'Invalid --difficulty "$v". Valid: auto, easy, normal, hard, super_hard',
            );
            exit(64);
          }
        }
        break;
      case '--mechanics':
        final v = nextValue(i++, arg);
        if (v.toLowerCase() != 'auto') {
          mechanics = MechanicCombo.tryParse(v);
          if (mechanics == null) {
            stderr.writeln(
              'Invalid --mechanics "$v". Valid: auto, '
              '${MechanicCombo.values.map((e) => e.cliName).join(", ")}',
            );
            exit(64);
          }
        }
        break;
      case '-o':
      case '--output':
        outputPath = nextValue(i++, arg);
        break;
      case '--campaign':
        campaignPath = nextValue(i++, arg);
        break;
      case '--append':
        appendToCampaign = true;
        break;
      case '--preview':
        preview = true;
        break;
      case '--pretty':
        pretty = true;
        break;
      case '--verify':
        verifyPath = nextValue(i++, arg);
        break;
      case '--show-steps':
        showSteps = true;
        break;
      case '--max-attempts':
        maxAttempts = int.parse(nextValue(i++, arg));
        break;
      case '--solver-limit':
        solverMaxVisited = int.parse(nextValue(i++, arg));
        break;
      case '--solver-timeout-ms':
        solverTimeoutMs = int.parse(nextValue(i++, arg));
        break;
      default:
        stderr.writeln('Unknown option: $arg (use --help for usage)');
        exit(64);
    }
  }

  return _CliOptions(
    count: math.max(1, count),
    startLevel: startLevel,
    seed: seed,
    difficulty: difficulty,
    mechanics: mechanics,
    outputPath: outputPath,
    campaignPath: campaignPath,
    appendToCampaign: appendToCampaign,
    preview: preview,
    pretty: pretty,
    showHelp: showHelp,
    verifyPath: verifyPath,
    showSteps: showSteps,
    maxAttempts: maxAttempts,
    solverMaxVisited: solverMaxVisited,
    solverTimeoutMs: solverTimeoutMs,
  );
}

void _printUsage() {
  stdout.writeln('''
Block Order 2048 — Procedural Level Generator & Solver CLI

Usage:
  dart run tool/level_generator/generate_levels.dart [options]

Generate Options:
  -n, --count <N>            So luong level muon sinh (default: 20)
      --start-level <N>      So thu tu level bat dau (default: last campaign level + 1)
      --seed <N>             Seed random de tai tao y het (default: 20261119)
      --difficulty <tier>    auto (sawtooth) | easy | normal | hard | super_hard
      --mechanics <combo>    auto | none | dud | ice | arrows | pinned |
                             dud+arrows | ice+dud | dud+pinned | ice+arrows |
                             ice+dud+arrows | ice+dud+pinned | dud+pinned+arrows | all4
  -o, --output <path>        File JSON xuat ra (default: $_defaultOutputPath)
      --append               Noi truc tiep vao $_defaultCampaignPath (co tao file .bak)
      --pretty               Format JSON dep de doc/review (mac dinh minified giong file goc)
      --preview              In ban do ASCII cua tung level ra terminal

Verify Mode (kiem tra file level co giai duoc 100% khong):
      --verify <path>        Chay A* Solver kiem chung toan bo level trong file JSON
      --show-steps           In chi tiet tung buoc giai khi dung --verify
      --solver-limit <N>     Gioi han trang thai A* (default: 22000)
      --solver-timeout-ms <ms> Timeout moi level (default: 900ms)

Examples:
  # 1. Sinh thu 10 level ra file rieng + in ASCII preview
  dart run tool/level_generator/generate_levels.dart --count 10 --preview

  # 2. Sinh 178 level (Lv 123 -> 300) va noi thang vao campaign (co backup .bak)
  dart run tool/level_generator/generate_levels.dart --count 178 --seed 2026 --append

  # 3. Sinh 5 level Super Hard du ca 4 mechanic
  dart run tool/level_generator/generate_levels.dart --count 5 --difficulty super_hard --mechanics all4 --pretty

  # 4. Kiem tra lai toan bo file level bang Solver
  dart run tool/level_generator/generate_levels.dart --verify assets/levels/generated_levels.json
''');
}
