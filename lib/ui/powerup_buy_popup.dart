import 'package:flutter/material.dart';
import '../services/player_progress_service.dart';
import 'unity_ui_kit.dart';

/// Exact 1:1 replica of Unity `PowerUpBuyView.prefab`:
/// - Fullscreen `#0F204A` (`98%` alpha = `0xFA0F204A`) dark backdrop (NO white popup cards!)
/// - Elevated top-left `CoinsWidget` (`CurrencyBar.ShowCoinsOnPopupLayer`)
/// - Full-width `Ribbon` (`Banner.png`, `height = 312.19`) containing BOTH uppercase title
///   (`"LEVEL UP"` / `"TIME FREEZE"`, `fontSize = 90.5`) AND description (`fontSize = 48.0`)
///   plus top-right `Button_Close.png` (`123.22 x 124.25`)
/// - Side-by-side horizontal offer row:
///   - Left `CoinPurchasePanel`: green `Glow_02` aura, large icon + floating `'x3'` (`fontSize = 118`),
///     2-line `Button_CTA.png` / `Button_CTA_Disabled.png` (`414.3 x 192.7`) with `"Buy"` on top and
///     `Inset_Button_CTA.png` (`Icon_Coin.png` + `600` / `450`) below
///   - Right `AdsPurchasePanel`: cyan `Glow_02` aura, large icon + floating `'x1'` (`fontSize = 118`),
///     `Button_Blue.png` (`416.7 x 192.7`) with `Icon_Ad.png` + `"Watch"`
class PowerUpBuyPopup extends StatelessWidget {
  final bool isLevelUp;
  final int playerCoins;
  final int? packCost;
  final VoidCallback onBuyPack;
  final VoidCallback onWatchAd;
  final VoidCallback onClose;

  const PowerUpBuyPopup({
    super.key,
    required this.isLevelUp,
    required this.playerCoins,
    this.packCost,
    required this.onBuyPack,
    required this.onWatchAd,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedCost = packCost ??
        (isLevelUp
            ? PlayerProgressService.levelUpPackCost
            : PlayerProgressService.timeFreezePackCost);
    final title = isLevelUp ? 'LEVEL UP' : 'TIME FREEZE';
    final description = isLevelUp
        ? 'Merge a matching pair instantly, wherever they are!'
        : 'Freezes the timer for 20 seconds';
    final iconAsset = isLevelUp
        ? 'assets/images/PowerUp_LevelUp.png'
        : 'assets/images/PowerUp_TimeFreeze.png';
    final canAfford = playerCoins >= resolvedCost;

    return Container(
      color: const Color(0xFA0F204A),
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Elevated Top-Left `CoinsWidget` (`CurrencyBar.ShowCoinsOnPopupLayer()`)
            Positioned(
              left: ux(context, 30),
              top: ux(context, 16),
              child: SizedBox(
                width: ux(context, 314),
                height: ux(context, 114),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned(
                      left: ux(context, 16),
                      right: 0,
                      child: UnityNineSlice(
                        sprite: 'WidgetBase.png',
                        height: ux(context, 92),
                        padding: EdgeInsets.only(
                          left: ux(context, 94),
                          right: ux(context, 22),
                          bottom: ux(context, 4),
                        ),
                        alignment: Alignment.center,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: UnitySdfText(
                            '$playerCoins',
                            unityFontSize: 52,
                            material: UnityTextMaterial.levelCounter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      child: Image.asset(
                        'assets/images/Icon_Coin.png',
                        width: ux(context, 112),
                        height: ux(context, 112),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Main `PowerUpBuyView` Content (`Ribbon` + Side-by-Side `CoinPurchasePanel` & `AdsPurchasePanel`)
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.86, end: 1.0),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) => Transform.scale(
                  scale: scale,
                  child: child,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Full-width `Ribbon` (`Banner.png`, `height = 312.19`) containing Title + Description + CloseButton
                    SizedBox(
                      width: double.infinity,
                      height: ux(context, 326),
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: -ux(context, 16),
                            right: -ux(context, 16),
                            top: ux(context, 14),
                            height: ux(context, 312),
                            child: UnityNineSlice(
                              sprite: 'Banner.png',
                              padding: EdgeInsets.fromLTRB(
                                ux(context, 78),
                                ux(context, 34),
                                ux(context, 78),
                                ux(context, 52),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: UnitySdfText(
                                      title,
                                      unityFontSize: 90.5,
                                      material: UnityTextMaterial.popupTitle,
                                    ),
                                  ),
                                  SizedBox(height: ux(context, 12)),
                                  Flexible(
                                    child: UnitySdfText(
                                      description,
                                      unityFontSize: 47.0,
                                      maxLines: 2,
                                      material: UnityTextMaterial.tutorialText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            right: ux(context, 24),
                            top: -ux(context, 18),
                            child: UnitySpriteButton(
                              asset: 'Button_Close.png',
                              unitySize: 124,
                              onTap: onClose,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: ux(context, 76)),

                    // Side-by-Side Horizontal Offer Row (`CoinPurchasePanel` & `AdsPurchasePanel`)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: ux(context, 44)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Left: `CoinPurchasePanel` (`x3` + Green `Buy` + `600` / `450` Coin Inset)
                          Expanded(
                            child: _PowerUpOfferColumn(
                              iconAsset: iconAsset,
                              isLevelUp: isLevelUp,
                              amountText: 'x3',
                              glowColor: const Color(0xCC15D334),
                              button: _PowerUpStackedBuyButton(
                                label: 'Buy',
                                coinPrice: resolvedCost,
                                enabled: canAfford,
                                onTap: canAfford ? onBuyPack : null,
                              ),
                            ),
                          ),
                          SizedBox(width: ux(context, 36)),

                          // Right: `AdsPurchasePanel` (`x1` + Blue `Icon_Ad` + `Watch`)
                          Expanded(
                            child: _PowerUpOfferColumn(
                              iconAsset: iconAsset,
                              isLevelUp: isLevelUp,
                              amountText: 'x1',
                              glowColor: const Color(0xCC15D3D3),
                              button: _PowerUpWatchAdButton(
                                onTap: onWatchAd,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PowerUpOfferColumn extends StatelessWidget {
  final String iconAsset;
  final bool isLevelUp;
  final String amountText;
  final Color glowColor;
  final Widget button;

  const _PowerUpOfferColumn({
    required this.iconAsset,
    required this.isLevelUp,
    required this.amountText,
    required this.glowColor,
    required this.button,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = isLevelUp ? 306.0 : 254.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: ux(context, 420),
          height: ux(context, 360),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Image.asset(
                'assets/images/Glow_02.png',
                width: ux(context, 440),
                height: ux(context, 440),
                color: glowColor,
                colorBlendMode: BlendMode.modulate,
              ),
              Image.asset(
                iconAsset,
                width: ux(context, iconSize),
                height: ux(context, iconSize),
                fit: BoxFit.contain,
              ),
              // Floating `'x3'` / `'x1'` (`fontSize = 131.65 * 0.88` at bottom-right, NO circle base!)
              Positioned(
                right: ux(context, 28),
                bottom: ux(context, 18),
                child: UnitySdfText(
                  amountText,
                  unityFontSize: 112,
                  material: UnityTextMaterial.popupTitle,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: ux(context, 28)),
        button,
      ],
    );
  }
}

/// Exact `CoinPurchasePanel/BuyButton` (`414.32 x 192.66` in `PowerUpBuyView.prefab`):
/// Stacked `"Buy"` (`fontSize = 66.1`) on top + `Inset_Button_CTA.png` (`245.61 x 60.63`)
/// with `Icon_Coin.png` + `600` / `450` below. Uses `Button_CTA_Disabled.png` + `ctaGray` when unaffordable!
class _PowerUpStackedBuyButton extends StatefulWidget {
  final String label;
  final int coinPrice;
  final bool enabled;
  final VoidCallback? onTap;

  const _PowerUpStackedBuyButton({
    required this.label,
    required this.coinPrice,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_PowerUpStackedBuyButton> createState() =>
      _PowerUpStackedBuyButtonState();
}

class _PowerUpStackedBuyButtonState extends State<_PowerUpStackedBuyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onTap != null;
    final sprite = enabled ? 'Button_CTA.png' : 'Button_CTA_Disabled.png';
    final textMat =
        enabled ? UnityTextMaterial.ctaGreen : UnityTextMaterial.ctaGray;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed && enabled ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: UnityNineSlice(
          sprite: sprite,
          width: ux(context, 414),
          height: ux(context, 193),
          padding: EdgeInsets.fromLTRB(
            ux(context, 24),
            ux(context, 14),
            ux(context, 24),
            ux(context, 24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: UnitySdfText(
                  widget.label,
                  unityFontSize: 66,
                  material: textMat,
                ),
              ),
              SizedBox(height: ux(context, 6)),
              UnityNineSlice(
                sprite: 'Inset_Button_CTA.png',
                width: ux(context, 246),
                height: ux(context, 62),
                tint: enabled ? null : const Color(0xFF99A3B0),
                padding: EdgeInsets.symmetric(
                  horizontal: ux(context, 18),
                  vertical: ux(context, 4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/Icon_Coin.png',
                      width: ux(context, 48),
                      height: ux(context, 48),
                    ),
                    SizedBox(width: ux(context, 10)),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: UnitySdfText(
                          '${widget.coinPrice}',
                          unityFontSize: 50,
                          material: textMat,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Exact `AdsPurchasePanel/WatchAdButton` (`416.70 x 192.66` in `PowerUpBuyView.prefab`):
/// `Button_Blue.png` with `Icon_Ad.png` (`92 x 114`) on left + `"Watch"` (`fontSize = 68.8`) on right.
class _PowerUpWatchAdButton extends StatefulWidget {
  final VoidCallback onTap;

  const _PowerUpWatchAdButton({required this.onTap});

  @override
  State<_PowerUpWatchAdButton> createState() => _PowerUpWatchAdButtonState();
}

class _PowerUpWatchAdButtonState extends State<_PowerUpWatchAdButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
        child: UnityNineSlice(
          sprite: 'Button_Blue.png',
          width: ux(context, 417),
          height: ux(context, 193),
          padding: EdgeInsets.fromLTRB(
            ux(context, 28),
            ux(context, 14),
            ux(context, 28),
            ux(context, 24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/Icon_Ad.png',
                width: ux(context, 84),
                height: ux(context, 104),
                fit: BoxFit.contain,
              ),
              SizedBox(width: ux(context, 14)),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: const UnitySdfText(
                    'Watch',
                    unityFontSize: 66,
                    material: UnityTextMaterial.ctaBlue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
