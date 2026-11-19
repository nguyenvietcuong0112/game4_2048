import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/remote_config_service.dart';
import 'unity_ui_kit.dart';

class MechanicUnlockInfo {
  final String id;
  final String title;
  final String subtitle;
  final String note;
  final String iconAsset;
  final bool isPowerUp;
  final bool isLevelUpPowerUp;
  final BoosterType? boosterType;
  final int unlockRewardCount;
  final double hudHorizontalOffsetUnity;
  final String analyticsName;

  bool get isMechanic => !isPowerUp;

  const MechanicUnlockInfo({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.note,
    required this.iconAsset,
    this.isPowerUp = false,
    this.isLevelUpPowerUp = false,
    this.boosterType,
    this.unlockRewardCount = 1,
    this.hudHorizontalOffsetUnity = 0.0,
    this.analyticsName = '',
  });

  static const ice = MechanicUnlockInfo(
    id: 'ice',
    title: 'Ice Blocks',
    note: 'Merge up to the number on the ice to free it!',
    iconAsset: 'assets/images/Icon_Mechanic_Ice.png',
  );

  static const dud = MechanicUnlockInfo(
    id: 'dud',
    title: 'Dud Blocks',
    note: "Duds can't merge, but you can slide them out of the way!",
    iconAsset: 'assets/images/Icon_Mechanic_Blocker.png',
  );

  static const pinned = MechanicUnlockInfo(
    id: 'pinned',
    title: 'Stationary Blocks',
    note: "Stationary blocks can't move, but you can merge with them!",
    iconAsset: 'assets/images/Icon_Mechanic_Cage.png',
  );

  static const arrows = MechanicUnlockInfo(
    id: 'arrows',
    title: 'Arrow Blocks',
    note: 'Arrow Blocks only move in the direction of the arrows!',
    iconAsset: 'assets/images/Icon_Mechanic_SingleAxis.png',
  );

  static const levelUpPowerUp = MechanicUnlockInfo(
    id: RemoteConfigService.boosterIdLevelUp,
    title: 'Level Up',
    subtitle: 'New power-up unlocked!',
    note: 'Merge a matching pair instantly, wherever they are!',
    iconAsset: 'assets/images/PowerUp_LevelUp.png',
    isPowerUp: true,
    isLevelUpPowerUp: true,
    boosterType: BoosterType.levelUp,
    unlockRewardCount: 1,
    hudHorizontalOffsetUnity: -402.0,
    analyticsName: 'level_up',
  );

  static const timeFreezePowerUp = MechanicUnlockInfo(
    id: RemoteConfigService.boosterIdTimeFreeze,
    title: 'Time Freeze',
    subtitle: 'New power-up unlocked!',
    note: 'Freezes the timer for 20 seconds',
    iconAsset: 'assets/images/PowerUp_TimeFreeze.png',
    isPowerUp: true,
    isLevelUpPowerUp: false,
    boosterType: BoosterType.timeFreeze,
    unlockRewardCount: 1,
    hudHorizontalOffsetUnity: -206.0,
    analyticsName: 'time_freeze',
  );

  static const shufflePowerUp = MechanicUnlockInfo(
    id: RemoteConfigService.boosterIdShuffle,
    title: 'Shuffle',
    subtitle: 'New power-up unlocked!',
    note: 'Shuffles unlocked block numbers to create fresh merges!',
    iconAsset: '',
    isPowerUp: true,
    isLevelUpPowerUp: false,
    boosterType: BoosterType.shuffle,
    unlockRewardCount: 1,
    hudHorizontalOffsetUnity: -10.0,
    analyticsName: 'shuffle',
  );

  static const hammerPowerUp = MechanicUnlockInfo(
    id: RemoteConfigService.boosterIdHammer,
    title: 'Hammer',
    subtitle: 'New power-up unlocked!',
    note: 'Split any block (4+) into two 1x1 half-value blocks!',
    iconAsset: '',
    isPowerUp: true,
    isLevelUpPowerUp: false,
    boosterType: BoosterType.hammer,
    unlockRewardCount: 1,
    hudHorizontalOffsetUnity: 186.0,
    analyticsName: 'hammer',
  );

  static MechanicUnlockInfo forBoosterType(BoosterType type) {
    switch (type) {
      case BoosterType.levelUp:
        return levelUpPowerUp;
      case BoosterType.timeFreeze:
        return timeFreezePowerUp;
      case BoosterType.shuffle:
        return shufflePowerUp;
      case BoosterType.hammer:
        return hammerPowerUp;
    }
  }
}

/// Shared glossy 3D cartoon booster icon widget used across HUD buttons,
/// `PowerUpBuyPopup`, `PowerUpFreeUnlockOverlay`, and `WaterGardenView`:
/// - `levelUp` / `timeFreeze`: existing PNG sprites
/// - `shuffle` / `hammer`: custom-painted high-DPI glossy cartoon icons matching the exact visual language
class BoosterIconWidget extends StatelessWidget {
  final BoosterType type;
  final double size;

  const BoosterIconWidget({
    super.key,
    required this.type,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case BoosterType.levelUp:
        return Image.asset(
          'assets/images/PowerUp_LevelUp.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        );
      case BoosterType.timeFreeze:
        return Image.asset(
          'assets/images/PowerUp_TimeFreeze.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
        );
      case BoosterType.shuffle:
        return SizedBox(
          width: size,
          height: size,
          child: const CustomPaint(
            painter: _ShuffleBoosterIconPainter(),
          ),
        );
      case BoosterType.hammer:
        return SizedBox(
          width: size,
          height: size,
          child: const CustomPaint(
            painter: _HammerBoosterIconPainter(),
          ),
        );
    }
  }
}

class _ShuffleBoosterIconPainter extends CustomPainter {
  const _ShuffleBoosterIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    if (s <= 1.0) return;

    canvas.save();
    canvas.translate((size.width - s) * 0.5, (size.height - s) * 0.5);

    const outlineColor = Color(0xFF1A1048);

    // Helper to build a thick curved ribbon arrow + head along cubic bezier
    void drawRibbonArrow({
      required Offset start,
      required Offset c1,
      required Offset c2,
      required Offset end,
      required Offset tip,
      required Offset wingA,
      required Offset wingB,
      required List<Color> gradientColors,
      required Color highlightColor,
    }) {
      final strokeW = s * 0.145;
      final outlineW = strokeW + s * 0.068;

      final curvePath = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);

      final headPath = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(wingA.dx, wingA.dy)
        ..lineTo(wingB.dx, wingB.dy)
        ..close();

      // Soft dark drop shadow
      canvas.save();
      canvas.translate(0, s * 0.035);
      canvas.drawPath(
        curvePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = outlineW
          ..color = const Color(0x5508041C),
      );
      canvas.drawPath(
        headPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s * 0.085
          ..color = const Color(0x5508041C),
      );
      canvas.restore();

      // Bold cartoon dark outline
      canvas.drawPath(
        curvePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = outlineW
          ..color = outlineColor,
      );
      canvas.drawPath(
        headPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s * 0.082
          ..color = outlineColor,
      );

      // Glossy gradient body fill
      final gradPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ).createShader(Rect.fromLTWH(0, 0, s, s));

      canvas.drawPath(
        curvePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeW
          ..shader = gradPaint.shader,
      );
      canvas.drawPath(
        headPath,
        Paint()
          ..style = PaintingStyle.fill
          ..shader = gradPaint.shader,
      );
      canvas.drawPath(
        headPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s * 0.025
          ..shader = gradPaint.shader,
      );

      // Crisp specular gloss ribbon along top
      canvas.save();
      canvas.translate(0, -s * 0.022);
      canvas.drawPath(
        curvePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeW * 0.28
          ..color = highlightColor,
      );
      canvas.restore();
    }

    // Back crossing ribbon: Top-Left -> Bottom-Right (Warm Golden Orange)
    drawRibbonArrow(
      start: Offset(s * 0.14, s * 0.28),
      c1: Offset(s * 0.44, s * 0.28),
      c2: Offset(s * 0.48, s * 0.72),
      end: Offset(s * 0.72, s * 0.72),
      tip: Offset(s * 0.90, s * 0.72),
      wingA: Offset(s * 0.67, s * 0.56),
      wingB: Offset(s * 0.67, s * 0.88),
      gradientColors: const [
        Color(0xFFFFF59D),
        Color(0xFFFFB703),
        Color(0xFFEA580C),
      ],
      highlightColor: Colors.white.withValues(alpha: 0.68),
    );

    // Front crossing ribbon: Bottom-Left -> Top-Right (Electric Cyan / Emerald)
    drawRibbonArrow(
      start: Offset(s * 0.14, s * 0.72),
      c1: Offset(s * 0.44, s * 0.72),
      c2: Offset(s * 0.48, s * 0.28),
      end: Offset(s * 0.72, s * 0.28),
      tip: Offset(s * 0.90, s * 0.28),
      wingA: Offset(s * 0.67, s * 0.12),
      wingB: Offset(s * 0.67, s * 0.44),
      gradientColors: const [
        Color(0xFFA5F3FC),
        Color(0xFF00E5FF),
        Color(0xFF0284C7),
      ],
      highlightColor: Colors.white.withValues(alpha: 0.78),
    );

    // 4-point cartoon sparkle star at top-left & center-top
    _drawMiniSparkle(canvas, Offset(s * 0.30, s * 0.14), s * 0.085);
    _drawMiniSparkle(canvas, Offset(s * 0.84, s * 0.50), s * 0.062);

    canvas.restore();
  }

  void _drawMiniSparkle(Canvas canvas, Offset c, double r) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r * 0.18, c.dy - r * 0.18, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + r * 0.18, c.dy + r * 0.18, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - r * 0.18, c.dy + r * 0.18, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - r * 0.18, c.dy - r * 0.18, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _ShuffleBoosterIconPainter oldDelegate) => false;
}

class _HammerBoosterIconPainter extends CustomPainter {
  const _HammerBoosterIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    if (s <= 1.0) return;

    canvas.save();
    canvas.translate(size.width * 0.5, size.height * 0.52);

    // Soft drop shadow behind whole angled mallet
    canvas.save();
    canvas.translate(0, s * 0.04);
    canvas.rotate(-0.72);
    final shadowPaint = Paint()..color = const Color(0x5508041C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, s * 0.14),
          width: s * 0.21,
          height: s * 0.66,
        ),
        Radius.circular(s * 0.10),
      ),
      shadowPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -s * 0.22),
          width: s * 0.64,
          height: s * 0.34,
        ),
        Radius.circular(s * 0.11),
      ),
      shadowPaint,
    );
    canvas.restore();

    canvas.rotate(-0.72);

    const outlineColor = Color(0xFF1A1048);
    final outlineStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeJoin = StrokeJoin.round
      ..color = outlineColor;

    // 1. Warm Wooden Handle
    final handleRect = Rect.fromCenter(
      center: Offset(0, s * 0.14),
      width: s * 0.165,
      height: s * 0.60,
    );
    final handleRRect =
        RRect.fromRectAndRadius(handleRect, Radius.circular(s * 0.082));
    canvas.drawRRect(handleRRect, outlineStroke);
    canvas.drawRRect(
      handleRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFFFD08A),
            Color(0xFFD9772B),
            Color(0xFF7C2D12),
          ],
          stops: [0.0, 0.52, 1.0],
        ).createShader(handleRect),
    );
    // Handle specular streak
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          handleRect.left + s * 0.028,
          handleRect.top + s * 0.08,
          s * 0.032,
          handleRect.height * 0.68,
        ),
        Radius.circular(s * 0.02),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.42),
    );

    // Golden handle pommel ring at bottom
    final pommelRect = Rect.fromCenter(
      center: Offset(0, s * 0.40),
      width: s * 0.21,
      height: s * 0.095,
    );
    final pommelRRect =
        RRect.fromRectAndRadius(pommelRect, Radius.circular(s * 0.045));
    canvas.drawRRect(pommelRRect, outlineStroke);
    canvas.drawRRect(
      pommelRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF59D), Color(0xFFFFB300), Color(0xFFB45309)],
        ).createShader(pommelRect),
    );

    // 2. Chunky Metallic-Silver & Crimson-Gold Mallet Head
    final headRect = Rect.fromCenter(
      center: Offset(0, -s * 0.22),
      width: s * 0.58,
      height: s * 0.30,
    );
    final headRRect =
        RRect.fromRectAndRadius(headRect, Radius.circular(s * 0.09));
    canvas.drawRRect(headRRect, outlineStroke);
    canvas.drawRRect(
      headRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFF8A65),
            Color(0xFFE53935),
            Color(0xFF991B1B),
          ],
          stops: [0.0, 0.52, 1.0],
        ).createShader(headRect),
    );

    // Metallic silver-steel striking caps on left & right ends
    for (final side in [-1.0, 1.0]) {
      final capRect = Rect.fromCenter(
        center: Offset(side * s * 0.255, -s * 0.22),
        width: s * 0.13,
        height: s * 0.335,
      );
      final capRRect =
          RRect.fromRectAndRadius(capRect, Radius.circular(s * 0.055));
      canvas.drawRRect(capRRect, outlineStroke);
      canvas.drawRRect(
        capRRect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8FAFC),
              Color(0xFF93C5FD),
              Color(0xFF3B5998),
            ],
            stops: [0.0, 0.5, 1.0],
          ).createShader(capRect),
      );
      // Tiny highlight bar on steel cap
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            capRect.left + s * 0.025,
            capRect.top + s * 0.032,
            capRect.width - s * 0.05,
            s * 0.052,
          ),
          Radius.circular(s * 0.025),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.85),
      );
    }

    // Central golden band wrapping the mallet barrel
    final bandRect = Rect.fromCenter(
      center: Offset(0, -s * 0.22),
      width: s * 0.155,
      height: s * 0.315,
    );
    final bandRRect =
        RRect.fromRectAndRadius(bandRect, Radius.circular(s * 0.04));
    canvas.drawRRect(bandRRect, outlineStroke);
    canvas.drawRRect(
      bandRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF59D),
            Color(0xFFFFB703),
            Color(0xFFD97706),
          ],
        ).createShader(bandRect),
    );

    // Glossy white highlight across top of head
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -s * 0.315),
          width: s * 0.32,
          height: s * 0.052,
        ),
        Radius.circular(s * 0.026),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.65),
    );

    canvas.restore();

    // Golden impact sparkle near top-right striking cap
    final cx = size.width * 0.82;
    final cy = size.height * 0.24;
    final r = s * 0.088;
    final star = Path()
      ..moveTo(cx, cy - r)
      ..quadraticBezierTo(cx + r * 0.2, cy - r * 0.2, cx + r, cy)
      ..quadraticBezierTo(cx + r * 0.2, cy + r * 0.2, cx, cy + r)
      ..quadraticBezierTo(cx - r * 0.2, cy + r * 0.2, cx - r, cy)
      ..quadraticBezierTo(cx - r * 0.2, cy - r * 0.2, cx, cy - r)
      ..close();
    canvas.drawPath(star, Paint()..color = const Color(0xFFFFF59D));
  }

  @override
  bool shouldRepaint(covariant _HammerBoosterIconPainter oldDelegate) => false;
}

/// Circular Booster HUD Button (`Play_Scene.png` & `Play_Scene 2.png`):
/// - Supports all 4 boosters (`LevelUp`, `TimeFreeze`, `Shuffle`, `Hammer`) across 4 balanced footer slots!
/// - Unlocked: `Powerup_Base.png` + `BoosterIconWidget` + corner `PowerUp_Amount.png` / `PowerUp_Plus.png` / `PowerUp_Free.png`
/// - Locked: `Powerup_Base_Locked.png` + `Icon_Padlock_Silver.png` above `"Lv.X"` label
/// Shared between `GameplayScreen` HUD and `PowerUpFreeUnlockOverlay` for pixel-identical alignment.
class UnityPowerUpHudButton extends StatefulWidget {
  static const double scaledUnitySize = 168.0;
  static const double horizontalOffsetUnity = 135.0;
  static const List<double> slotOffsetsUnity = <double>[
    -402.0,
    -206.0,
    -10.0,
    186.0,
  ];
  static const double bottomOffsetUnity = 76.0;
  static const double footerTopLineUnity = 160.0;

  final BoosterType? boosterType;
  final bool isLevelUp;
  final bool isUnlocked;
  final int? unlockLevel;
  final bool isFree;
  final int count;
  final bool isActionable;
  final bool isHighlighted;
  final bool isActiveTargeting;
  final VoidCallback? onTap;

  const UnityPowerUpHudButton({
    super.key,
    this.boosterType,
    this.isLevelUp = true,
    required this.isUnlocked,
    this.unlockLevel,
    required this.isFree,
    required this.count,
    required this.isActionable,
    this.isHighlighted = false,
    this.isActiveTargeting = false,
    required this.onTap,
  });

  BoosterType get resolvedBoosterType =>
      boosterType ?? (isLevelUp ? BoosterType.levelUp : BoosterType.timeFreeze);

  @override
  State<UnityPowerUpHudButton> createState() => _UnityPowerUpHudButtonState();
}

class _UnityPowerUpHudButtonState extends State<UnityPowerUpHudButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final type = widget.resolvedBoosterType;
    // Interactive whenever onTap is provided (when locked, tapping triggers "Unlock at level X!" toast)
    final interactive = widget.onTap != null;
    final sz = ux(context, UnityPowerUpHudButton.scaledUnitySize);
    final k = UnityPowerUpHudButton.scaledUnitySize / 208.0;

    // Visual dim ONLY when unlocked, `count > 0` (`!isFree`), and game state doesn't permit usage yet
    // (when `count == 0`, tapping `+` is ALWAYS actionable to open `PowerUpBuyView`!).
    final dimUnavailable = widget.isUnlocked &&
        !widget.isFree &&
        widget.count > 0 &&
        !widget.isActionable &&
        !widget.isHighlighted &&
        !widget.isActiveTargeting;

    Widget content = SizedBox(
      width: sz,
      height: sz,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (!widget.isUnlocked) ...[
            // Locked State: metallic grey circle + padlock above `"Lv.X"` label inside the circle
            Image.asset(
              'assets/images/Powerup_Base_Locked.png',
              width: ux(context, 204.0 * k),
              height: ux(context, 204.0 * k),
              fit: BoxFit.contain,
            ),
            Positioned(
              top: ux(context, 40.0 * k),
              child: Image.asset(
                'assets/images/Icon_Padlock_Silver.png',
                width: ux(context, 68.0 * k),
                height: ux(context, 85.0 * k),
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: ux(context, 128.0 * k),
              width: ux(context, 122.0 * k),
              height: ux(context, 38.0 * k),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: UnitySdfText(
                    'Lv.${widget.unlockLevel ?? RemoteConfigService.unlockLevelForBoosterType(type)}',
                    unityFontSize: 28.0,
                    material: UnityTextMaterial.lockedBoosterLabel,
                    singleTextNode: true,
                  ),
                ),
              ),
            ),
          ] else ...[
            // Optional FTUE `SelectedHighlight_01` cyan/green glow OR active Hammer targeting amber glow
            if (widget.isHighlighted || widget.isActiveTargeting)
              Positioned(
                left: -ux(context, 34),
                right: -ux(context, 34),
                top: -ux(context, 34),
                bottom: -ux(context, 34),
                child: IgnorePointer(
                  child: Image.asset(
                    'assets/images/Glow_02.png',
                    fit: BoxFit.contain,
                    color: widget.isActiveTargeting
                        ? const Color(0xF0FFB300)
                        : const Color(0xE63CFFB0),
                    colorBlendMode: BlendMode.modulate,
                  ),
                ),
              ),

            // 1. Unlocked Gold-Rimmed Blue Circle (`Powerup_Base.png`)
            Image.asset(
              'assets/images/Powerup_Base.png',
              width: sz,
              height: sz,
              fit: BoxFit.contain,
            ),

            // Active targeting ring around the button rim when Hammer is armed
            if (widget.isActiveTargeting)
              IgnorePointer(
                child: Container(
                  width: sz,
                  height: sz,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFFFE57F),
                      width: ux(context, 7.0),
                    ),
                  ),
                ),
              ),

            // 2. Centered Booster Icon (`LevelUp` / `TimeFreeze` / `Shuffle` / `Hammer`)
            Transform.translate(
              offset: Offset(
                0,
                -ux(context, type == BoosterType.levelUp ? 1.5 : 2.5),
              ),
              child: Opacity(
                opacity: dimUnavailable ? 0.58 : 1.0,
                child: BoosterIconWidget(
                  type: type,
                  size: ux(
                    context,
                    (type == BoosterType.levelUp ? 126.0 : 132.0) * k,
                  ),
                ),
              ),
            ),

            // 3A. Free FTUE Badge (`PowerUp_Free.png`)
            if (widget.isFree)
              Positioned(
                bottom: ux(context, 2.0),
                child: Image.asset(
                  'assets/images/PowerUp_Free.png',
                  width: ux(context, 148.0 * k),
                  height: ux(context, 51.0 * k),
                  fit: BoxFit.contain,
                ),
              )
            // 3B. Empty Inventory `+` Badge (`PowerUp_Plus.png` at bottom-right)
            else if (widget.count <= 0)
              Positioned(
                right: 0,
                bottom: 0,
                child: Image.asset(
                  'assets/images/PowerUp_Plus.png',
                  width: ux(context, 69.0 * k),
                  height: ux(context, 69.0 * k),
                  fit: BoxFit.contain,
                ),
              )
            // 3C. Red Numeric Amount Badge (`PowerUp_Amount.png` at bottom-right)
            else
              Positioned(
                right: 0,
                bottom: 0,
                width: ux(context, 69.0 * k),
                height: ux(context, 69.0 * k),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/images/PowerUp_Amount.png',
                      width: ux(context, 69.0 * k),
                      height: ux(context, 69.0 * k),
                      fit: BoxFit.contain,
                    ),
                    Transform.translate(
                      offset: Offset(0, -ux(context, 1.0)),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: UnitySdfText(
                          '${widget.count}',
                          unityFontSize: 32.0,
                          material: UnityTextMaterial.pinkBadge,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );

    if (!interactive) {
      return IgnorePointer(child: content);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.91 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: content,
      ),
    );
  }
}

/// Unified Unlock Popup (`884x1044` Unity px) supporting both feature categories:
/// - **Boosters (`info.isPowerUp == true`) — `New Feature`**:
///   - Header ribbon: `"New Feature"`
///   - Single centered green `"Claim"` (+1) button (`top = 725`, `520x221`)
/// - **Mechanics (`info.isPowerUp == false`) — `New Mechanic`**:
///   - Header ribbon: `"New Mechanic"`
///   - Single centered long green `"Next Level"` button (`top = 725`, `560x221`)
class MechanicUnlockDialog extends StatefulWidget {
  final MechanicUnlockInfo info;
  final VoidCallback onDismiss;
  final VoidCallback? onClaim;
  final VoidCallback? onClaimX2;
  final VoidCallback? onNextLevel;
  final VoidCallback? onClose;

  const MechanicUnlockDialog({
    super.key,
    required this.info,
    required this.onDismiss,
    this.onClaim,
    this.onClaimX2,
    this.onNextLevel,
    this.onClose,
  });

  @override
  State<MechanicUnlockDialog> createState() => _MechanicUnlockDialogState();
}

class _MechanicUnlockDialogState extends State<MechanicUnlockDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  void _handleClaim() => (widget.onClaim ?? widget.onDismiss).call();
  void _handleNextLevel() =>
      (widget.onNextLevel ?? widget.onClaim ?? widget.onDismiss).call();
  void _handleClose() => (widget.onClose ?? widget.onDismiss).call();

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final isBooster = info.isPowerUp;
    final headerTitle = isBooster ? 'New Feature' : 'New Mechanic';
    final ribbonWidthUnity = isBooster ? 558.0 : 576.0;

    return AnimatedBuilder(
      animation: _entranceCtrl,
      builder: (context, cardChild) {
        final raw = _entranceCtrl.value.clamp(0.0, 1.0);
        final scrimAlpha = 0.80 * Curves.easeOut.transform(raw);
        final t = Curves.easeOutBack.transform(raw);
        return ColoredBox(
          color: Color.fromRGBO(6, 4, 20, scrimAlpha),
          child: SafeArea(
            child: Center(
              child: Transform.scale(
                scale: 0.84 + 0.16 * t,
                child: Opacity(
                  opacity: raw,
                  child: cardChild,
                ),
              ),
            ),
          ),
        );
      },
      child: SizedBox(
        key: const ValueKey('new_feature_popup_card'),
              width: ux(context, 884),
              height: ux(context, 1044),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 1. Gold-Rimmed Royal-Blue Popup Body (`popup_bg.png`, `884x1021` at `top = 23`)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: ux(context, 23),
                    height: ux(context, 1021),
                    child: Image.asset(
                      'assets/images/popup_bg.png',
                      width: ux(context, 884),
                      height: ux(context, 1021),
                      fit: BoxFit.fill,
                    ),
                  ),

                  // 2. Cream Inner Content Well (`frame_content.png`, `784x495` at `left = 50, top = 167`)
                  Positioned(
                    left: ux(context, 50),
                    top: ux(context, 167),
                    width: ux(context, 784),
                    height: ux(context, 495),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/frame_content.png',
                          fit: BoxFit.fill,
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            ux(context, 40),
                            ux(context, 22),
                            ux(context, 40),
                            ux(context, 24),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Top Brown Feature/Mechanic Title (`info.title`)
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  info.title,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontFamily: 'Baloo2',
                                    fontSize: ux(context, 56),
                                    fontWeight: FontWeight.w800,
                                    fontVariations: const [
                                      FontVariation('wght', 800),
                                    ],
                                    color: const Color(0xFF5A270B),
                                    height: 1.08,
                                  ),
                                ),
                              ),

                              SizedBox(height: ux(context, 10)),

                              // Center Booster / Mechanic Icon
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: ux(context, 4),
                                  ),
                                  child: info.boosterType != null
                                      ? Center(
                                          child: BoosterIconWidget(
                                            type: info.boosterType!,
                                            size: ux(context, 228),
                                          ),
                                        )
                                      : Image.asset(
                                          info.iconAsset,
                                          fit: BoxFit.contain,
                                        ),
                                ),
                              ),

                              SizedBox(height: ux(context, 10)),

                              // Bottom Brown Description (`info.note`)
                              Text(
                                info.note,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Baloo2',
                                  fontSize: ux(context, 40),
                                  fontWeight: FontWeight.w800,
                                  fontVariations: const [
                                    FontVariation('wght', 800),
                                  ],
                                  color: const Color(0xFF5A270B),
                                  height: 1.12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3. Bottom Action Button:
                  //    - Boosters (`New Feature`): Single centered green "Claim"
                  //    - Mechanics (`New Mechanic`): Single centered long green "Next Level"
                  if (isBooster)
                    Positioned(
                      left: ux(context, (884 - 520) * 0.5),
                      top: ux(context, 725),
                      width: ux(context, 520),
                      height: ux(context, 221),
                      child: _UnlockPillButton(
                        buttonKey: const ValueKey('mechanic_claim_btn'),
                        sprite: 'Button_Green.png',
                        useNineSlice: true,
                        label: 'Claim',
                        unityFontSize: 64,
                        material: UnityTextMaterial.ctaGreen,
                        textPadding: EdgeInsets.only(
                          left: ux(context, 44),
                          right: ux(context, 44),
                          bottom: ux(context, 12),
                        ),
                        onTap: _handleClaim,
                      ),
                    )
                  else
                    Positioned(
                      left: ux(context, (884 - 560) * 0.5),
                      top: ux(context, 725),
                      width: ux(context, 560),
                      height: ux(context, 221),
                      child: _UnlockPillButton(
                        buttonKey: const ValueKey('mechanic_next_level_btn'),
                        sprite: 'Button_Green.png',
                        useNineSlice: true,
                        label: 'Next Level',
                        unityFontSize: 64,
                        material: UnityTextMaterial.ctaGreen,
                        textPadding: EdgeInsets.only(
                          left: ux(context, 44),
                          right: ux(context, 44),
                          bottom: ux(context, 12),
                        ),
                        onTap: _handleNextLevel,
                      ),
                    ),

                  // 4. Top Header Ribbon (`Frame_Popup_Title.png`, `"New Feature"` or `"New Mechanic"`)
                  Positioned(
                    left: ux(context, (884 - ribbonWidthUnity) * 0.5),
                    top: 0,
                    width: ux(context, ribbonWidthUnity),
                    height: ux(context, 143),
                    child: IgnorePointer(
                      child: UnityNineSlice(
                        sprite: 'Frame_Popup_Title.png',
                        padding: EdgeInsets.fromLTRB(
                          ux(context, 40),
                          ux(context, 8),
                          ux(context, 40),
                          ux(context, 16),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: UnitySdfText(
                            headerTitle,
                            unityFontSize: isBooster ? 64 : 62,
                            material: UnityTextMaterial.popupTitle,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 5. Top-Right Red-Gold Close Button (`Button_Close.png`, `139x139` at `right = 14, top = 4`)
                  Positioned(
                    right: ux(context, 14),
                    top: ux(context, 4),
                    width: ux(context, 139),
                    height: ux(context, 139),
                    child: UnitySpriteButton(
                      key: const ValueKey('mechanic_close_btn'),
                      asset: 'Button_Close.png',
                      unitySize: 139,
                      onTap: _handleClose,
                    ),
                  ),
                ],
              ),
            ),
          );
  }
}

class _UnlockPillButton extends StatefulWidget {
  final Key buttonKey;
  final String sprite;
  final bool useNineSlice;
  final String label;
  final double unityFontSize;
  final UnityTextMaterial material;
  final EdgeInsetsGeometry textPadding;
  final VoidCallback onTap;

  const _UnlockPillButton({
    required this.buttonKey,
    required this.sprite,
    this.useNineSlice = false,
    required this.label,
    required this.unityFontSize,
    required this.material,
    required this.textPadding,
    required this.onTap,
  });

  @override
  State<_UnlockPillButton> createState() => _UnlockPillButtonState();
}

class _UnlockPillButtonState extends State<_UnlockPillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: widget.buttonKey,
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: widget.useNineSlice
                  ? UnityNineSlice(
                      sprite: widget.sprite,
                      pixelMultiplier: 1.0,
                    )
                  : Image.asset(
                      'assets/images/${widget.sprite}',
                      fit: BoxFit.fill,
                    ),
            ),
            Padding(
              padding: widget.textPadding,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: UnitySdfText(
                  widget.label,
                  unityFontSize: widget.unityFontSize,
                  material: widget.material,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fullscreen Booster Unlock Spotlight Overlay shown when reaching a booster's unlock level:
/// - Semi-transparent dark dim backdrop over the live gameplay board
/// - Top bold yellow booster title (`UnityTextMaterial.ctaYellow`)
/// - Center luminous booster icon with our existing `effect_outerglow.webp` + `effect_star.png`
/// - Crisp white description text directly below (`UnityTextMaterial.tutorialText`)
/// - Elevated bottom `UnityPowerUpHudButton` at its exact HUD coordinates with green `FREE` badge
///
/// Interaction:
/// - Tapping the highlighted `FREE` booster button activates the free turn immediately.
/// - Tapping anywhere outside dismisses the overlay while keeping the `FREE` turn pending on the HUD!
class PowerUpFreeUnlockOverlay extends StatefulWidget {
  final MechanicUnlockInfo info;
  final int currentCount;
  final double? hudHorizontalOffsetUnity;
  final VoidCallback onUseFreePowerUp;
  final VoidCallback onDismissOutside;

  const PowerUpFreeUnlockOverlay({
    super.key,
    required this.info,
    required this.currentCount,
    this.hudHorizontalOffsetUnity,
    required this.onUseFreePowerUp,
    required this.onDismissOutside,
  });

  @override
  State<PowerUpFreeUnlockOverlay> createState() =>
      _PowerUpFreeUnlockOverlayState();
}

class _PowerUpFreeUnlockOverlayState extends State<PowerUpFreeUnlockOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final AnimationController _idleCtrl;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    _idleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _idleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final isLevelUp = info.isLevelUpPowerUp;
    final safePadding = MediaQuery.paddingOf(context);
    final bottomReserve = safePadding.bottom +
        ux(
          context,
          UnityPowerUpHudButton.bottomOffsetUnity +
              UnityPowerUpHudButton.scaledUnitySize +
              36,
        );

    return AnimatedBuilder(
      animation: _entranceCtrl,
      builder: (context, child) {
        final raw = _entranceCtrl.value.clamp(0.0, 1.0);
        final scrimAlpha = 0.78 * Curves.easeOut.transform(raw);
        final pop = Curves.easeOutBack.transform(raw);
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            // 1. Tap-outside dark dim scrim (dismisses overlay while keeping FREE turn!)
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('booster_unlock_outside_backdrop'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDismissOutside,
                child: ColoredBox(
                  color: Color.fromRGBO(7, 5, 26, scrimAlpha),
                ),
              ),
            ),

            // 2. Center showcase: Title + glowing booster icon + description (tapping falls through to backdrop)
            Positioned(
              left: 0,
              right: 0,
              top: safePadding.top + ux(context, 48),
              bottom: bottomReserve,
              child: IgnorePointer(
                child: Opacity(
                  opacity: raw,
                  child: Transform.scale(
                    scale: 0.86 + 0.14 * pop,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(flex: 2),

                        // Booster Title (`LEVEL UP` / `TIME FREEZE`)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: ux(context, 48),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: UnitySdfText(
                              info.title.toUpperCase(),
                              unityFontSize: 104,
                              material: UnityTextMaterial.ctaYellow,
                            ),
                          ),
                        ),

                        const Spacer(flex: 2),

                        // Glowing Booster Icon (`effect_outerglow.webp` + `effect_star.png` + booster graphic)
                        Flexible(
                          flex: 6,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _FtueHeroIllustration(
                              controller: _idleCtrl,
                              iconAsset: info.iconAsset,
                              boosterType: info.boosterType,
                              iconUnityWidth: 320,
                              iconUnityHeight: 320,
                            ),
                          ),
                        ),

                        const Spacer(flex: 1),

                        // Crisp Outlined Description Text
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: ux(context, 76),
                          ),
                          child: UnitySdfText(
                            info.note,
                            unityFontSize: 48,
                            material: UnityTextMaterial.tutorialText,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                          ),
                        ),

                        const Spacer(flex: 3),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 3. Elevated Highlighted Booster Button with `FREE` badge at pixel-exact HUD position!
            Positioned(
              left: 0,
              right: 0,
              bottom: safePadding.bottom +
                  ux(context, UnityPowerUpHudButton.bottomOffsetUnity),
              child: Center(
                child: Transform.translate(
                  offset: Offset(
                    ux(
                      context,
                      widget.hudHorizontalOffsetUnity ??
                          info.hudHorizontalOffsetUnity,
                    ),
                    0,
                  ),
                  child: AnimatedBuilder(
                    animation: _idleCtrl,
                    builder: (context, btnChild) {
                      final pulse =
                          1.0 + 0.032 * math.sin(_idleCtrl.value * math.pi * 4);
                      return Transform.scale(
                        scale: (0.88 + 0.12 * pop) * pulse,
                        child: btnChild,
                      );
                    },
                    child: UnityPowerUpHudButton(
                      key: ValueKey(
                        'ftue_free_${info.analyticsName.isNotEmpty ? info.analyticsName : (isLevelUp ? 'level_up' : 'time_freeze')}_btn',
                      ),
                      boosterType: info.boosterType,
                      isLevelUp: isLevelUp,
                      isUnlocked: true,
                      isFree: true,
                      count: widget.currentCount,
                      isActionable: true,
                      isHighlighted: true,
                      onTap: widget.onUseFreePowerUp,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FtueHeroIllustration extends StatelessWidget {
  final AnimationController controller;
  final String iconAsset;
  final BoosterType? boosterType;
  final double iconUnityWidth;
  final double iconUnityHeight;

  const _FtueHeroIllustration({
    required this.controller,
    required this.iconAsset,
    this.boosterType,
    required this.iconUnityWidth,
    required this.iconUnityHeight,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final phase = controller.value * math.pi * 2;
        final pulse = 1.0 + 0.04 * math.sin(phase);
        final starTwinkle =
            (0.72 + 0.28 * math.sin(phase * 2.0)).clamp(0.0, 1.0);
        return SizedBox(
          width: ux(context, 760),
          height: ux(context, 480),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 1. Soft Outer Glow (`effect_outerglow.webp`)
              Positioned(
                left: -ux(context, 120),
                right: -ux(context, 120),
                top: -ux(context, 210),
                bottom: -ux(context, 210),
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: pulse,
                    child: Image.asset(
                      'assets/images/effect_outerglow.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              // 2. Golden 4-Point Sparkle Stars (`effect_star.png`)
              IgnorePointer(
                child: Opacity(
                  opacity: starTwinkle,
                  child: Transform.scale(
                    scale: 0.97 + 0.05 * math.sin(phase),
                    child: Image.asset(
                      'assets/images/effect_star.png',
                      width: ux(context, 660),
                      height: ux(context, 495),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              // 3. Center Booster Icon
              Transform.scale(
                scale: 0.98 + 0.03 * pulse,
                child: boosterType != null
                    ? BoosterIconWidget(
                        type: boosterType!,
                        size: ux(context, iconUnityWidth),
                      )
                    : Image.asset(
                        iconAsset,
                        width: ux(context, iconUnityWidth),
                        height: ux(context, iconUnityHeight),
                        fit: BoxFit.contain,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Non-blocking animated pointer arrow rendered directly above a newly unlocked
/// bottom HUD booster button once its `New Feature` popup is dismissed.
class PowerUpHudArrowHint extends StatefulWidget {
  final double horizontalOffsetUnity;

  const PowerUpHudArrowHint({
    super.key,
    required this.horizontalOffsetUnity,
  });

  @override
  State<PowerUpHudArrowHint> createState() => _PowerUpHudArrowHintState();
}

class _PowerUpHudArrowHintState extends State<PowerUpHudArrowHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final phase = _ctrl.value * math.pi * 2;
          final bobY = ux(context, 16.0 * math.sin(phase));
          final wobbleRot = 0.045 * math.sin(phase * 0.5);
          return Transform.translate(
            offset: Offset(
              ux(context, widget.horizontalOffsetUnity),
              bobY,
            ),
            child: Transform.rotate(
              angle: wobbleRot,
              child: child,
            ),
          );
        },
        child: Image.asset(
          'assets/images/PowerUp_Icon_Arrow.png',
          width: ux(context, 92),
          height: ux(context, 188),
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
