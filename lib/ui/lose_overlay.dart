import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/player_progress_service.dart';
import 'unity_ui_kit.dart';

/// Two-Stage `Out of time!` (`assets/UI Bo Sung/Out of time/Out of time.png`) -> `LoseGameplayView.prefab`:
///
/// - **Backdrop (`DarkOverlay`)**: `rgba(0.020, 0.000, 0.051, 0.949)` (`Color.fromRGBO(5, 0, 13, 0.949)`).
///   Acts as `_backgroundHoldButton` (`HoldButton`): pressing & holding anywhere outside
///   the popup card (including on `"Hold to see board"`) fades the entire `Out of time!`
///   canvas to `alpha = 0.0`, and releasing restores `alpha = 1.0`.
///
/// - **Stage 1 (`Out of time!`, `0.000s..1.500s`)**:
///   1. `0.000s..1.333s`: Full-width `Banner_Root` (`Banner.png` + `"OUT OF TIME"`)
///      wiping in `0.00s..0.25s`, holding `0.25s..1.083s`, and wiping out `1.083s..1.333s`.
///   2. `1.333s..1.500s`: Redesigned `Out of time!` popup (`884x1044` in `ux` coordinates)
///      and bottom `"Hold to see board"` prompt fade in:
///      - `popup_bg.png` (`884x1021` at `top = 23`)
///      - `Frame_Popup_Title.png` (`558x143` at `top = 0`) with `"Out of time!"`
///      - `Button_Close.png` (`139x139` at `right = 14, top = 4`)
///      - `frame_content.png` (`784x495` at `left = 50, top = 167`):
///        - `Icon_Clock.png` (`232x278` at `top = 43`) with overlapping `"+30s"` at bottom-right
///        - `"Add 30 seconds\nto keep playing"` (`#5A270B`, `fontSize = 54`)
///      - Bottom row at `top = 725`:
///        - Left `_PlayOnCoinsButton` (`Button_Green.png` `393x221`, `Icon_Coin.png` + `${playOnCost}`)
///        - Right `_PlayOnAdsButton` (`Button_Yellow.png` `386x221`, `"Continue"` + top-left `Icon_Ads.png` `122x127`)
///
/// - **Stage 2 (`LoseGameplayView` when tapping `CloseButton`)**:
///   - Centered `PopupContainer` (`"${levelLabel} failed"`, `Icon_BrokenLife.png`, `"-1"`, 5 hearts, `"Try Again"`).
class LoseOverlay extends StatefulWidget {
  final String levelLabel;
  final int playerCoins;
  final int remainingLives;
  final int playOnCost;
  final int extraSeconds;
  final VoidCallback onPlayOnCoins;
  final VoidCallback onPlayOnAd;
  final VoidCallback? onEnterFailedStage;
  final ValueChanged<bool>? onPeekingChanged;
  final VoidCallback onRetry;

  const LoseOverlay({
    super.key,
    required this.levelLabel,
    required this.playerCoins,
    required this.remainingLives,
    this.playOnCost = 450,
    this.extraSeconds = 30,
    required this.onPlayOnCoins,
    required this.onPlayOnAd,
    this.onEnterFailedStage,
    this.onPeekingChanged,
    required this.onRetry,
  });

  @override
  State<LoseOverlay> createState() => _LoseOverlayState();
}

class _LoseOverlayState extends State<LoseOverlay>
    with SingleTickerProviderStateMixin {
  /// Exact `PlayOn_Open` clip duration (`stopTime = 1.500s` at `60fps`).
  static const Duration _openDuration = Duration(milliseconds: 1500);

  late final AnimationController _openCtrl;
  bool _peekingBoard = false;
  bool _inFailedStage = false;

  @override
  void initState() {
    super.initState();
    _openCtrl = AnimationController(
      vsync: this,
      duration: _openDuration,
    )..forward();
  }

  @override
  void dispose() {
    _openCtrl.dispose();
    super.dispose();
  }

  void _setPeeking(bool peeking) {
    if (_inFailedStage) return;
    // Only allow board peek once popup & `"Hold to see board"` have appeared (`t >= 1.333s`)
    if (peeking && _openCtrl.value < (1.333 / 1.500)) return;
    if (_peekingBoard == peeking) return;
    setState(() => _peekingBoard = peeking);
    widget.onPeekingChanged?.call(peeking);
  }

  void _goToFailedStage() {
    if (_inFailedStage) return;
    if (_peekingBoard) {
      _peekingBoard = false;
      widget.onPeekingChanged?.call(false);
    }
    widget.onEnterFailedStage?.call();
    setState(() {
      _inFailedStage = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_inFailedStage) {
      return _buildStage2LoseFailed(context);
    }
    return _buildStage1PlayOn(context);
  }

  /// Stage 1: Redesigned `Out of time!` popup (`assets/UI Bo Sung/Out of time/Out of time.png`)
  /// + `PlayOn_Open.anim` + `PlayOn_PeekBoard.anim`.
  Widget _buildStage1PlayOn(BuildContext context) {
    final canAfford = widget.playerCoins >= widget.playOnCost;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      opacity: _peekingBoard ? 0.0 : 1.0,
      child: AnimatedBuilder(
        animation: _openCtrl,
        builder: (context, popupAndPeekChild) {
          final tSec = _openCtrl.value * 1.5;
          final showBanner = tSec < 1.333;
          final showPopup = tSec >= 1.333;
          final popupAlpha =
              showPopup ? ((tSec - 1.333) / (1.500 - 1.333)).clamp(0.0, 1.0) : 0.0;

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. `DarkOverlay` (`rgba(0.020, 0.000, 0.051, 0.949)`) + `_backgroundHoldButton`
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _setPeeking(true),
                onPointerUp: (_) => _setPeeking(false),
                onPointerCancel: (_) => _setPeeking(false),
                child: const ColoredBox(
                  color: Color.fromRGBO(5, 0, 13, 0.949),
                  child: SizedBox.expand(),
                ),
              ),

              // 2. `Banner_Root` (`0.000s..1.333s` full-width `"OUT OF TIME"` diagonal side-swipe)
              if (showBanner) _buildOutOfTimeBanner(context, tSec),

              // 3. `Out of time!` Popup Card + `"Hold to see board"` (`1.333s..1.500s` fade-in)
              if (showPopup)
                Opacity(
                  opacity: popupAlpha,
                  child: IgnorePointer(
                    ignoring: _peekingBoard,
                    child: popupAndPeekChild,
                  ),
                ),
            ],
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Redesigned `Out of time!` Popup Card (`884 x 1044` Unity px)
            SafeArea(
              child: Center(
                child: Transform.translate(
                  offset: Offset(0.0, -ux(context, 24.0)),
                  child: _buildOutOfTimePopupCard(context, canAfford: canAfford),
                ),
              ),
            ),

            // Bottom `"Hold to see board"` prompt (`Out of time.png`)
            Positioned(
              left: 0,
              right: 0,
              bottom: math.max(
                MediaQuery.paddingOf(context).bottom + ux(context, 48.0),
                ux(context, 160.0),
              ),
              height: ux(context, 84.0),
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    'Hold to see board',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontSize: ux(context, 54.0),
                      fontWeight: FontWeight.w800,
                      fontVariations: const [FontVariation('wght', 800)],
                      color: Colors.white,
                      height: 1.05,
                      shadows: const [
                        Shadow(
                          color: Color(0xCC000000),
                          offset: Offset(0, 2.5),
                          blurRadius: 5.0,
                        ),
                      ],
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

  /// Redesigned `Out of time!` Popup Card (`Out of time.png`, `884x1044` Unity px):
  /// - `popup_bg.png` (`884x1021` at `top = 23`)
  /// - `Frame_Popup_Title.png` (`558x143` centered at `top = 0`) with `"Out of time!"`
  /// - `Button_Close.png` (`139x139` at `right = 14, top = 4`)
  /// - `frame_content.png` (`784x495` at `left = 50, top = 167`):
  ///   - `Icon_Clock.png` (`232x278` at `top = 43`) + overlapping `"+30s"` at bottom-right
  ///   - `"Add 30 seconds\nto keep playing"` (`#5A270B`, `fontSize = 54`)
  /// - Bottom Buttons Row (`top = 725`):
  ///   - Left `_PlayOnCoinsButton` (`Button_Green.png` `393x221`)
  ///   - Right `_PlayOnAdsButton` (`Button_Yellow.png` `386x221` + `Icon_Ads.png` `122x127`)
  Widget _buildOutOfTimePopupCard(
    BuildContext context, {
    required bool canAfford,
  }) {
    return SizedBox(
      key: const ValueKey('out_of_time_popup_card'),
      width: ux(context, 884),
      height: ux(context, 1044),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Main Gold-Rimmed Blue Popup Body (`popup_bg.png`, `884x1021` at `top = 23`)
          // Absorbs pointer hits inside the card so taps never leak to `DarkOverlay` hold-to-peek!
          Positioned(
            left: 0,
            right: 0,
            top: ux(context, 23),
            height: ux(context, 1021),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: Image.asset(
                'assets/images/popup_bg.png',
                width: ux(context, 884),
                height: ux(context, 1021),
                fit: BoxFit.fill,
              ),
            ),
          ),

          // 2. Cream Inner Content Well (`frame_content.png`, `784x495` at `left = 50, top = 167`)
          Positioned(
            left: ux(context, 50),
            top: ux(context, 167),
            width: ux(context, 784),
            height: ux(context, 495),
            child: IgnorePointer(
              child: Stack(
                alignment: Alignment.topCenter,
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/frame_content.png',
                      fit: BoxFit.fill,
                    ),
                  ),

                  // Stopwatch Icon (`Icon_Clock.png`, `232x278` at `top = 43`)
                  Positioned(
                    top: ux(context, 43),
                    width: ux(context, 232),
                    height: ux(context, 278),
                    child: Image.asset(
                      'assets/images/Icon_Clock.png',
                      fit: BoxFit.contain,
                    ),
                  ),

                  // Overlapping `"+30s"` at bottom-right of the stopwatch (`Out of time.png`)
                  Positioned(
                    left: ux(context, 372),
                    top: ux(context, 224),
                    child: UnitySdfText(
                      '+${widget.extraSeconds}s',
                      unityFontSize: 82,
                      material: UnityTextMaterial.winCoinAmount,
                    ),
                  ),

                  // Dark brown description (`"Add 30 seconds\nto keep playing"`, `#5A270B`)
                  Positioned(
                    left: ux(context, 40),
                    right: ux(context, 40),
                    bottom: ux(context, 26),
                    child: Text(
                      'Add ${widget.extraSeconds} seconds\nto keep playing',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontSize: ux(context, 56),
                        fontWeight: FontWeight.w800,
                        fontVariations: const [FontVariation('wght', 800)],
                        color: const Color(0xFF5A270B),
                        height: 1.08,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Bottom Left Coin Button (`Button_Green.png`, `393x221` at `left = 51, top = 727`)
          Positioned(
            left: ux(context, 51),
            top: ux(context, 727),
            width: ux(context, 393),
            height: ux(context, 221),
            child: _PlayOnCoinsButton(
              cost: widget.playOnCost,
              enabled: canAfford,
              onTap: canAfford ? widget.onPlayOnCoins : null,
            ),
          ),

          // 4. Bottom Right Ad Continue Button (`Button_Yellow.png`, `386x221` at `right = 45, top = 725`)
          Positioned(
            right: ux(context, 45),
            top: ux(context, 725),
            width: ux(context, 386),
            height: ux(context, 221),
            child: _PlayOnAdsButton(
              onTap: widget.onPlayOnAd,
            ),
          ),

          // 5. Top Header Ribbon (`Frame_Popup_Title.png`, `558x143` centered at `top = 0`, `"Out of time!"`)
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
                    'Out of time!',
                    unityFontSize: 64,
                    material: UnityTextMaterial.popupTitle,
                  ),
                ),
              ),
            ),
          ),

          // 6. Top-Right Red-Gold Close Button (`Button_Close.png`, `139x139` at `right = 14, top = 4`)
          Positioned(
            right: ux(context, 14),
            top: ux(context, 4),
            width: ux(context, 139),
            height: ux(context, 139),
            child: UnitySpriteButton(
              asset: 'Button_Close.png',
              unitySize: 139,
              onTap: _goToFailedStage,
            ),
          ),
        ],
      ),
    );
  }

  /// Exact `Banner_Root` (`amin=(0, 0.5) amax=(1, 0.5) pos=(0,0) sz=(+18.95, 372.70)`)
  /// with `UISideSwipeMask_Material` (`rotation = 30°`, `softness = 0.2`).
  Widget _buildOutOfTimeBanner(BuildContext context, double tSec) {
    // Text alpha: 0 at t <= 0.05s, ramps 0->1 over 0.05..0.25s, holds 1 over 0.25..1.083s, ramps 1->0 over 1.083..1.333s
    double textAlpha;
    if (tSec <= 0.050) {
      textAlpha = 0.0;
    } else if (tSec < 0.250) {
      textAlpha = ((tSec - 0.050) / 0.200).clamp(0.0, 1.0);
    } else if (tSec <= 1.083) {
      textAlpha = 1.0;
    } else {
      textAlpha = (1.0 - (tSec - 1.083) / (1.333 - 1.083)).clamp(0.0, 1.0);
    }

    Widget banner = SizedBox(
      height: ux(context, 372.70),
      width: MediaQuery.sizeOf(context).width + ux(context, 18.95),
      child: UnityNineSlice(
        sprite: 'Banner.png',
        pixelMultiplier: 1.0,
        child: SizedBox(
          width: ux(context, 1022.01),
          height: ux(context, 246.87),
          child: Center(
            child: Opacity(
              opacity: textAlpha,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: ux(context, 24.0)),
                  child: const UnitySdfText(
                    'OUT OF TIME',
                    unityFontSize: 134.1,
                    material: UnityTextMaterial.outOfTime,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Apply 30-degree feathered diagonal side-swipe mask during wipe-in (0..0.25s) and wipe-out (1.083..1.333s)
    const double softness = 0.20;
    const double cos30 = 0.8660254;
    const double sin30 = 0.50;
    const beginAlign = Alignment(-cos30, -sin30);
    const endAlign = Alignment(cos30, sin30);

    if (tSec < 0.250) {
      final u = (tSec / 0.250).clamp(0.0, 1.0);
      final lead = (u * (1.0 + softness)).clamp(0.0, 1.0);
      final solid = (u * (1.0 + softness) - softness).clamp(0.0, 1.0);
      banner = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: beginAlign,
          end: endAlign,
          colors: const [
            Colors.white,
            Colors.white,
            Colors.transparent,
            Colors.transparent,
          ],
          stops: [0.0, solid, lead, 1.0],
        ).createShader(bounds),
        child: banner,
      );
    } else if (tSec > 1.083) {
      final v = ((tSec - 1.083) / (1.333 - 1.083)).clamp(0.0, 1.0);
      final clearEnd = (v * (1.0 + softness) - softness).clamp(0.0, 1.0);
      final solidStart = (v * (1.0 + softness)).clamp(0.0, 1.0);
      banner = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: beginAlign,
          end: endAlign,
          colors: const [
            Colors.transparent,
            Colors.transparent,
            Colors.white,
            Colors.white,
          ],
          stops: [0.0, clearEnd, solidStart, 1.0],
        ).createShader(bounds),
        child: banner,
      );
    }

    return IgnorePointer(
      child: Center(
        child: OverflowBox(
          maxWidth: MediaQuery.sizeOf(context).width + ux(context, 24.0),
          child: banner,
        ),
      ),
    );
  }

  /// Stage 2: Exact `LoseGameplayView.prefab` (`Level X failed`, `Icon_BrokenLife.png` `510.72x403.71`,
  /// overlapping `"-1"` `212.2` at `(+103.80, -31.90)`, 5 `Icon_Life.png` hearts, green `"Try Again"` CTA).
  Widget _buildStage2LoseFailed(BuildContext context) {
    final activeHearts =
        widget.remainingLives.clamp(0, PlayerProgressService.maxLives);
    const double panelCx = UnityPopupCard.localInnerWidth * 0.5; // 513.25
    const double panelCy = UnityPopupCard.localPanelHeight * 0.5; // 367.115

    // `BrokenLife`: `pos = (0, +90.66) sz = (510.72, 403.71)`
    const double brokenW = 510.72;
    const double brokenH = 403.71;
    const double brokenCy = panelCy - 90.66;

    // `Text (TMP)` `"-1"`: `pos = (+103.80, -31.90) sz = (197.94, 190.39)`
    const double minusCx = panelCx + 103.80;
    const double minusCy = panelCy + 31.90;

    // `Lives`: `pos = (0, -253.00) sz = (-148.05, -609.73)` -> `878.45 x 124.50`, `Spacing = -20.4`
    const double livesW = 878.45;
    const double livesH = 124.50;
    const double livesCy = panelCy + 253.00;
    const int maxHearts = PlayerProgressService.maxLives; // 5
    const double heartSpacing = -20.4;
    const double heartSlotW =
        (livesW - heartSpacing * (maxHearts - 1)) / maxHearts; // 192.01

    return ColoredBox(
      color: const Color.fromRGBO(5, 0, 13, 0.949),
      child: SafeArea(
        child: Center(
          child: UnityPopupCard(
            title: '${widget.levelLabel} failed',
            localTitleFontSize: 137.37,
            onClose: null, // `CloseButton` is `active = False` in `LoseGameplayView.prefab`
            panelChild: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. `BrokenLife` (`Icon_BrokenLife.png`, `510.72 x 403.71`)
                Positioned(
                  left: ppx(context, panelCx - brokenW * 0.5),
                  top: ppx(context, brokenCy - brokenH * 0.5),
                  width: ppx(context, brokenW),
                  height: ppx(context, brokenH),
                  child: Image.asset(
                    'assets/images/Icon_BrokenLife.png',
                    fit: BoxFit.contain,
                  ),
                ),

                // 2. Overlapping `"-1"` (`pos = (+103.80, -31.90)`, `fontSize = 212.2`)
                Positioned(
                  left: ppx(context, minusCx - 130.0),
                  top: ppx(context, minusCy - 120.0),
                  width: ppx(context, 260.0),
                  height: ppx(context, 240.0),
                  child: Center(
                    child: UnitySdfText(
                      '-1',
                      unityFontSize: 212.2 * kUnityPopupScale,
                      letterSpacing: ppx(context, 3.0),
                      material: UnityTextMaterial.brownCounter,
                    ),
                  ),
                ),

                // 3. `Lives` row (`878.45 x 124.50` directly on white panel, `Spacing = -20.4`,
                //    `DisabledLifeAlpha = 0.7` in `LoseGameplayView.SetAmountOfLives`)
                Positioned(
                  left: ppx(context, panelCx - livesW * 0.5),
                  top: ppx(context, livesCy - livesH * 0.5),
                  width: ppx(context, livesW),
                  height: ppx(context, livesH),
                  child: Stack(
                    children: List.generate(maxHearts, (idx) {
                      final filled = idx < activeHearts;
                      final slotLeft = idx * (heartSlotW + heartSpacing);
                      return Positioned(
                        left: ppx(context, slotLeft),
                        top: 0,
                        width: ppx(context, heartSlotW),
                        height: ppx(context, livesH),
                        child: Opacity(
                          opacity: filled ? 1.0 : 0.7,
                          child: Image.asset(
                            'assets/images/Icon_Life.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
            footerChild: UnityPopupCtaButton(
              skin: UnityButtonSkin.green,
              label: 'Try Again',
              onTap: widget.onRetry,
            ),
          ),
        ),
      ),
    );
  }
}

/// Redesigned `Out of time!` Left Coin Button (`Button_Green.png`, `393x221` in `Out of time.png`):
/// - Single horizontal row with `Icon_Coin.png` (`76x79`) + `${cost}` (`unityFontSize = 72`).
/// - Uses `UnityButtonColorFilters.disabledSilver` + `ctaGray` when unaffordable.
class _PlayOnCoinsButton extends StatefulWidget {
  final int cost;
  final bool enabled;
  final VoidCallback? onTap;

  const _PlayOnCoinsButton({
    required this.cost,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_PlayOnCoinsButton> createState() => _PlayOnCoinsButtonState();
}

class _PlayOnCoinsButtonState extends State<_PlayOnCoinsButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    final textMat =
        active ? UnityTextMaterial.ctaGreen : UnityTextMaterial.ctaGray;

    Widget buttonBody = Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/Button_Green.png',
            fit: BoxFit.fill,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(
            left: ux(context, 34),
            right: ux(context, 34),
            bottom: ux(context, 12),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/Icon_Coin.png',
                  width: ux(context, 76),
                  height: ux(context, 79),
                  fit: BoxFit.contain,
                ),
                SizedBox(width: ux(context, 16)),
                UnitySdfText(
                  '${widget.cost}',
                  unityFontSize: 72,
                  material: textMat,
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (!active) {
      buttonBody = ColorFiltered(
        colorFilter: UnityButtonColorFilters.disabledSilver,
        child: buttonBody,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: active ? (_) => setState(() => _pressed = true) : null,
      onTapUp: active
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: active ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed && active ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: buttonBody,
      ),
    );
  }
}

/// Redesigned `Out of time!` Right Ad Continue Button (`Button_Yellow.png`, `386x221` in `Out of time.png`):
/// - Golden-orange pill (`Button_Yellow.png`)
/// - Centered `"Continue"` (`unityFontSize = 62`, `ctaYellowButton`)
/// - Overlapping top-left clapperboard badge `assets/images/Icon_Ads.png` (`122x127` at `left = -8, top = -42`)!
class _PlayOnAdsButton extends StatefulWidget {
  final VoidCallback? onTap;

  const _PlayOnAdsButton({required this.onTap});

  @override
  State<_PlayOnAdsButton> createState() => _PlayOnAdsButtonState();
}

class _PlayOnAdsButtonState extends State<_PlayOnAdsButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

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
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // 1. Golden-orange pill (`Button_Yellow.png`, `386x221`)
            Positioned.fill(
              child: Image.asset(
                'assets/images/Button_Yellow.png',
                fit: BoxFit.fill,
              ),
            ),

            // 2. Centered `"Continue"` label
            Padding(
              padding: EdgeInsets.only(
                left: ux(context, 44),
                right: ux(context, 36),
                bottom: ux(context, 10),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: UnitySdfText(
                  'Continue',
                  unityFontSize: 62,
                  material: enabled
                      ? UnityTextMaterial.ctaYellowButton
                      : UnityTextMaterial.ctaGray,
                ),
              ),
            ),

            // 3. Top-Left Overlapping Clapperboard Badge (`Icon_Ads.png`, `122x127` at `left = -8, top = -42`)
            Positioned(
              left: -ux(context, 8),
              top: -ux(context, 42),
              width: ux(context, 122),
              height: ux(context, 127),
              child: Image.asset(
                'assets/images/Icon_Ads.png',
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
