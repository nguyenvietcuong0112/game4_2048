import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'unity_ui_kit.dart';

class MechanicUnlockInfo {
  final String id;
  final String title;
  final String subtitle;
  final String note;
  final String iconAsset;
  final bool isPowerUp;

  const MechanicUnlockInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.note,
    required this.iconAsset,
    this.isPowerUp = false,
  });

  static const ice = MechanicUnlockInfo(
    id: 'ice',
    title: 'Ice Blocks',
    subtitle: 'New mechanic unlocked!',
    note: 'Merge up to the number on the ice to free it!',
    iconAsset: 'assets/images/Icon_Mechanic_Ice.png',
  );

  static const dud = MechanicUnlockInfo(
    id: 'dud',
    title: 'Dud Blocks',
    subtitle: 'New mechanic unlocked!',
    note: "Duds can't merge, but you can slide them out of the way!",
    iconAsset: 'assets/images/Icon_Mechanic_Blocker.png',
  );

  static const pinned = MechanicUnlockInfo(
    id: 'pinned',
    title: 'Stationary Blocks',
    subtitle: 'New mechanic unlocked!',
    note: "Stationary blocks can't move, but you can merge with them!",
    iconAsset: 'assets/images/Icon_Mechanic_Cage.png',
  );

  static const arrows = MechanicUnlockInfo(
    id: 'arrows',
    title: 'Arrow Blocks',
    subtitle: 'New mechanic unlocked!',
    note: 'Arrow Blocks only move in the direction of the arrows!',
    iconAsset: 'assets/images/Icon_Mechanic_SingleAxis.png',
  );

  static const levelUpPowerUp = MechanicUnlockInfo(
    id: 'pu_level_up',
    title: 'Level Up',
    subtitle: 'New power-up unlocked!',
    note: 'Merge a matching pair instantly, wherever they are!',
    iconAsset: 'assets/images/PowerUp_LevelUp.png',
    isPowerUp: true,
  );

  static const timeFreezePowerUp = MechanicUnlockInfo(
    id: 'pu_time_freeze',
    title: 'Time Freeze',
    subtitle: 'New power-up unlocked!',
    note: 'Freezes the timer for 20 seconds!',
    iconAsset: 'assets/images/PowerUp_TimeFreeze.png',
    isPowerUp: true,
  );
}

/// Authentic replica of Unity `MechanicFTUE.prefab` & `PowerUpFTUEView.prefab`:
/// - `#0F204A(a=0.97)` full-screen backdrop
/// - `"New mechanic unlocked!"` / `"New power-up unlocked!"` (`Baloo2_ExtraBold_Tutorial_Text`)
/// - Golden hero title (`Baloo2_ExtraBold_CTA_Yellow_Text`)
/// - `#FF82B2` `Glow_02.png` + twinkling `Sparkle_01.png` behind large illustration
/// - 9-slice `Box_Text.png` info card with `#06269A` `Baloo2` note
/// - 9-slice `Button_CTA.png` `"Continue"` button
class MechanicUnlockDialog extends StatefulWidget {
  final MechanicUnlockInfo info;
  final VoidCallback onDismiss;

  const MechanicUnlockDialog({
    super.key,
    required this.info,
    required this.onDismiss,
  });

  @override
  State<MechanicUnlockDialog> createState() => _MechanicUnlockDialogState();
}

class _MechanicUnlockDialogState extends State<MechanicUnlockDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static const List<(double, double, double, double)> _sparkles = [
    (-2.45, 225, 24, 0.0),
    (-1.75, 200, 18, 0.35),
    (-1.05, 232, 30, 0.15),
    (-0.35, 228, 22, 0.65),
    (0.42, 238, 28, 0.85),
    (2.55, 235, 26, 0.45),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;

    return Container(
      color: const Color(0xF70F204A),
      child: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.78, end: 1.0),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          builder: (context, pop, child) => Transform.scale(
            scale: pop,
            child: Opacity(
              opacity: pop.clamp(0.0, 1.0),
              child: child,
            ),
          ),
          child: Column(
            children: [
              const Spacer(flex: 3),

              // 1. Subtitle (`New mechanic unlocked!`) + Golden Title (`Ice Blocks`, etc.)
              UnitySdfText(
                info.subtitle,
                unityFontSize: 56,
                material: UnityTextMaterial.tutorialText,
              ),
              SizedBox(height: ux(context, 14)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: ux(context, 48)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: UnitySdfText(
                    info.title,
                    unityFontSize: 108,
                    material: UnityTextMaterial.ctaYellow,
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // 2. Rose-Gold Halo (`Glow_02.png`) + `Sparkle_01.png` + Hero Illustration
              AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final pulse = 1.0 + 0.04 * math.sin(_ctrl.value * math.pi * 2);
                  return SizedBox(
                    width: ux(context, 650),
                    height: ux(context, 560),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Transform.scale(
                          scale: pulse,
                          child: Image.asset(
                            'assets/images/Glow_02.png',
                            width: ux(context, 640),
                            height: ux(context, 640),
                            color: const Color(0xEBFF82B2),
                            colorBlendMode: BlendMode.modulate,
                          ),
                        ),
                        for (final (ang, dist, sz, phase) in _sparkles)
                          Builder(
                            builder: (_) {
                              final tw = 0.35 +
                                  0.65 *
                                      (0.5 +
                                          0.5 *
                                              math.sin(
                                                (_ctrl.value + phase) * math.pi * 2,
                                              ));
                              final r = ux(context, dist);
                              final s = ux(context, sz * 1.55);
                              return Transform.translate(
                                offset: Offset(math.cos(ang) * r, math.sin(ang) * r),
                                child: Opacity(
                                  opacity: tw.clamp(0.0, 1.0),
                                  child: Image.asset(
                                    'assets/images/Sparkle_01.png',
                                    width: s,
                                    height: s,
                                  ),
                                ),
                              );
                            },
                          ),
                        Transform.scale(
                          scale: 0.98 + 0.03 * pulse,
                          child: SizedBox(
                            width: ux(context, 360),
                            height: ux(context, 360),
                            child: Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: [
                                if (info.isPowerUp)
                                  Image.asset(
                                    'assets/images/Powerup_Base.png',
                                    width: ux(context, 340),
                                    height: ux(context, 340),
                                  ),
                                Image.asset(
                                  info.iconAsset,
                                  width: ux(context, info.isPowerUp ? 270 : 340),
                                  height: ux(context, info.isPowerUp ? 270 : 340),
                                  fit: BoxFit.contain,
                                ),
                                if (info.isPowerUp)
                                  Positioned(
                                    bottom: ux(context, 6),
                                    right: ux(context, 8),
                                    child: Image.asset(
                                      'assets/images/PowerUp_Free.png',
                                      width: ux(context, 134),
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const Spacer(flex: 2),

              // 3. 9-Slice `Box_Text.png` Card (`#06269A` note text)
              UnityNineSlice(
                sprite: 'Box_Text.png',
                width: ux(context, 860),
                padding: EdgeInsets.symmetric(
                  horizontal: ux(context, 56),
                  vertical: ux(context, 42),
                ),
                child: Text(
                  info.note,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontSize: ux(context, 50),
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: const Color(0xFF06269A),
                    height: 1.24,
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // 4. 9-Slice `Button_CTA.png` `"Continue"`
              UnityCtaButton(
                label: 'Continue',
                unityWidth: 572,
                unityHeight: 160,
                unityFontSize: 80,
                onTap: widget.onDismiss,
              ),

              const Spacer(flex: 4),
            ],
          ),
        ),
      ),
    );
  }
}
