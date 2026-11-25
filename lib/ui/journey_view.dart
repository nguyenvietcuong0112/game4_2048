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
      builder: (dialogCtx) {
        return AnimatedBuilder(
          animation: widget.progress,
          builder: (ctx, _) {
            final isEquipped =
                widget.progress.selectedJourneyBgId == theme.id;
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: EdgeInsets.all(ux(ctx, 26)),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF2DA),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFF0A91D),
                    width: 4,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    UnitySdfText(
                      '${theme.title} World',
                      unityFontSize: 52,
                      material: UnityTextMaterial.popupTitle,
                    ),
                    SizedBox(height: ux(ctx, 16)),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 16 / 10,
                        child: Image.asset(
                          theme.galleryCardAsset,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    SizedBox(height: ux(ctx, 22)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(dialogCtx).pop(),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ux(ctx, 36),
                              vertical: ux(ctx, 16),
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4769AA),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const UnitySdfText(
                              'Close',
                              unityFontSize: 38,
                              material: UnityTextMaterial.ctaBlue,
                            ),
                          ),
                        ),
                        SizedBox(width: ux(ctx, 20)),
                        GestureDetector(
                          key: ValueKey('journey_equip_bg_${theme.id}'),
                          onTap: isEquipped
                              ? null
                              : () {
                                  widget.progress.selectJourneyBg(theme.id);
                                  Navigator.of(dialogCtx).pop();
                                  _showToast(
                                    'Equipped ${theme.title} Background!',
                                  );
                                },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ux(ctx, 40),
                              vertical: ux(ctx, 16),
                            ),
                            decoration: BoxDecoration(
                              color: isEquipped
                                  ? const Color(0xFF8AA490)
                                  : const Color(0xFF28B53E),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: UnitySdfText(
                              isEquipped ? 'Equipped' : 'Equip',
                              unityFontSize: 38,
                              material: UnityTextMaterial.ctaGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
                top: widget.topClearance,
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
              Positioned.fill(
                child: ListView.builder(
                  key: const ValueKey('journey_list_view'),
                  controller: _scrollCtrl,
                  reverse: true,
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.only(
                    top: widget.topClearance + ux(context, 24),
                    bottom: widget.bottomClearance + ux(context, 20),
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
    final spineW = ux(context, 84).clamp(32.0, 48.0);
    final nodeH = milestone.isBgMilestone
        ? ux(context, 560).clamp(220.0, 310.0)
        : ux(context, 236).clamp(96.0, 134.0);

    return SizedBox(
      height: nodeH,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Continuous central progress spine (`Exp_Bar` + green fill `Proges_bar`)
          Positioned(
            top: isTopMost ? nodeH * 0.45 : 0,
            bottom: isBottomMost ? 0 : 0,
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
                      widthFactor: 0.72,
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

class _RewardMilestonePill extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final pillW = ux(context, 680).clamp(240.0, 356.0);
    final pillH = ux(context, 166).clamp(68.0, 94.0);
    final levelStr = milestone.levelUnlock.toString().padLeft(2, '0');

    return GestureDetector(
      key: ValueKey('journey_milestone_${milestone.levelUnlock}'),
      onTap: onTap,
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
                Expanded(
                  child: _HalfRewardBox(
                    child: UnitySdfText(
                      'Level\n$levelStr',
                      unityFontSize: 40,
                      material: UnityTextMaterial.popupTitle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                SizedBox(width: ux(context, 48)),
                // Right side: Reward icon + label
                Expanded(
                  child: _HalfRewardBox(
                    highlight: unlocked && !claimed,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _RewardIcon(milestone: milestone),
                            UnitySdfText(
                              milestone.rewardLabel,
                              unityFontSize: 30,
                              material: UnityTextMaterial.darkStroke,
                            ),
                          ],
                        ),
                        if (claimed) ...[
                          SizedBox(width: ux(context, 8)),
                          Image.asset(
                            'assets/images/Journey/asset_tick.png',
                            width: ux(context, 56).clamp(22.0, 32.0),
                            height: ux(context, 56).clamp(22.0, 32.0),
                            fit: BoxFit.contain,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // "Claim" pill callout when ready
            if (unlocked && !claimed)
              Positioned(
                bottom: -ux(context, 16),
                right: ux(context, 36),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ux(context, 24),
                    vertical: ux(context, 6),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF28C33E),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        offset: Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const UnitySdfText(
                    'Claim',
                    unityFontSize: 30,
                    material: UnityTextMaterial.ctaGreen,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HalfRewardBox extends StatelessWidget {
  final Widget child;
  final bool highlight;

  const _HalfRewardBox({
    required this.child,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/Journey/Fr_reward.png',
            fit: BoxFit.fill,
          ),
        ),
        if (highlight)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF4EFF6A),
                  width: 2.5,
                ),
              ),
            ),
          ),
        Center(child: child),
      ],
    );
  }
}

class _RewardIcon extends StatelessWidget {
  final JourneyMilestoneConfig milestone;

  const _RewardIcon({required this.milestone});

  @override
  Widget build(BuildContext context) {
    final sz = ux(context, 72).clamp(28.0, 42.0);
    if (milestone.coins > 0) {
      return Image.asset(
        'assets/images/Shop/asset_coin_1.png',
        width: sz,
        height: sz,
        fit: BoxFit.contain,
      );
    }
    if (milestone.infinityMinutes > 0) {
      return SizedBox(
        width: sz,
        height: sz,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              'assets/images/UI Home/Home/icon_heart.png',
              width: sz,
              height: sz,
              fit: BoxFit.contain,
            ),
            const UnitySdfText(
              '∞',
              unityFontSize: 26,
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
      width: sz,
      height: sz,
      fit: BoxFit.contain,
    );
  }
}

class _GalleryBgMilestoneCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = milestone.bgTheme!;
    final cardW = ux(context, 840).clamp(260.0, 390.0);
    final cardH = ux(context, 430).clamp(170.0, 238.0);
    final titleW = ux(context, 520).clamp(180.0, 250.0);
    final titleH = ux(context, 128).clamp(50.0, 72.0);

    return GestureDetector(
      key: ValueKey('journey_milestone_${milestone.levelUnlock}'),
      onTap: onTap,
      child: SizedBox(
        width: cardW,
        height: cardH + titleH * 0.52,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            SizedBox(
              width: cardW,
              height: cardH,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/Journey/Fr_Gallery.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        ux(context, 38),
                        ux(context, 38),
                        ux(context, 38),
                        ux(context, 38),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              theme.galleryCardAsset,
                              fit: BoxFit.cover,
                            ),
                            if (!unlocked)
                              Container(
                                color: Colors.black38,
                                alignment: Alignment.center,
                                child: Image.asset(
                                  'assets/images/Journey/lock.png',
                                  width: ux(context, 120).clamp(48.0, 68.0),
                                  height: ux(context, 120).clamp(48.0, 68.0),
                                  fit: BoxFit.contain,
                                ),
                              ),
                            if (unlocked && !claimed)
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  margin: EdgeInsets.only(
                                    bottom: ux(context, 14),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ux(context, 32),
                                    vertical: ux(context, 8),
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF28C33E),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.5,
                                    ),
                                  ),
                                  child: const UnitySdfText(
                                    'Claim',
                                    unityFontSize: 38,
                                    material: UnityTextMaterial.ctaGreen,
                                  ),
                                ),
                              ),
                            if (claimed)
                              Positioned(
                                right: ux(context, 12),
                                bottom: ux(context, 12),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ux(context, 18),
                                    vertical: ux(context, 6),
                                  ),
                                  decoration: BoxDecoration(
                                    color: isEquipped
                                        ? const Color(0xCC1E9B35)
                                        : const Color(0xBB162B5C),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isEquipped) ...[
                                        Image.asset(
                                          'assets/images/Journey/asset_tick.png',
                                          width: ux(context, 34)
                                              .clamp(14.0, 20.0),
                                          height: ux(context, 34)
                                              .clamp(14.0, 20.0),
                                        ),
                                        SizedBox(width: ux(context, 6)),
                                      ],
                                      UnitySdfText(
                                        isEquipped ? 'Equipped' : 'Use BG',
                                        unityFontSize: 28,
                                        material: UnityTextMaterial.ctaGreen,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Top overlapping purple title ribbon (`Fr_tittle.png`)
            Positioned(
              top: 0,
              child: SizedBox(
                width: titleW,
                height: titleH,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/images/Journey/Fr_tittle.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        UnitySdfText(
                          theme.title,
                          unityFontSize: 46,
                          material: UnityTextMaterial.popupTitle,
                        ),
                        UnitySdfText(
                          'Level ${milestone.levelUnlock}',
                          unityFontSize: 28,
                          material: UnityTextMaterial.popupTitle,
                        ),
                      ],
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
