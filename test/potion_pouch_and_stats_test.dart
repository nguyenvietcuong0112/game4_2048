import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_order_2048/game/piece_component.dart';
import 'package:block_order_2048/game/sand_jar_component.dart';
import 'package:block_order_2048/models/level_models.dart';
import 'package:block_order_2048/models/palette.dart';
import 'package:block_order_2048/models/unity_curve.dart';
import 'package:block_order_2048/ui/win_overlay.dart';
import 'package:flame/extensions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Potion Pouch Jar renders plump idle & pouring states with target goal tag',
    (tester) async {
      late final BlockOrderPalette palette;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
      });
      final style = palette.styleFor(number: 64, isFrozen: false);

      const jarHeight = 160.0;
      const jarWidth = jarHeight * 1.12;
      final jar = MagicSandJarComponent(
        style: style,
        levelNumber: 4,
        targetNumber: 4096,
        centerPosition: Vector2(200, 200),
        jarWidth: jarWidth,
        jarHeight: jarHeight,
      );

      expect(jar.targetNumber, 4096);
      expect(jar.size.x, greaterThan(jar.size.y));
      expect(jar.mouthWorldPos.y, lessThan(jar.position.y));

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Render idle closed pouch
      expect(jar.fillProgress, 0.0);
      jar.update(0.10);
      jar.render(canvas);

      // Render pouring parted curtains + rising liquid + ripples
      jar.setWinSequenceState(
        fillProgress: 0.48,
        glowIntensity: 0.25,
        shakeIntensity: 0.0,
        openProgress: 0.0,
      );
      expect(jar.fillProgress, 0.48);
      jar.update(0.10);
      jar.render(canvas);

      final pic = recorder.endRecording();
      pic.dispose();
    },
  );

  testWidgets(
    'Crystal-glass PieceComponent animates gentle idle wave at rest and stronger slosh on click/drag',
    (tester) async {
      late final BlockOrderPalette palette;
      late final PieceVisualSettings visualSettings;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
        visualSettings = await PieceVisualSettings.loadFromAssets();
      });

      final model = PieceModel(
        id: 1,
        key: '64',
        col: 1,
        row: 2,
        localCells: const [(0, 0), (1, 0)],
        number: 64,
      );

      final piece = PieceComponent(
        model: model,
        cellSize: 78.0,
        palette: palette,
        visualSettings: visualSettings,
        boardOrigin: Vector2(40, 120),
      );

      expect(piece.isVisuallyAtRest, isTrue);

      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      piece.update(0.10);
      piece.render(canvas);

      // Static glass back-shell sprite is baked & used while gentle live wave renders on top
      expect(piece.debugHasStaticBakedSprite, isTrue);
      expect(piece.debugUsedStaticSpriteLastRender, isTrue);

      // Clicking/tapping activates stronger sloshing wave (`isVisuallyAtRest == false`)
      piece.triggerTapSquish();
      expect(piece.isVisuallyAtRest, isFalse);
      piece.update(0.016);
      piece.render(canvas);
      expect(piece.debugUsedStaticSpriteLastRender, isFalse);

      // Dragging also activates stronger sloshing wave + dynamic glass rendering
      piece.beginDragging();
      piece.setDragTargetWorld(Vector2(150, 276));
      piece.update(0.016);
      piece.render(canvas);
      expect(piece.isVisuallyAtRest, isFalse);
      expect(piece.debugUsedStaticSpriteLastRender, isFalse);

      rec.endRecording().dispose();
    },
  );

  testWidgets(
    'WinOverlay displays Time, Moves, and Combo stats matching media_1794007597111.png',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WinOverlay(
              levelLabel: 'Level 4',
              rewardCoins: 25,
              timeFormatted: '01:55',
              movesCount: 32,
              comboCount: 13,
              onNextLevel: () {},
            ),
          ),
        ),
      );

      // Advance past Stage 1 (0.92s) into Stage 2
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 200));

      // Verify labels and formatted stats values appear in the widget tree
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('01:55'), findsOneWidget);
      expect(find.text('Moves'), findsOneWidget);
      expect(find.text('32'), findsOneWidget);
      expect(find.text('Combo'), findsOneWidget);
      expect(find.text('13'), findsOneWidget);
    },
  );

  testWidgets(
    'Unbroken BoardSandStreamToJarVfx plunges seamlessly into MagicSandJarComponent with foreground occlusion',
    (tester) async {
      late final BlockOrderPalette palette;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
      });
      final style4096 = palette.styleFor(number: 4096, isFrozen: false);

      final jar = MagicSandJarComponent(
        style: style4096,
        levelNumber: 4,
        targetNumber: 4096,
        centerPosition: Vector2(220, 180),
        jarWidth: 168 * 1.12,
        jarHeight: 168,
      );

      final stream = BoardSandStreamToJarVfx(
        finalTileCenter: Vector2(230, 420),
        boardOrigins: [Vector2(230, 420)],
        targetMouthProvider: () => jar.mouthWorldPos,
        style: style4096,
        cellSize: 76.0,
        jar: jar,
      );

      expect(stream.archSideSign, 1.0);
      expect(jar.liquidSurfaceWorldPos.y, greaterThan(jar.mouthWorldPos.y));

      jar.setWinSequenceState(
        appearProgress: 1.0,
        fillProgress: 0.45,
        glowIntensity: 0.55,
        shakeIntensity: 0.35,
        openProgress: 0.0,
        curtainOpenProgress: 1.0,
        externalStreamActive: true,
        externalStreamSideSign: stream.archSideSign,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (int i = 0; i < 20; i++) {
        jar.update(0.032);
        stream.update(0.032);
        jar.renderTree(canvas);
        stream.render(canvas);
      }
      recorder.endRecording().dispose();
    },
  );
}
