import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_order_2048/services/audio_haptics_service.dart';
import 'package:block_order_2048/services/player_progress_service.dart';
import 'package:block_order_2048/ui/water_garden_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'WaterGardenView renders all 5 3D vase shapes, 5 flower types, pouring, and 100% bloom cleanly',
    (tester) async {
      final configs = <VaseMilestoneConfig>[
        for (int id = 1; id <= 5; id++) VaseMilestoneConfig.getForVaseId(id),
      ];

      expect(configs.map((c) => c.shapeType).toSet().length, 5);
      expect(configs.map((c) => c.flowerType).toSet().length, 5);

      for (final config in configs) {
        // 1. Mid-progress pouring state (bud + pouring waterfall + rising water)
        final partialResult = VaseStepAdvanceResult(
          vaseId: config.vaseId,
          oldStep: 0,
          newStep: 1,
          totalSteps: config.totalSteps,
          oldProgress: 0.0,
          newProgress: 0.45,
          didReach100Percent: false,
          config: config,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 420,
                  height: 860,
                  child: WaterGardenView(
                    key: ValueKey('partial_${config.vaseId}'),
                    advanceResult: partialResult,
                    finalBlockNumber: 2048,
                    levelNumber: config.startLevel,
                    onNextLevel: () {},
                    onClaimMilestone: () {},
                    playEntranceAnim: false,
                  ),
                ),
              ),
            ),
          ),
        );

        // Pump through jar enter, mid-pour waterfall & crown splash, and resting bud
        await tester.pump(const Duration(milliseconds: 520));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 800));
        expect(tester.takeException(), isNull);

        // 2. 100% Bloom Celebration + New Mechanic / Bouquet state
        final fullResult = VaseStepAdvanceResult(
          vaseId: config.vaseId,
          oldStep: config.totalSteps - 1,
          newStep: config.totalSteps,
          totalSteps: config.totalSteps,
          oldProgress: 0.80,
          newProgress: 1.0,
          didReach100Percent: true,
          config: config,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 420,
                  height: 860,
                  child: WaterGardenView(
                    key: ValueKey('bloom_${config.vaseId}'),
                    advanceResult: fullResult,
                    finalBlockNumber: 4096,
                    levelNumber: config.endLevel,
                    onNextLevel: () {},
                    onClaimMilestone: () {},
                    playEntranceAnim: false,
                  ),
                ),
              ),
            ),
          ),
        );

        // Pump through pouring, sunburst rays, 3D petals unfurling & floating petals
        await tester.pump(const Duration(milliseconds: 650));
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pump(const Duration(milliseconds: 1100));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'WaterGardenView plays pour, progressive flower grow, full bloom, and new vase reveal SFX cues',
    (tester) async {
      final audio = AudioHapticsService();
      addTearDown(audio.dispose);
      audio.clearDebugLogs();

      final cfg = VaseMilestoneConfig.getForVaseId(2);
      final growResult = VaseStepAdvanceResult(
        vaseId: 2,
        oldStep: 1,
        newStep: 2,
        totalSteps: cfg.totalSteps,
        oldProgress: 0.20,
        newProgress: 0.40,
        didReach100Percent: false,
        config: cfg,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaterGardenView(
              key: const ValueKey('sfx_grow'),
              advanceResult: growResult,
              finalBlockNumber: 1024,
              audio: audio,
              onNextLevel: () {},
              onClaimMilestone: () {},
              playEntranceAnim: false,
            ),
          ),
        ),
      );

      for (int i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(audio.debugPlayedSfxLog, contains('sfx_water_stream.wav'));
      expect(audio.debugPlayedSfxLog, contains('new_8.mp3'));

      audio.clearDebugLogs();
      final bloomResult = VaseStepAdvanceResult(
        vaseId: 2,
        oldStep: 4,
        newStep: 5,
        totalSteps: cfg.totalSteps,
        oldProgress: 0.80,
        newProgress: 1.0,
        didReach100Percent: true,
        config: cfg,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaterGardenView(
              key: const ValueKey('sfx_bloom'),
              advanceResult: bloomResult,
              finalBlockNumber: 2048,
              audio: audio,
              onNextLevel: () {},
              onClaimMilestone: () {},
              playEntranceAnim: false,
            ),
          ),
        ),
      );

      for (int i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(audio.debugPlayedSfxLog, contains('sfx_water_stream.wav'));
      expect(audio.debugPlayedSfxLog, contains('sfx_win_complete.wav'));
      expect(audio.debugPlayedSfxLog, contains('new_11.mp3'));

      await tester.tap(find.text('Claim').last);
      await tester.pump();
      expect(audio.debugPlayedSfxLog, contains('new_9.mp3'));
    },
  );
}
