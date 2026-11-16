import 'dart:ui' as ui;

import 'package:block_order_2048/game/block_order_game.dart';
import 'package:block_order_2048/game/vfx_components.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/models/palette.dart';
import 'package:block_order_2048/models/unity_curve.dart';
import 'package:block_order_2048/services/ads_manager.dart';
import 'package:block_order_2048/services/analytics_service.dart';
import 'package:block_order_2048/services/audio_haptics_service.dart';
import 'package:block_order_2048/services/player_progress_service.dart';
import 'package:block_order_2048/ui/gameplay_screen.dart';
import 'package:block_order_2048/ui/intro_splash_view.dart';
import 'package:block_order_2048/ui/lose_overlay.dart';
import 'package:block_order_2048/ui/mechanic_unlock_dialog.dart';
import 'package:block_order_2048/ui/powerup_buy_popup.dart';
import 'package:block_order_2048/ui/unity_ui_kit.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentAudioService extends AudioHapticsService {
  int blockedHaptics = 0;

  @override
  Future<void> init() async {}

  @override
  void playClick() {}

  @override
  void playCoinCollect() {}

  @override
  void playPowerUpSelect() {}

  @override
  void playTimeFreeze() {}

  @override
  void playLevelFailed() {}

  @override
  void hapticBlocked() {
    blockedHaptics++;
  }
}

Future<void> _preloadGameTestAssets(WidgetTester tester) async {
  await tester.runAsync(() async {
    await UnitySpriteRegistry.preloadAll();
    const sprites = [
      'IceLock.png',
      'IceBlocks.png',
      'Ice_Shards.png',
      'Icon_Mechanic_Blocker.png',
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
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AdsManager.enableAds = false;
    AdsManager.mockRewardResult = null;
    AdsManager.mockRewardFailReason = null;
    AdsManager.mockInternetCheck = null;
    AnalyticsService.debugEventObserver = null;
  });

  testWidgets(
    '1. IntroSplashView smoothly grows loading progress bar from 0% -> 100%',
    (tester) async {
      await tester.runAsync(() async {
        await UnitySpriteRegistry.loadOne('Loading_BG.png');
        await UnitySpriteRegistry.loadOne('Loading_Progress.png');
      });

      await tester.binding.setSurfaceSize(const Size(540, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // At 0%: fill bar is hidden
      await tester.pumpWidget(
        const MaterialApp(home: IntroSplashView(progress: 0.0)),
      );
      expect(
        find.byKey(const ValueKey('intro_loading_progress_fill')),
        findsNothing,
      );

      final widths = <double>[];
      for (final p in [0.05, 0.25, 0.60, 1.00]) {
        await tester.pumpWidget(
          MaterialApp(home: IntroSplashView(progress: p)),
        );
        await tester.pump();
        final rect = tester.getRect(
          find.byKey(const ValueKey('intro_loading_progress_fill')),
        );
        widths.add(rect.width);
      }

      // Strictly increasing visual widths across 5% -> 25% -> 60% -> 100%
      expect(widths[0], greaterThan(4.0));
      expect(widths[1], greaterThan(widths[0]));
      expect(widths[2], greaterThan(widths[1]));
      expect(widths[3], greaterThan(widths[2]));
    },
  );

  testWidgets(
    '2 & 3. Insufficient coins Toast ("Not enough coins!") & Rewarded Ad Offline / No-Ads Toasts on PowerUpBuyPopup and LoseOverlay',
    (tester) async {
      await _preloadGameTestAssets(tester);
      final repo = await tester.runAsync(() => LevelRepository.loadFromAssets());
      final palette =
          await tester.runAsync(() => BlockOrderPalette.loadFromAssets());
      final settings =
          await tester.runAsync(() => PieceVisualSettings.loadFromAssets());

      SharedPreferences.setMockInitialValues({
        'bo_current_level': 28,
        'bo_highest_level': 28,
        'bo_coins': 100, // Below both 450 (Revive / TimeFreeze) and 600 (LevelUp)
        'bo_pu_level_up': 0,
        'bo_pu_time_freeze': 0,
        'bo_seen_mechanics': [
          'ice',
          'dud',
          'arrows',
          'pinned',
          'pu_level_up',
          'pu_time_freeze',
        ],
      });
      final progress = PlayerProgressService();
      await tester.runAsync(() => progress.init());
      final audio = _SilentAudioService();

      await tester.binding.setSurfaceSize(const Size(540, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            repository: repo!,
            palette: palette!,
            visualSettings: settings!,
            audio: audio,
            progress: progress,
          ),
        ),
      );
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      // ── A. PowerUpBuyPopup: Insufficient Coins Toast ───────────────────────
      await tester.tap(find.byKey(const ValueKey('hud_level_up_btn')));
      await tester.pump(const Duration(milliseconds: 220));
      expect(find.byType(PowerUpBuyPopup), findsOneWidget);

      await tester.tap(find.text('600').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PowerUpBuyPopup), findsOneWidget);
      expect(progress.coins, 100);
      expect(find.text('Not enough coins!'), findsOneWidget);
      expect(audio.blockedHaptics, greaterThanOrEqualTo(1));

      // Let toast auto-dismiss
      await tester.pump(const Duration(milliseconds: 2200));

      // ── B. PowerUpBuyPopup: Offline ("No internet connection!") Toast ──────
      AdsManager.enableAds = true;
      AdsManager.mockInternetCheck = () async => false;

      await tester.tap(find.text('Watch').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PowerUpBuyPopup), findsOneWidget);
      expect(progress.levelUpCount, 0);
      expect(find.text('No internet connection!'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2200));

      // ── C. PowerUpBuyPopup: Online but No Ad Fill ("No ads available right now!")
      AdsManager.mockInternetCheck = () async => true;
      AdsManager.mockRewardResult = false;
      AdsManager.mockRewardFailReason = RewardedAdFailReason.noAdsAvailable;

      await tester.tap(find.text('Watch').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(PowerUpBuyPopup), findsOneWidget);
      expect(progress.levelUpCount, 0);
      expect(find.text('No ads available right now!'), findsOneWidget);

      // Close PowerUpBuyPopup
      final closeBtn = find.descendant(
        of: find.byType(PowerUpBuyPopup),
        matching: find.byType(UnitySpriteButton),
      );
      await tester.tap(closeBtn.first);
      await tester.pump(const Duration(milliseconds: 2200));
      expect(find.byType(PowerUpBuyPopup), findsNothing);

      // ── D. LoseOverlay (Revive): Insufficient Coins & Offline Ad Toasts ───
      final game = tester
          .widget<GameWidget<BlockOrderGame>>(
            find.byType(GameWidget<BlockOrderGame>),
          )
          .game!;
      game.onTimeExpired();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.byType(LoseOverlay), findsOneWidget);

      // Tap unaffordable 450 coin button -> shows "Not enough coins!" toast
      await tester.tap(find.text('450').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LoseOverlay), findsOneWidget);
      expect(find.text('Not enough coins!'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2200));

      // Tap "Continue" Watch Ad while offline -> shows "No internet connection!" toast
      AdsManager.mockInternetCheck = () async => false;
      AdsManager.mockRewardResult = null;
      await tester.tap(find.text('Continue').last);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(LoseOverlay), findsOneWidget);
      expect(find.text('No internet connection!'), findsOneWidget);
    },
  );

  testWidgets(
    '4. Time Freeze Frost_Gradient R8 mask renders 100% transparent center (fixes dark/black screen bug)',
    (tester) async {
      // 1. Verify GPU pixel math on exact Frost_Gradient.png center (0,0,0,255) & corner (141,0,3,255)
      final filter = UnityChannelMaskFilters.redChannelAlphaTint(
        const Color(0xCC99F0FF),
        alphaScale: 1.15,
      );

      final imgData = await tester.runAsync(() async {
        // Build a 2x1 test texture: pixel 0 = (0,0,0,255) center, pixel 1 = (141,0,3,255) corner
        final srcRecorder = ui.PictureRecorder();
        final srcCanvas = Canvas(srcRecorder);
        srcCanvas.drawRect(
          const Rect.fromLTWH(0, 0, 1, 1),
          Paint()..color = const Color.fromARGB(255, 0, 0, 0),
        );
        srcCanvas.drawRect(
          const Rect.fromLTWH(1, 0, 1, 1),
          Paint()..color = const Color.fromARGB(255, 141, 0, 3),
        );
        final srcImg = await srcRecorder.endRecording().toImage(2, 1);

        // Composite onto bright gameplay purple (0xFF47279B) using `filter`
        final dstRecorder = ui.PictureRecorder();
        final dstCanvas = Canvas(dstRecorder);
        dstCanvas.drawRect(
          const Rect.fromLTWH(0, 0, 2, 1),
          Paint()..color = const Color(0xFF47279B),
        );
        dstCanvas.drawImage(
          srcImg,
          Offset.zero,
          Paint()..colorFilter = filter,
        );
        final outImg = await dstRecorder.endRecording().toImage(2, 1);
        final bytes =
            await outImg.toByteData(format: ui.ImageByteFormat.rawRgba);
        return bytes!.buffer.asUint8List();
      });

      // Pixel 0 (center where Frost_Gradient R=0): MUST match pure 0xFF47279B (R=71, G=39, B=155) — ZERO black darkening!
      expect(imgData![0], closeTo(0x47, 2));
      expect(imgData[1], closeTo(0x27, 2));
      expect(imgData[2], closeTo(0x9B, 2));
      expect(imgData[3], 255);

      // Pixel 1 (corner where Frost_Gradient R=141): MUST brighten towards icy cyan (#99F0FF), strictly brighter than base purple!
      expect(imgData[4], greaterThan(0x47));
      expect(imgData[5], greaterThan(0x80));
      expect(imgData[6], greaterThan(0xB0));

      // 2. Verify GameplayScreen mounts `time_freeze_frost_vignette` with `colorFilter` (and `tint == null`)
      await _preloadGameTestAssets(tester);
      final repo = await tester.runAsync(() => LevelRepository.loadFromAssets());
      final palette =
          await tester.runAsync(() => BlockOrderPalette.loadFromAssets());
      final settings =
          await tester.runAsync(() => PieceVisualSettings.loadFromAssets());

      SharedPreferences.setMockInitialValues({
        'bo_current_level': 28,
        'bo_highest_level': 28,
        'bo_coins': 500,
        'bo_pu_time_freeze': 2,
        'bo_seen_mechanics': [
          'ice',
          'dud',
          'arrows',
          'pinned',
          'pu_level_up',
          'pu_time_freeze',
        ],
      });
      final progress = PlayerProgressService();
      await tester.runAsync(() => progress.init());

      await tester.binding.setSurfaceSize(const Size(540, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            repository: repo!,
            palette: palette!,
            visualSettings: settings!,
            audio: _SilentAudioService(),
            progress: progress,
          ),
        ),
      );
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      final game = tester
          .widget<GameWidget<BlockOrderGame>>(
            find.byType(GameWidget<BlockOrderGame>),
          )
          .game!;

      // 5. Right upon entering the level (0 moves made, timer NOT started yet),
      // `canUseTimeFreeze` MUST already be true and tapping `hud_time_freeze_btn` MUST activate!
      expect(game.movesCount, 0);
      expect(game.isTimerStartedNotifier.value, isFalse);
      expect(game.canUseTimeFreeze, isTrue);
      expect(progress.timeFreezeCount, 2);

      await tester.tap(find.byKey(const ValueKey('hud_time_freeze_btn')));
      for (int i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      expect(progress.timeFreezeCount, 1);
      expect(game.isTimeFrozen, isTrue);
      expect(game.timeFreezeNotifier.value, greaterThan(18.0));

      final vignetteFinder =
          find.byKey(const ValueKey('time_freeze_frost_vignette'));
      expect(vignetteFinder, findsOneWidget);
      final vignetteWidget = tester.widget<UnityNineSlice>(vignetteFinder);
      expect(vignetteWidget.tint, isNull);
      expect(vignetteWidget.colorFilter, isNotNull);
    },
  );

  testWidgets(
    '5. Analytics Event QA Fixes: Single dispatch (zero duplicate rows) & complete FTUE tut_action funnel (ftue_loading_start -> ftue_loading_finish -> tut_start -> action_1..3 -> tut_finish)',
    (tester) async {
      await _preloadGameTestAssets(tester);
      final repo = await tester.runAsync(() => LevelRepository.loadFromAssets());
      final palette =
          await tester.runAsync(() => BlockOrderPalette.loadFromAssets());
      final settings =
          await tester.runAsync(() => PieceVisualSettings.loadFromAssets());

      // Intercept Flutter FirebaseAnalytics channel to prove ZERO duplicate direct calls
      const firebaseChannel =
          MethodChannel('plugins.flutter.io/firebase_analytics');
      final firebaseDirectCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(firebaseChannel, (call) async {
        firebaseDirectCalls.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(firebaseChannel, null);
      });

      final loggedEvents = <(String name, Map<String, Object?> params)>[];
      AnalyticsService.debugEventObserver = (name, params) {
        loggedEvents.add((name, params));
      };

      // ── Fresh Install / app_clear_data FTUE Session ────────────────────────
      SharedPreferences.setMockInitialValues({});
      final progress = PlayerProgressService();
      await tester.runAsync(() => progress.init());
      expect(progress.isFtueCompleted, isFalse);

      // Simulate exact `main.dart` `_initializeAll()` FTUE boot sequence
      final logFtueLoading = progress.consumeFtueLoadingIfPending();
      expect(logFtueLoading, isTrue);
      // Second call in same/later session must NOT re-consume FTUE loading
      expect(progress.consumeFtueLoadingIfPending(), isFalse);

      AnalyticsService.logLoadingStart(placement: 'splash');
      if (logFtueLoading) {
        AnalyticsService.logTutorial(name: 'ftue_loading_start', value: 1);
      }
      AnalyticsService.logLoadingFinish(
        placement: 'splash',
        success: true,
        value: 1.71,
      );
      if (logFtueLoading) {
        AnalyticsService.logTutorial(name: 'ftue_loading_finish', value: 2);
      }

      // Mount GameplayScreen on cold boot into Level 1
      await tester.binding.setSurfaceSize(const Size(540, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            repository: repo!,
            palette: palette!,
            visualSettings: settings!,
            audio: _SilentAudioService(),
            progress: progress,
          ),
        ),
      );
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      // Verify exact startup funnel BEFORE any touch:
      // 1x loading_start -> 1x ftue_loading_start -> 1x loading_finish ->
      // 1x ftue_loading_finish -> 1x level_start (level: 1) -> 1x tut_start
      expect(
        loggedEvents.map((e) => e.$1).toList(),
        [
          'loading_start',
          'tut_action',
          'loading_finish',
          'tut_action',
          'level_start',
          'tut_action',
        ],
      );
      expect(
        loggedEvents
            .where((e) => e.$1 == 'tut_action')
            .map((e) => (e.$2['name'], e.$2['value']))
            .toList(),
        [
          ('ftue_loading_start', 1),
          ('ftue_loading_finish', 2),
          ('tut_start', 3),
        ],
      );
      expect(
        loggedEvents.where((e) => e.$1 == 'loading_finish').length,
        1,
      );
      expect(
        loggedEvents.where((e) => e.$1 == 'level_start').length,
        1,
      );

      final game = tester
          .widget<GameWidget<BlockOrderGame>>(
            find.byType(GameWidget<BlockOrderGame>),
          )
          .game!;

      // Helper to drag a piece from `(fromCol, fromRow)` to `(toCol, toRow)` on GameWidget
      final gameOrigin =
          tester.getTopLeft(find.byType(GameWidget<BlockOrderGame>));
      Future<void> dragPieceCells(
        int fromCol,
        int fromRow,
        int toCol,
        int toRow,
      ) async {
        final start = gameOrigin + game.debugCellCenterCanvas(fromCol, fromRow);
        final end = gameOrigin + game.debugCellCenterCanvas(toCol, toRow);
        final gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 16));
        const steps = 14;
        for (int s = 1; s <= steps; s++) {
          final t = s / steps;
          await gesture.moveTo(Offset.lerp(start, end, t)!);
          await tester.pump(const Duration(milliseconds: 24));
        }
        await gesture.up();
        for (int i = 0; i < 16; i++) {
          await tester.pump(const Duration(milliseconds: 32));
        }
      }

      // A non-merging nudge on Level 1 must NOT prematurely emit `action_1`!
      final twoPiecesInitial =
          game.debugPieces.where((p) => p.model.number == 2).toList();
      expect(twoPiecesInitial.length, 2);
      // Find a `2` piece and nudge it 1 cell into empty space if available
      final p2First = twoPiecesInitial.last;
      await dragPieceCells(
        p2First.model.col,
        p2First.model.row,
        p2First.model.col,
        (p2First.model.row - 1).clamp(0, 4),
      );
      expect(
        loggedEvents
            .where((e) => e.$1 == 'tut_action')
            .map((e) => e.$2['name'])
            .toList(),
        ['ftue_loading_start', 'ftue_loading_finish', 'tut_start'],
      );

      // Step 1 Merge: `2 + 2 -> 4` -> emits `action_1` (value: 4)
      final twos = game.debugPieces.where((p) => p.model.number == 2).toList();
      await dragPieceCells(
        twos[1].model.col,
        twos[1].model.row,
        twos[0].model.col,
        twos[0].model.row,
      );
      expect(
        loggedEvents
            .where((e) => e.$1 == 'tut_action')
            .map((e) => (e.$2['name'], e.$2['value']))
            .last,
        ('action_1', 4),
      );

      // Step 2 Merge: `4 + 4 -> 8` -> emits `action_2` (value: 5)
      final fours = game.debugPieces.where((p) => p.model.number == 4).toList();
      expect(fours.length, 2);
      await dragPieceCells(
        fours[1].model.col,
        fours[1].model.row,
        fours[0].model.col,
        fours[0].model.row,
      );
      expect(
        loggedEvents
            .where((e) => e.$1 == 'tut_action')
            .map((e) => (e.$2['name'], e.$2['value']))
            .last,
        ('action_2', 5),
      );

      // Step 3 Merge: `8 + 8 -> 16` -> emits `action_3` (value: 6), then win sequence -> `tut_finish` (value: 7)
      final eights =
          game.debugPieces.where((p) => p.model.number == 8).toList();
      expect(eights.length, 2);
      await dragPieceCells(
        eights[1].model.col,
        eights[1].model.row,
        eights[0].model.col,
        eights[0].model.row,
      );

      // Advance past the 2.10s Potion Jar Win Sequence so `_handleLevelWon` fires
      for (int i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }

      // Verify full ordered FTUE `tut_action` sequence from boot to win!
      expect(
        loggedEvents
            .where((e) => e.$1 == 'tut_action')
            .map((e) => (e.$2['name'], e.$2['value']))
            .toList(),
        [
          ('ftue_loading_start', 1),
          ('ftue_loading_finish', 2),
          ('tut_start', 3),
          ('action_1', 4),
          ('action_2', 5),
          ('action_3', 6),
          ('tut_finish', 7),
        ],
      );
      expect(progress.isFtueCompleted, isTrue);
      expect(loggedEvents.where((e) => e.$1 == 'level_end').length, 1);
      expect(firebaseDirectCalls, isEmpty);

      // ── Returning Session (Level 2 / FTUE Completed): ZERO duplicate FTUE events ──
      loggedEvents.clear();
      progress.advanceToNextCampaignLevel();
      expect(progress.currentLevel, 2);
      expect(progress.consumeFtueLoadingIfPending(), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            repository: repo,
            palette: palette,
            visualSettings: settings,
            audio: _SilentAudioService(),
            progress: progress,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(loggedEvents.map((e) => e.$1).toList(), ['level_start']);
      expect(loggedEvents.first.$2['level'], 2);
      expect(loggedEvents.where((e) => e.$1 == 'tut_action'), isEmpty);
      expect(firebaseDirectCalls, isEmpty);
    },
  );

  testWidgets(
    '6. Feature (Booster) vs Mechanic unlock popups: "New Feature" grants Claim/+1 & Claim X2/+2 (or X closes to arrow hint), "New Mechanic" shows single "Next Level" button',
    (tester) async {
      await _preloadGameTestAssets(tester);
      final repo = await tester.runAsync(() => LevelRepository.loadFromAssets());
      final palette =
          await tester.runAsync(() => BlockOrderPalette.loadFromAssets());
      final settings =
          await tester.runAsync(() => PieceVisualSettings.loadFromAssets());

      await tester.binding.setSurfaceSize(const Size(540, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // A. Generic custom Booster renders as "New Feature" with Claim + Claim X2
      const customBooster = MechanicUnlockInfo(
        id: 'pu_custom_bomb',
        title: 'Color Bomb',
        note: 'Clears matching tiles on board',
        iconAsset: 'assets/images/PowerUp_LevelUp.png',
        isPowerUp: true,
        unlockRewardCount: 1,
        hudHorizontalOffsetUnity: -135.0,
        analyticsName: 'color_bomb',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MechanicUnlockDialog(
              info: customBooster,
              onDismiss: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('New Feature'), findsWidgets);
      expect(find.text('New Mechanic'), findsNothing);
      expect(find.byKey(const ValueKey('mechanic_claim_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('mechanic_claim_x2_btn')), findsOneWidget);
      expect(find.byKey(const ValueKey('mechanic_next_level_btn')), findsNothing);

      // B. Generic custom Mechanic renders as "New Mechanic" with ONLY 1 long green "Next Level" button
      const customMechanic = MechanicUnlockInfo(
        id: 'mech_chain',
        title: 'Chain Lock',
        note: 'Break the chain to slide',
        iconAsset: 'assets/images/Icon_Mechanic_SingleAxis.png',
      );
      bool mechDismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MechanicUnlockDialog(
              info: customMechanic,
              onDismiss: () => mechDismissed = true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('New Mechanic'), findsWidgets);
      expect(find.text('New Feature'), findsNothing);
      expect(find.text('Next Level'), findsWidgets);
      expect(find.byKey(const ValueKey('mechanic_claim_btn')), findsNothing);
      expect(find.byKey(const ValueKey('mechanic_claim_x2_btn')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mechanic_next_level_btn')));
      await tester.pump();
      expect(mechDismissed, isTrue);

      // C. Closing "New Feature" via `X` keeps inventory unchanged (`3`) & still shows HUD pointer arrow
      SharedPreferences.setMockInitialValues({
        'bo_current_level': 17,
        'bo_highest_level': 17,
        'bo_coins': 500,
      });
      final progress = PlayerProgressService();
      await tester.runAsync(() => progress.init());
      expect(progress.levelUpCount, 3);

      await tester.pumpWidget(
        MaterialApp(
          home: GameplayScreen(
            repository: repo!,
            palette: palette!,
            visualSettings: settings!,
            audio: _SilentAudioService(),
            progress: progress,
          ),
        ),
      );
      for (int i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      expect(find.byType(MechanicUnlockDialog), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mechanic_close_btn')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MechanicUnlockDialog), findsNothing);
      expect(progress.levelUpCount, 3);
      expect(progress.coins, 500);
      expect(
        find.byKey(const ValueKey('booster_hud_arrow_hint')),
        findsOneWidget,
      );
    },
  );
}
