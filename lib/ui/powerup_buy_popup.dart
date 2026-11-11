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
              left: ux(context, UnityCoinsWidget.hudLeftUnity),
              top: ux(context, UnityCoinsWidget.hudTopUnity),
              child: UnityCoinsWidget(coins: playerCoins),
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
    final iconSize = isLevelUp ? 168.0 : 174.0;
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
                'assets/images/Powerup_Base.png',
                width: ux(context, 272),
                height: ux(context, 272),
                fit: BoxFit.contain,
              ),
              Image.asset(
                iconAsset,
                width: ux(context, iconSize),
                height: ux(context, iconSize),
                fit: BoxFit.contain,
              ),
              // Floating `'x3'` / `'x1'` at bottom-right
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

/// Gold-rimmed `CoinPurchasePanel/BuyButton` (`Button_CTA.png`):
/// Stacked `"Buy"` on top + `Inset_Button_CTA.png` (`Icon_Coin.png` + `600` / `450`) below.
/// Uses `UnityButtonColorFilters.disabledSilver` + `ctaGray` when unaffordable.
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
          sprite: 'Button_CTA.png',
          colorFilter:
              enabled ? null : UnityButtonColorFilters.disabledSilver,
          width: ux(context, 430),
          height: ux(context, 200),
          padding: EdgeInsets.fromLTRB(
            ux(context, 42),
            ux(context, 16),
            ux(context, 42),
            ux(context, 24),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: UnitySdfText(
                  widget.label,
                  unityFontSize: 64,
                  material: textMat,
                ),
              ),
              SizedBox(height: ux(context, 4)),
              UnityNineSlice(
                sprite: 'Inset_Button_CTA.png',
                width: ux(context, 236),
                height: ux(context, 58),
                tint: enabled ? null : const Color(0xFF99A3B0),
                padding: EdgeInsets.symmetric(
                  horizontal: ux(context, 16),
                  vertical: ux(context, 4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/Icon_Coin.png',
                      width: ux(context, 46),
                      height: ux(context, 46),
                    ),
                    SizedBox(width: ux(context, 10)),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: UnitySdfText(
                          '${widget.coinPrice}',
                          unityFontSize: 48,
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

/// Gold-rimmed blue `AdsPurchasePanel/WatchAdButton` (`Button_CTA.png` + `blueWithGoldRim`)
/// with `Icon_Ad.png` on left + `"Watch"` on right.
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
          sprite: 'Button_CTA.png',
          colorFilter: UnityButtonColorFilters.blueWithGoldRim,
          width: ux(context, 430),
          height: ux(context, 200),
          padding: EdgeInsets.fromLTRB(
            ux(context, 44),
            ux(context, 16),
            ux(context, 44),
            ux(context, 24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/Icon_Ad.png',
                width: ux(context, 80),
                height: ux(context, 98),
                fit: BoxFit.contain,
              ),
              SizedBox(width: ux(context, 14)),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: const UnitySdfText(
                    'Watch',
                    unityFontSize: 64,
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
