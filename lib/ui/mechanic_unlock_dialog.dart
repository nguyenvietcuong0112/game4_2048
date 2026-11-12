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

/// Circular Booster HUD Button (`Play_Scene.png` & `Play_Scene 2.png`):
/// - Unlocked: `Powerup_Base.png` (`208x208`) + `PowerUp_LevelUp.png` / `PowerUp_TimeFreeze.png`
///   + corner `PowerUp_Amount.png` / `PowerUp_Plus.png` / `PowerUp_Free.png`
/// - Locked: `Powerup_Base_Locked.png` (`204x204`) + centered `Icon_Padlock_Silver.png` (`78x98`)
/// Shared between `GameplayScreen` HUD and Step 2 of `PowerUpFtueOverlay` for pixel-identical alignment.
class UnityPowerUpHudButton extends StatefulWidget {
  static const double scaledUnitySize = 208.0;
  static const double horizontalOffsetUnity = 135.0;
  static const double bottomOffsetUnity = 56.0;
  static const double footerTopLineUnity = 160.0;

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

  @override
  Widget build(BuildContext context) {
    // Interactive whenever onTap is provided (when locked, tapping triggers "Unlock at level X!" toast)
    final interactive = widget.onTap != null;
    final sz = ux(context, UnityPowerUpHudButton.scaledUnitySize);

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
          if (!widget.isUnlocked) ...[
            // Locked State (`Play_Scene 2.png`): metallic grey circle + centered golden padlock
            Image.asset(
              'assets/images/Powerup_Base_Locked.png',
              width: ux(context, 204.0),
              height: ux(context, 204.0),
              fit: BoxFit.contain,
            ),
            Transform.translate(
              offset: Offset(0, -ux(context, 2.0)),
              child: Image.asset(
                'assets/images/Icon_Padlock_Silver.png',
                width: ux(context, 78.0),
                height: ux(context, 98.0),
                fit: BoxFit.contain,
              ),
            ),
          ] else ...[
            // Optional FTUE Step 2 `SelectedHighlight_01` cyan/green additive glow
            if (widget.isHighlighted)
              Positioned(
                left: -ux(context, 42),
                right: -ux(context, 42),
                top: -ux(context, 42),
                bottom: -ux(context, 42),
                child: IgnorePointer(
                  child: Image.asset(
                    'assets/images/Glow_02.png',
                    fit: BoxFit.contain,
                    color: const Color(0xE63CFFB0),
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

            // 2. Centered Booster Icon (`PowerUp_LevelUp.png` / `PowerUp_TimeFreeze.png`)
            Transform.translate(
              offset: Offset(0, -ux(context, widget.isLevelUp ? 2.0 : 3.0)),
              child: Opacity(
                opacity: dimUnavailable ? 0.58 : 1.0,
                child: Image.asset(
                  widget.isLevelUp
                      ? 'assets/images/PowerUp_LevelUp.png'
                      : 'assets/images/PowerUp_TimeFreeze.png',
                  width: ux(context, widget.isLevelUp ? 126.0 : 132.0),
                  height: ux(context, widget.isLevelUp ? 124.0 : 130.0),
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // 3A. Free FTUE Badge (`PowerUp_Free.png`)
            if (widget.isFree)
              Positioned(
                bottom: ux(context, 4.0),
                child: Image.asset(
                  'assets/images/PowerUp_Free.png',
                  width: ux(context, 148.0),
                  height: ux(context, 51.0),
                  fit: BoxFit.contain,
                ),
              )
            // 3B. Empty Inventory `+` Badge (`PowerUp_Plus.png` at bottom-right)
            else if (widget.count <= 0)
              Positioned(
                right: ux(context, 2.0),
                bottom: ux(context, 2.0),
                child: Image.asset(
                  'assets/images/PowerUp_Plus.png',
                  width: ux(context, 69.0),
                  height: ux(context, 69.0),
                  fit: BoxFit.contain,
                ),
              )
            // 3C. Red Numeric Amount Badge (`PowerUp_Amount.png` at bottom-right)
            else
              Positioned(
                right: ux(context, 2.0),
                bottom: ux(context, 2.0),
                width: ux(context, 69.0),
                height: ux(context, 69.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/images/PowerUp_Amount.png',
                      width: ux(context, 69.0),
                      height: ux(context, 69.0),
                      fit: BoxFit.contain,
                    ),
                    Transform.translate(
                      offset: Offset(0, -ux(context, 1.5)),
                      child: UnitySdfText(
                        '${widget.count}',
                        unityFontSize: 38.0,
                        material: UnityTextMaterial.pinkBadge,
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

/// Redesigned `New mechanic` Unlock Overlay matching `assets/UI Bo Sung/New mechanic/New_feature.png` (`1080x2160`):
/// - Dark backdrop (`0xE00A051C`)
/// - Top Header Image: `assets/images/text_newfeature.png` (`756x219`, `"NEW FEATURE\nUnlocked!"`)
/// - Center Hero Illustration (`_FtueHeroIllustration`):
///   - `assets/images/effect_outerglow.png` (`1080x1335` purple radial glow)
///   - `assets/images/effect_star.png` (`703x527` golden 4-point sparkle stars)
///   - Center `Icon_Mechanic_*.png` (`362x312`)
/// - Below the Icon:
///   - Golden-yellow `info.title` (`#FFD11A`, `fontSize = 68`)
///   - Crisp white `info.note` (`#FFFFFF`, `fontSize = 48`)
/// - Bottom CTA Button: `btn_green.png` / `UnityCtaButton` (`500 x 221`, `"Continue"`, `fontSize = 68`)
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
      color: const Color(0xE00A051C),
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

              // 1. Top `"NEW FEATURE / Unlocked!"` Header (`text_newfeature.png`, `756x219`)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: ux(context, 64)),
                child: Image.asset(
                  'assets/images/text_newfeature.png',
                  width: ux(context, 756),
                  height: ux(context, 219),
                  fit: BoxFit.contain,
                ),
              ),

              const Spacer(flex: 2),

              // 2. Hero Illustration (`effect_outerglow.png` + `effect_star.png` + `Icon_Mechanic_*.png`)
              _FtueHeroIllustration(
                controller: _ctrl,
                iconAsset: info.iconAsset,
                iconUnityWidth: 362,
                iconUnityHeight: 332,
              ),

              const Spacer(flex: 1),

              // 3. Golden Mechanic Title (`info.title`, e.g. `"Ice Blocks"` / `"Block Ice"`)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: ux(context, 64)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    info.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontSize: ux(context, 72),
                      fontWeight: FontWeight.w800,
                      fontVariations: const [FontVariation('wght', 800)],
                      color: const Color(0xFFFFD11A),
                      height: 1.08,
                      shadows: const [
                        Shadow(
                          color: Color(0xCC180636),
                          offset: Offset(0, 3.0),
                          blurRadius: 6.0,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              SizedBox(height: ux(context, 16)),

              // 4. Crisp White Description Text (`info.note`)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: ux(context, 96)),
                child: Text(
                  info.note,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontSize: ux(context, 48),
                    fontWeight: FontWeight.w700,
                    fontVariations: const [FontVariation('wght', 700)],
                    color: Colors.white,
                    height: 1.22,
                    shadows: const [
                      Shadow(
                        color: Color(0xCC0D0422),
                        offset: Offset(0, 2.5),
                        blurRadius: 5.0,
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(flex: 2),

              // 5. Green `"Continue"` CTA Button (`500 x 221`, `fontSize = 68`)
              UnityCtaButton(
                label: 'Continue',
                unityWidth: 500,
                unityHeight: 221,
                unityFontSize: 68,
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

                    // Bare `PowerUp_LevelUp.png` / `PowerUp_TimeFreeze.png`
                    _FtueHeroIllustration(
                      controller: _ctrl,
                      iconAsset: info.iconAsset,
                      iconUnityWidth: 310,
                      iconUnityHeight: 310,
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

                    // `Button_CTA` (`499 x 221`, `"Continue"`, `fontSize = 68`)
                    UnityCtaButton(
                      label: 'Continue',
                      unityWidth: 499,
                      unityHeight: 221,
                      unityFontSize: 68,
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
                bottom: ux(context, UnityPowerUpHudButton.bottomOffsetUnity),
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
        final phase = controller.value * math.pi * 2;
        final pulse = 1.0 + 0.04 * math.sin(phase);
        final starTwinkle = (0.72 + 0.28 * math.sin(phase * 2.0)).clamp(0.0, 1.0);
        return SizedBox(
          width: ux(context, 820),
          height: ux(context, 580),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 1. Soft Purple Outer Glow (`effect_outerglow.png`, `1080x1335`)
              Positioned(
                left: -ux(context, 130),
                right: -ux(context, 130),
                top: -ux(context, 240),
                bottom: -ux(context, 240),
                child: IgnorePointer(
                  child: Transform.scale(
                    scale: pulse,
                    child: Image.asset(
                      'assets/images/effect_outerglow.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              // 2. Golden 4-Point Sparkle Stars (`effect_star.png`, `703x527`)
              IgnorePointer(
                child: Opacity(
                  opacity: starTwinkle,
                  child: Transform.scale(
                    scale: 0.97 + 0.05 * math.sin(phase),
                    child: Image.asset(
                      'assets/images/effect_star.png',
                      width: ux(context, 703),
                      height: ux(context, 527),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

              // 3. Center Mechanic / Booster Icon
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
