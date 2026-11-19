import 'dart:async';
import 'package:flutter/material.dart';
import '../services/player_progress_service.dart';
import '../services/remote_config_service.dart';
import 'unity_ui_kit.dart';

/// `"More Lives?"` Refill & Regen Modal matching mockup design:
/// - `Frame_Popup_Title.png` (`"More Lives?"`) + top-right `Button_Close.png`
/// - Cream `frame_content.png` inner well: large `Icon_Life.png` with live count,
///   `"Next life in:"` + clock capsule `MM:SS` countdown (`15:00` regen), and prompt text
/// - Left blue ad button (`Button_Blue.png` + `Icon_Ads.png`): `"GET"` + Heart `+1`
/// - Right green coin button (`Button_Green.png`): `"Refill Lives"` + `Icon_Coin.png` `900`
class MoreLivesDialog extends StatefulWidget {
  final PlayerProgressService progress;
  final int? refillCost;
  final VoidCallback onWatchAdForOneLife;
  final VoidCallback onRefillWithCoins;
  final VoidCallback? onInsufficientCoins;
  final VoidCallback? onLifeRecovered;
  final VoidCallback onClose;

  const MoreLivesDialog({
    super.key,
    required this.progress,
    this.refillCost,
    required this.onWatchAdForOneLife,
    required this.onRefillWithCoins,
    this.onInsufficientCoins,
    this.onLifeRecovered,
    required this.onClose,
  });

  @override
  State<MoreLivesDialog> createState() => _MoreLivesDialogState();
}

class _MoreLivesDialogState extends State<MoreLivesDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..forward();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final gained = widget.progress.syncLivesRegen();
      setState(() {});
      if (gained > 0 && widget.progress.lives > 0) {
        widget.onLifeRecovered?.call();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _entranceCtrl.dispose();
    super.dispose();
  }

  static const _heartCountMaterial = UnityTextMaterial(
    faceTop: Colors.white,
    faceBottom: Color(0xFFFFF5F5),
    strokeColor: Color(0xFF9F1111),
    strokeRatio: 0.16,
    outerStrokeColor: Color(0xFF6B0606),
    outerStrokeRatio: 0.22,
    underlayColor: Color(0xAA4A0404),
    underlayYRatio: 0.08,
    fontFamily: 'PoetsenOne',
    fontWeight: FontWeight.w400,
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.progress,
      builder: (context, _) {
        final lives = widget.progress.lives;
        final isFull = lives >= widget.progress.currentMaxLives;
        final resolvedRefillCost =
            widget.refillCost ?? RemoteConfigService.liveHeartRefillPrice;
        final canAfford = widget.progress.coins >= resolvedRefillCost;
        final countdown = widget.progress.formattedNextLifeCountdown();

        return AnimatedBuilder(
          animation: _entranceCtrl,
          builder: (context, cardChild) {
            final raw = _entranceCtrl.value.clamp(0.0, 1.0);
            final scrimAlpha = 0.80 * Curves.easeOut.transform(raw);
            final scaleT = Curves.easeOutBack.transform(raw);
            return ColoredBox(
              key: const ValueKey('more_lives_modal'),
              color: Color.fromRGBO(6, 4, 20, scrimAlpha),
              child: SafeArea(
                child: Center(
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * scaleT,
                    child: Opacity(opacity: raw, child: cardChild),
                  ),
                ),
              ),
            );
          },
          child: SizedBox(
            key: const ValueKey('more_lives_popup_card'),
            width: ux(context, 884),
            height: ux(context, 930),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Gold-Rimmed Royal-Blue Popup Body (`popup_bg.png`)
                Positioned(
                  left: 0,
                  right: 0,
                  top: ux(context, 23),
                  height: ux(context, 907),
                  child: Image.asset(
                    'assets/images/popup_bg.png',
                    width: ux(context, 884),
                    height: ux(context, 907),
                    fit: BoxFit.fill,
                  ),
                ),

                // 2. Cream Inner Content Well (`frame_content.png`)
                Positioned(
                  left: ux(context, 50),
                  top: ux(context, 165),
                  width: ux(context, 784),
                  height: ux(context, 425),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/frame_content.png',
                        fit: BoxFit.fill,
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ux(context, 36),
                          vertical: ux(context, 28),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Left: Glossy 3D Heart + Current Lives Number
                                    SizedBox(
                                      width: ux(context, 240),
                                      height: ux(context, 224),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Image.asset(
                                            'assets/images/icon_heart.png',
                                            width: ux(context, 234),
                                            height: ux(context, 218),
                                            fit: BoxFit.contain,
                                          ),
                                          Transform.translate(
                                            offset: Offset(0, -ux(context, 6)),
                                            child: UnitySdfText(
                                              '$lives',
                                              key: const ValueKey(
                                                'more_lives_count_text',
                                              ),
                                              unityFontSize: 108,
                                              material: _heartCountMaterial,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: ux(context, 28)),

                                    // Right: "Next life in:" + Clock Countdown Pill
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          isFull
                                              ? 'Lives full!'
                                              : 'Next life in:',
                                          style: TextStyle(
                                            fontFamily: 'Baloo2',
                                            fontSize: ux(context, 44),
                                            fontWeight: FontWeight.w800,
                                            fontVariations: const [
                                              FontVariation('wght', 800),
                                            ],
                                            color: const Color(0xFF5A270B),
                                            height: 1.05,
                                          ),
                                        ),
                                        SizedBox(height: ux(context, 14)),
                                        _NextLifeCountdownPill(
                                          countdown: countdown,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Bottom prompt text
                            Padding(
                              padding: EdgeInsets.only(bottom: ux(context, 8)),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  'Get more lives to continue playing',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Baloo2',
                                    fontSize: ux(context, 41),
                                    fontWeight: FontWeight.w800,
                                    fontVariations: const [
                                      FontVariation('wght', 800),
                                    ],
                                    color: const Color(0xFF5A270B),
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 3a. Left Blue Ads CTA (`GET +1` Heart)
                Positioned(
                  left: ux(context, 51),
                  top: ux(context, 636),
                  width: ux(context, 386),
                  height: ux(context, 221),
                  child: _MoreLivesAdsButton(
                    enabled: !isFull,
                    onTap: !isFull ? widget.onWatchAdForOneLife : null,
                  ),
                ),

                // 3b. Right Green Coins CTA (`Refill Lives 900`)
                Positioned(
                  right: ux(context, 45),
                  top: ux(context, 636),
                  width: ux(context, 393),
                  height: ux(context, 221),
                  child: _MoreLivesCoinsButton(
                    cost: resolvedRefillCost,
                    enabled: !isFull && canAfford,
                    onTap: !isFull
                        ? (canAfford
                              ? widget.onRefillWithCoins
                              : widget.onInsufficientCoins)
                        : null,
                  ),
                ),

                // 4. Top Header Ribbon (`Frame_Popup_Title.png`, `"More Lives?"`)
                Positioned(
                  left: ux(context, (884 - 558) * 0.5),
                  top: 0,
                  width: ux(context, 558),
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
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: UnitySdfText(
                          'More Lives?',
                          unityFontSize: 64,
                          material: UnityTextMaterial.popupTitle,
                        ),
                      ),
                    ),
                  ),
                ),

                // 5. Top-Right Close Button (`Button_Close.png`)
                Positioned(
                  right: ux(context, 14),
                  top: ux(context, 4),
                  width: ux(context, 139),
                  height: ux(context, 139),
                  child: UnitySpriteButton(
                    key: const ValueKey('more_lives_close_btn'),
                    asset: 'Button_Close.png',
                    unitySize: 139,
                    onTap: widget.onClose,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NextLifeCountdownPill extends StatelessWidget {
  final String countdown;

  const _NextLifeCountdownPill({required this.countdown});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ux(context, 286),
      height: ux(context, 84),
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: ux(context, 26),
            right: 0,
            top: ux(context, 10),
            bottom: ux(context, 10),
            child: Container(
              padding: EdgeInsets.only(
                left: ux(context, 54),
                right: ux(context, 18),
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFA8332B), Color(0xFF7B1F1B)],
                ),
                borderRadius: BorderRadius.circular(ux(context, 20)),
                border: Border.all(
                  color: const Color(0xFFD99E6E),
                  width: ux(context, 3.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x66400C0A),
                    blurRadius: ux(context, 6),
                    offset: Offset(0, ux(context, 3)),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  countdown,
                  key: const ValueKey('more_lives_countdown_text'),
                  style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontSize: ux(context, 44),
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: Colors.white,
                    height: 1.0,
                    shadows: const [
                      Shadow(
                        offset: Offset(0, 1.8),
                        blurRadius: 2.0,
                        color: Color(0xCC3B0907),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: ux(context, 4),
            width: ux(context, 76),
            height: ux(context, 76),
            child: Image.asset(
              'assets/images/Icon_Clock.png',
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreLivesAdsButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onTap;

  const _MoreLivesAdsButton({required this.enabled, required this.onTap});

  @override
  State<_MoreLivesAdsButton> createState() => _MoreLivesAdsButtonState();
}

class _MoreLivesAdsButtonState extends State<_MoreLivesAdsButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    final mat = active ? UnityTextMaterial.ctaBlue : UnityTextMaterial.ctaGray;

    Widget content = Stack(
      clipBehavior: Clip.none,
      children: [
        UnityNineSlice(
          sprite: 'Button_Blue.png',
          width: ux(context, 386),
          height: ux(context, 221),
          padding: EdgeInsets.fromLTRB(
            ux(context, 26),
            0,
            ux(context, 24),
            ux(context, 14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              UnitySdfText('GET', unityFontSize: 62, material: mat),
              SizedBox(width: ux(context, 12)),
              SizedBox(
                width: ux(context, 102),
                height: ux(context, 96),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/images/icon_heart.png',
                      fit: BoxFit.contain,
                    ),
                    Transform.translate(
                      offset: Offset(0, -ux(context, 3)),
                      child: const UnitySdfText(
                        '+1',
                        unityFontSize: 42,
                        material: _MoreLivesDialogState._heartCountMaterial,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: -ux(context, 8),
          top: -ux(context, 42),
          width: ux(context, 122),
          height: ux(context, 127),
          child: IgnorePointer(
            child: Image.asset(
              'assets/images/Icon_Ads.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ],
    );

    if (!active) {
      content = ColorFiltered(
        colorFilter: UnityButtonColorFilters.disabledSilver,
        child: content,
      );
    }

    return GestureDetector(
      key: const ValueKey('more_lives_watch_ad_btn'),
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => setState(() => _pressed = true) : null,
      onTapUp: active ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: active ? () => setState(() => _pressed = false) : null,
      onTap: active ? widget.onTap : null,
      child: AnimatedScale(
        scale: (_pressed && active) ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: content,
      ),
    );
  }
}

class _MoreLivesCoinsButton extends StatefulWidget {
  final int cost;
  final bool enabled;
  final VoidCallback? onTap;

  const _MoreLivesCoinsButton({
    required this.cost,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_MoreLivesCoinsButton> createState() => _MoreLivesCoinsButtonState();
}

class _MoreLivesCoinsButtonState extends State<_MoreLivesCoinsButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    final interactive = widget.onTap != null;
    final mat = active ? UnityTextMaterial.ctaGreen : UnityTextMaterial.ctaGray;

    Widget content = UnityNineSlice(
      sprite: 'Button_Green.png',
      width: ux(context, 393),
      height: ux(context, 221),
      padding: EdgeInsets.fromLTRB(
        ux(context, 22),
        ux(context, 8),
        ux(context, 22),
        ux(context, 14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: UnitySdfText('Refill Lives', unityFontSize: 48, material: mat),
          ),
          SizedBox(height: ux(context, 4)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/Icon_Coin.png',
                width: ux(context, 56),
                height: ux(context, 56),
                fit: BoxFit.contain,
              ),
              SizedBox(width: ux(context, 8)),
              UnitySdfText('${widget.cost}', unityFontSize: 54, material: mat),
            ],
          ),
        ],
      ),
    );

    if (!active) {
      content = ColorFiltered(
        colorFilter: UnityButtonColorFilters.disabledSilver,
        child: content,
      );
    }

    return GestureDetector(
      key: const ValueKey('more_lives_refill_coins_btn'),
      behavior: HitTestBehavior.opaque,
      onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
      onTapUp: interactive ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: interactive ? () => setState(() => _pressed = false) : null,
      onTap: interactive ? widget.onTap : null,
      child: AnimatedScale(
        scale: (_pressed && interactive) ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: content,
      ),
    );
  }
}
