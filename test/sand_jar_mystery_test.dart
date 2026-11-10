import 'dart:ui' as ui;
import 'package:flame/extensions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:block_order_2048/game/sand_jar_component.dart';
import 'package:block_order_2048/models/palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'MagicSandJarComponent: Potion Pouch Jar renders with target goal tag and fills without error',
    (tester) async {
      late final BlockOrderPalette palette;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
      });
      final style = palette.styleFor(number: 64, isFrozen: false);

      final jar = MagicSandJarComponent(
        style: style,
        levelNumber: 5,
        targetNumber: 4096,
        centerPosition: Vector2(200, 200),
        jarWidth: 120,
        jarHeight: 160,
        initialAppearProgress: 1.0,
      );

      expect(jar.targetNumber, 4096);
      jar.updateTargetNumber(2048);
      expect(jar.targetNumber, 2048);
      jar.updateTargetNumber(4096);
      expect(jar.fillProgress, 0.0);
      expect(jar.appearProgress, 1.0);
      expect(jar.isOpened, isFalse);

      // Test rendering on PictureRecorder canvas in idle Mystery Jar mode (fillProgress == 0.0)
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 400));
      jar.update(0.016);
      jar.render(canvas);
      final pic = recorder.endRecording();
      expect(pic, isNotNull);

      // Test transition to winning fill sequence
      jar.setWinSequenceState(
        appearProgress: 1.0,
        fillProgress: 0.50,
        glowIntensity: 0.50,
        shakeIntensity: 0.30,
        openProgress: 0.0,
      );
      expect(jar.fillProgress, 0.50);

      final recorderFill = ui.PictureRecorder();
      final canvasFill = Canvas(recorderFill, const Rect.fromLTWH(0, 0, 400, 400));
      jar.update(0.016);
      jar.render(canvasFill);
      final picFill = recorderFill.endRecording();
      expect(picFill, isNotNull);

      // Test opening state
      jar.setWinSequenceState(
        appearProgress: 1.0,
        fillProgress: 1.0,
        glowIntensity: 1.0,
        shakeIntensity: 0.0,
        openProgress: 0.65,
      );
      expect(jar.isOpened, isTrue);

      final recorderOpen = ui.PictureRecorder();
      final canvasOpen = Canvas(recorderOpen, const Rect.fromLTWH(0, 0, 400, 400));
      jar.update(0.016);
      jar.render(canvasOpen);
      final picOpen = recorderOpen.endRecording();
      expect(picOpen, isNotNull);
    },
  );

  testWidgets(
    'BoardSandStreamToJarVfx: Wide base tapers down smoothly to narrow jar mouth and renders without error',
    (tester) async {
      late final BlockOrderPalette palette;
      await tester.runAsync(() async {
        palette = await BlockOrderPalette.loadFromAssets();
      });
      final style = palette.styleFor(number: 128, isFrozen: false);

      final vfx = BoardSandStreamToJarVfx(
        finalTileCenter: Vector2(100, 500),
        boardOrigins: [Vector2(100, 500)],
        targetMouthProvider: () => Vector2(250, 150),
        style: style,
        cellSize: 50.0,
      );

      // Render across animation lifecycle
      for (double t = 0.0; t <= 1.30; t += 0.20) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 600, 800));
        vfx.update(0.20);
        vfx.render(canvas);
        final pic = recorder.endRecording();
        expect(pic, isNotNull);
      }
    },
  );
}
