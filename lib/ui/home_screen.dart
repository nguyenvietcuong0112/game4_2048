import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/level_models.dart';
import '../services/ads_manager.dart';
import '../services/analytics_service.dart';
import '../services/app_version_service.dart';
import '../services/audio_haptics_service.dart';
// Temporarily disabled while IAP/Shop/Journey are deferred to next version:
// import '../services/iap_service.dart';
import '../services/player_progress_service.dart';
// import 'journey_view.dart';
import 'more_lives_dialog.dart';
// import 'shop_view.dart';
import 'unity_ui_kit.dart';

// enum _HomeTab {
//   shop,
//   home,
//   journey,
// }

/// Home Screen displayed before Gameplay matching `assets/images/UI Home/Home/Home_view.png`:
/// - Tabs: `Shop`, `Home` (Kitchen Scene + Play CTA), and `Journey` (currently commented for next version)
/// - Top bar: Avatar (`frame_avatar.png`), Hearts pill, Coins pill, Settings (`btn_setting.png`)
/// - Primary Play CTA: `btn_green_play.png` (`"Level X"`), gated by Heart > 0 (`MoreLivesDialog`)
class HomeScreen extends StatefulWidget {
  final LevelRepository repository;
  final AudioHapticsService audio;
  final PlayerProgressService progress;
  final VoidCallback onPlayLevel;

  const HomeScreen({
    super.key,
    required this.repository,
    required this.audio,
    required this.progress,
    required this.onPlayLevel,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ctaPulseCtrl;
  Timer? _lifeRegenTimer;
  Timer? _toastTimer;
  String? _toastMessage;
  double _toastOpacity = 0.0;
  bool _settingsOpen = false;
  bool _showMoreLivesModal = false;
  bool _pendingPlayAfterLifeRecovery = false;
  // Temporarily disabled while IAP/Shop/Journey are deferred to next version:
  // _HomeTab _activeTab = _HomeTab.home;
  // ShopScrollSection _shopSection = ShopScrollSection.top;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(AppVersionService.init());
    widget.progress.syncLivesRegen();
    _syncLifeRegenTicker();
    AdsManager.showBanner('home', level: widget.progress.currentLevel);

    _ctaPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   _checkPendingJourneyShowcase();
    // });
  }

  // @override
  // void didUpdateWidget(covariant HomeScreen oldWidget) {
  //   super.didUpdateWidget(oldWidget);
  //   WidgetsBinding.instance.addPostFrameCallback((_) {
  //     _checkPendingJourneyShowcase();
  //   });
  // }

  // void _checkPendingJourneyShowcase() {
  //   if (!mounted) return;
  //   if (widget.progress.consumePendingJourneyUnlockShowcase()) {
  //     setState(() => _activeTab = _HomeTab.journey);
  //     _showToast('Journey Unlocked!');
  //   }
  // }

  // void _openShopTab([ShopScrollSection section = ShopScrollSection.top]) {
  //   setState(() {
  //     _activeTab = _HomeTab.shop;
  //     _shopSection = section;
  //   });
  // }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.progress.syncLivesRegen();
      _syncLifeRegenTicker();
      if (_showMoreLivesModal &&
          _pendingPlayAfterLifeRecovery &&
          widget.progress.canPlay()) {
        _completePendingPlay();
      }
      if (mounted) setState(() {});
    }
  }

  void _syncLifeRegenTicker() {
    final needsRegen = widget.progress.isInfinityLives() ||
        widget.progress.lives < widget.progress.currentMaxLives;
    if (needsRegen && _lifeRegenTimer == null) {
      _lifeRegenTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        widget.progress.syncLivesRegen();
        _syncLifeRegenTicker();
        setState(() {});
      });
    } else if (!needsRegen && _lifeRegenTimer != null) {
      _lifeRegenTimer?.cancel();
      _lifeRegenTimer = null;
    }
  }

  @override
  void dispose() {
    AdsManager.hideBanner();
    WidgetsBinding.instance.removeObserver(this);
    _lifeRegenTimer?.cancel();
    _toastTimer?.cancel();
    _ctaPulseCtrl.dispose();
    super.dispose();
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = msg;
      _toastOpacity = 1.0;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() => _toastOpacity = 0.0);
      }
    });
  }

  void _handlePlayTapped() {
    widget.progress.syncLivesRegen();
    _syncLifeRegenTicker();
    widget.audio.playClick();

    if (!widget.progress.canPlay()) {
      AnalyticsService.logPopupShow(
        name: 'more_lives_home',
        level: widget.progress.currentLevel,
      );
      setState(() {
        _pendingPlayAfterLifeRecovery = true;
        _showMoreLivesModal = true;
      });
      return;
    }
    widget.onPlayLevel();
  }

  void _completePendingPlay() {
    if (!mounted || !widget.progress.canPlay()) return;
    final shouldStart = _pendingPlayAfterLifeRecovery;
    setState(() {
      _showMoreLivesModal = false;
      _pendingPlayAfterLifeRecovery = false;
    });
    _syncLifeRegenTicker();
    if (shouldStart) {
      widget.onPlayLevel();
    }
  }

  void _handleHeartsPillTapped() {
    widget.audio.playClick();
    widget.progress.syncLivesRegen();
    if (widget.progress.isInfinityLives() ||
        widget.progress.lives >= widget.progress.currentMaxLives) {
      _showToast('Your hearts are full!');
      return;
    }
    setState(() {
      _pendingPlayAfterLifeRecovery = false;
      _showMoreLivesModal = true;
    });
  }

  void _handleMoreLivesWatchAd() {
    widget.audio.playClick();
    AdsManager.showRewardedAd(
      placement: 'home_more_lives_add_one',
      levelNumber: widget.progress.currentLevel,
      onAdFailed: (_) {
        if (!mounted) return;
        _showToast('No ads available right now!');
      },
      onRewardResult: (success) {
        if (success && mounted) {
          widget.progress.addOneLife();
          _syncLifeRegenTicker();
          _showToast('+1 Life!');
          _completePendingPlay();
        }
      },
    );
  }

  void _handleMoreLivesRefillCoins() {
    widget.audio.playClick();
    if (widget.progress.lives >= widget.progress.currentMaxLives) {
      _completePendingPlay();
      return;
    }
    if (widget.progress.refillLivesWithCoins()) {
      _syncLifeRegenTicker();
      _showToast('Lives Refilled!');
      _completePendingPlay();
    } else {
      _showToast('Not enough coins!');
    }
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFF28125B),
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenSize = constraints.biggest;

          // `BG.png` (`1080x2160`) uses `BoxFit.fill` (`fitXY`) so the entire kitchen artwork
          // stays uncropped and vertical landmarks (`counter rim = 1436 / 2160`) map 1:1.
          const double bgDesignH = 2160.0;
          final bgScaleY = screenSize.height / bgDesignH;
          // Temporarily unused while bottom nav dock is commented out for next version:
          // final dockArtH = 232.0 * bgScaleY;
          // final activeCardLift = 89.0 * bgScaleY;
          // final activeCardW = ux(context, 385);

          final playW = ux(context, 491);
          final playH = ux(context, 259);
          final buttonTargetCenterY = 1600.0 * bgScaleY;
          final minPlayTop = safePadding.top + ux(context, 540);

          return ListenableBuilder(
            listenable: Listenable.merge([
              widget.progress,
              AdsManager.bannerVisibleNotifier,
            ]),
            builder: (context, _) {
              // Only reserve the bottom ad banner strip (`167px` at bottom of `1080x2160`)
              // while a banner ad is actually allowed, requested, and loaded.
              final showBannerSpace = AdsManager.isBannerVisible;
              final bottomBannerH = showBannerSpace
                  ? math.max(
                      167.0 * bgScaleY,
                      safePadding.bottom + ux(context, 132),
                    )
                  : 0.0;
              // final navSafeBottom = showBannerSpace ? 0.0 : safePadding.bottom;
              // final bottomDockBarH = dockArtH + navSafeBottom;
              final maxPlayTop =
                  screenSize.height - bottomBannerH - playH - ux(context, 36);
              final double playTop = (buttonTargetCenterY - playH * 0.5)
                  .clamp(minPlayTop, math.max(minPlayTop, maxPlayTop))
                  .toDouble();

              final currentLv = widget.progress.currentLevel;
              final lives = widget.progress.lives;
              final isInfinity = widget.progress.isInfinityLives();
              final isFull =
                  !isInfinity && lives >= widget.progress.currentMaxLives;
              final heartText = isFull
                  ? 'Full'
                  : widget.progress.formattedNextLifeCountdown();
              // final journeyUnlocked = widget.progress.isJourneyUnlocked;
              // final navTotalClearance =
              //     bottomBannerH + bottomDockBarH + ux(context, 24);
              // final topHudClearance = safePadding.top + ux(context, 185);

              return Stack(
                fit: StackFit.expand,
                children: [
              // 1. Active Tab Body (`Shop` & `Journey` temporarily commented out for next version)
              /*
              if (_activeTab == _HomeTab.shop)
                ShopView(
                  progress: widget.progress,
                  initialSection: _shopSection,
                  bottomClearance: navTotalClearance,
                )
              else if (_activeTab == _HomeTab.journey)
                JourneyView(
                  progress: widget.progress,
                  topClearance: topHudClearance,
                  bottomClearance: navTotalClearance,
                )
              else ...[
              */
                // Fullscreen Kitchen Workshop Art Backdrop (`BG.webp` fitXY)
                RepaintBoundary(
                  child: Image.asset(
                    'assets/images/UI Home/Home/BG.webp',
                    fit: BoxFit.fill,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),

                // Subtle top vignette for crisp HUD contrast
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: safePadding.top + ux(context, 200),
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x5512052E), Color(0x0012052E)],
                        ),
                      ),
                    ),
                  ),
                ),
              // ],

              // 3. Top Resource Bar (`Avatar`, `Hearts`, `Coins`, `Settings`)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      ux(context, 40),
                      ux(context, 22),
                      ux(context, 46),
                      0,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _HomeAvatarBadge(size: ux(context, 161)),
                        SizedBox(width: ux(context, 18)),
                        Expanded(
                          child: _HomeResourcePill(
                            key: const ValueKey('home_hearts_pill'),
                            onTap: _handleHeartsPillTapped,
                            leadingAsset:
                                'assets/images/UI Home/Home/icon_heart.png',
                            leadingOverlayText: isInfinity
                                ? '∞'
                                : (isFull ? null : '$lives'),
                            label: heartText,
                          ),
                        ),
                        SizedBox(width: ux(context, 18)),
                        Expanded(
                          child: _HomeResourcePill(
                            key: const ValueKey('home_coins_pill'),
                            onTap: () {
                              widget.audio.playClick();
                              _showToast('Shop coming soon!');
                              // _openShopTab(ShopScrollSection.coins);
                            },
                            leadingAsset: 'assets/images/Icon_Coin.png',
                            showPlusBadge: true,
                            label: '${widget.progress.coins}',
                          ),
                        ),
                        SizedBox(width: ux(context, 18)),
                        UnitySpriteButton(
                          key: const ValueKey('home_settings_btn'),
                          asset: 'UI Home/Home/btn_setting.png',
                          unitySize: 139,
                          onTap: () {
                            widget.audio.playClick();
                            setState(() => _settingsOpen = true);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 4. Upper Promo Shortcuts (`No Ads` & `Starter Pack`) — temporarily commented out
              /*
              if (_activeTab == _HomeTab.home)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        ux(context, 31),
                        ux(context, 260),
                        ux(context, 32),
                        0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!widget.progress.noAdsPurchased)
                            _HomePromoShortcut(
                              key: const ValueKey('home_no_ads_btn'),
                              iconAsset:
                                  'assets/images/UI Home/Home/icon_ads.png',
                              label: 'No Ads',
                              unityWidth: 204,
                              unityHeight: 214,
                              unityIconWidth: 182,
                              unityIconHeight: 185,
                              onTap: () {
                                widget.audio.playClick();
                                _openShopTab(ShopScrollSection.top);
                              },
                            )
                          else
                            const SizedBox.shrink(),
                          _HomePromoShortcut(
                            key: const ValueKey('home_starter_pack_btn'),
                            iconAsset:
                                'assets/images/UI Home/Home/icon_reward 1.png',
                            label: 'Starter Pack',
                            unityWidth: 204,
                            unityHeight: 224,
                            unityIconWidth: 183,
                            unityIconHeight: 196,
                            onTap: () {
                              widget.audio.playClick();
                              _openShopTab(ShopScrollSection.bundles);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              */

              // 5. Primary Play Button (`btn_green_play.png` -> `"Level X"`)
              Positioned(
                left: 0,
                right: 0,
                top: playTop,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _ctaPulseCtrl,
                    builder: (context, child) {
                      final pulse =
                          1.0 + 0.022 * math.sin(_ctaPulseCtrl.value * math.pi);
                      return Transform.scale(scale: pulse, child: child);
                    },
                    child: _HomePlayButton(
                      key: const ValueKey('home_play_level_btn'),
                      levelNumber: currentLv,
                      width: playW,
                      height: playH,
                      onTap: _handlePlayTapped,
                    ),
                  ),
                ),
              ),

              // 6. Transparent Reserved Bottom Ad Banner Overlay Region
              Positioned(
                key: const ValueKey('home_bottom_banner'),
                left: 0,
                right: 0,
                bottom: 0,
                height: bottomBannerH,
                child: const IgnorePointer(child: SizedBox.expand()),
              ),

              // 6b. Bottom Navigation Bar (`Shop`, `Home`, `Journey`/`Lock`) — temporarily commented out
              /*
              Positioned(
                key: const ValueKey('home_bottom_nav_bar'),
                left: 0,
                right: 0,
                bottom: bottomBannerH,
                height: bottomDockBarH + activeCardLift,
                child: _HomeBottomNavDock(
                  activeTab: _activeTab,
                  journeyUnlocked: journeyUnlocked,
                  hasJourneyNotice: widget.progress.hasClaimableJourneyReward,
                  bottomDockBarH: bottomDockBarH,
                  dockArtH: dockArtH,
                  navSafeBottom: navSafeBottom,
                  activeCardLift: activeCardLift,
                  activeCardW: activeCardW,
                  bgScaleY: bgScaleY,
                  onSelectShop: () {
                    widget.audio.playClick();
                    _openShopTab(ShopScrollSection.top);
                  },
                  onSelectHome: () {
                    widget.audio.playClick();
                    setState(() => _activeTab = _HomeTab.home);
                  },
                  onSelectJourney: () {
                    widget.audio.playClick();
                    if (!journeyUnlocked) {
                      _showToast('Unlock at Level 20!');
                      return;
                    }
                    setState(() => _activeTab = _HomeTab.journey);
                  },
                ),
              ),
              */

              // 7. Home Settings Modal (`PopUp_Setting`)
              if (_settingsOpen) _buildHomeSettingsOverlay(context),

              // 8. More Lives Popup when Heart == 0 or user taps Heart pill
              if (_showMoreLivesModal)
                MoreLivesDialog(
                  progress: widget.progress,
                  onWatchAdForOneLife: _handleMoreLivesWatchAd,
                  onRefillWithCoins: _handleMoreLivesRefillCoins,
                  onInsufficientCoins: () => _showToast('Not enough coins!'),
                  onLifeRecovered: _completePendingPlay,
                  onClose: () {
                    widget.audio.playClick();
                    setState(() {
                      _showMoreLivesModal = false;
                      _pendingPlayAfterLifeRecovery = false;
                    });
                  },
                ),

              // 9. Elevated Top-Right Coins Pill above MoreLivesDialog backdrop
              if (_showMoreLivesModal)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: ux(context, UnityCoinsWidget.hudLeftUnity),
                        top: ux(context, UnityCoinsWidget.hudTopUnity),
                      ),
                      child: UnityCoinsWidget(coins: widget.progress.coins),
                    ),
                  ),
                ),

              // 10. Toast Pill
              if (_toastMessage != null)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: bottomBannerH + ux(context, 24),
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _toastOpacity,
                      duration: const Duration(milliseconds: 180),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xEB150A38),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFFFFC126),
                              width: 1.8,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x77000000),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            _toastMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Baloo2',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
            },
          );
        },
      ),
    );
  }

  // ignore: unused_field
  static const _homeTabTextMaterial = UnityTextMaterial(
    faceTop: Colors.white,
    faceBottom: Colors.white,
    strokeColor: Color(0xFF0A2A78),
    strokeRatio: 0.16,
    underlayColor: Color(0xCC04123E),
    underlayYRatio: 0.08,
    fontFamily: 'Baloo2',
    fontWeight: FontWeight.w900,
  );

  Widget _buildHomeSettingsOverlay(BuildContext context) {
    void close() {
      widget.audio.playClick();
      setState(() => _settingsOpen = false);
    }

    return GestureDetector(
      key: const ValueKey('home_settings_modal'),
      behavior: HitTestBehavior.opaque,
      onTap: close,
      child: Container(
        color: const Color(0xCC0D0622),
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {},
          child: SizedBox(
            width: ux(context, 884),
            // Compact height while Restore is commented out (was 780 with Restore button)
            height: ux(context, 600),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: ux(context, 38),
                  bottom: 0,
                  child: const UnityNineSlice(
                    sprite: 'Background_Popup.png',
                    pixelMultiplier: 1.0,
                  ),
                ),
                Positioned(
                  left: ux(context, 50),
                  right: ux(context, 50),
                  top: ux(context, 184),
                  // Compact inner panel while Restore is commented out (was 520 with Restore button)
                  height: ux(context, 340),
                  child: UnityNineSlice(
                    sprite: 'Panel_Popup.png',
                    pixelMultiplier: 1.0,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ListenableBuilder(
                          listenable: widget.audio,
                          builder: (context, _) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _HomeSettingToggle(
                                  isEnabled: widget.audio.soundEnabled,
                                  enabledIcon: 'assets/images/Icon_Sounds.png',
                                  disabledIcon:
                                      'assets/images/Icon_Sounds_Off.png',
                                  onTap: widget.audio.toggleSound,
                                ),
                                SizedBox(width: ux(context, 28)),
                                _HomeSettingToggle(
                                  isEnabled: widget.audio.musicEnabled,
                                  enabledIcon: 'assets/images/Icon_Music.png',
                                  disabledIcon:
                                      'assets/images/Icon_Music_Off.png',
                                  onTap: widget.audio.toggleMusic,
                                ),
                                SizedBox(width: ux(context, 28)),
                                _HomeSettingToggle(
                                  isEnabled: widget.audio.hapticsEnabled,
                                  enabledIcon:
                                      'assets/images/Icon_Haptics.png',
                                  disabledIcon:
                                      'assets/images/Icon_Haptics_Off.png',
                                  onTap: widget.audio.toggleHaptics,
                                ),
                              ],
                            );
                          },
                        ),
                        // Temporarily disabled while IAP/Shop/Journey are deferred to next version:
                        // SizedBox(height: ux(context, 36)),
                        // _HomeAssetActionButton(
                        //   key: const ValueKey('home_settings_restore_btn'),
                        //   assetPath:
                        //       'assets/images/UI Home/btn_green_setting 2.png',
                        //   label: 'Restore',
                        //   width: ux(context, 420),
                        //   height: ux(context, 190),
                        //   onTap: () async {
                        //     widget.audio.playClick();
                        //     final ok = await IapService.restorePurchases(
                        //       widget.progress,
                        //     );
                        //     if (!mounted) return;
                        //     _showToast(
                        //       ok
                        //           ? 'Purchases restored!'
                        //           : 'No previous purchases found.',
                        //     );
                        //   },
                        // ),
                        SizedBox(height: ux(context, 44)),
                        ValueListenableBuilder<String>(
                          valueListenable: AppVersionService.versionNotifier,
                          builder: (context, _, _) => Text(
                            AppVersionService.displayLabel,
                            key: const ValueKey('home_settings_version_text'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Baloo2',
                              fontSize: ux(context, 40),
                              fontWeight: FontWeight.w800,
                              fontVariations: const [
                                FontVariation('wght', 800),
                              ],
                              color: const Color(0xFF9C5B40),
                              height: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
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
                          'Setting',
                          unityFontSize: 64,
                          material: UnityTextMaterial.popupTitle,
                          singleTextNode: true,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: ux(context, 10),
                  top: ux(context, 12),
                  width: ux(context, 139),
                  height: ux(context, 139),
                  child: UnitySpriteButton(
                    asset: 'Button_Close.png',
                    unitySize: 139,
                    onTap: close,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeAvatarBadge extends StatelessWidget {
  final double size;

  const _HomeAvatarBadge({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/images/UI Home/Home/frame_avatar.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
          ),
          Padding(
            padding: EdgeInsets.all(size * 0.12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.16),
              child: const SizedBox.expand(
                child: CustomPaint(painter: _BlueCatAvatarPainter()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlueCatAvatarPainter extends CustomPainter {
  const _BlueCatAvatarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.5;
    final paint = Paint()..isAntiAlias = true;

    // Ears
    final earColor = const Color(0xFF3E9DF5);
    final innerEarColor = const Color(0xFF1D4F9E);
    for (final sign in [-1.0, 1.0]) {
      final outer = Path()
        ..moveTo(cx + sign * w * 0.12, h * 0.25)
        ..lineTo(cx + sign * w * 0.36, h * 0.08)
        ..lineTo(cx + sign * w * 0.38, h * 0.38)
        ..close();
      paint.color = earColor;
      canvas.drawPath(outer, paint);

      final inner = Path()
        ..moveTo(cx + sign * w * 0.17, h * 0.24)
        ..lineTo(cx + sign * w * 0.32, h * 0.13)
        ..lineTo(cx + sign * w * 0.33, h * 0.32)
        ..close();
      paint.color = innerEarColor;
      canvas.drawPath(inner, paint);
    }

    // Shoulders & gold collar bell
    paint.color = const Color(0xFF287BE0);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, h * 0.90), width: w * 0.64, height: h * 0.36),
      paint,
    );
    paint.color = const Color(0xFFFFCA28);
    canvas.drawCircle(Offset(cx, h * 0.80), w * 0.08, paint);

    // Head base
    paint.shader = const RadialGradient(
      center: Alignment(-0.2, -0.2),
      colors: [Color(0xFF69C6FF), Color(0xFF3188EB)],
    ).createShader(Rect.fromCircle(center: Offset(cx, h * 0.48), radius: w * 0.36));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, h * 0.47), width: w * 0.72, height: h * 0.56),
      paint,
    );
    paint.shader = null;

    // Cream muzzle/cheeks
    paint.color = const Color(0xFFFFF8E8);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, h * 0.56), width: w * 0.56, height: h * 0.33),
      paint,
    );

    // Eyes
    for (final sign in [-1.0, 1.0]) {
      final ex = cx + sign * w * 0.17;
      final ey = h * 0.46;
      paint.color = const Color(0xFF291408);
      canvas.drawCircle(Offset(ex, ey), w * 0.068, paint);
      paint.color = Colors.white;
      canvas.drawCircle(Offset(ex - w * 0.02, ey - h * 0.02), w * 0.022, paint);
    }

    // Golden nose & smile
    paint.color = const Color(0xFFF6A526);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, h * 0.53), width: w * 0.09, height: h * 0.06),
      paint,
    );
    paint
      ..color = const Color(0xFF5A2B0C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.032
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, h * 0.58), width: w * 0.16, height: h * 0.10),
      0.15,
      math.pi - 0.30,
      false,
      paint,
    );
    paint.style = PaintingStyle.fill;
  }

  @override
  bool shouldRepaint(covariant _BlueCatAvatarPainter oldDelegate) => false;
}

class _HomeResourcePill extends StatefulWidget {
  final String leadingAsset;
  final String? leadingOverlayText;
  final bool showPlusBadge;
  final String label;
  final VoidCallback onTap;

  const _HomeResourcePill({
    super.key,
    required this.leadingAsset,
    this.leadingOverlayText,
    this.showPlusBadge = false,
    required this.label,
    required this.onTap,
  });

  @override
  State<_HomeResourcePill> createState() => _HomeResourcePillState();
}

class _HomeResourcePillState extends State<_HomeResourcePill> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final pillH = ux(context, 92);
    final iconSize = ux(context, 98);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          height: iconSize,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              // Gold-rimmed blue capsule (`asset_frame.png`)
              Positioned(
                left: ux(context, 34),
                right: 0,
                height: pillH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/UI Home/Home/asset_frame.png',
                      fit: BoxFit.fill,
                    ),
                    Padding(
                      padding: EdgeInsets.only(
                        left: ux(context, 54),
                        right: ux(context, 16),
                      ),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'Baloo2',
                              fontSize: ux(context, 42),
                              fontWeight: FontWeight.w900,
                              fontVariations: const [
                                FontVariation('wght', 900),
                              ],
                              color: Colors.white,
                              height: 1.0,
                              shadows: const [
                                Shadow(
                                  offset: Offset(0, 1.5),
                                  blurRadius: 2.0,
                                  color: Color(0xCC04103B),
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

              // Overlapping Left Icon (Heart / Coin)
              SizedBox(
                width: iconSize,
                height: iconSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      widget.leadingAsset,
                      width: iconSize,
                      height: iconSize,
                      fit: BoxFit.contain,
                    ),
                    if (widget.leadingOverlayText != null)
                      Transform.translate(
                        offset: Offset(0, -ux(context, 2)),
                        child: Text(
                          widget.leadingOverlayText!,
                          style: TextStyle(
                            fontFamily: 'PoetsenOne',
                            fontSize: ux(context, 42),
                            color: Colors.white,
                            shadows: const [
                              Shadow(
                                offset: Offset(0, 1.5),
                                blurRadius: 2.0,
                                color: Color(0xCC4A0404),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (widget.showPlusBadge)
                      Positioned(
                        right: ux(context, 2),
                        bottom: ux(context, 2),
                        child: Image.asset(
                          'assets/images/PowerUp_Plus.png',
                          width: ux(context, 44),
                          height: ux(context, 44),
                          fit: BoxFit.contain,
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

// ignore: unused_element
class _HomePromoShortcut extends StatefulWidget {
  final String iconAsset;
  final String label;
  final double unityWidth;
  final double unityHeight;
  final double unityIconWidth;
  final double unityIconHeight;
  final VoidCallback onTap;

  const _HomePromoShortcut({
    // ignore: unused_element_parameter
    super.key,
    required this.iconAsset,
    required this.label,
    required this.unityWidth,
    required this.unityHeight,
    required this.unityIconWidth,
    required this.unityIconHeight,
    required this.onTap,
  });

  @override
  State<_HomePromoShortcut> createState() => _HomePromoShortcutState();
}

class _HomePromoShortcutState extends State<_HomePromoShortcut> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: ux(context, widget.unityWidth),
          height: ux(context, widget.unityHeight),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Image.asset(
                widget.iconAsset,
                width: ux(context, widget.unityIconWidth),
                height: ux(context, widget.unityIconHeight),
                fit: BoxFit.contain,
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ux(context, 22),
                    vertical: ux(context, 7),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A245D),
                    borderRadius: BorderRadius.circular(ux(context, 24)),
                    border: Border.all(
                      color: const Color(0xFFFFB915),
                      width: ux(context, 4),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x8800051F),
                        blurRadius: 6,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Baloo2',
                      fontSize: ux(context, 31),
                      fontWeight: FontWeight.w800,
                      fontVariations: const [FontVariation('wght', 800)],
                      color: Colors.white,
                      height: 1.0,
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

class _HomePlayButton extends StatefulWidget {
  final int levelNumber;
  final double width;
  final double height;
  final VoidCallback onTap;

  const _HomePlayButton({
    super.key,
    required this.levelNumber,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  State<_HomePlayButton> createState() => _HomePlayButtonState();
}

class _HomePlayButtonState extends State<_HomePlayButton> {
  bool _pressed = false;

  static const _playLabelMaterial = UnityTextMaterial(
    faceTop: Colors.white,
    faceBottom: Colors.white,
    strokeColor: Color(0xFF094E00),
    strokeRatio: 0.16,
    outerStrokeColor: Color(0xFF053300),
    outerStrokeRatio: 0.22,
    underlayColor: Color(0xCC042800),
    underlayYRatio: 0.08,
    fontFamily: 'Baloo2',
    fontWeight: FontWeight.w900,
  );

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = widget.height;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1.0,
        duration: const Duration(milliseconds: 95),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/images/UI Home/Home/btn_green_play.png',
                width: w,
                height: h,
                fit: BoxFit.contain,
              ),
              Padding(
                padding: EdgeInsets.only(bottom: ux(context, 12)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: UnitySdfText(
                    'Level ${widget.levelNumber}',
                    unityFontSize: 78,
                    material: _playLabelMaterial,
                    singleTextNode: true,
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

// ignore: unused_element
class _HomeNavTabButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _HomeNavTabButton({
    // ignore: unused_element_parameter
    super.key,
    required this.onTap,
    required this.child,
  });

  @override
  State<_HomeNavTabButton> createState() => _HomeNavTabButtonState();
}

class _HomeNavTabButtonState extends State<_HomeNavTabButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Center(child: widget.child),
      ),
    );
  }
}

class _HomeSettingToggle extends StatelessWidget {
  final bool isEnabled;
  final String enabledIcon;
  final String disabledIcon;
  final VoidCallback onTap;

  const _HomeSettingToggle({
    required this.isEnabled,
    required this.enabledIcon,
    required this.disabledIcon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final sz = ux(context, 152);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: sz,
        height: sz,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              isEnabled
                  ? 'assets/images/Button_Circle_Blue.png'
                  : 'assets/images/Button_Circle_Gray.png',
              width: sz,
              height: sz,
              fit: BoxFit.contain,
            ),
            Image.asset(
              isEnabled ? enabledIcon : disabledIcon,
              width: sz * 0.56,
              height: sz * 0.56,
              fit: BoxFit.contain,
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _HomeAssetActionButton extends StatefulWidget {
  final String assetPath;
  final String label;
  final double width;
  final double height;
  final VoidCallback onTap;

  const _HomeAssetActionButton({
    // ignore: unused_element_parameter
    super.key,
    required this.assetPath,
    required this.label,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  State<_HomeAssetActionButton> createState() => _HomeAssetActionButtonState();
}

class _HomeAssetActionButtonState extends State<_HomeAssetActionButton> {
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
        scale: _pressed ? 0.935 : 1.0,
        duration: const Duration(milliseconds: 85),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                widget.assetPath,
                width: widget.width,
                height: widget.height,
                fit: BoxFit.contain,
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: ux(context, 28),
                  right: ux(context, 28),
                  bottom: ux(context, 10),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: UnitySdfText(
                    widget.label,
                    unityFontSize: 64,
                    material: UnityTextMaterial.ctaGreen,
                    singleTextNode: true,
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

/*
class _HomeBottomNavDock extends StatelessWidget {
  final _HomeTab activeTab;
  final bool journeyUnlocked;
  final bool hasJourneyNotice;
  final double bottomDockBarH;
  final double dockArtH;
  final double navSafeBottom;
  final double activeCardLift;
  final double activeCardW;
  final double bgScaleY;
  final VoidCallback onSelectShop;
  final VoidCallback onSelectHome;
  final VoidCallback onSelectJourney;

  const _HomeBottomNavDock({
    required this.activeTab,
    required this.journeyUnlocked,
    required this.hasJourneyNotice,
    required this.bottomDockBarH,
    required this.dockArtH,
    required this.navSafeBottom,
    required this.activeCardLift,
    required this.activeCardW,
    required this.bgScaleY,
    required this.onSelectShop,
    required this.onSelectHome,
    required this.onSelectJourney,
  });

  @override
  Widget build(BuildContext context) {
    final activeAlignment = switch (activeTab) {
      _HomeTab.shop => Alignment.bottomLeft,
      _HomeTab.home => Alignment.bottomCenter,
      _HomeTab.journey => Alignment.bottomRight,
    };

    final activeIcon = switch (activeTab) {
      _HomeTab.shop => Image.asset(
          'assets/images/UI Home/Home/icon_shop.png',
          width: ux(context, 172),
          height: ux(context, 165),
          fit: BoxFit.contain,
        ),
      _HomeTab.home => Image.asset(
          'assets/images/UI Home/Home/icon_home.png',
          width: ux(context, 177),
          height: ux(context, 173),
          fit: BoxFit.contain,
        ),
      _HomeTab.journey => Image.asset(
          'assets/images/Journey/Icon_Gllery.png',
          width: ux(context, 172),
          height: ux(context, 165),
          fit: BoxFit.contain,
        ),
    };

    final activeLabel = switch (activeTab) {
      _HomeTab.shop => 'Shop',
      _HomeTab.home => 'Home',
      _HomeTab.journey => 'Journey',
    };

    final activeKey = switch (activeTab) {
      _HomeTab.shop => const ValueKey('home_nav_shop_btn'),
      _HomeTab.home => const ValueKey('home_nav_home_btn'),
      _HomeTab.journey => const ValueKey('home_nav_journey_btn'),
    };

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // Base Indigo Bar with Gold Rim (`frame_menubar.png`)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: bottomDockBarH,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: math.max(bottomDockBarH, ux(context, 400)),
                  child: Image.asset(
                    'assets/images/UI Home/Home/frame_menubar.png',
                    fit: BoxFit.fill,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    top: 10.0 * bgScaleY,
                    bottom: navSafeBottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: activeTab == _HomeTab.shop
                            ? const SizedBox.shrink()
                            : _HomeNavTabButton(
                                key: const ValueKey('home_nav_shop_btn'),
                                onTap: onSelectShop,
                                child: SizedBox(
                                  width: ux(context, 180),
                                  height: math.min(
                                    ux(context, 158),
                                    dockArtH - 18.0 * bgScaleY,
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.center,
                                    children: [
                                      Image.asset(
                                        'assets/images/UI Home/Home/icon_shop.png',
                                        width: ux(context, 157),
                                        height: ux(context, 146),
                                        fit: BoxFit.contain,
                                      ),
                                      Positioned(
                                        right: -ux(context, 4),
                                        top: -ux(context, 4),
                                        child: Image.asset(
                                          'assets/images/UI Home/Home/notice.png',
                                          width: ux(context, 78),
                                          height: ux(context, 83),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      Expanded(
                        child: activeTab == _HomeTab.home
                            ? const SizedBox.shrink()
                            : _HomeNavTabButton(
                                key: const ValueKey('home_nav_home_btn'),
                                onTap: onSelectHome,
                                child: Image.asset(
                                  'assets/images/UI Home/Home/icon_home.png',
                                  width: ux(context, 152),
                                  height: math.min(
                                    ux(context, 148),
                                    dockArtH - 18.0 * bgScaleY,
                                  ),
                                  fit: BoxFit.contain,
                                ),
                              ),
                      ),
                      Expanded(
                        child: activeTab == _HomeTab.journey
                            ? const SizedBox.shrink()
                            : _HomeNavTabButton(
                                key: ValueKey(
                                  journeyUnlocked
                                      ? 'home_nav_journey_btn'
                                      : 'home_nav_lock_btn',
                                ),
                                onTap: onSelectJourney,
                                child: journeyUnlocked
                                    ? SizedBox(
                                        width: ux(context, 180),
                                        height: math.min(
                                          ux(context, 158),
                                          dockArtH - 18.0 * bgScaleY,
                                        ),
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          alignment: Alignment.center,
                                          children: [
                                            Image.asset(
                                              'assets/images/Journey/Icon_Gllery.png',
                                              width: ux(context, 152),
                                              height: ux(context, 145),
                                              fit: BoxFit.contain,
                                            ),
                                            if (hasJourneyNotice)
                                              Positioned(
                                                right: -ux(context, 4),
                                                top: -ux(context, 4),
                                                child: Image.asset(
                                                  'assets/images/UI Home/Home/notice.png',
                                                  width: ux(context, 74),
                                                  height: ux(context, 78),
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                          ],
                                        ),
                                      )
                                    : Image.asset(
                                        'assets/images/UI Home/Home/icon_lock.png',
                                        width: ux(context, 114),
                                        height: math.min(
                                          ux(context, 145),
                                          dockArtH - 22.0 * bgScaleY,
                                        ),
                                        fit: BoxFit.contain,
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

        // Raised Active Tab Card (`frame_footer.png`)
        Align(
          alignment: activeAlignment,
          child: GestureDetector(
            key: activeKey,
            onTap: switch (activeTab) {
              _HomeTab.shop => onSelectShop,
              _HomeTab.home => onSelectHome,
              _HomeTab.journey => onSelectJourney,
            },
            child: SizedBox(
              width: activeCardW,
              height: bottomDockBarH + activeCardLift,
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: math.max(
                        bottomDockBarH + activeCardLift,
                        ux(context, 484),
                      ),
                      child: Image.asset(
                        'assets/images/UI Home/Home/frame_footer.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        ux(context, 16),
                        34.0 * bgScaleY,
                        ux(context, 16),
                        24.0 * bgScaleY + navSafeBottom,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(child: activeIcon),
                          SizedBox(height: 10.0 * bgScaleY),
                          UnitySdfText(
                            activeLabel,
                            unityFontSize: 52,
                            material: _HomeScreenState._homeTabTextMaterial,
                            singleTextNode: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
*/


