import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/ads_manager.dart';
import '../services/iap_service.dart';
import '../services/player_progress_service.dart';
import '../services/remote_config_service.dart';
import 'unity_ui_kit.dart';

enum ShopScrollSection {
  top,
  coins,
  bundles,
}

String formatShopNumber(int value) {
  final str = value.toString();
  final buf = StringBuffer();
  for (int i = 0; i < str.length; i++) {
    final revIdx = str.length - i;
    if (i > 0 && revIdx % 3 == 0) {
      buf.write(',');
    }
    buf.write(str[i]);
  }
  return buf.toString();
}

const List<({BoosterType type, String asset, String label})> _kGameBoosters = [
  (
    type: BoosterType.levelUp,
    asset: 'assets/images/PowerUp_LevelUp.png',
    label: 'Level Up',
  ),
  (
    type: BoosterType.timeFreeze,
    asset: 'assets/images/PowerUp_TimeFreeze.png',
    label: 'Freeze',
  ),
  (
    type: BoosterType.shuffle,
    asset: 'assets/images/PowerUp_Shuffle.png',
    label: 'Shuffle',
  ),
  (
    type: BoosterType.hammer,
    asset: 'assets/images/PowerUp_Hammer.png',
    label: 'Hammer',
  ),
];

/// Main Shop screen matching the Shop UI mockups while displaying Block Order
/// boosters and crown-coin artwork with pricing from the Shop IAP catalog.
class ShopView extends StatefulWidget {
  final PlayerProgressService progress;
  final ShopScrollSection initialSection;
  final double bottomClearance;
  final VoidCallback? onClose;

  const ShopView({
    super.key,
    required this.progress,
    this.initialSection = ShopScrollSection.top,
    this.bottomClearance = 0,
    this.onClose,
  });

  @override
  State<ShopView> createState() => ShopViewState();
}

class ShopViewState extends State<ShopView> {
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _coinsHeaderKey = GlobalKey();
  final GlobalKey _bundlesHeaderKey = GlobalKey();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    IapService.logIapShow(
      level: widget.progress.currentLevel,
      location: 'shop',
      type: 'shop_open',
      productId: IapService.noAdsProductId,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToSection(widget.initialSection, animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant ShopView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToSection(widget.initialSection, animate: true);
      });
    }
  }

  void scrollToSection(ShopScrollSection section, {bool animate = true}) {
    if (!mounted) return;
    if (section == ShopScrollSection.top) {
      if (_scrollCtrl.hasClients) {
        if (animate) {
          _scrollCtrl.animateTo(
            0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          );
        } else {
          _scrollCtrl.jumpTo(0);
        }
      }
      return;
    }

    final targetKey =
        section == ShopScrollSection.coins ? _coinsHeaderKey : _bundlesHeaderKey;
    final targetCtx = targetKey.currentContext;
    if (targetCtx != null) {
      Scrollable.ensureVisible(
        targetCtx,
        alignment: 0.04,
        duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Baloo2',
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF14357A),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _buyBundle(ShopBundlePack pack) async {
    if (_busy) return;
    if (pack.isNonConsumable && widget.progress.noAdsPurchased) {
      _showToast('No Ads is already active!');
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await IapService.buyBundlePack(
        pack: pack,
        progress: widget.progress,
        location: 'shop',
      );
      if (ok) {
        _showToast('Purchased ${pack.title}!');
      } else {
        _showToast('Purchase could not be completed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _tapCoinPack(ShopCoinPack pack) async {
    if (_busy) return;
    if (pack.isFreeRewardedAd) {
      setState(() => _busy = true);
      await AdsManager.showRewardedAd(
        placement: 'shop_free_coins',
        levelNumber: widget.progress.currentLevel,
        onAdFailed: (reason) {
          final msg = reason == RewardedAdFailReason.noInternet
              ? 'No internet connection.'
              : 'Ad not ready right now. Try again!';
          _showToast(msg);
        },
        onRewardResult: (success) {
          if (success) {
            widget.progress.addCoins(pack.coins);
            _showToast('+${pack.coins} Coins!');
          }
        },
      );
      if (mounted) setState(() => _busy = false);
      return;
    }

    setState(() => _busy = true);
    try {
      final ok = await IapService.buyCoinPack(
        pack: pack,
        progress: widget.progress,
        location: 'shop',
      );
      if (ok) {
        _showToast('+${formatShopNumber(pack.coins)} Coins!');
      } else {
        _showToast('Purchase could not be completed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final awningH = ux(context, 235).clamp(96.0, 142.0);
    final topPad = MediaQuery.paddingOf(context).top;

    return AnimatedBuilder(
      animation: widget.progress,
      builder: (context, _) {
        final noAdsOwned = widget.progress.noAdsPurchased;
        return Material(
          color: const Color(0xFF142A68),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/Shop/BG.png',
                  fit: BoxFit.cover,
                ),
              ),

              // Main scrollable shop shelf
              Positioned.fill(
                child: CustomScrollView(
                  key: const ValueKey('shop_scroll_view'),
                  controller: _scrollCtrl,
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(height: awningH + ux(context, 18)),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: ux(context, 42),
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _NoAdsCompactCard(
                            owned: noAdsOwned,
                            priceLabel: IapService.priceLabelFor(
                              IapService.noAdsPack.productId,
                              IapService.noAdsPack.fallbackPrice,
                            ),
                            onTap: () => _buyBundle(IapService.noAdsPack),
                          ),
                          SizedBox(height: ux(context, 28)),
                          _BundleCard(
                            key: const ValueKey('shop_pack_no_ads_bundle'),
                            pack: IapService.noAdsBundlePack,
                            noAdsAlreadyOwned: noAdsOwned,
                            includeNoAdsIcon: true,
                            onTap: () => _buyBundle(IapService.noAdsBundlePack),
                          ),
                          SizedBox(height: ux(context, 42)),
                          _SectionBanner(
                            key: _coinsHeaderKey,
                            assetPath: 'assets/images/Shop/tittle_coins.png',
                            title: 'Coins',
                          ),
                          SizedBox(height: ux(context, 24)),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: IapService.coinPacks.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: ux(context, 22),
                              crossAxisSpacing: ux(context, 20),
                              childAspectRatio: 0.72,
                            ),
                            itemBuilder: (context, index) {
                              final pack = IapService.coinPacks[index];
                              return _CoinGridCard(
                                pack: pack,
                                onTap: () => _tapCoinPack(pack),
                              );
                            },
                          ),
                          SizedBox(height: ux(context, 42)),
                          _SectionBanner(
                            key: _bundlesHeaderKey,
                            assetPath: 'assets/images/Shop/tittle_bundles.png',
                            title: 'Bundles',
                          ),
                          SizedBox(height: ux(context, 28)),
                          for (final bundle in IapService.shopBundles) ...[
                            _BundleCard(
                              key: ValueKey('shop_pack_${bundle.enumKey}'),
                              pack: bundle,
                              noAdsAlreadyOwned: false,
                              includeNoAdsIcon: false,
                              onTap: () => _buyBundle(bundle),
                            ),
                            SizedBox(height: ux(context, 28)),
                          ],
                          SizedBox(
                            height: widget.bottomClearance + ux(context, 36),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),

              // Top striped awning (`hud_shop.png`) + Coin counter HUD + optional close button
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: awningH,
                child: IgnorePointer(
                  ignoring: widget.onClose == null,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          'assets/images/Shop/hud_shop.png',
                          fit: BoxFit.fill,
                          width: screenW,
                        ),
                      ),
                      if (widget.onClose != null)
                        Positioned(
                          top: math.max(topPad + 6, ux(context, 28)),
                          left: ux(context, 28),
                          child: _ShopCloseButton(onTap: widget.onClose!),
                        ),
                      Positioned(
                        top: math.max(topPad + 6, ux(context, 32)),
                        right: ux(context, 34),
                        child: _ShopCoinsBadge(coins: widget.progress.coins),
                      ),
                    ],
                  ),
                ),
              ),

              if (_busy)
                Positioned.fill(
                  child: Container(
                    color: Colors.black26,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(
                      color: Color(0xFFFFD84D),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ShopCloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ShopCloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sz = ux(context, 84).clamp(36.0, 48.0);
    return GestureDetector(
      key: const ValueKey('shop_close_btn'),
      onTap: onTap,
      child: SizedBox(
        width: sz,
        height: sz,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset('assets/images/Button_Red.png', fit: BoxFit.contain),
            const UnitySdfText(
              'X',
              unityFontSize: 42,
              material: UnityTextMaterial.ctaRed,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopCoinsBadge extends StatelessWidget {
  final int coins;

  const _ShopCoinsBadge({required this.coins});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: ux(context, 66).clamp(30.0, 38.0),
      padding: EdgeInsets.only(
        left: ux(context, 10),
        right: ux(context, 22),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFBEEDC),
        borderRadius: BorderRadius.circular(ux(context, 33)),
        border: Border.all(
          color: const Color(0xFFD69E3B),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            offset: Offset(0, 3),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/Shop/asset_coin_1.png',
            width: ux(context, 52).clamp(24.0, 32.0),
            height: ux(context, 52).clamp(24.0, 32.0),
            fit: BoxFit.contain,
          ),
          SizedBox(width: ux(context, 10)),
          Text(
            formatShopNumber(coins),
            style: TextStyle(
              fontFamily: 'Baloo2',
              fontWeight: FontWeight.w800,
              fontSize: ux(context, 38).clamp(15.0, 20.0),
              color: const Color(0xFF5D2D09),
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionBanner extends StatelessWidget {
  final String assetPath;
  final String title;

  const _SectionBanner({
    super.key,
    required this.assetPath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final h = ux(context, 104).clamp(42.0, 56.0);
    return SizedBox(
      height: h,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Image.asset(
              assetPath,
              fit: BoxFit.fill,
            ),
          ),
          UnitySdfText(
            title,
            unityFontSize: 54,
            material: UnityTextMaterial.popupTitle,
          ),
        ],
      ),
    );
  }
}

class _ShopPriceButton extends StatelessWidget {
  final String label;
  final bool isYellow;
  final bool disabled;
  final VoidCallback onTap;
  final double width;
  final double height;
  final double unityFontSize;

  const _ShopPriceButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isYellow = false,
    this.disabled = false,
    this.width = 250,
    this.height = 96,
    this.unityFontSize = 44,
  });

  @override
  Widget build(BuildContext context) {
    final asset = isYellow
        ? 'assets/images/Shop/btn_yellow.png'
        : 'assets/images/Shop/btn_green_shirt.png';
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: disabled ? 0.65 : 1.0,
        child: SizedBox(
          width: ux(context, width),
          height: ux(context, height),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Image.asset(asset, fit: BoxFit.fill),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: ux(context, 14)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: UnitySdfText(
                    label,
                    unityFontSize: unityFontSize,
                    material: isYellow
                        ? UnityTextMaterial.ctaYellowButton
                        : UnityTextMaterial.ctaGreen,
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

class _NoAdsCompactCard extends StatelessWidget {
  final bool owned;
  final String priceLabel;
  final VoidCallback onTap;

  const _NoAdsCompactCard({
    required this.owned,
    required this.priceLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardH = ux(context, 210).clamp(84.0, 120.0);
    return SizedBox(
      key: const ValueKey('shop_pack_no_ads'),
      height: cardH,
      width: double.infinity,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/Shop/frame_noads.png',
              fit: BoxFit.fill,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ux(context, 38),
              vertical: ux(context, 24),
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/Shop/icon_ads.png',
                  width: ux(context, 128).clamp(52.0, 74.0),
                  height: ux(context, 128).clamp(52.0, 74.0),
                  fit: BoxFit.contain,
                ),
                SizedBox(width: ux(context, 24)),
                Expanded(
                  child: Text(
                    'No Ads',
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontWeight: FontWeight.w800,
                      fontSize: ux(context, 54).clamp(20.0, 28.0),
                      color: const Color(0xFF5D2D09),
                    ),
                  ),
                ),
                _ShopPriceButton(
                  key: const ValueKey('shop_buy_no_ads_btn'),
                  label: owned ? 'Owned' : priceLabel,
                  disabled: owned,
                  width: 268,
                  height: 102,
                  unityFontSize: 44,
                  onTap: onTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BundleCard extends StatelessWidget {
  final ShopBundlePack pack;
  final bool includeNoAdsIcon;
  final bool noAdsAlreadyOwned;
  final VoidCallback onTap;

  const _BundleCard({
    super.key,
    required this.pack,
    required this.includeNoAdsIcon,
    required this.noAdsAlreadyOwned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardH = ux(context, 396).clamp(160.0, 224.0);
    final frameAsset =
        pack.frameAsset ?? 'assets/images/Shop/frame_starter+noads.png';
    final priceText = IapService.priceLabelFor(pack.productId, pack.fallbackPrice);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          height: cardH,
          width: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(frameAsset, fit: BoxFit.fill),
              ),
              Column(
                children: [
                  // Upper rewards band (~63% height)
                  Expanded(
                    flex: 63,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        ux(context, 28),
                        ux(context, 22),
                        ux(context, 28),
                        ux(context, 12),
                      ),
                      child: Row(
                        children: [
                          // Coins pile + amount
                          _CoinPileReward(
                            asset: pack.coinAsset ??
                                'assets/images/Shop/asset_coin_4.png',
                            coins: pack.coins,
                          ),
                          if (includeNoAdsIcon) ...[
                            SizedBox(width: ux(context, 12)),
                            Image.asset(
                              'assets/images/Shop/icon_ads.png',
                              width: ux(context, 118).clamp(44.0, 62.0),
                              height: ux(context, 118).clamp(44.0, 62.0),
                              fit: BoxFit.contain,
                            ),
                          ],
                          if (pack.infinityHours > 0) ...[
                            SizedBox(width: ux(context, 10)),
                            _InfinityHeartReward(hours: pack.infinityHours),
                          ],
                          SizedBox(width: ux(context, 10)),
                          Expanded(
                            child: _BoostersCluster(
                              countEach: pack.boosterEachCount,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom title + CTA band (~37% height)
                  Expanded(
                    flex: 37,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        ux(context, 36),
                        0,
                        ux(context, 28),
                        ux(context, 14),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: UnitySdfText(
                                  pack.title,
                                  unityFontSize: 48,
                                  material: UnityTextMaterial.popupTitle,
                                  textAlign: TextAlign.left,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: ux(context, 16)),
                          _ShopPriceButton(
                            key: ValueKey('shop_buy_${pack.enumKey}_btn'),
                            label: noAdsAlreadyOwned && pack.isNonConsumable
                                ? 'Owned'
                                : priceText,
                            disabled: noAdsAlreadyOwned && pack.isNonConsumable,
                            width: 264,
                            height: 98,
                            unityFontSize: 44,
                            onTap: onTap,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (pack.badgeText != null)
          Positioned(
            top: -ux(context, 18),
            left: -ux(context, 14),
            child: _ScallopedDiscountBadge(text: pack.badgeText!),
          ),
      ],
    );
  }
}

class _CoinPileReward extends StatelessWidget {
  final String asset;
  final int coins;

  const _CoinPileReward({required this.asset, required this.coins});

  @override
  Widget build(BuildContext context) {
    final w = ux(context, 224).clamp(88.0, 126.0);
    return SizedBox(
      width: w,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: ux(context, 16)),
            child: Image.asset(asset, fit: BoxFit.contain),
          ),
          Positioned(
            bottom: 0,
            child: UnitySdfText(
              formatShopNumber(coins),
              unityFontSize: 42,
              material: UnityTextMaterial.darkStroke,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfinityHeartReward extends StatelessWidget {
  final int hours;

  const _InfinityHeartReward({required this.hours});

  @override
  Widget build(BuildContext context) {
    final sz = ux(context, 110).clamp(44.0, 60.0);
    return SizedBox(
      width: sz,
      height: sz,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/images/UI Home/Home/icon_heart.png',
            width: sz * 0.92,
            height: sz * 0.92,
            fit: BoxFit.contain,
          ),
          const UnitySdfText(
            '∞',
            unityFontSize: 28,
            material: UnityTextMaterial.darkStroke,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: UnitySdfText(
              '${hours}h',
              unityFontSize: 32,
              material: UnityTextMaterial.darkStroke,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoostersCluster extends StatelessWidget {
  final int countEach;

  const _BoostersCluster({required this.countEach});

  @override
  Widget build(BuildContext context) {
    final itemSize = ux(context, 84).clamp(32.0, 48.0);
    return Wrap(
      alignment: WrapAlignment.center,
      runAlignment: WrapAlignment.center,
      spacing: ux(context, 10),
      runSpacing: ux(context, 4),
      children: [
        for (final booster in _kGameBoosters)
          SizedBox(
            width: itemSize,
            height: itemSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.all(ux(context, 4)),
                  child: Image.asset(booster.asset, fit: BoxFit.contain),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: UnitySdfText(
                    'x$countEach',
                    unityFontSize: 28,
                    material: UnityTextMaterial.darkStroke,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CoinGridCard extends StatelessWidget {
  final ShopCoinPack pack;
  final VoidCallback onTap;

  const _CoinGridCard({required this.pack, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final priceLabel = pack.productId == null
        ? pack.fallbackPrice
        : IapService.priceLabelFor(pack.productId!, pack.fallbackPrice);

    return GestureDetector(
      key: ValueKey('shop_coin_${pack.enumKey ?? "free"}'),
      onTap: onTap,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/Shop/frame_coin.png',
              fit: BoxFit.fill,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              ux(context, 16),
              ux(context, 18),
              ux(context, 16),
              ux(context, 18),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Image.asset(
                    pack.coinAsset,
                    fit: BoxFit.contain,
                  ),
                ),
                SizedBox(height: ux(context, 6)),
                Text(
                  formatShopNumber(pack.coins),
                  style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontWeight: FontWeight.w800,
                    fontSize: ux(context, 38).clamp(14.0, 20.0),
                    color: const Color(0xFF5D2D09),
                    height: 1.0,
                  ),
                ),
                SizedBox(height: ux(context, 8)),
                _ShopPriceButton(
                  key: ValueKey('shop_coin_btn_${pack.enumKey ?? "free"}'),
                  label: priceLabel,
                  isYellow: pack.isFreeRewardedAd,
                  width: 240,
                  height: 78,
                  unityFontSize: 38,
                  onTap: onTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScallopedDiscountBadge extends StatelessWidget {
  final String text;

  const _ScallopedDiscountBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final sz = ux(context, 134).clamp(52.0, 74.0);
    return Transform.rotate(
      angle: -0.18,
      child: SizedBox(
        width: sz,
        height: sz,
        child: CustomPaint(
          painter: _ScallopedBadgePainter(),
          child: Center(
            child: UnitySdfText(
              text,
              unityFontSize: 32,
              material: UnityTextMaterial.ctaRed,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScallopedBadgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width * 0.48;
    const lobes = 10;
    final path = Path();
    for (int i = 0; i < lobes * 2; i++) {
      final angle = (i * math.pi) / lobes;
      final r = i.isEven ? outerR : outerR * 0.84;
      final p = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE5333A)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Modal popup offering `Fail Offer` ($3.99: 1,500 Coins + 4 Boosters) when stuck or after losing.
class FailOfferDialog extends StatefulWidget {
  final PlayerProgressService progress;

  const FailOfferDialog({super.key, required this.progress});

  @override
  State<FailOfferDialog> createState() => _FailOfferDialogState();
}

class _FailOfferDialogState extends State<FailOfferDialog> {
  bool _buying = false;

  @override
  void initState() {
    super.initState();
    IapService.logIapShow(
      level: widget.progress.currentLevel,
      location: 'fail_offer',
      type: IapService.failOfferPack.enumKey,
      productId: IapService.failOfferPack.productId,
    );
  }

  Future<void> _buy() async {
    if (_buying) return;
    setState(() => _buying = true);
    final ok = await IapService.buyBundlePack(
      pack: IapService.failOfferPack,
      progress: widget.progress,
      location: 'fail_offer',
    );
    if (!mounted) return;
    setState(() => _buying = false);
    Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final pack = IapService.failOfferPack;
    final price = IapService.priceLabelFor(pack.productId, pack.fallbackPrice);
    final cardW = ux(context, 860).clamp(290.0, 390.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: cardW,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                ux(context, 36),
                ux(context, 48),
                ux(context, 36),
                ux(context, 38),
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFF6DE), Color(0xFFF3D299)],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFFFFC12A),
                  width: 4,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x88000000),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const UnitySdfText(
                    'Fail Offer!',
                    unityFontSize: 56,
                    material: UnityTextMaterial.ctaYellow,
                  ),
                  SizedBox(height: ux(context, 18)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CoinPileReward(
                        asset: pack.coinAsset!,
                        coins: pack.coins,
                      ),
                      SizedBox(width: ux(context, 18)),
                      Expanded(
                        child: _BoostersCluster(
                          countEach: pack.boosterEachCount,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ux(context, 28)),
                  _ShopPriceButton(
                    key: const ValueKey('fail_offer_buy_btn'),
                    label: _buying ? '...' : price,
                    disabled: _buying,
                    width: 340,
                    height: 112,
                    unityFontSize: 48,
                    onTap: _buy,
                  ),
                ],
              ),
            ),
            Positioned(
              top: -12,
              right: -12,
              child: GestureDetector(
                key: const ValueKey('fail_offer_close_btn'),
                onTap: () => Navigator.of(context).pop(false),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset('assets/images/Button_Red.png'),
                      const UnitySdfText(
                        'X',
                        unityFontSize: 34,
                        material: UnityTextMaterial.ctaRed,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> showFailOfferDialog(
  BuildContext context, {
  required PlayerProgressService progress,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => FailOfferDialog(progress: progress),
  );
  return result == true;
}
