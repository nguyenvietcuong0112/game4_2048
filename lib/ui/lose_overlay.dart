import 'package:flutter/material.dart';
import '../services/player_progress_service.dart';
import 'unity_ui_kit.dart';

/// Authentic two-stage replica of Unity `PlayOnPopupView.prefab` -> `LoseGameplayView.prefab`:
/// - Stage 1 (`PlayOnPopupView`): `#05000D(a=0.95)` backdrop, 9-slice `Banner.png` `"OUT OF TIME"`,
///   `UnityPopupCard` `"Continue?"` with `Button_Close.png`, 9-slice `Panel_PlayOn.png` `"+30s"`,
///   `"Add 30 seconds to keep playing!"` (`#07279A`), green `Play On` (`200` coins) + blue `Play On`
///   (`Icon_Ad.png`), and bottom `"Tap to see the board"` + `Icon_Eye.png` peek toggle.
/// - Stage 2 (`LoseGameplayView` when tapping `Button_Close.png`): `UnityPopupCard` `"Level X failed"`,
///   `Icon_BrokenLife.png` `"-1"`, 5 `Icon_Life.png` hearts, and green `"Try Again"` CTA.
class LoseOverlay extends StatefulWidget {
  final String levelLabel;
  final int playerCoins;
  final int remainingLives;
  final int playOnCost;
  final VoidCallback onPlayOnCoins;
  final VoidCallback onPlayOnAd;
  final VoidCallback? onEnterFailedStage;
  final VoidCallback onRetry;

  const LoseOverlay({
    super.key,
    required this.levelLabel,
    required this.playerCoins,
    required this.remainingLives,
    this.playOnCost = 200,
    required this.onPlayOnCoins,
    required this.onPlayOnAd,
    this.onEnterFailedStage,
    required this.onRetry,
  });

  @override
  State<LoseOverlay> createState() => _LoseOverlayState();
}

class _LoseOverlayState extends State<LoseOverlay> {
  bool _peekingBoard = false;
  bool _inFailedStage = false;

  void _goToFailedStage() {
    if (_inFailedStage) return;
    widget.onEnterFailedStage?.call();
    setState(() {
      _peekingBoard = false;
      _inFailedStage = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      color: Color.fromRGBO(5, 0, 13, _peekingBoard ? 0.14 : 0.93),
      child: SafeArea(
        child: _inFailedStage
            ? _buildStage2LoseFailed(context)
            : _buildStage1PlayOn(context),
      ),
    );
  }

  Widget _buildStage1PlayOn(BuildContext context) {
    final canAfford = widget.playerCoins >= widget.playOnCost;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Tapping anywhere while peeking restores the popup immediately
        if (_peekingBoard)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _peekingBoard = false),
            ),
          ),

        // Main `PlayOnPopupView` content (fades cleanly while peeking board)
        AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: _peekingBoard ? 0.04 : 1.0,
          child: IgnorePointer(
            ignoring: _peekingBoard,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.78, end: 1.0),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) => Transform.scale(
                scale: scale,
                child: child,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top 9-Slice `Banner.png` `"OUT OF TIME"`
                  UnityNineSlice(
                    sprite: 'Banner.png',
                    width: ux(context, 780),
                    height: ux(context, 162),
                    padding: EdgeInsets.only(bottom: ux(context, 14)),
                    child: const UnitySdfText(
                      'OUT OF TIME',
                      unityFontSize: 76,
                      material: UnityTextMaterial.popupTitle,
                    ),
                  ),
                  SizedBox(height: ux(context, 28)),

                  // `UnityPopupCard` `"Continue?"`
                  UnityPopupCard(
                    title: 'Continue?',
                    unityWidth: 910,
                    onClose: _goToFailedStage,
                    panelChild: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 9-Slice `Panel_PlayOn.png` (`Icon_Timer.png` + `+30s`)
                        UnityNineSlice(
                          sprite: 'Panel_PlayOn.png',
                          width: ux(context, 520),
                          height: ux(context, 210),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/images/Icon_Timer.png',
                                width: ux(context, 128),
                                height: ux(context, 128),
                              ),
                              SizedBox(width: ux(context, 22)),
                              const UnitySdfText(
                                '+30s',
                                unityFontSize: 102,
                                material: UnityTextMaterial.ctaBlue,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: ux(context, 26)),

                        Text(
                          'Add 30 seconds to keep playing!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Baloo2',
                            fontSize: ux(context, 48),
                            fontWeight: FontWeight.w700,
                            fontVariations: const [FontVariation('wght', 700)],
                            color: const Color(0xFF07279A),
                            height: 1.18,
                          ),
                        ),
                      ],
                    ),
                    footerChild: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Green `Play On` (`Inset_Button_CTA.png` + `200` coins)
                        UnityCtaButton(
                          skin: UnityButtonSkin.green,
                          label: 'Play On',
                          coinPrice: widget.playOnCost,
                          unityWidth: 720,
                          unityHeight: 156,
                          unityFontSize: 74,
                          onTap: canAfford ? widget.onPlayOnCoins : null,
                        ),
                        SizedBox(height: ux(context, 22)),

                        // Blue `Play On` (`Icon_Ad.png` free +30s)
                        UnityCtaButton(
                          skin: UnityButtonSkin.blue,
                          label: 'Play On',
                          showAdBadge: true,
                          unityWidth: 720,
                          unityHeight: 156,
                          unityFontSize: 74,
                          onTap: widget.onPlayOnAd,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Bottom `"Tap to see the board"` + `Icon_Eye.png` (`PlayOnPopupView.prefab`)
        Positioned(
          bottom: ux(context, 44),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _peekingBoard = true),
            onTapUp: (_) => setState(() => _peekingBoard = false),
            onTapCancel: () => setState(() => _peekingBoard = false),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ux(context, 36),
                vertical: ux(context, 18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/Icon_Eye.png',
                    width: ux(context, 68),
                    height: ux(context, 68),
                  ),
                  SizedBox(width: ux(context, 20)),
                  Text(
                    _peekingBoard ? 'Release to return' : 'Tap to see the board',
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontSize: ux(context, 46),
                      fontWeight: FontWeight.w700,
                      fontVariations: const [FontVariation('wght', 700)],
                      color: const Color(0xFFD8E7FF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Stage 2: Authentic `LoseGameplayView.prefab` (`Level X failed`, `Icon_BrokenLife.png` `-1`,
  /// 5 `Icon_Life.png` hearts bar, green `Try Again` CTA).
  Widget _buildStage2LoseFailed(BuildContext context) {
    final activeHearts = widget.remainingLives.clamp(0, PlayerProgressService.maxLives);

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.78, end: 1.0),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          child: child,
        ),
        child: UnityPopupCard(
          title: '${widget.levelLabel} failed',
          unityWidth: 900,
          onClose: widget.onRetry,
          panelChild: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Giant `Icon_BrokenLife.png` + `-1` counter
              SizedBox(
                width: ux(context, 290),
                height: ux(context, 250),
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Image.asset(
                      'assets/images/Icon_BrokenLife.png',
                      width: ux(context, 252),
                      height: ux(context, 226),
                      fit: BoxFit.contain,
                    ),
                    Positioned(
                      right: ux(context, 4),
                      bottom: ux(context, 6),
                      child: const UnitySdfText(
                        '-1',
                        unityFontSize: 96,
                        material: UnityTextMaterial.brownCounter,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: ux(context, 28)),

              // 5-Lives Heart Strip (`Icon_Life.png`)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ux(context, 34),
                  vertical: ux(context, 18),
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5EEFF),
                  borderRadius: BorderRadius.circular(ux(context, 44)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(PlayerProgressService.maxLives, (idx) {
                    final filled = idx < activeHearts;
                    return Padding(
                      padding: EdgeInsets.symmetric(horizontal: ux(context, 8)),
                      child: Opacity(
                        opacity: filled ? 1.0 : 0.26,
                        child: ColorFiltered(
                          colorFilter: filled
                              ? const ColorFilter.mode(
                                  Colors.transparent,
                                  BlendMode.dst,
                                )
                              : const ColorFilter.mode(
                                  Color(0xFF4F6496),
                                  BlendMode.modulate,
                                ),
                          child: Image.asset(
                            'assets/images/Icon_Life.png',
                            width: ux(context, 82),
                            height: ux(context, 82),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          footerChild: UnityCtaButton(
            skin: UnityButtonSkin.green,
            label: 'Try Again',
            unityWidth: 640,
            unityHeight: 158,
            unityFontSize: 80,
            onTap: widget.onRetry,
          ),
        ),
      ),
    );
  }
}
