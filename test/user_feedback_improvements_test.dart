import 'dart:ui' as ui;
import 'package:flame/extensions.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:block_order_2048/game/block_order_game.dart';
import 'package:block_order_2048/game/sand_jar_component.dart';
import 'package:block_order_2048/game/vfx_components.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/models/palette.dart';
import 'package:block_order_2048/models/unity_curve.dart';
import 'package:block_order_2048/services/audio_haptics_service.dart';
import 'package:block_order_2048/services/player_progress_service.dart';
import 'package:block_order_2048/services/remote_config_service.dart';
import 'package:block_order_2048/ui/gameplay_screen.dart';
import 'package:block_order_2048/ui/unity_ui_kit.dart';
import 'package:block_order_2048/ui/win_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channelName in const [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(channelName),
        (_) async => 1,
      );
    }
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
      SharedPreferences.setMockInitialValues({'bo_current_level': 2});
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

      // Find locked LevelUp button (displays "Level 17" inside the lock circle)
      final levelUpBtn = find.byKey(const ValueKey('hud_level_up_btn'));
      expect(levelUpBtn, findsOneWidget);
      expect(
        find.descendant(of: levelUpBtn, matching: find.text('Level 17')),
        findsOneWidget,
      );

      // Tap locked LevelUp button
      await tester.tap(levelUpBtn);
      await tester.pump(const Duration(milliseconds: 50));

      // Toast "Unlock at level 17!" should appear
      expect(find.text('Unlock at level 17!'), findsOneWidget);

      // Find locked TimeFreeze button (displays "Level 27" inside the lock circle)
      final timeFreezeBtn = find.byKey(const ValueKey('hud_time_freeze_btn'));
      expect(timeFreezeBtn, findsOneWidget);
      expect(
        find.descendant(of: timeFreezeBtn, matching: find.text('Level 27')),
        findsOneWidget,
      );

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

    test('5. Water stream, combo new_1..new_13 SFX, and anti-clipping mixer behavior', () {
      final audio = AudioHapticsService();
      audio.clearDebugLogs();

      // When sound is enabled, playWaterStreamFlow logs 'sfx_water_stream.wav'
      audio.playWaterStreamFlow();
      expect(audio.debugPlayedSfxLog, contains('sfx_water_stream.wav'));

      // Combo 1..15 maps cleanly to ascending new_1.mp3 .. new_13.mp3 (clamped at 13)
      audio.clearDebugLogs();
      for (int c = 1; c <= 15; c++) {
        audio.playComboPraise(c);
      }
      for (int c = 1; c <= 13; c++) {
        expect(audio.debugPlayedSfxLog, contains('new_$c.mp3'));
      }
      // 14 & 15 share 'new_13.mp3' and deduplicate within minGapMs on simultaneous fire
      expect(
        audio.debugPlayedSfxLog.where((e) => e == 'new_13.mp3').length,
        1,
      );

      // Simultaneous duplicate triggers on same frame deduplicate to prevent phase clipping
      audio.clearDebugLogs();
      audio.playIceBreak();
      audio.playIceBreak();
      audio.playIceBreak();
      expect(
        audio.debugPlayedSfxLog.where((e) => e == 'sfx_ice_break_whole.wav').length,
        1,
      );

      // Concurrent polyphony mixer lowers headroom proportionally as burst count grows
      final solo = AudioHapticsService.computeMixGain(
        'sfx_block_put.wav',
        volume: 1.0,
        concurrentCount: 1,
      );
      final triple = AudioHapticsService.computeMixGain(
        'sfx_block_put.wav',
        volume: 1.0,
        concurrentCount: 3,
      );
      final quad = AudioHapticsService.computeMixGain(
        'sfx_block_put.wav',
        volume: 1.0,
        concurrentCount: 4,
      );
      expect(triple, lessThan(solo));
      expect(quad, lessThan(triple));

      // When sound is disabled, no SFX is logged or played
      audio.clearDebugLogs();
      audio.toggleSound(); // disables sound
      expect(audio.soundEnabled, isFalse);
      audio.playWaterStreamFlow();
      audio.playComboPraise(1);
      expect(audio.debugPlayedSfxLog, isEmpty);
    });

    testWidgets('6. Redesigned Bottom-Right Footer Settings button opens Setting modal popup with Sound/Music/Haptics toggles & Restart', (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      late final LevelRepository repo;
      SharedPreferences.setMockInitialValues({'bo_current_level': 2});
      final audio = AudioHapticsService();
      final progress = PlayerProgressService();

      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
        repo = await LevelRepository.loadFromAssets();
        await progress.init();
      });

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

      // Verify Settings gear icon sits in the Bottom-Right Footer (`Play_Scene.png`)
      final gearImg = find.image(const AssetImage('assets/images/Icon_Settings.png'));
      expect(gearImg, findsOneWidget);
      final gearCenter = tester.getCenter(gearImg);
      expect(gearCenter.dx, greaterThan(540 * 0.75));
      expect(gearCenter.dy, greaterThan(1080 * 0.80));

      await tester.tap(gearImg);
      await tester.pump(const Duration(milliseconds: 250));

      // Verify `PopUp_Setting.png` elements render without layout errors
      expect(find.text('Setting'), findsWidgets);
      expect(find.text('Restart'), findsWidgets);
      expect(find.text('v.1.0.6'), findsOneWidget);

      // Toggle Sound OFF -> `Icon_Sounds_Off.png` appears
      expect(audio.soundEnabled, isTrue);
      await tester.tap(find.image(const AssetImage('assets/images/Icon_Sounds.png')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.soundEnabled, isFalse);
      expect(
        find.image(const AssetImage('assets/images/Icon_Sounds_Off.png')),
        findsOneWidget,
      );

      // Tap Close (`Button_Close.png`) -> Settings modal closes
      await tester.tap(find.image(const AssetImage('assets/images/Button_Close.png')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('v.1.0.6'), findsNothing);
    });

    testWidgets('7. Redesigned Gameplay HUD (Play_Scene.png): Top-Right Stopwatch Timer Pill & Top-Center Combo Progress Bar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      late final LevelRepository repo;
      SharedPreferences.setMockInitialValues({'bo_current_level': 2});
      final audio = AudioHapticsService();
      final progress = PlayerProgressService();

      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
        repo = await LevelRepository.loadFromAssets();
        await progress.init();
        progress.setCurrentLevel(15); // Timed level (`!timerDisabled`, matching `Play_Scene.png`)
      });

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

      // 1. Top-Right Stopwatch Timer (`Icon_Clock.png`) sits in Top-Right on the same HUD row as `CoinsWidget`
      final clockImg = find.image(const AssetImage('assets/images/Icon_Clock.png'));
      expect(clockImg, findsOneWidget);
      final clockCenter = tester.getCenter(clockImg);
      expect(clockCenter.dx, greaterThan(540 * 0.65));
      expect(clockCenter.dy, lessThan(1080 * 0.15));

      final lv15 = repo.getCampaignLevel(15);
      expect(lv15.timerDisabled, isFalse);
      final expectedTime =
          '${(lv15.timeSeconds ~/ 60).toString().padLeft(2, '0')}:${(lv15.timeSeconds % 60).toString().padLeft(2, '0')}';
      expect(find.text(expectedTime), findsOneWidget);

      // 2. Top-Center Combo Progress Bar (`progress_combo_bg.png` + `progress_combo_fg.png`)
      final gameWidget = tester.widget<GameWidget<BlockOrderGame>>(
        find.byType(GameWidget<BlockOrderGame>),
      );
      final game = gameWidget.game!;

      // Before any merge (`comboCount == 0`), combo bar is invisible (`opacity == 0.0`)
      expect(
        find.byWidgetPredicate(
          (w) => w is UnityNineSlice && w.sprite == 'progress_combo_bg.png',
        ),
        findsOneWidget,
      );

      // Activate Combo x1 (`frac = 0.65`) -> Combo bar pops in with `progress_combo_fg.png` & `'Combo x1'`
      game.comboCountNotifier.value = 1;
      game.comboCountdownFractionNotifier.value = 0.65;
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Combo x1'), findsWidgets);
      final comboFgFinder = find.byWidgetPredicate(
        (w) => w is UnityNineSlice && w.sprite == 'progress_combo_fg.png',
      );
      expect(comboFgFinder, findsOneWidget);

      // Escalate to Combo x2 -> updates label to `'Combo x2'`
      game.comboCountNotifier.value = 2;
      game.comboCountdownFractionNotifier.value = 1.0;
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Combo x2'), findsWidgets);

      // Expire combo (`comboCount == 0, frac == 0.0`) -> green fill bar disappears cleanly
      game.comboCountNotifier.value = 0;
      game.comboCountdownFractionNotifier.value = 0.0;
      await tester.pump(const Duration(milliseconds: 220));
      expect(comboFgFinder, findsNothing);

      // 3. Urgent Low-Time (`<= 10s`) feathered red outer-edge vignette pulses in sync with `00:04`
      expect(
        find.byKey(const ValueKey('urgent_low_time_vignette')),
        findsNothing,
      );
      game.cheatSetRemainingSeconds(4);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('00:04'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('urgent_low_time_vignette')),
        findsOneWidget,
      );
    });

    testWidgets('8. RemoteConfig cheat_enable gates CheatHudButton & CheatPanelOverlay (default false for store, live-enabled when true)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(540, 1080));
      addTearDown(() {
        RemoteConfigService.setMockValues(cheatEnable: false);
        tester.binding.setSurfaceSize(null);
      });

      // Ensure store-safe default is false without overriding first
      expect(RemoteConfigService.cheatEnable, isFalse);

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      late final LevelRepository repo;
      SharedPreferences.setMockInitialValues({'bo_current_level': 2});
      final audio = AudioHapticsService();
      final progress = PlayerProgressService();

      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
        repo = await LevelRepository.loadFromAssets();
        await progress.init();
      });

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

      // 1. When `cheat_enable == false` (store default), Cheat button & panel do NOT exist
      expect(find.byKey(const ValueKey('hud_cheat_btn')), findsNothing);
      expect(find.byKey(const ValueKey('cheat_panel_overlay')), findsNothing);

      // 2. When `cheat_enable == true` from Remote Config, Cheat button appears live!
      RemoteConfigService.setMockValues(cheatEnable: true);
      await tester.pump(const Duration(milliseconds: 100));
      final cheatBtn = find.byKey(const ValueKey('hud_cheat_btn'));
      expect(cheatBtn, findsOneWidget);

      // 3. Open Cheat Panel & test economy + level jump actions
      await tester.tap(cheatBtn);
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const ValueKey('cheat_panel_overlay')), findsOneWidget);

      final initialCoins = progress.coins;
      final addCoinsBtn = find.byKey(const ValueKey('cheat_add_1k_coins_btn'));
      await tester.ensureVisible(addCoinsBtn);
      await tester.tap(addCoinsBtn);
      await tester.pump(const Duration(milliseconds: 50));
      expect(progress.coins, initialCoins + 1000);

      final initialLvUp = progress.levelUpCount;
      final addBoostersBtn = find.byKey(const ValueKey('cheat_add_5_boosters_btn'));
      await tester.ensureVisible(addBoostersBtn);
      await tester.tap(addBoostersBtn);
      await tester.pump(const Duration(milliseconds: 50));
      expect(progress.levelUpCount, initialLvUp + 5);

      // Close & reopen panel so Section 1 (Level Jump) is at top of scroll view
      await tester.tap(find.byKey(const ValueKey('cheat_close_btn')));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(cheatBtn);
      await tester.pump(const Duration(milliseconds: 150));

      // Jump to Level 15 via Cheat input
      final levelInput = find.byKey(const ValueKey('cheat_level_input'));
      final goBtn = find.byKey(const ValueKey('cheat_level_go_btn'));
      await tester.enterText(levelInput, '15');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(goBtn);
      await tester.pump(const Duration(milliseconds: 350));
      expect(progress.currentLevel, 15);
      expect(find.text('Level 15'), findsWidgets);

      // Level 15 triggers the first-time Dud Block FTUE modal; dismiss it first
      final continueBtn = find.text('Continue');
      if (continueBtn.evaluate().isNotEmpty) {
        await tester.tap(continueBtn.last);
        await tester.pump(const Duration(milliseconds: 200));
      }

      // Reopen Cheat Panel & expand all 25 Bonus levels -> jump to Bonus #4
      await tester.tap(cheatBtn);
      await tester.pump(const Duration(milliseconds: 150));
      final toggleBonusBtn =
          find.byKey(const ValueKey('cheat_toggle_bonus_list_btn'));
      expect(toggleBonusBtn, findsOneWidget);
      await tester.ensureVisible(toggleBonusBtn);
      await tester.tap(toggleBonusBtn);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('cheat_bonus_lv_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('cheat_bonus_lv_25')), findsOneWidget);

      final bonus4Chip = find.byKey(const ValueKey('cheat_bonus_lv_4'));
      await tester.ensureVisible(bonus4Chip);
      await tester.tap(bonus4Chip);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(repo.bonusLevels[3].title), findsWidgets);

      // 4. Turning `cheat_enable == false` hides Cheat UI immediately
      RemoteConfigService.setMockValues(cheatEnable: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('hud_cheat_btn')), findsNothing);
      expect(find.byKey(const ValueKey('cheat_panel_overlay')), findsNothing);
    });

    testWidgets(
        '9. Typing level in Cheat with soft keyboard & same-frame resize leaves ZERO ghost pieces at old position',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
        RemoteConfigService.setMockValues(cheatEnable: false);
      });

      RemoteConfigService.setMockValues(cheatEnable: true);

      late final BlockOrderPalette palette;
      late final PieceVisualSettings settings;
      late final LevelRepository repo;
      SharedPreferences.setMockInitialValues({'bo_current_level': 2});
      final audio = AudioHapticsService();
      final progress = PlayerProgressService();

      await tester.runAsync(() async {
        Flame.images.clearCache();
        const sprites = [
          'IceLock.png',
          'IceBlocks.png',
          'Ice_Shards.png',
          'Screw_Greyscale_01.png',
          'Screw_Greyscale_02.png',
          'Screw_Greyscale_03.png',
          'Movement_Single-Horizontal_Shadow.png',
          'Movement_Single-Horizontal_Stroke.png',
          'Movement_Single-Horizontal_Top.png',
          'Movement_Double_Horizontal.png',
          'Movement_Double_Vertical.png',
          'Sparkle_01.png',
          'ParticleFlare.png',
          'Explosion_Halo.png',
          'Glow_Ring.png',
          'Glow_02.png',
          'PowerUp_Icon_Arrow.png',
          'Hand_01.png',
        ];
        for (final s in sprites) {
          await Flame.images.load(s);
        }
        await ScrewTextureCleaner.ensureCleanedScrewsLoaded();
        await SparkleAtlas.ensureLoaded();
        palette = await BlockOrderPalette.loadFromAssets();
        settings = await PieceVisualSettings.loadFromAssets();
        repo = await LevelRepository.loadFromAssets();
        await progress.init();
      });

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
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      final gameWidgetFinder = find.byType(GameWidget<BlockOrderGame>);
      final fullGameSize = tester.getSize(gameWidgetFinder);
      final game = tester.widget<GameWidget<BlockOrderGame>>(gameWidgetFinder).game!;

      // Open Cheat Panel and simulate soft keyboard appearing (`viewInsets.bottom = 700` physical px)
      await tester.tap(find.byKey(const ValueKey('hud_cheat_btn')));
      await tester.pump(const Duration(milliseconds: 150));

      tester.view.viewInsets = const FakeViewPadding(bottom: 700);
      await tester.pump(const Duration(milliseconds: 100));

      // `GameWidget` must NOT shrink when soft keyboard opens (`resizeToAvoidBottomInset: false`)
      expect(tester.getSize(gameWidgetFinder), fullGameSize);

      // Type level 4 and tap GO while simultaneously closing keyboard & triggering same-frame resize
      await tester.enterText(
        find.byKey(const ValueKey('cheat_level_input')),
        '4',
      );
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const ValueKey('cheat_level_go_btn')));

      // Even if a same-frame `onGameResize` fires before Flame's next `updateTree` tick,
      // pending `add()` pieces from `loadLevel` must be dequeued cleanly without ghost clones!
      game.onGameResize(Vector2(536, 956));
      game.onGameResize(Vector2(540, 960));
      tester.view.resetViewInsets();

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      final lv4Count = repo.getCampaignLevel(4).initialPieces.length;
      expect(game.debugPieces.length, lv4Count);
      expect(game.debugMountedStagePieceCount, lv4Count);
      expect(game.debugRawStagePieceCount, lv4Count);
    });
  });
}
