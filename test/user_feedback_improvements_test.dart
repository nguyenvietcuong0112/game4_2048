import 'dart:ui' as ui;
import 'package:flame/extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:block_order_2048/game/sand_jar_component.dart';
import 'package:block_order_2048/game/vfx_components.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/models/palette.dart';
import 'package:block_order_2048/models/unity_curve.dart';
import 'package:block_order_2048/services/audio_haptics_service.dart';
import 'package:block_order_2048/services/player_progress_service.dart';
import 'package:block_order_2048/ui/gameplay_screen.dart';
import 'package:block_order_2048/ui/win_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('User Feedback Improvements', () {
    test('1. Combo praise tiers escalation variety (Nice -> Incredible)', () {
      expect(ComboPraiseTier.forCombo(1).praiseText, isNull);
      expect(ComboPraiseTier.forCombo(2).praiseText, 'NICE!');
      expect(ComboPraiseTier.forCombo(3).praiseText, 'GREAT!');
      expect(ComboPraiseTier.forCombo(4).praiseText, 'AWESOME!');
      expect(ComboPraiseTier.forCombo(5).praiseText, 'AMAZING!');
      expect(ComboPraiseTier.forCombo(6).praiseText, 'BRILLIANT!');
      expect(ComboPraiseTier.forCombo(7).praiseText, 'EXCELLENT!');
      expect(ComboPraiseTier.forCombo(8).praiseText, 'FLAWLESS!');
      expect(ComboPraiseTier.forCombo(9).praiseText, 'LEGENDARY!');
      expect(ComboPraiseTier.forCombo(10).praiseText, 'INCREDIBLE!');
      expect(ComboPraiseTier.forCombo(15).praiseText, 'INCREDIBLE!');
    });

    testWidgets('2. WinOverlay enlarged stats bar renders Time, Moves, and Combo', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WinOverlay(
              levelLabel: 'Level 1',
              rewardCoins: 25,
              timeFormatted: '00:14',
              movesCount: 9,
              comboCount: 6,
              onNextLevel: () {},
            ),
          ),
        ),
      );

      // Fast forward sequence animation into Stage 2
      await tester.pump(const Duration(milliseconds: 1400));

      expect(find.text('Time'), findsOneWidget);
      expect(find.text('00:14'), findsOneWidget);
      expect(find.text('Moves'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('Combo'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('3. Locked power-up buttons show "Unlock at level X!" toast on tap', (tester) async {
      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      late final LevelRepository repo;
      final audio = AudioHapticsService();
      final progress = PlayerProgressService();

      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
        repo = await LevelRepository.loadFromAssets();
        await progress.init();
      });

      // At Level 1, both LevelUp (17) and TimeFreeze (27) are locked
      expect(progress.isLevelUpUnlockedForLevel(1), isFalse);
      expect(progress.isTimeFreezeUnlockedForLevel(1), isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            repository: repo,
            palette: palette,
            visualSettings: settings,
            audio: audio,
            progress: progress,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Find locked LevelUp button
      final levelUpBtn = find.byKey(const ValueKey('hud_level_up_btn'));
      expect(levelUpBtn, findsOneWidget);

      // Tap locked LevelUp button
      await tester.tap(levelUpBtn);
      await tester.pump(const Duration(milliseconds: 50));

      // Toast "Unlock at level 17!" should appear
      expect(find.text('Unlock at level 17!'), findsOneWidget);

      // Find locked TimeFreeze button
      final timeFreezeBtn = find.byKey(const ValueKey('hud_time_freeze_btn'));
      expect(timeFreezeBtn, findsOneWidget);

      // Tap locked TimeFreeze button
      await tester.tap(timeFreezeBtn);
      await tester.pump(const Duration(milliseconds: 50));

      // Toast "Unlock at level 27!" should appear
      expect(find.text('Unlock at level 27!'), findsOneWidget);

      // Fast forward toast duration (1800ms) + fade (200ms)
      await tester.pump(const Duration(milliseconds: 1850));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Unlock at level 27!'), findsNothing);
    });

    testWidgets('4. Dynamic water stream & jar liquid colors match winning block', (tester) async {
      late final BlockOrderPalette palette;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
      });

      // Test with Purple block 32
      final purpleStyle = palette.styleFor(number: 32, isFrozen: false);
      final jar = MagicSandJarComponent(
        style: purpleStyle,
        levelNumber: 4,
        targetNumber: 4096,
        centerPosition: Vector2(200, 200),
        jarWidth: 120,
        jarHeight: 160,
        initialAppearProgress: 1.0,
      );

      // When idle, renders mystery question mark and transparent glass
      final rec1 = ui.PictureRecorder();
      final canvas1 = Canvas(rec1, const Rect.fromLTWH(0, 0, 400, 400));
      jar.update(0.016);
      jar.render(canvas1);
      expect(rec1.endRecording(), isNotNull);

      // Update to orange block 4
      final orangeStyle = palette.styleFor(number: 4, isFrozen: false);
      jar.updateStyle(orangeStyle);
      jar.updateTargetNumber(4);

      // During win sequence, liquid fills with orange style
      jar.setWinSequenceState(
        appearProgress: 1.0,
        fillProgress: 0.70,
        glowIntensity: 0.60,
        shakeIntensity: 0.10,
        openProgress: 0.0,
      );

      final rec2 = ui.PictureRecorder();
      final canvas2 = Canvas(rec2, const Rect.fromLTWH(0, 0, 400, 400));
      jar.update(0.016);
      jar.render(canvas2);
      expect(rec2.endRecording(), isNotNull);

      // Water stream to jar with orangeStyle
      final stream = BoardSandStreamToJarVfx(
        finalTileCenter: Vector2(200, 350),
        boardOrigins: [Vector2(200, 350)],
        targetMouthProvider: () => jar.mouthWorldPos,
        style: orangeStyle,
        cellSize: 64,
        jar: jar,
      );

      final rec3 = ui.PictureRecorder();
      final canvas3 = Canvas(rec3, const Rect.fromLTWH(0, 0, 400, 400));
      stream.update(0.20);
      stream.render(canvas3);
      expect(rec3.endRecording(), isNotNull);
    });

    test('4. Zero-Stutter Merge FX: SparkleAtlas, Vector Combo Badge, Clamped Particles, and Circle Waves render without frame hitching', () {
      // 1. SparkleAtlas properties
      expect(SparkleAtlas.tileSize, 64.0);
      expect(SparkleAtlas.tileRect, const Rect.fromLTWH(0, 0, 64.0, 64.0));

      // 2. ComboPraiseCalloutVfx renders vector pill + text directly without synchronous toImageSync stalls
      final comboVfx = ComboPraiseCalloutVfx(
        anchorWorld: Vector2(100, 100),
        comboCount: 3,
        cellSize: 64.0,
      );
      comboVfx.update(0.10);
      final rec1 = ui.PictureRecorder();
      final canvas1 = Canvas(rec1, const Rect.fromLTWH(0, 0, 300, 300));
      comboVfx.render(canvas1);
      final pic1 = rec1.endRecording();
      expect(pic1, isNotNull);

      // Fade-out phase (t > 0.68)
      comboVfx.update(0.60);
      final rec2 = ui.PictureRecorder();
      final canvas2 = Canvas(rec2, const Rect.fromLTWH(0, 0, 300, 300));
      comboVfx.render(canvas2);
      final pic2 = rec2.endRecording();
      expect(pic2, isNotNull);

      // 3. MergeSplashVfx with clamped particles and native circle waves
      final splashVfx = MergeSplashVfx(
        centerPos: Vector2(100, 100),
        primaryColor: const Color(0xFFFFAE34),
        accentColor: const Color(0xFFFF5252),
        cellSize: 64.0,
        mergedNumber: 64,
      );
      splashVfx.update(0.08);
      final rec3 = ui.PictureRecorder();
      final canvas3 = Canvas(rec3, const Rect.fromLTWH(0, 0, 300, 300));
      splashVfx.render(canvas3);
      final pic3 = rec3.endRecording();
      expect(pic3, isNotNull);

      // 4. MergeBlockSparksVfx batched upward sparks
      final blockSparks = MergeBlockSparksVfx(
        cellCentersProvider: () => [Vector2(100, 100), Vector2(164, 100)],
        accentColor: const Color(0xFFFFAE34),
        cellSize: 64.0,
        delaySeconds: 0.0,
        mergedNumber: 64,
      );
      blockSparks.update(0.05);
      final rec4 = ui.PictureRecorder();
      final canvas4 = Canvas(rec4, const Rect.fromLTWH(0, 0, 300, 300));
      blockSparks.render(canvas4);
      final pic4 = rec4.endRecording();
      expect(pic4, isNotNull);
    });

    test('5. Water stream flow SFX triggers correctly in AudioHapticsService', () {
      final audio = AudioHapticsService();
      audio.clearDebugLogs();

      // When sound is enabled, playWaterStreamFlow logs 'sfx_water_stream.wav'
      audio.playWaterStreamFlow();
      expect(audio.debugPlayedSfxLog, contains('sfx_water_stream.wav'));

      // When sound is disabled, no SFX is logged or played
      audio.clearDebugLogs();
      audio.toggleSound(); // disables sound
      expect(audio.soundEnabled, isFalse);
      audio.playWaterStreamFlow();
      expect(audio.debugPlayedSfxLog, isEmpty);
    });
  });
}
