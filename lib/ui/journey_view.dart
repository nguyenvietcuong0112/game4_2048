import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/player_progress_service.dart';
import '../services/remote_config_service.dart';
import 'unity_ui_kit.dart';

/// Vertical bottom-to-top Journey & Background Gallery progression screen.
class JourneyView extends StatefulWidget {
  final PlayerProgressService progress;
  final double topClearance;
  final double bottomClearance;

  const JourneyView({
    super.key,
    required this.progress,
    this.topClearance = 0,
    this.bottomClearance = 0,
  });

  @override
  State<JourneyView> createState() => _JourneyViewState();
}

class _JourneyViewState extends State<JourneyView> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.progress.markJourneyUnlockedSeen();
    unawaited(UnitySpriteRegistry.loadOne('Journey/Fr_reward.png'));
    unawaited(UnitySpriteRegistry.loadOne('Journey/Fr_Gallery.png'));
    unawaited(UnitySpriteRegistry.loadOne('Journey/Fr_tittle.png'));
    unawaited(UnitySpriteRegistry.loadOne('Button_CTA.png'));
    unawaited(UnitySpriteRegistry.loadOne('Background_Popup.png'));
    unawaited(UnitySpriteRegistry.loadOne('Panel_Popup.png'));
    unawaited(UnitySpriteRegistry.loadOne('Frame_Popup_Title.png'));
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
          backgroundColor: const Color(0xFF28429C),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _handleMilestoneTap(JourneyMilestoneConfig m) {
    final unlocked = widget.progress.isJourneyMilestoneUnlocked(m.levelUnlock);
    if (!unlocked) {
      _showToast('Unlock at Level ${m.levelUnlock}!');
      return;
    }

    final claimed = widget.progress.hasClaimedJourneyMilestone(m.levelUnlock);
    if (!claimed) {
      final didClaim = widget.progress.claimJourneyMilestone(m);
      if (didClaim) {
        if (m.bgTheme != null) {
          _showToast('${m.bgTheme!.title} Background unlocked & equipped!');
        } else if (m.coins > 0) {
          _showToast('+${m.coins} Coins claimed!');
        } else if (m.infinityMinutes > 0) {
          _showToast('+${m.infinityMinutes}m Unlimited Lives claimed!');
        } else if (m.boosterType != null) {
          _showToast('+${m.boosterCount} Booster claimed!');
        }
      }
      return;
    }

    if (m.bgTheme != null) {
      _openGalleryPreview(m.bgTheme!);
    }
  }

  Future<void> _openGalleryPreview(JourneyBgTheme theme) async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0xCC0A0520),
      builder: (dialogCtx) {
        return AnimatedBuilder(
          animation: widget.progress,
          builder: (ctx, _) {
            final isEquipped =
                widget.progress.selectedJourneyBgId == theme.id;
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 16,
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: UnityPopupCard(
                    title: '${theme.title} World',
                    localTitleFontSize: 104,
                    onClose: () => Navigator.of(dialogCtx).pop(),
                    panelChild: Padding(
                      padding: EdgeInsets.fromLTRB(
                        ppx(ctx, 44),
                        ppx(ctx, 42),
                        ppx(ctx, 44),
                        ppx(ctx, 36),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(ppx(ctx, 30)),
                              child: AspectRatio(
                                aspectRatio: 740 / 420,
                                child: Image.asset(
                                  theme.galleryCardAsset,
                                  fit: BoxFit.cover,
                                  alignment: theme.id == 0
                                      ? const Alignment(0.0, -0.22)
                                      : Alignment.center,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: ppx(ctx, 26)),
                          Text(
                            isEquipped
                                ? 'Active on your Home screen'
                                : 'Equip to set as your Home background',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Baloo2',
                              fontSize: ppx(ctx, 50),
                              fontWeight: FontWeight.w800,
                              fontVariations: const [
                                FontVariation('wght', 800),
                              ],
                              color: const Color(0xFF123696),
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    footerChild: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        UnityPopupCtaButton(
                          label: 'Close',
                          skin: UnityButtonSkin.blue,
                          localWidth: 430,
                          localHeight: 204,
                          localFontSize: 84,
                          onTap: () => Navigator.of(dialogCtx).pop(),
                        ),
                        SizedBox(width: ppx(ctx, 36)),
                        UnityPopupCtaButton(
                          key: ValueKey('journey_equip_bg_${theme.id}'),
                          label: isEquipped ? 'Equipped' : 'Equip',
                          skin: UnityButtonSkin.green,
                          localWidth: 450,
                          localHeight: 204,
                          localFontSize: 84,
                          onTap: isEquipped
                              ? null
                              : () {
                                  widget.progress.selectJourneyBg(theme.id);
                                  Navigator.of(dialogCtx).pop();
                                  _showToast(
                                    'Equipped ${theme.title} Background!',
                                  );
                                },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const items = JourneyMilestoneConfig.schedule;
    final screenW = MediaQuery.sizeOf(context).width;
    final hudSpriteH = screenW * (283.0 / 1080.0);
    final showTopHud = widget.topClearance > 0;
    final hudTotalH = showTopHud
        ? math.max(widget.topClearance + ux(context, 12), hudSpriteH)
        : 0.0;

    return AnimatedBuilder(
      animation: widget.progress,
      builder: (context, _) {
        return Material(
          color: const Color(0xFF1579C6),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  'assets/images/Journey/BG.webp',
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: hudTotalH + ux(context, 24),
                left: -ux(context, 40),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.35,
                    child: Image.asset(
                      'assets/images/Journey/Cloud.webp',
                      width: ux(context, 420),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: hudTotalH + ux(context, 520),
                right: -ux(context, 60),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.28,
                    child: Image.asset(
                      'assets/images/Journey/Cloud.webp',
                      width: ux(context, 360),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: ListView.builder(
                  key: const ValueKey('journey_list_view'),
                  controller: _scrollCtrl,
                  reverse: true,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: hudTotalH + ux(context, 28),
                    bottom: widget.bottomClearance + ux(context, 24),
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final milestone = items[index];
                    final prevUnlock =
                        index > 0 ? items[index - 1].levelUnlock : 0;
                    final fillRatio = _segmentFillRatio(
                      highestLevel: widget.progress.highestLevel,
                      prevLevel: prevUnlock,
                      targetLevel: milestone.levelUnlock,
                    );
                    final unlocked = widget.progress
                        .isJourneyMilestoneUnlocked(milestone.levelUnlock);
                    final claimed = widget.progress
                        .hasClaimedJourneyMilestone(milestone.levelUnlock);

                    return _JourneyMilestoneNode(
                      milestone: milestone,
                      unlocked: unlocked,
                      claimed: claimed,
                      isEquippedBg: milestone.bgId != null &&
                          widget.progress.selectedJourneyBgId ==
                              milestone.bgId,
                      spineFillRatio: fillRatio,
                      isTopMost: index == items.length - 1,
                      isBottomMost: index == 0,
                      onTap: () => _handleMilestoneTap(milestone),
                    );
                  },
                ),
              ),
              if (showTopHud)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: hudTotalH,
                  child: IgnorePointer(
                    child: _JourneyTopHudBanner(
                      hudSpriteH: hudSpriteH,
                      totalH: hudTotalH,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double _segmentFillRatio({
    required int highestLevel,
    required int prevLevel,
    required int targetLevel,
  }) {
    final completed = (highestLevel - 1).clamp(0, 99999);
    if (completed >= targetLevel) return 1.0;
    if (completed <= prevLevel) return 0.0;
    final span = (targetLevel - prevLevel).clamp(1, 99999);
    return ((completed - prevLevel) / span).clamp(0.0, 1.0);
  }
}

class _JourneyTopHudBanner extends StatelessWidget {
  final double hudSpriteH;
  final double totalH;

  const _JourneyTopHudBanner({
    required this.hudSpriteH,
    required this.totalH,
  });

  @override
  Widget build(BuildContext context) {
    final extraTop = math.max(0.0, totalH - hudSpriteH);
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (extraTop > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: extraTop + 4,
            child: const ColoredBox(color: Color(0xFF5A4FD9)),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: hudSpriteH,
          child: Image.asset(
            'assets/images/Journey/HUD.png',
            fit: BoxFit.fill,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: hudSpriteH * 0.14,
          child: Opacity(
            opacity: 0.16,
            child: Image.asset(
              'assets/images/Journey/Pattern HUD.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
      ],
    );
  }
}

class _JourneyMilestoneNode extends StatelessWidget {
  final JourneyMilestoneConfig milestone;
  final bool unlocked;
  final bool claimed;
  final bool isEquippedBg;
  final double spineFillRatio;
  final bool isTopMost;
  final bool isBottomMost;
  final VoidCallback onTap;

  const _JourneyMilestoneNode({
    required this.milestone,
    required this.unlocked,
    required this.claimed,
    required this.isEquippedBg,
    required this.spineFillRatio,
    required this.isTopMost,
    required this.isBottomMost,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spineW = ux(context, 78);
    final nodeH = milestone.isBgMilestone
        ? ux(context, 628)
        : ux(context, 256);

    return SizedBox(
      height: nodeH,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Continuous central progress spine (`Exp_Bar` + green fill `Proges_bar`)
          Positioned(
            top: isTopMost ? nodeH * 0.45 : 0,
            bottom: isBottomMost ? nodeH * 0.45 : 0,
            child: SizedBox(
              width: spineW,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/Journey/Exp_Bar.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                  if (spineFillRatio > 0)
                    FractionallySizedBox(
                      heightFactor: spineFillRatio,
                      widthFactor: 0.70,
                      alignment: Alignment.bottomCenter,
                      child: Image.asset(
                        'assets/images/Journey/Proges_bar.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (milestone.isBgMilestone)
            _GalleryBgMilestoneCard(
              milestone: milestone,
              unlocked: unlocked,
              claimed: claimed,
              isEquipped: isEquippedBg,
              onTap: onTap,
            )
          else
            _RewardMilestonePill(
              milestone: milestone,
              unlocked: unlocked,
              claimed: claimed,
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}

class _RewardMilestonePill extends StatefulWidget {
  final JourneyMilestoneConfig milestone;
  final bool unlocked;
  final bool claimed;
  final VoidCallback onTap;

  const _RewardMilestonePill({
    required this.milestone,
    required this.unlocked,
    required this.claimed,
    required this.onTap,
  });

  @override
  State<_RewardMilestonePill> createState() => _RewardMilestonePillState();
}

class _RewardMilestonePillState extends State<_RewardMilestonePill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final pillW = ux(context, 760);
    final pillH = ux(context, 178);
    final gapW = ux(context, 44);
    final halfW = (pillW - gapW) * 0.5;
    final levelStr = widget.milestone.levelUnlock.toString().padLeft(2, '0');
    final readyToClaim = widget.unlocked && !widget.claimed;

    return GestureDetector(
      key: ValueKey('journey_milestone_${widget.milestone.levelUnlock}'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 85),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: pillW,
          height: pillH,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  // Left side: Level number
                  SizedBox(
                    width: halfW,
                    height: pillH,
                    child: _HalfRewardBox(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: UnitySdfText(
                          'Level\n$levelStr',
                          unityFontSize: 38,
                          material: UnityTextMaterial.popupTitle,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: gapW),
                  // Right side: Reward icon + label + status indicator
                  SizedBox(
                    width: halfW,
                    height: pillH,
                    child: _HalfRewardBox(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _RewardIcon(
                            milestone: widget.milestone,
                            size: ux(context, 72),
                          ),
                          SizedBox(width: ux(context, 12)),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: UnitySdfText(
                                widget.milestone.rewardLabel,
                                unityFontSize: 38,
                                material: UnityTextMaterial.darkStroke,
                              ),
                            ),
                          ),
                          if (widget.claimed) ...[
                            SizedBox(width: ux(context, 10)),
                            Image.asset(
                              'assets/images/Journey/asset_tick.png',
                              width: ux(context, 52),
                              height: ux(context, 52),
                              fit: BoxFit.contain,
                            ),
                          ] else if (!widget.unlocked) ...[
                            SizedBox(width: ux(context, 10)),
                            Opacity(
                              opacity: 0.9,
                              child: Image.asset(
                                'assets/images/Journey/lock.png',
                                width: ux(context, 42),
                                height: ux(context, 46),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // 3-slice gold-rimmed "Claim" CTA button when ready
              if (readyToClaim)
                Positioned(
                  bottom: -ux(context, 22),
                  right: (halfW - ux(context, 200)) * 0.5,
                  child: UnityCtaButton(
                    label: 'Claim',
                    skin: UnityButtonSkin.green,
                    unityWidth: 200,
                    unityHeight: 74,
                    unityFontSize: 34,
                    sliceScale: 0.42,
                    onTap: widget.onTap,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HalfRewardBox extends StatelessWidget {
  final Widget child;

  const _HalfRewardBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return UnityNineSlice(
      sprite: 'Journey/Fr_reward.png',
      pixelMultiplier: 0.72,
      padding: EdgeInsets.fromLTRB(
        ux(context, 22),
        ux(context, 14),
        ux(context, 22),
        ux(context, 24),
      ),
      child: child,
    );
  }
}

class _RewardIcon extends StatelessWidget {
  final JourneyMilestoneConfig milestone;
  final double size;

  const _RewardIcon({
    required this.milestone,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (milestone.coins > 0) {
      return Image.asset(
        'assets/images/Shop/asset_coin_1.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    if (milestone.infinityMinutes > 0) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/images/UI Home/Home/icon_heart.png',
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
            const UnitySdfText(
              '∞',
              unityFontSize: 28,
              material: UnityTextMaterial.darkStroke,
            ),
          ],
        ),
      );
    }
    final asset = switch (milestone.boosterType) {
      BoosterType.shuffle => 'assets/images/PowerUp_Shuffle.png',
      BoosterType.timeFreeze => 'assets/images/PowerUp_TimeFreeze.png',
      BoosterType.hammer => 'assets/images/PowerUp_Hammer.png',
      BoosterType.levelUp || null => 'assets/images/PowerUp_LevelUp.png',
    };
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class _GalleryBgMilestoneCard extends StatefulWidget {
  final JourneyMilestoneConfig milestone;
  final bool unlocked;
  final bool claimed;
  final bool isEquipped;
  final VoidCallback onTap;

  const _GalleryBgMilestoneCard({
    required this.milestone,
    required this.unlocked,
    required this.claimed,
    required this.isEquipped,
    required this.onTap,
  });

  @override
  State<_GalleryBgMilestoneCard> createState() =>
      _GalleryBgMilestoneCardState();
}

class _GalleryBgMilestoneCardState extends State<_GalleryBgMilestoneCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.milestone.bgTheme!;
    final cardW = ux(context, 840);
    final cardH = ux(context, 508);
    final titleW = ux(context, 460);
    final titleH = ux(context, 128);

    return GestureDetector(
      key: ValueKey('journey_milestone_${widget.milestone.levelUnlock}'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 85),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: cardW,
          height: cardH + titleH * 0.52,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              // 9-sliced golden Gallery frame (`Fr_Gallery.png`)
              SizedBox(
                width: cardW,
                height: cardH,
                child: UnityNineSlice(
                  sprite: 'Journey/Fr_Gallery.png',
                  pixelMultiplier: 0.78,
                  padding: EdgeInsets.fromLTRB(
                    ux(context, 40),
                    ux(context, 34),
                    ux(context, 40),
                    ux(context, 48),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(ux(context, 24)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          theme.galleryCardAsset,
                          fit: BoxFit.cover,
                          alignment: theme.id == 0
                              ? const Alignment(0.0, -0.22)
                              : Alignment.center,
                        ),
                        if (!widget.unlocked)
                          Container(
                            color: Colors.black38,
                            alignment: Alignment.center,
                            child: Image.asset(
                              'assets/images/Journey/lock.png',
                              width: ux(context, 120),
                              height: ux(context, 120),
                              fit: BoxFit.contain,
                            ),
                          ),
                        if (widget.unlocked && !widget.claimed)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: EdgeInsets.only(bottom: ux(context, 14)),
                              child: UnityCtaButton(
                                label: 'Claim',
                                skin: UnityButtonSkin.green,
                                unityWidth: 260,
                                unityHeight: 100,
                                unityFontSize: 40,
                                sliceScale: 0.52,
                                onTap: widget.onTap,
                              ),
                            ),
                          ),
                        if (widget.claimed)
                          Positioned(
                            right: ux(context, 14),
                            bottom: ux(context, 14),
                            child: UnityCtaButton(
                              label: widget.isEquipped ? 'Equipped' : 'Use BG',
                              skin: widget.isEquipped
                                  ? UnityButtonSkin.green
                                  : UnityButtonSkin.blue,
                              unityWidth: widget.isEquipped ? 286 : 236,
                              unityHeight: 86,
                              unityFontSize: 34,
                              sliceScale: 0.45,
                              trailingBadge: widget.isEquipped
                                  ? Image.asset(
                                      'assets/images/Journey/asset_tick.png',
                                      width: ux(context, 38),
                                      height: ux(context, 38),
                                      fit: BoxFit.contain,
                                    )
                                  : null,
                              onTap: widget.onTap,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // 9-sliced purple title ribbon (`Fr_tittle.png`) overlapping top center
              Positioned(
                top: 0,
                child: UnityNineSlice(
                  sprite: 'Journey/Fr_tittle.png',
                  width: titleW,
                  height: titleH,
                  pixelMultiplier: 0.65,
                  padding: EdgeInsets.fromLTRB(
                    ux(context, 28),
                    ux(context, 10),
                    ux(context, 28),
                    ux(context, 18),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        UnitySdfText(
                          theme.title,
                          unityFontSize: 46,
                          material: UnityTextMaterial.popupTitle,
                        ),
                        UnitySdfText(
                          'Level ${widget.milestone.levelUnlock}',
                          unityFontSize: 28,
                          material: UnityTextMaterial.popupTitle,
                        ),
                      ],
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
