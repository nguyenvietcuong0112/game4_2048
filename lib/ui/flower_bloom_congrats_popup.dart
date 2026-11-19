import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/player_progress_service.dart';
import 'unity_ui_kit.dart';

/// Celebratory modal popup displayed automatically when a Garden Vase reaches 100%
/// and its flower blooms to Stage 3:
/// - Dimmed fullscreen backdrop with softly drifting color-matched flower petals
/// - Gold-rimmed royal-blue `popup_bg.png` + overlapping `"Congratulations!"` ribbon (`Frame_Popup_Title.png`)
/// - Warm cream inner showcase (`frame_content.png`) featuring:
///   - `"<Flower Name> Bloomed!"` subtitle
///   - Animated full-bloom Stage-3 flower sprite (`assets/images/flowers/{prefix}_stage_3.webp`)
///     framed by rotating sunburst rays (`fx_bloom_rays.webp`), `effect_outerglow.webp`, & `effect_star.png`
///   - Golden coin reward badge (`Reward_Coin.png` + `+<rewardCoins>`)
///   - Next crystal vase unlock caption
/// - Bottom CTA row: Green `"Claim"` (`+N`) + Shimmering Gold Ad `"Claim x2"` (`+2N`)!
class FlowerBloomCongratsPopup extends StatefulWidget {
  final VaseMilestoneConfig config;
  final bool isBusy;
  final VoidCallback onClaim;
  final VoidCallback? onClaimX2;

  const FlowerBloomCongratsPopup({
    super.key,
    required this.config,
    this.isBusy = false,
    required this.onClaim,
    this.onClaimX2,
  });

  static String flowerPrefix(FlowerType type) => switch (type) {
        FlowerType.tulipPink => 'tulip',
        FlowerType.trioDaisy => 'daisy',
        FlowerType.sunflower => 'sunflower',
        FlowerType.scarletPoppy => 'poppy',
        FlowerType.crystalLotus => 'lotus',
      };

  static String flowerStage3Asset(FlowerType type) =>
      'assets/images/flowers/${flowerPrefix(type)}_stage_3.webp';

  static String flowerPetalAsset(FlowerType type) =>
      'assets/images/flowers/petal_${flowerPrefix(type)}.webp';

  @override
  State<FlowerBloomCongratsPopup> createState() =>
      _FlowerBloomCongratsPopupState();
}

class _FlowerBloomCongratsPopupState extends State<FlowerBloomCongratsPopup>
    with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final AnimationController _ambientCtrl;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _ambientCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final baseCoins = math.max(1, cfg.rewardCoins);
    final doubleCoins = baseCoins * 2;
    final stage3Asset =
        FlowerBloomCongratsPopup.flowerStage3Asset(cfg.flowerType);
    final petalAsset =
        FlowerBloomCongratsPopup.flowerPetalAsset(cfg.flowerType);

    return AnimatedBuilder(
      animation: _entranceCtrl,
      builder: (context, cardChild) {
        final raw = _entranceCtrl.value.clamp(0.0, 1.0);
        final scrimAlpha = 0.80 * Curves.easeOut.transform(raw);
        final pop = Curves.easeOutBack.transform(raw);

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Celebratory Dim Scrim absorbing background touches
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: ColoredBox(
                color: Color.fromRGBO(7, 5, 26, scrimAlpha),
              ),
            ),

            // 2. Softly Drifting Color-Matched Flower Petals in Background
            IgnorePointer(
              child: Opacity(
                opacity: raw * 0.85,
                child: AnimatedBuilder(
                  animation: _ambientCtrl,
                  builder: (context, _) => _FloatingCongratsPetals(
                    petalAsset: petalAsset,
                    phase: _ambientCtrl.value,
                  ),
                ),
              ),
            ),

            // 3. Centered Congrats Popup Card (leaves room at top for elevated UnityCoinsWidget!)
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  ux(context, 42),
                  ux(context, 118),
                  ux(context, 42),
                  ux(context, 36),
                ),
                child: Center(
                  child: Opacity(
                    opacity: raw,
                    child: Transform.scale(
                      scale: (0.82 + 0.18 * pop).clamp(0.5, 1.15),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: cardChild,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: SizedBox(
        key: const ValueKey('flower_bloom_congrats_popup'),
        width: ux(context, 920),
        height: ux(context, 1084),
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // A. Gold-Rimmed Royal-Blue Popup Body (`popup_bg.png`)
            Positioned(
              left: 0,
              right: 0,
              top: ux(context, 48),
              bottom: 0,
              child: const UnityNineSlice(
                sprite: 'popup_bg.png',
                pixelMultiplier: 1.0,
              ),
            ),

            // B. Warm Cream Inner Showcase Well (`frame_content.png`)
            Positioned(
              left: ux(context, 52),
              right: ux(context, 52),
              top: ux(context, 168),
              height: ux(context, 586),
              child: UnityNineSlice(
                sprite: 'frame_content.png',
                pixelMultiplier: 1.0,
                padding: EdgeInsets.fromLTRB(
                  ux(context, 34),
                  ux(context, 24),
                  ux(context, 34),
                  ux(context, 22),
                ),
                child: Column(
                  children: [
                    // Flower Bloom Subtitle (`"Pink Tulip Bloomed!"`)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${cfg.flowerTitle} Bloomed!',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontSize: ux(context, 52),
                          fontWeight: FontWeight.w800,
                          fontVariations: const [FontVariation('wght', 800)],
                          height: 1.05,
                          color: const Color(0xFF5A270B),
                        ),
                      ),
                    ),

                    SizedBox(height: ux(context, 6)),

                    // Animated Full-Bloom Flower Hero + Sunburst Rays + Golden Coin Reward Badge
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _ambientCtrl,
                        builder: (context, _) {
                          final angle = _ambientCtrl.value * math.pi * 2.0;
                          final bobY = ux(context, 8.0 * math.sin(angle * 2.0));
                          final glowPulse = 1.0 + 0.05 * math.sin(angle * 2.0);
                          final starAlpha =
                              (0.68 + 0.32 * math.sin(angle * 3.0))
                                  .clamp(0.0, 1.0);
                          return Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              // Rotating Sunburst Rays
                              IgnorePointer(
                                child: Transform.rotate(
                                  angle: angle * 0.5,
                                  child: Transform.scale(
                                    scale: glowPulse,
                                    child: Image.asset(
                                      'assets/images/flowers/fx_bloom_rays.webp',
                                      width: ux(context, 420),
                                      height: ux(context, 420),
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, _, _) =>
                                          const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              ),

                              // Soft Golden Outer Aura
                              IgnorePointer(
                                child: Transform.scale(
                                  scale: glowPulse,
                                  child: Image.asset(
                                    'assets/images/effect_outerglow.webp',
                                    width: ux(context, 410),
                                    height: ux(context, 410),
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                              ),

                              // Twinkling 4-Point Stars
                              IgnorePointer(
                                child: Opacity(
                                  opacity: starAlpha,
                                  child: Image.asset(
                                    'assets/images/effect_star.png',
                                    width: ux(context, 440),
                                    height: ux(context, 340),
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                              ),

                              // Full-Bloom Stage-3 Flower Artwork
                              Transform.translate(
                                offset: Offset(-ux(context, 56), bobY - ux(context, 4)),
                                child: Image.asset(
                                  stage3Asset,
                                  width: ux(context, 300),
                                  height: ux(context, 300),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      const SizedBox.shrink(),
                                ),
                              ),

                              // Golden Reward Coin Stack + Amount Pill on Right Side
                              Positioned(
                                right: ux(context, 18),
                                bottom: ux(context, 18),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset(
                                      'assets/images/Reward_Coin.png',
                                      width: ux(context, 188),
                                      height: ux(context, 142),
                                      fit: BoxFit.contain,
                                    ),
                                    Transform.translate(
                                      offset: Offset(0, -ux(context, 16)),
                                      child: UnitySdfText(
                                        '+$baseCoins',
                                        unityFontSize: 66,
                                        material: UnityTextMaterial.winCoinAmount,
                                        singleTextNode: true,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    SizedBox(height: ux(context, 6)),

                    // Reward Chest Title & Next Vase Unlock Caption
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ux(context, 30),
                        vertical: ux(context, 8),
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x22B45309),
                        borderRadius: BorderRadius.circular(ux(context, 28)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${cfg.rewardTitle}  •  New Vase Unlocked!',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Baloo2',
                            fontSize: ux(context, 34),
                            fontWeight: FontWeight.w800,
                            fontVariations: const [FontVariation('wght', 800)],
                            height: 1.1,
                            color: const Color(0xFF7B3B11),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // C. Bottom CTA Buttons (`Claim` + Optional `Claim x2` Ad Button)
            Positioned(
              left: ux(context, 50),
              right: ux(context, 50),
              bottom: ux(context, 48),
              child: widget.onClaimX2 != null
                  ? Row(
                      children: [
                        Expanded(
                          child: UnityStackedCoinCtaButton(
                            key: const ValueKey('bloom_congrats_claim_btn'),
                            label: 'Claim',
                            coinLabel: '+$baseCoins',
                            sprite: 'Button_Green.png',
                            unityHeight: 206,
                            unityFontSize: 52,
                            insetUnityWidth: 210,
                            insetUnityHeight: 54,
                            onTap: widget.isBusy ? null : widget.onClaim,
                          ),
                        ),
                        SizedBox(width: ux(context, 24)),
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _ambientCtrl,
                            builder: (context, _) {
                              return UnityStackedAdCtaButton(
                                key: const ValueKey(
                                  'bloom_congrats_claim_x2_btn',
                                ),
                                label: 'Claim x2',
                                coinLabel: '+$doubleCoins',
                                shimmerPhase: _ambientCtrl.value,
                                unityHeight: 206,
                                unityFontSize: 50,
                                insetUnityWidth: 210,
                                insetUnityHeight: 54,
                                onTap:
                                    widget.isBusy ? null : widget.onClaimX2,
                              );
                            },
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: UnityStackedCoinCtaButton(
                        key: const ValueKey('bloom_congrats_claim_btn'),
                        label: 'Claim',
                        coinLabel: '+$baseCoins',
                        sprite: 'Button_Green.png',
                        unityWidth: 500,
                        unityHeight: 208,
                        unityFontSize: 58,
                        insetUnityWidth: 232,
                        insetUnityHeight: 58,
                        onTap: widget.isBusy ? null : widget.onClaim,
                      ),
                    ),
            ),

            // D. Overlapping Top Header Ribbon (`Frame_Popup_Title.png`, `"Congratulations!"`)
            Positioned(
              top: 0,
              width: ux(context, 696),
              height: ux(context, 154),
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey<String>('Congratulations!'),
                  alignment: Alignment.center,
                  child: UnityNineSlice(
                    sprite: 'Frame_Popup_Title.png',
                    padding: EdgeInsets.fromLTRB(
                      ux(context, 52),
                      ux(context, 8),
                      ux(context, 52),
                      ux(context, 18),
                    ),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: UnitySdfText(
                        'Congratulations!',
                        unityFontSize: 60,
                        material: UnityTextMaterial.popupTitle,
                        singleTextNode: true,
                      ),
                    ),
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

/// Decorative floating flower petals gently drifting behind the Congrats Popup card.
class _FloatingCongratsPetals extends StatelessWidget {
  final String petalAsset;
  final double phase;

  const _FloatingCongratsPetals({
    required this.petalAsset,
    required this.phase,
  });

  static const _seeds = <(double xFrac, double yOffset, double speed, double size, double spin)>[
    (0.10, 0.05, 1.0, 56, 1.2),
    (0.24, 0.38, 0.85, 46, -1.5),
    (0.84, 0.14, 1.15, 58, -1.1),
    (0.90, 0.56, 0.90, 48, 1.4),
    (0.14, 0.72, 1.05, 50, 0.9),
    (0.76, 0.82, 0.95, 54, -1.3),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (int i = 0; i < _seeds.length; i++)
              Builder(
                builder: (context) {
                  final (xFrac, yOff, spd, szUnity, spin) = _seeds[i];
                  final prog = (yOff + phase * spd) % 1.0;
                  final sway =
                      math.sin((phase * math.pi * 2.0) + i * 1.3) * ux(context, 28);
                  final left = w * xFrac + sway;
                  final top = -ux(context, 60) + (h + ux(context, 120)) * prog;
                  final alpha = (math.sin(prog * math.pi)).clamp(0.0, 1.0);
                  final sz = ux(context, szUnity);
                  return Positioned(
                    left: left - sz * 0.5,
                    top: top - sz * 0.5,
                    child: Opacity(
                      opacity: alpha * 0.78,
                      child: Transform.rotate(
                        angle: phase * math.pi * 2.0 * spin + i,
                        child: Image.asset(
                          petalAsset,
                          width: sz,
                          height: sz,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
