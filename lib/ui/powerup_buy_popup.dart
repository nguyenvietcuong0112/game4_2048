import 'package:flutter/material.dart';
import 'unity_ui_kit.dart';

/// Authentic replica of Unity `PowerUpBuyView.prefab`:
/// - `#0F204A(a=0.96)` backdrop
/// - Top 9-slice `Banner.png` ribbon with power-up title + `Button_Close.png`
/// - Description subtitle (`Baloo2_ExtraBold_Tutorial_Text`)
/// - `CoinPurchasePanel` (`x3` pack with green `Glow_02.png` aura + `Buy` `200` coins)
/// - `AdsPurchasePanel` (`x1` pack with cyan `Glow_02.png` aura + `Watch` `Icon_Ad.png`)
class PowerUpBuyPopup extends StatelessWidget {
  final bool isLevelUp;
  final int playerCoins;
  final int packCost;
  final VoidCallback onBuyPack;
  final VoidCallback onWatchAd;
  final VoidCallback onClose;

  const PowerUpBuyPopup({
    super.key,
    required this.isLevelUp,
    required this.playerCoins,
    this.packCost = 200,
    required this.onBuyPack,
    required this.onWatchAd,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final title = isLevelUp ? 'Level Up' : 'Time Freeze';
    final description = isLevelUp
        ? 'Merge a matching pair instantly, wherever they are!'
        : 'Freezes the timer for 20 seconds!';
    final iconAsset = isLevelUp
        ? 'assets/images/PowerUp_LevelUp.png'
        : 'assets/images/PowerUp_TimeFreeze.png';
    final canAfford = playerCoins >= packCost;

    return Container(
      color: const Color(0xF50F204A),
      child: SafeArea(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.80, end: 1.0),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: child,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(vertical: ux(context, 24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Header: `Banner.png` + overlapping `Button_Close.png`
                  SizedBox(
                    width: ux(context, 930),
                    height: ux(context, 184),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        UnityNineSlice(
                          sprite: 'Banner.png',
                          width: ux(context, 780),
                          height: ux(context, 166),
                          padding: EdgeInsets.only(bottom: ux(context, 14)),
                          child: UnitySdfText(
                            title,
                            unityFontSize: 82,
                            material: UnityTextMaterial.popupTitle,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: -ux(context, 8),
                          child: UnitySpriteButton(
                            asset: 'Button_Close.png',
                            unitySize: 138,
                            onTap: onClose,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: ux(context, 18)),

                  // Power-up description (`Baloo2_ExtraBold_Tutorial_Text`)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: ux(context, 84)),
                    child: UnitySdfText(
                      description,
                      unityFontSize: 50,
                      material: UnityTextMaterial.tutorialText,
                    ),
                  ),
                  SizedBox(height: ux(context, 36)),

                  // 1. `CoinPurchasePanel` (`x3` Pack -> Green `Buy 200`)
                  _buildOfferCard(
                    context: context,
                    iconAsset: iconAsset,
                    amountText: 'x3',
                    glowColor: const Color(0xCC48FF6A),
                    iconUnitySize: 210,
                    cta: UnityCtaButton(
                      skin: UnityButtonSkin.green,
                      label: 'Buy',
                      coinPrice: packCost,
                      unityWidth: 660,
                      unityHeight: 148,
                      unityFontSize: 74,
                      onTap: canAfford ? onBuyPack : null,
                    ),
                  ),
                  SizedBox(height: ux(context, 28)),

                  // 2. `AdsPurchasePanel` (`x1` Free -> Blue `Watch`)
                  _buildOfferCard(
                    context: context,
                    iconAsset: iconAsset,
                    amountText: 'x1',
                    glowColor: const Color(0xCC47D4FF),
                    iconUnitySize: 184,
                    cta: UnityCtaButton(
                      skin: UnityButtonSkin.blue,
                      label: 'Watch',
                      showAdBadge: true,
                      unityWidth: 660,
                      unityHeight: 148,
                      unityFontSize: 74,
                      onTap: onWatchAd,
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

  Widget _buildOfferCard({
    required BuildContext context,
    required String iconAsset,
    required String amountText,
    required Color glowColor,
    required double iconUnitySize,
    required Widget cta,
  }) {
    return UnityNineSlice(
      sprite: 'Background_Popup.png',
      width: ux(context, 880),
      padding: EdgeInsets.fromLTRB(
        ux(context, 38),
        ux(context, 34),
        ux(context, 38),
        ux(context, 44),
      ),
      child: UnityNineSlice(
        sprite: 'Panel_Popup.png',
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          ux(context, 36),
          ux(context, 28),
          ux(context, 36),
          ux(context, 34),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: ux(context, 280),
              height: ux(context, 236),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Image.asset(
                    'assets/images/Glow_02.png',
                    width: ux(context, 280),
                    height: ux(context, 280),
                    color: glowColor,
                    colorBlendMode: BlendMode.modulate,
                  ),
                  Image.asset(
                    iconAsset,
                    width: ux(context, iconUnitySize),
                    height: ux(context, iconUnitySize),
                    fit: BoxFit.contain,
                  ),
                  Positioned(
                    right: ux(context, 14),
                    bottom: ux(context, 8),
                    child: SizedBox(
                      width: ux(context, 96),
                      height: ux(context, 96),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            'assets/images/PowerUp_Amount.png',
                            width: ux(context, 96),
                            height: ux(context, 96),
                          ),
                          UnitySdfText(
                            amountText,
                            unityFontSize: 48,
                            material: UnityTextMaterial.pinkBadge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ux(context, 18)),
            cta,
          ],
        ),
      ),
    );
  }
}
