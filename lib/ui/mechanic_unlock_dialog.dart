import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../game/vfx_components.dart';
import 'unity_ui_kit.dart';

class MechanicUnlockInfo {
  final String id;
  final String title;
  final String subtitle;
  final String note;
  final String iconAsset;
  final bool isPowerUp;
  final bool isLevelUpPowerUp;

  const MechanicUnlockInfo({
    required this.id,
    required this.title,
    this.subtitle = '',
    required this.note,
    required this.iconAsset,
    this.isPowerUp = false,
    this.isLevelUpPowerUp = false,
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
    id: 'pu_level_up',
    title: 'Level Up',
    subtitle: 'New power-up unlocked!',
    note: 'Merge a matching pair instantly, wherever they are!',
    iconAsset: 'assets/images/PowerUp_LevelUp.png',
    isPowerUp: true,
    isLevelUpPowerUp: true,
  );

  static const timeFreezePowerUp = MechanicUnlockInfo(
    id: 'pu_time_freeze',
    title: 'Time Freeze',
    subtitle: 'New power-up unlocked!',
    note: 'Freezes the timer for 20 seconds',
    iconAsset: 'assets/images/PowerUp_TimeFreeze.png',
    isPowerUp: true,
    isLevelUpPowerUp: false,
  );
}

const List<(double, double, double, double)> _kFtueSparkles = [
  (-2.45, 240, 24, 0.0),
  (-1.75, 214, 18, 0.35),
  (-1.05, 248, 30, 0.15),
  (-0.35, 242, 22, 0.65),
  (0.42, 252, 28, 0.85),
  (2.55, 248, 26, 0.45),
];

/// Exact 1:1 `PowerUpButtonView` (`GameplayView.prefab`: `PowerUps` parent `sc = 0.816`,
/// button `sz = (282.39, 282.39)` at `pos = (±145.10, +6.80)` -> `230.43 x 230.43` Unity px at `X = ±118.40`).
/// Shared between `GameplayScreen` HUD and Step 2 of `PowerUpFtueOverlay` for pixel-identical alignment!
class UnityPowerUpHudButton extends StatefulWidget {
  static const double containerScale = 0.816;
  static const double unscaledSize = 282.39;
  static const double scaledUnitySize = unscaledSize * containerScale; // 230.43
  static const double horizontalOffsetUnity = 145.10 * containerScale; // 118.40

  final bool isLevelUp;
  final bool isUnlocked;
  final bool isFree;
  final int count;
  final bool isActionable;
  final bool isHighlighted;
  final VoidCallback? onTap;

  const UnityPowerUpHudButton({
    super.key,
    required this.isLevelUp,
    required this.isUnlocked,
    required this.isFree,
    required this.count,
    required this.isActionable,
    this.isHighlighted = false,
    required this.onTap,
  });

  @override
  State<UnityPowerUpHudButton> createState() => _UnityPowerUpHudButtonState();
}

class _UnityPowerUpHudButtonState extends State<UnityPowerUpHudButton> {
  bool _pressed = false;

  double _bpx(BuildContext context, double unscaled) =>
      ux(context, unscaled * UnityPowerUpHudButton.containerScale);

  @override
  Widget build(BuildContext context) {
    // Locked buttons (`SetInteractive(false)` in `PowerUpButtonView.SetLockedState`) are completely
    // non-interactive and NEVER show a snackbar or squish!
    final interactive = widget.isUnlocked && widget.onTap != null;
    final sz = _bpx(context, UnityPowerUpHudButton.unscaledSize);

    const baseAsset = 'assets/images/Powerup_Base.png';
    final iconAsset = widget.isLevelUp
        ? (widget.isUnlocked
            ? 'assets/images/PowerUp_LevelUp.png'
            : 'assets/images/PowerUp_LevelUp_Locked.png')
        : (widget.isUnlocked
            ? 'assets/images/PowerUp_TimeFreeze.png'
            : 'assets/images/PowerUp_TimeFreeze_Locked.png');

    // Exact prefab icon sizes inside `282.39 x 282.39` button space:
    // - `LevelUp`: `pos = (0, +10.31)`, `sz = (289.54, 294.46)`
    // - `TimeFreeze`: `pos = (0, +16.70)`, `sz = (215.35, 211.01)`
    final iconW = _bpx(context, widget.isLevelUp ? 268.0 : 215.35);
    final iconH = _bpx(context, widget.isLevelUp ? 272.0 : 211.01);
    final iconOffsetY = _bpx(context, widget.isLevelUp ? -10.31 : -16.70);

    // Visual dim ONLY when unlocked, `count > 0` (`!isFree`), and game state doesn't permit usage yet
    // (when `count == 0`, tapping `+` is ALWAYS actionable to open `PowerUpBuyView`!).
    final dimUnavailable = widget.isUnlocked &&
        !widget.isFree &&
        widget.count > 0 &&
        !widget.isActionable &&
        !widget.isHighlighted;

    Widget content = SizedBox(
      width: sz,
      height: sz,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Optional FTUE Step 2 `SelectedHighlight_01` cyan/green additive glow
          if (widget.isHighlighted)
            Positioned(
              left: -_bpx(context, 48),
              right: -_bpx(context, 48),
              top: -_bpx(context, 48),
              bottom: -_bpx(context, 48),
              child: IgnorePointer(
                child: Image.asset(
                  'assets/images/Glow_02.png',
                  fit: BoxFit.contain,
                  color: const Color(0xE63CFFB0),
                  colorBlendMode: BlendMode.modulate,
                ),
              ),
            ),

          // 1. `Background` (`Powerup_Base.png` / `Powerup_Base_Locked.png`, `pos=(0,-1.28) sz=(221.39, 232.38)`)
          Transform.translate(
            offset: Offset(0, _bpx(context, 1.28)),
            child: Image.asset(
              baseAsset,
              width: _bpx(context, 224.0),
              height: _bpx(context, 234.0),
              fit: BoxFit.contain,
            ),
          ),

          // 2. `Icon` (`PowerUp_LevelUp` / `PowerUp_TimeFreeze`)
          Transform.translate(
            offset: Offset(0, iconOffsetY),
            child: Opacity(
              opacity: dimUnavailable ? 0.58 : 1.0,
              child: Image.asset(
                iconAsset,
                width: iconW,
                height: iconH,
                fit: BoxFit.contain,
              ),
            ),
          ),

          // 3A. Locked Padlock (`Icon_Padlock_Silver.png`, `pos=(+98.20, -71.20)`, `sz=(108.85, 114.30)`)
          if (!widget.isUnlocked)
            Transform.translate(
              offset: Offset(_bpx(context, 84.0), _bpx(context, 66.0)),
              child: Image.asset(
                'assets/images/Icon_Padlock_Silver.png',
                width: _bpx(context, 108.85),
                height: _bpx(context, 114.30),
                fit: BoxFit.contain,
              ),
            )
          // 3B. Free FTUE Badge (`PowerUp_Free.png`, `amin/amax=(0.5, 0)`, `pos=(0, +48.80)`, `sz=(168.40, 57.94)`)
          else if (widget.isFree)
            Positioned(
              bottom: _bpx(context, 18.0),
              child: Image.asset(
                'assets/images/PowerUp_Free.png',
                width: _bpx(context, 172.0),
                height: _bpx(context, 59.0),
                fit: BoxFit.contain,
              ),
            )
          // 3C. Empty Inventory `+` Badge (`PowerUp_Plus.png`, `pos=(+90.30, -79.77)`, `sz=(108.94, 110.94)`)
          else if (widget.count <= 0)
            Transform.translate(
              offset: Offset(_bpx(context, 78.0), _bpx(context, 70.0)),
              child: Image.asset(
                'assets/images/PowerUp_Plus.png',
                width: _bpx(context, 108.94),
                height: _bpx(context, 110.94),
                fit: BoxFit.contain,
              ),
            )
          // 3D. Numeric Amount Badge (`PowerUp_Amount.png`, `pos=(+90.60, -77.20)`, `sz=(108.34, 119.43)`, `fontSize=48.28`)
          else
            Transform.translate(
              offset: Offset(_bpx(context, 78.0), _bpx(context, 68.0)),
              child: SizedBox(
                width: _bpx(context, 108.34),
                height: _bpx(context, 119.43),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/images/PowerUp_Amount.png',
                      width: _bpx(context, 108.34),
                      height: _bpx(context, 119.43),
                      fit: BoxFit.contain,
                    ),
                    Transform.translate(
                      offset: Offset(0, -_bpx(context, 5.5)),
                      child: UnitySdfText(
                        '${widget.count}',
                        unityFontSize:
                            48.28 * UnityPowerUpHudButton.containerScale,
                        material: UnityTextMaterial.pinkBadge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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

/// Exact 1:1 replica of Unity `MechanicFTUE.prefab` (`Ice Blocks` L6, `Dud Blocks` L13,
/// `Arrow Blocks` L21, `Stationary Blocks` L41):
/// - Fullscreen `#0F204A` (`98%` alpha = `0xFA0F204A`) dark backdrop
/// - `SubTitleContainer` is **INACTIVE / HIDDEN** (`active = False` in `MechanicFTUE.prefab`!)
/// - `TitleContainer` at top (`fontSize = 125.5`, `Baloo2_ExtraBold_CTA_Yellow_Text`)
/// - `VFX_Group`: pink `Glow_02.png` (`768.7 x 768.7`) + twinkling `Sparkle_01.png` + `361 x 303` `Icon_Mechanic_*.png`
/// - `InstructionsPanel`: `Box_Text.png` (`897 x 227`) with `#06269A` `Baloo2` (`fontSize = 52`)
/// - `Button_CTA`: `"Continue"` (`583.4 x 185.0`, `fontSize = 90`)
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
      color: const Color(0xFA0F204A),
      child: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.82, end: 1.0),
          duration: const Duration(milliseconds: 280),
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

              // 1. `TitleContainer` (`SubTitleContainer` is inactive/hidden in `MechanicFTUE.prefab`!)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: ux(context, 48)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: UnitySdfText(
                    info.title,
                    unityFontSize: 122,
                    material: UnityTextMaterial.ctaYellow,
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // 2. `VFX_Group` (`Glow_02.png` `768.7 x 768.7` + `Sparkle_01.png`) + `Mechanic_Icon` (`361 x 303`)
              _FtueHeroIllustration(
                controller: _ctrl,
                iconAsset: info.iconAsset,
                iconUnityWidth: 362,
                iconUnityHeight: 312,
              ),

              const Spacer(flex: 2),

              // 3. `InstructionsPanel` (`Box_Text.png`, `897 x 227`, `fontSize = 52`, `#06269A`)
              UnityNineSlice(
                sprite: 'Box_Text.png',
                width: ux(context, 896),
                padding: EdgeInsets.symmetric(
                  horizontal: ux(context, 56),
                  vertical: ux(context, 44),
                ),
                child: Text(
                  info.note,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontSize: ux(context, 52),
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: const Color(0xFF06269A),
                    height: 1.22,
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // 4. `Button_CTA` (`583.4 x 185.0`, `"Continue"`, `fontSize = 90`)
              UnityCtaButton(
                label: 'Continue',
                unityWidth: 583,
                unityHeight: 185,
                unityFontSize: 90,
                onTap: widget.onDismiss,
              ),

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Exact 1:1 2-Step `PowerUpFTUEView.prefab` + `PowerUpTutorialScreenPresenter`:
/// - **Step 1**: Fullscreen `#0F204A` (`98%` alpha), `TitleContainer` (`"Level Up"` / `"Time Freeze"`,
///   `125.5` yellow) **ABOVE** `SubTitleContainer` (`"New power-up unlocked!"`, `62.86` white/blue stroke),
///   pink `Glow_02` + sparkles + bare `PowerUp_*.png` (`475 x 540`, NO base/free badge),
///   `Box_Text.png` instructions, and `"Continue"` button.
/// - **Step 2** (after tapping `"Continue"`): Center card fades out, dark `#0F204A` veil stays active,
///   and the target bottom `UnityPowerUpHudButton` is elevated above the dark veil at its exact bottom
///   HUD coordinates (`X = ∓118.4` Unity px) with `SelectedHighlight_01` glow, `PowerUp_Free.png` `"FREE"`
///   badge, and wobbling `PowerUp_Icon_Arrow.png` (`↓`) pointer arrow! Tapping it immediately executes
///   the free booster without decrementing the player's `3` initial inventory!
class PowerUpFtueOverlay extends StatefulWidget {
  final MechanicUnlockInfo info;
  final VoidCallback? onContinueStep1;
  final VoidCallback onActivateFreePowerUp;

  const PowerUpFtueOverlay({
    super.key,
    required this.info,
    this.onContinueStep1,
    required this.onActivateFreePowerUp,
  });

  @override
  State<PowerUpFtueOverlay> createState() => _PowerUpFtueOverlayState();
}

class _PowerUpFtueOverlayState extends State<PowerUpFtueOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleContinue() {
    if (_step != 0) return;
    widget.onContinueStep1?.call();
    setState(() => _step = 1);
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final isLevelUp = info.isLevelUpPowerUp;

    return Container(
      color: const Color(0xFA0F204A),
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Step 1: Center Unlock Card (`Title` ABOVE `SubTitle`, bare icon, `Box_Text`, `Continue`)
            if (_step == 0)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.82, end: 1.0),
                duration: const Duration(milliseconds: 280),
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

                    // `TitleContainer` ABOVE `SubTitleContainer` (`PowerUpFTUEView.prefab`!)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: ux(context, 48)),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: UnitySdfText(
                          info.title,
                          unityFontSize: 122,
                          material: UnityTextMaterial.ctaYellow,
                        ),
                      ),
                    ),
                    SizedBox(height: ux(context, 10)),
                    UnitySdfText(
                      info.subtitle,
                      unityFontSize: 62,
                      material: UnityTextMaterial.tutorialText,
                    ),

                    const Spacer(flex: 2),

                    // Bare `PowerUp_LevelUp.png` (`475 x 540`) / `PowerUp_TimeFreeze.png` (`390 x 390`)
                    _FtueHeroIllustration(
                      controller: _ctrl,
                      iconAsset: info.iconAsset,
                      iconUnityWidth: isLevelUp ? 450 : 370,
                      iconUnityHeight: isLevelUp ? 500 : 370,
                    ),

                    const Spacer(flex: 2),

                    // `InstructionsPanel` (`Box_Text.png`, `890.5 x 229.0`)
                    UnityNineSlice(
                      sprite: 'Box_Text.png',
                      width: ux(context, 890),
                      padding: EdgeInsets.symmetric(
                        horizontal: ux(context, 56),
                        vertical: ux(context, 44),
                      ),
                      child: Text(
                        info.note,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontSize: ux(context, 52),
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          color: const Color(0xFF06269A),
                          height: 1.22,
                        ),
                      ),
                    ),

                    const Spacer(flex: 3),

                    // `Button_CTA` (`580.5 x 181.8`, `"Continue"`, `fontSize = 90`)
                    UnityCtaButton(
                      label: 'Continue',
                      unityWidth: 580,
                      unityHeight: 182,
                      unityFontSize: 90,
                      onTap: _handleContinue,
                    ),

                    const Spacer(flex: 3),
                  ],
                ),
              ),

            // Step 2: Highlighted Bottom `"FREE"` Power-Up Button + Wobbling `PowerUp_Icon_Arrow.png` (`↓`)
            if (_step == 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: ux(context, 10),
                child: SizedBox(
                  height: ux(context, 480),
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      final phase = _ctrl.value * math.pi * 4;
                      final bobY = ux(context, 16.0 * math.sin(phase));
                      final wobbleRot = 0.045 * math.sin(phase * 0.5);
                      final targetOffsetX = ux(
                        context,
                        isLevelUp
                            ? -UnityPowerUpHudButton.horizontalOffsetUnity
                            : UnityPowerUpHudButton.horizontalOffsetUnity,
                      );

                      return Stack(
                        alignment: Alignment.bottomCenter,
                        clipBehavior: Clip.none,
                        children: [
                          // Wobbling lime-green downward pointer arrow (`PowerUp_Icon_Arrow.png`)
                          Positioned(
                            bottom: ux(
                                  context,
                                  UnityPowerUpHudButton.scaledUnitySize + 18,
                                ) -
                                bobY,
                            child: Transform.translate(
                              offset: Offset(targetOffsetX, 0),
                              child: IgnorePointer(
                                child: Transform.rotate(
                                  angle: wobbleRot,
                                  child: Image.asset(
                                    'assets/images/PowerUp_Icon_Arrow.png',
                                    width: ux(context, 92),
                                    height: ux(context, 188),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Elevated `"FREE"` Power-Up Button at exact HUD X/Y position!
                          Positioned(
                            bottom: 0,
                            child: Transform.translate(
                              offset: Offset(targetOffsetX, 0),
                              child: UnityPowerUpHudButton(
                                key: ValueKey(
                                  isLevelUp
                                      ? 'ftue_free_level_up_btn'
                                      : 'ftue_free_time_freeze_btn',
                                ),
                                isLevelUp: isLevelUp,
                                isUnlocked: true,
                                isFree: true,
                                count: 3,
                                isActionable: true,
                                isHighlighted: true,
                                onTap: widget.onActivateFreePowerUp,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FtueHeroIllustration extends StatelessWidget {
  final AnimationController controller;
  final String iconAsset;
  final double iconUnityWidth;
  final double iconUnityHeight;

  const _FtueHeroIllustration({
    required this.controller,
    required this.iconAsset,
    required this.iconUnityWidth,
    required this.iconUnityHeight,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final pulse = 1.0 + 0.04 * math.sin(controller.value * math.pi * 2);
        return SizedBox(
          width: ux(context, 720),
          height: ux(context, 560),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.scale(
                scale: pulse,
                child: Image.asset(
                  'assets/images/Glow_02.png',
                  width: ux(context, 740),
                  height: ux(context, 740),
                  color: const Color(0x94FF82B2),
                  colorBlendMode: BlendMode.modulate,
                ),
              ),
              for (final (ang, dist, sz, phase) in _kFtueSparkles)
                Builder(
                  builder: (_) {
                    final tw = 0.35 +
                        0.65 *
                            (0.5 +
                                0.5 *
                                    math.sin(
                                      (controller.value + phase) * math.pi * 2,
                                    ));
                    final r = ux(context, dist);
                    final s = ux(context, sz * 1.55);
                    return Transform.translate(
                      offset: Offset(math.cos(ang) * r, math.sin(ang) * r),
                      child: Opacity(
                        opacity: tw.clamp(0.0, 1.0),
                        child: ColorFiltered(
                          colorFilter: UnityChannelMaskFilters.rgDualChannelStar(
                            const Color(0xFFFF9EC6),
                          ),
                          child: Image.asset(
                            'assets/images/Sparkle_01.png',
                            width: s,
                            height: s,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              Transform.scale(
                scale: 0.98 + 0.03 * pulse,
                child: Image.asset(
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
