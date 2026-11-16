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
    id: 'pu_level_up',
    title: 'Level Up',
    subtitle: 'New power-up unlocked!',
    note: 'Merge a matching pair instantly, wherever they are!',
    iconAsset: 'assets/images/PowerUp_LevelUp.png',
    isPowerUp: true,
    isLevelUpPowerUp: true,
    unlockRewardCount: 1,
    hudHorizontalOffsetUnity: -UnityPowerUpHudButton.horizontalOffsetUnity,
    analyticsName: 'level_up',
  );

  static const timeFreezePowerUp = MechanicUnlockInfo(
    id: 'pu_time_freeze',
    title: 'Time Freeze',
    subtitle: 'New power-up unlocked!',
    note: 'Freezes the timer for 20 seconds',
    iconAsset: 'assets/images/PowerUp_TimeFreeze.png',
    isPowerUp: true,
    isLevelUpPowerUp: false,
    unlockRewardCount: 1,
    hudHorizontalOffsetUnity: UnityPowerUpHudButton.horizontalOffsetUnity,
    analyticsName: 'time_freeze',
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
  final int? unlockLevel;
  final bool isFree;
  final int count;
  final bool isActionable;
  final bool isHighlighted;
  final VoidCallback? onTap;

  const UnityPowerUpHudButton({
    super.key,
    required this.isLevelUp,
    required this.isUnlocked,
    this.unlockLevel,
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
            // Locked State: metallic grey circle + `"Level X"` label above golden padlock inside the circle
            Image.asset(
              'assets/images/Powerup_Base_Locked.png',
              width: ux(context, 204.0),
              height: ux(context, 204.0),
              fit: BoxFit.contain,
            ),
            Positioned(
              top: ux(context, 48.0),
              width: ux(context, 122.0),
              height: ux(context, 34.0),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: UnitySdfText(
                    'Level ${widget.unlockLevel ?? (widget.isLevelUp ? 17 : 27)}',
                    unityFontSize: 29.0,
                    material: UnityTextMaterial.lockedBoosterLabel,
                    singleTextNode: true,
                  ),
                ),
              ),
            ),
            Positioned(
              top: ux(context, 83.0),
              child: Image.asset(
                'assets/images/Icon_Padlock_Silver.png',
                width: ux(context, 68.0),
                height: ux(context, 85.0),
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

/// Unified Unlock Popup (`884x1044` Unity px) supporting both feature categories:
/// - **Boosters (`info.isPowerUp == true`) — `New Feature`**:
///   - Header ribbon: `"New Feature"`
///   - Dual bottom actions (`top = 725`): Green `"Claim"` (+1) & Yellow `"Claim X2"` (+2 Ad)
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
  void _handleClaimX2() => (widget.onClaimX2 ?? widget.onDismiss).call();
  void _handleNextLevel() =>
      (widget.onNextLevel ?? widget.onClaim ?? widget.onDismiss).call();
  void _handleClose() => (widget.onClose ?? widget.onDismiss).call();

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final isBooster = info.isPowerUp;
    final headerTitle = isBooster ? 'New Feature' : 'New Mechanic';
    final ribbonWidthUnity = isBooster ? 558.0 : 576.0;

    return ColoredBox(
      color: const Color(0xCC060414),
      child: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _entranceCtrl,
            builder: (context, child) {
              final t = Curves.easeOutBack.transform(_entranceCtrl.value);
              return Transform.scale(
                scale: 0.84 + 0.16 * t,
                child: Opacity(
                  opacity: _entranceCtrl.value.clamp(0.0, 1.0),
                  child: child,
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
                                  child: Image.asset(
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

                  // 3. Bottom Action Buttons:
                  //    - Boosters (`New Feature`): Green "Claim" + Yellow "Claim X2" (Ads)
                  //    - Mechanics (`New Mechanic`): Single centered long green "Next Level"
                  if (isBooster) ...[
                    Positioned(
                      left: ux(context, 51),
                      top: ux(context, 727),
                      width: ux(context, 393),
                      height: ux(context, 221),
                      child: _UnlockPillButton(
                        buttonKey: const ValueKey('mechanic_claim_btn'),
                        sprite: 'Button_Green.png',
                        label: 'Claim',
                        unityFontSize: 64,
                        material: UnityTextMaterial.ctaGreen,
                        textPadding: EdgeInsets.only(
                          left: ux(context, 32),
                          right: ux(context, 32),
                          bottom: ux(context, 12),
                        ),
                        onTap: _handleClaim,
                      ),
                    ),
                    Positioned(
                      right: ux(context, 45),
                      top: ux(context, 725),
                      width: ux(context, 386),
                      height: ux(context, 221),
                      child: _UnlockPillButton(
                        buttonKey: const ValueKey('mechanic_claim_x2_btn'),
                        sprite: 'Button_Yellow.png',
                        label: 'Claim X2',
                        unityFontSize: 58,
                        material: UnityTextMaterial.ctaYellowButton,
                        textPadding: EdgeInsets.only(
                          left: ux(context, 36),
                          right: ux(context, 28),
                          bottom: ux(context, 10),
                        ),
                        badgeOverlay: Positioned(
                          left: -ux(context, 8),
                          top: -ux(context, 42),
                          width: ux(context, 122),
                          height: ux(context, 127),
                          child: Image.asset(
                            'assets/images/Icon_Ads.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        onTap: _handleClaimX2,
                      ),
                    ),
                  ] else
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
          ),
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
  final Widget? badgeOverlay;
  final VoidCallback onTap;

  const _UnlockPillButton({
    required this.buttonKey,
    required this.sprite,
    this.useNineSlice = false,
    required this.label,
    required this.unityFontSize,
    required this.material,
    required this.textPadding,
    this.badgeOverlay,
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
            if (widget.badgeOverlay != null) widget.badgeOverlay!,
          ],
        ),
      ),
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
