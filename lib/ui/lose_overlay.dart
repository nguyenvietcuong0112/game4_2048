import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/player_progress_service.dart';
import 'unity_ui_kit.dart';

/// 100% Pixel-Exact Two-Stage Replica of Unity `PlayOnPopupView.prefab` -> `LoseGameplayView.prefab`:
///
/// - **Backdrop (`DarkOverlay`)**: `rgba(0.020, 0.000, 0.051, 0.949)` (`Color.fromRGBO(5, 0, 13, 0.949)`).
///   Acts as Unity's `_backgroundHoldButton` (`HoldButton`): pressing & holding anywhere outside
///   `PopupContainer` (including on `"Tap to see the board"`) fades the entire `PlayOnPopupView`
///   canvas to `alpha = 0.0` (`PlayOn_PeekBoard`), and releasing restores `alpha = 1.0` (`PlayOn_UnpeekBoard`).
///
/// - **Stage 1 (`PlayOnPopupView`, `PlayOn_Open` `0.000s..1.500s`)**:
///   1. `0.000s..1.333s`: Full-width `Banner_Root` (`sz = (+18.95, 372.70)` at screen center) with
///      9-slice `Banner.png` + `"OUT OF TIME"` (`sz = 134.1`, `Baloo2_ExtraBold_OutOfTime`),
///      animated via `UISideSwipeMask_Material` (`rotation = 30°`, `softness = 0.2`) wiping in
///      `0.00s..0.25s`, holding `0.25s..1.083s`, and wiping out `1.083s..1.333s`.
///   2. `1.333s..1.500s`: `PopupContainer` (`1106.25 x 1337.91`, `sc = 0.816`, `dy = -34.49` above
///      `SafeArea` center) and bottom `TapToPeek` (`Icon_Eye.png` + `"Tap to see the board"`) fade in:
///      - `Header`: `"Continue?"` (`localFontSize = 116.5`) + `CloseButton` (`173.90 x 170.18`).
///      - `Panel`: `Panel_PlayOn.png` circular badge (`m_Type = Simple`, `PreserveAspect = 1`,
///        `429.06 x 421.68` local) with `+{extraSeconds}<size=128>s</size>` (`193.3` / `128.0`),
///        plus `"Add {extraSeconds} seconds to keep playing!"` (`localFontSize = 76.6`, `#07279A`).
///      - `Footer`: Horizontal pair (`spacing = 30.0`) of `CoinsButton` (`500.00 x 226.79`, top
///        `"Play On"` `79.4` + bottom `Inset_Button_CTA` `305.55 x 79.18` with `Icon_Coin` `65x65`
///        & price `82.26`, swapping to `Button_CTA_Disabled` + `Inset_Button_CTA_Red` + `ctaGray`
///        when `!canAfford`) and `AdsButton` (`500.00 x 226.79`, `Button_Blue`, left `Icon_Ad`
///        `121.76 x 121.76` at `x = 73.5` + right `"Play On"` `75.91`).
///
/// - **Stage 2 (`LoseGameplayView` when tapping `CloseButton`)**:
///   - Centered `PopupContainer` (`1106.25 x 1337.91`, `sc = 0.816`), `CloseButton` hidden (`active = False`):
///     - `Header`: `"${levelLabel} failed"` (`localFontSize = 137.37`).
///     - `Panel`: `Icon_BrokenLife.png` (`510.72 x 403.71` at `(0, +90.66)`), overlapping `"-1"`
///       (`pos = (+103.80, -31.90)`, `localFontSize = 212.2`, `Baloo2_ExtraBold_Navigation_Bar_Label_Brown`),
///       and 5 `Icon_Life.png` hearts (`878.45 x 124.50` at `(0, -253.00)`, `spacing = -20.4`,
///       remaining lives `alpha = 1.0`, lost lives `alpha = 0.7` per `LoseGameplayView.DisabledLifeAlpha`).
///     - `Footer`: Single centered `Button_CTA.png` (`585.20 x 217.44`, `"Try Again"`, `localFontSize = 116.6`).
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
    // Only allow board peek once `PopupContainer` & `TapToPeek` have appeared (`t >= 1.333s`)
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

  /// Stage 1: Exact `PlayOnPopupView.prefab` + `PlayOn_Open.anim` + `PlayOn_PeekBoard.anim`.
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

              // 3. `SafeArea / PopupContainer` + `TapToPeek` (`1.333s..1.500s` fade-in)
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
            // `SafeArea -> PopupContainer` (`pos = (540, -925.51)` => `-34.49` above center)
            SafeArea(
              child: Center(
                child: Transform.translate(
                  offset: Offset(0.0, -ux(context, 34.49)),
                  child: UnityPopupCard(
                    title: 'Continue?',
                    localTitleFontSize: 116.5,
                    animateEntrance: false,
                    onClose: _goToFailedStage,
                    panelChild: _buildPlayOnPanel(context),
                    footerChild: OverflowBox(
                      maxWidth: ppx(context, 1040.0),
                      maxHeight: ppx(context, 290.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PlayOnCoinsButton(
                            cost: widget.playOnCost,
                            enabled: canAfford,
                            onTap: canAfford ? widget.onPlayOnCoins : null,
                          ),
                          SizedBox(width: ppx(context, 30.0)),
                          _PlayOnAdsButton(
                            onTap: widget.onPlayOnAd,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // `Canvas / TapToPeek` (`amin=(0.5,0) pos=(0,212) sz=(1094.05, 237.49) sc=0.816`, `blocksRaycasts=False`)
            Positioned(
              left: 0,
              right: 0,
              bottom: math.max(
                MediaQuery.paddingOf(context).bottom + ux(context, 8.0),
                ux(context, 212.0) - ppx(context, 237.49 * 0.5),
              ),
              height: ppx(context, 237.49),
              child: IgnorePointer(
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // `EyeIcon`: `amin=(0.5,0) piv=(0.5,0) pos=(0, 132.70) sz=(111.31, 80.00)`
                    Positioned(
                      bottom: ppx(context, 132.70),
                      width: ppx(context, 111.31),
                      height: ppx(context, 80.00),
                      child: Image.asset(
                        'assets/images/Icon_Eye.png',
                        fit: BoxFit.contain,
                      ),
                    ),

                    // `TapToPeekText`: `amin=(0.5,0) piv=(0.5,0) pos=(0, 40.00) sz=(900.00, 80.00)`
                    Positioned(
                      bottom: ppx(context, 40.00),
                      width: ppx(context, 900.00),
                      height: ppx(context, 80.00),
                      child: Center(
                        child: Text(
                          'Tap to see the board',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Baloo2',
                            fontSize: ppx(context, 60.31),
                            fontWeight: FontWeight.w800,
                            fontVariations: const [FontVariation('wght', 800)],
                            color: Colors.white,
                            height: 1.05,
                          ),
                        ),
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

  /// Exact `PlayOnPopupView` `Panel` (`1026.50 x 734.23` local, center `(513.25, 367.115)`):
  /// - `RewardItem` (`pos = (0.12, +80.21)`, `sz = (826.25, 325.00)`):
  ///   - `Background`: `Panel_PlayOn.png` (`m_Type = 0` Simple, `PreserveAspect = 1`,
  ///     `pos = (0, +23.03)`, `sz = (+24.00, +96.68)` -> `850.25 x 421.68` box -> `429.06 x 421.68` circle)
  ///   - `Text`: `+{extraSeconds}<size=128>s</size>` (`fontSize = 193.3`, `'s'` `= 128.0`, `pos = (0, +23.00)`)
  /// - `RewardDescription` (`pos = (0.12, -216.00)`, `sz = (565.69, 180.74)`):
  ///   `"Add 30 seconds to keep playing!"` (`fontSize = 76.6`, `lineSpacing = -38.0`, `#07279A`).
  Widget _buildPlayOnPanel(BuildContext context) {
    const double panelCx = UnityPopupCard.localInnerWidth * 0.5; // 513.25
    const double panelCy = UnityPopupCard.localPanelHeight * 0.5; // 367.115

    // Circle center in Panel: `panelCy - 80.21 - 23.03 = 263.875`
    const double circleCx = panelCx + 0.12;
    const double circleCy = panelCy - 80.21 - 23.03;
    const double circleW = 850.25;
    const double circleH = 421.68;

    // Description center in Panel: `panelCy + 216.00 = 583.115`
    const double descCx = panelCx + 0.12;
    const double descCy = panelCy + 216.00;
    const double descW = 580.0;
    const double descH = 186.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 1. `RewardItem / Background` (`Panel_PlayOn.png` glossy blue circle, NOT 9-sliced!)
        Positioned(
          left: ppx(context, circleCx - circleW * 0.5),
          top: ppx(context, circleCy - circleH * 0.5),
          width: ppx(context, circleW),
          height: ppx(context, circleH),
          child: Image.asset(
            'assets/images/Panel_PlayOn.png',
            fit: BoxFit.contain,
          ),
        ),

        // 2. `RewardItem / Text` (`+30<size=128>s</size>` centered inside the circle)
        Positioned(
          left: ppx(context, circleCx - 210.0),
          top: ppx(context, (panelCy - 80.21 - 23.00) - 130.0),
          width: ppx(context, 420.0),
          height: ppx(context, 260.0),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  UnitySdfText(
                    '+${widget.extraSeconds}',
                    unityFontSize: 193.3 * kUnityPopupScale,
                    material: UnityTextMaterial.popupTitle,
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: ppx(context, 15.0)),
                    child: UnitySdfText(
                      's',
                      unityFontSize: 128.0 * kUnityPopupScale,
                      material: UnityTextMaterial.popupTitle,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 3. `RewardDescription` (`"Add 30 seconds to keep playing!"`, `76.6`, `#07279A`)
        Positioned(
          left: ppx(context, descCx - descW * 0.5),
          top: ppx(context, descCy - descH * 0.5),
          width: ppx(context, descW),
          height: ppx(context, descH),
          child: Center(
            child: Text(
              'Add ${widget.extraSeconds} seconds to keep playing!',
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontFamily: 'Baloo2',
                fontSize: ppx(context, 76.6),
                fontWeight: FontWeight.w800,
                fontVariations: const [FontVariation('wght', 800)],
                color: const Color(0xFF07279A),
                height: 0.98,
              ),
            ),
          ),
        ),
      ],
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

/// Exact `PlayOnPopupView` `CoinsButton` (`sz = (500.00, 226.79)` inside `0.816` `PopupContainer`):
/// - `Background`: `Button_CTA.png` (`ppuMult = 0.82`) or `Button_CTA_Disabled.png`,
///   `pos = (0, -10), sz = (+20, +20)` (`left=-10, right=-10, top=0, bottom=-20`).
/// - `Label`: `"Play On"` (`fontSize = 79.4`, `pos = (4.79, +41.80)` -> upper half).
/// - `Inset`: `amin=(0.5, 0) pos=(0, 72.96) sz=(305.55, 79.18)`:
///   - `Background`: `Inset_Button_CTA.png` (`Interactive`) or `Inset_Button_CTA_Red.png`
///     (`Noninteractive`), `ppuMult = 0.80`, `pos=(0, -0.5) sz=(+4, +5)`.
///   - `Content`: `pos=(0, -3.0)`, `Spacing = 21.2`, `Icon_Coin.png` (`65x65`) + `Price` (`82.26`).
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
    final insetSprite =
        active ? 'Inset_Button_CTA.png' : 'Inset_Button_CTA_Red.png';
    final textMat =
        active ? UnityTextMaterial.ctaGreen : UnityTextMaterial.ctaGray;

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
        scale: _pressed && active ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: ppx(context, 500.00),
          height: ppx(context, 226.79),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Gold-rimmed pill background (`Button_CTA.png`)
              Positioned(
                left: ppx(context, -6.0),
                right: ppx(context, -6.0),
                top: 0.0,
                bottom: ppx(context, -16.0),
                child: IgnorePointer(
                  child: UnityNineSlice(
                    sprite: 'Button_CTA.png',
                    colorFilter: active
                        ? null
                        : UnityButtonColorFilters.disabledSilver,
                    pixelMultiplier: kUnityPopupScale,
                  ),
                ),
              ),

              // 2. Top `Label` (`"Play On"`, `pos=(4.79, +41.80) sz=(-38.42, -118.00)`)
              Positioned(
                left: ppx(context, 19.21 + 4.79),
                right: ppx(context, 19.21 - 4.79),
                top: ppx(context, 59.00 - 41.80),
                height: ppx(context, 108.79),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: UnitySdfText(
                      'Play On',
                      unityFontSize: 79.4 * kUnityPopupScale,
                      material: textMat,
                    ),
                  ),
                ),
              ),

              // 3. Bottom `Inset` (`amin=(0.5,0) pos=(0, 72.96) sz=(305.55, 79.18)`)
              Positioned(
                left: ppx(context, (500.00 - 305.55) * 0.5),
                bottom: ppx(context, 72.96 - 79.18 * 0.5),
                width: ppx(context, 305.55),
                height: ppx(context, 79.18),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // `Inset/Background` (`pos=(0,-0.5) sz=(+4,+5)`, `ppuMult = 0.80`)
                    Positioned(
                      left: ppx(context, -2.0),
                      right: ppx(context, -2.0),
                      top: ppx(context, -2.0),
                      bottom: ppx(context, -3.0),
                      child: IgnorePointer(
                        child: UnityNineSlice(
                          sprite: insetSprite,
                          pixelMultiplier: kUnityPopupScale / 0.80,
                        ),
                      ),
                    ),

                    // `Inset/Content` (`pos=(0,-3.0)`, `Spacing = 21.2`, `Coin` `65x65` + `Price` `82.26`)
                    Positioned.fill(
                      top: ppx(context, 3.0),
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: ppx(context, 14.0),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/images/Icon_Coin.png',
                                  width: ppx(context, 65.0),
                                  height: ppx(context, 65.0),
                                  fit: BoxFit.contain,
                                ),
                                SizedBox(width: ppx(context, 21.2)),
                                UnitySdfText(
                                  '${widget.cost}',
                                  unityFontSize: 82.26 * kUnityPopupScale,
                                  letterSpacing: ppx(context, -1.2),
                                  material: textMat,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Exact `PlayOnPopupView` `AdsButton` (`sz = (500.00, 226.79)` inside `0.816` `PopupContainer`):
/// - `Background`: `Button_Blue.png` (`ppuMult = 0.82`), `left=-10, right=-10, top=0, bottom=-20`.
/// - `Icon_Ad`: `Icon_Ad.png`, `amin=(0, 0.5) pos=(73.50, 0) sz=(121.76, 121.76)`.
/// - `Label`: `"Play On"`, `pos=(+50.35, -4.20) sz=(-124.00, -56.39)`, `fontSize = 75.91`, `charSpacing = 1.0`.
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
        scale: _pressed && enabled ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: ppx(context, 500.00),
          height: ppx(context, 226.79),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 1. Gold-rimmed royal-blue pill background (`Button_CTA.png` + `blueWithGoldRim`)
              Positioned(
                left: ppx(context, -6.0),
                right: ppx(context, -6.0),
                top: 0.0,
                bottom: ppx(context, -16.0),
                child: IgnorePointer(
                  child: UnityNineSlice(
                    sprite: 'Button_CTA.png',
                    colorFilter: enabled
                        ? UnityButtonColorFilters.blueWithGoldRim
                        : UnityButtonColorFilters.disabledSilver,
                    pixelMultiplier: kUnityPopupScale,
                  ),
                ),
              ),

              // 2. `Icon_Ad`
              Positioned(
                left: ppx(context, 48.0),
                top: ppx(context, (226.79 - 106.0) * 0.5),
                width: ppx(context, 106.0),
                height: ppx(context, 106.0),
                child: Image.asset(
                  'assets/images/Icon_Ad.png',
                  fit: BoxFit.contain,
                ),
              ),

              // 3. `Label` (`"Play On"`)
              Positioned(
                left: ppx(context, 162.0),
                right: ppx(context, 40.0),
                top: ppx(context, 28.0),
                bottom: ppx(context, 28.0),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: UnitySdfText(
                      'Play On',
                      unityFontSize: 75.91 * kUnityPopupScale,
                      letterSpacing: ppx(context, 0.6),
                      material: enabled
                          ? UnityTextMaterial.ctaBlue
                          : UnityTextMaterial.ctaGray,
                    ),
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
