import 'dart:math' as math;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../game/block_order_game.dart';
import '../models/level_models.dart';
import '../models/palette.dart';
import '../models/unity_curve.dart';
import '../services/audio_haptics_service.dart';
import '../services/player_progress_service.dart';
import 'exit_gameplay_popup.dart';
import 'level_picker_sheet.dart';
import 'lose_overlay.dart';
import 'mechanic_unlock_dialog.dart';
import 'powerup_buy_popup.dart';
import 'unity_ui_kit.dart';
import 'win_overlay.dart';

class GameplayScreen extends StatefulWidget {
  final LevelRepository repository;
  final BlockOrderPalette palette;
  final PieceVisualSettings visualSettings;
  final AudioHapticsService audio;
  final PlayerProgressService progress;

  const GameplayScreen({
    super.key,
    required this.repository,
    required this.palette,
    required this.visualSettings,
    required this.audio,
    required this.progress,
  });

  @override
  State<GameplayScreen> createState() => _GameplayScreenState();
}

class _GameplayScreenState extends State<GameplayScreen>
    with TickerProviderStateMixin {
  late LevelDefinition _activeLevel;
  late final BlockOrderGame _game;

  late final AnimationController _coinBounceCtrl;
  late final AnimationController _freezeFlyCtrl;
  late final AnimationController _lowTimerPulseCtrl;

  bool _showWinOverlay = false;
  bool _showLoseOverlay = false;
  bool _showExitRestartPopup = false;
  bool? _buyPopupIsLevelUp; // null = closed, true = Level Up, false = Time Freeze
  bool _settingsOpen = false;
  bool _hideTutorialBanner = false;
  MechanicUnlockInfo? _activeMechanicModal;

  @override
  void initState() {
    super.initState();
    _activeLevel =
        widget.repository.getCampaignLevel(widget.progress.currentLevel);

    _coinBounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _freezeFlyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    _lowTimerPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..repeat(reverse: true);

    _game = BlockOrderGame(
      initialLevel: _activeLevel,
      palette: widget.palette,
      visualSettings: widget.visualSettings,
      audio: widget.audio,
      onLevelWon: _handleLevelWon,
      onTimeExpired: _handleTimeExpired,
      onFirstAction: () {
        if (mounted && !_hideTutorialBanner) {
          setState(() => _hideTutorialBanner = true);
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNewMechanicOrPowerUpUnlock(_activeLevel);
    });
  }

  @override
  void dispose() {
    _coinBounceCtrl.dispose();
    _freezeFlyCtrl.dispose();
    _lowTimerPulseCtrl.dispose();
    super.dispose();
  }

  void _syncGamePauseState() {
    _game.isModalPaused = _showWinOverlay ||
        _showLoseOverlay ||
        _showExitRestartPopup ||
        _buyPopupIsLevelUp != null ||
        _settingsOpen ||
        _activeMechanicModal != null;
  }

  void _checkNewMechanicOrPowerUpUnlock(LevelDefinition lv) {
    if (lv.isBonus) return;
    MechanicUnlockInfo? unlock;
    if (lv.hasIce &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.ice.id)) {
      unlock = MechanicUnlockInfo.ice;
    } else if (lv.hasDud &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.dud.id)) {
      unlock = MechanicUnlockInfo.dud;
    } else if (lv.hasPinned &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.pinned.id)) {
      unlock = MechanicUnlockInfo.pinned;
    } else if (lv.hasArrows &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.arrows.id)) {
      unlock = MechanicUnlockInfo.arrows;
    } else if (lv.number == 5 &&
        !widget.progress
            .hasSeenMechanic(MechanicUnlockInfo.levelUpPowerUp.id)) {
      unlock = MechanicUnlockInfo.levelUpPowerUp;
    } else if (lv.number == 9 &&
        !widget.progress
            .hasSeenMechanic(MechanicUnlockInfo.timeFreezePowerUp.id)) {
      unlock = MechanicUnlockInfo.timeFreezePowerUp;
    }

    if (unlock != null && mounted) {
      setState(() {
        _activeMechanicModal = unlock;
        _syncGamePauseState();
      });
    }
  }

  void _startLevel(LevelDefinition level) {
    if (!level.isBonus) {
      widget.progress.setCurrentLevel(level.number);
    } else {
      widget.progress.flushPendingWinCoins();
    }
    setState(() {
      _activeLevel = level;
      _showWinOverlay = false;
      _showLoseOverlay = false;
      _showExitRestartPopup = false;
      _buyPopupIsLevelUp = null;
      _settingsOpen = false;
      _hideTutorialBanner = false;
      _activeMechanicModal = null;
      _syncGamePauseState();
    });
    _game.loadLevel(level);
    _checkNewMechanicOrPowerUpUnlock(level);
  }

  void _handleLevelWon() {
    if (!mounted) return;
    widget.progress.stageLevelWinReward(
      rewardCoins: _activeLevel.coinReward,
      isBonus: _activeLevel.isBonus,
    );
    setState(() {
      _showWinOverlay = true;
      _settingsOpen = false;
      _showExitRestartPopup = false;
      _buyPopupIsLevelUp = null;
      _syncGamePauseState();
    });
  }

  void _handleTimeExpired() {
    if (!mounted) return;
    setState(() {
      _showLoseOverlay = true;
      _settingsOpen = false;
      _showExitRestartPopup = false;
      _buyPopupIsLevelUp = null;
      _syncGamePauseState();
    });
  }

  void _handleNextLevelAfterWin() {
    widget.progress.flushPendingWinCoins();
    widget.audio.playClick();
    if (_activeLevel.isBonus) {
      final list = widget.repository.bonusLevels;
      final idx = list.indexWhere((b) => b.number == _activeLevel.number);
      final nextBonus = list[(idx + 1) % list.length];
      _startLevel(nextBonus);
      return;
    }
    widget.progress.advanceToNextCampaignLevel();
    final nextLv =
        widget.repository.getCampaignLevel(widget.progress.currentLevel);
    _startLevel(nextLv);
  }

  void _handlePlayOnCoins() {
    const cost = 200;
    if (!widget.progress.spendCoins(cost)) {
      widget.audio.hapticBlocked();
      return;
    }
    widget.audio.playClick();
    setState(() {
      _showLoseOverlay = false;
      _syncGamePauseState();
    });
    _game.addExtraTime(30);
  }

  void _handlePlayOnAd() {
    widget.audio.playClick();
    setState(() {
      _showLoseOverlay = false;
      _syncGamePauseState();
    });
    _game.addExtraTime(30);
  }

  void _handleEnterFailedStage() {
    widget.audio.playLevelFailed();
    widget.progress.loseLife();
  }

  void _handleRetryLevel() {
    widget.audio.playClick();
    widget.progress.ensureAtLeastOneLife();
    setState(() {
      _showLoseOverlay = false;
      _showWinOverlay = false;
      _showExitRestartPopup = false;
      _settingsOpen = false;
      _hideTutorialBanner = false;
      _syncGamePauseState();
    });
    _game.restartLevel();
  }

  void _handleRequestReplayFromSettings() {
    widget.audio.playClick();
    setState(() {
      _settingsOpen = false;
      _showExitRestartPopup = true;
      _syncGamePauseState();
    });
  }

  void _handleConfirmExitRestart() {
    widget.progress.loseLife();
    _handleRetryLevel();
  }

  bool get _isLevelUpLocked =>
      !_activeLevel.isBonus && _activeLevel.number < 5;

  bool get _isTimeFreezeLocked => _activeLevel.timerDisabled;

  void _handleLevelUpTap() {
    if (_isLevelUpLocked) {
      widget.audio.hapticBlocked();
      _showUnityBannerToast('Unlocks at Level 5');
      return;
    }
    if (widget.progress.levelUpCount <= 0) {
      widget.audio.playPowerUpSelect();
      setState(() {
        _buyPopupIsLevelUp = true;
        _syncGamePauseState();
      });
      return;
    }
    if (_game.isBusyWithPowerUp || !_game.canLevelUpNotifier.value) {
      widget.audio.hapticBlocked();
      return;
    }
    widget.audio.playPowerUpSelect();
    if (_game.triggerLevelUpPowerUp()) {
      widget.progress.consumeLevelUp();
    }
  }

  void _handleTimeFreezeTap() {
    if (_isTimeFreezeLocked) {
      widget.audio.hapticBlocked();
      _showUnityBannerToast('No timer on this tutorial level');
      return;
    }
    if (widget.progress.timeFreezeCount <= 0) {
      widget.audio.playPowerUpSelect();
      setState(() {
        _buyPopupIsLevelUp = false;
        _syncGamePauseState();
      });
      return;
    }
    if (_game.timeFreezeNotifier.value > 1.0) {
      widget.audio.hapticBlocked();
      return;
    }
    widget.audio.playPowerUpSelect();
    if (_game.triggerTimeFreezePowerUp()) {
      widget.progress.consumeTimeFreeze();
      _freezeFlyCtrl.forward(from: 0.0);
    }
  }

  void _openLevelPicker() {
    widget.audio.playClick();
    setState(() {
      _settingsOpen = false;
      _game.isModalPaused = true;
    });
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LevelPickerSheet(
        repository: widget.repository,
        activeLevelNumber: _activeLevel.number,
        activeIsBonus: _activeLevel.isBonus,
        highestUnlockedLevel: widget.progress.highestLevel,
        onSelectLevel: _startLevel,
      ),
    ).whenComplete(() {
      if (mounted) {
        setState(_syncGamePauseState);
      }
    });
  }

  void _showUnityBannerToast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1400),
          margin: EdgeInsets.fromLTRB(
            ux(context, 90),
            0,
            ux(context, 90),
            ux(context, 280),
          ),
          content: UnityNineSlice(
            sprite: 'Banner.png',
            height: ux(context, 120),
            padding: EdgeInsets.only(bottom: ux(context, 10)),
            child: UnitySdfText(
              msg,
              unityFontSize: 44,
              material: UnityTextMaterial.popupTitle,
            ),
          ),
        ),
      );
  }

  String _formatTimer(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tutorialHint = !_activeLevel.isBonus
        ? widget.repository.tutorialHints[_activeLevel.number]
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0330AC),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Exact Sampled Multi-Radial Unity Gameplay Background (`ref_gameplay.png`)
          const _UnityGameplayBackground(),

          // 2. Flame 2.5D Board & Block Puzzle Canvas
          GameWidget<BlockOrderGame>(game: _game),

          // 3. Authentic `TimeFreezeFullScreenEffectView.prefab` Frost & Corner Crystals
          ValueListenableBuilder<double>(
            valueListenable: _game.timeFreezeNotifier,
            builder: (context, freezeLeft, _) {
              if (freezeLeft <= 0) return const SizedBox.shrink();
              final alpha = (freezeLeft / 2.5).clamp(0.0, 1.0);
              return _TimeFreezeFullscreenOverlay(opacity: alpha);
            },
          ),

          // 4. Urgent Low-Time (<= 10s) Soft Red Vignette Pulse
          ValueListenableBuilder<int>(
            valueListenable: _game.remainingSecondsNotifier,
            builder: (context, secs, _) {
              if (_activeLevel.timerDisabled || secs > 10 || secs <= 0) {
                return const SizedBox.shrink();
              }
              return AnimatedBuilder(
                animation: _lowTimerPulseCtrl,
                builder: (context, _) {
                  final a = 0.14 + 0.28 * _lowTimerPulseCtrl.value;
                  return IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Color.fromRGBO(255, 38, 78, a),
                          width: ux(context, 16),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),

          // 5. Top HUD (`CoinsWidget`, Tappable `Level X`, `TimerGameplayView`)
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: ux(context, 42),
                right: ux(context, 46),
                top: ux(context, 18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Top-Left `CoinsWidget` (hidden here when `_showWinOverlay` elevates it above dim)
                      Opacity(
                        opacity: _showWinOverlay ? 0.0 : 1.0,
                        child: IgnorePointer(
                          ignoring: _showWinOverlay,
                          child: _buildCoinsWidget(context),
                        ),
                      ),

                      // Top-Right `Level 20` (`Baloo2_ExtraBold_LevelCounter`, `sz = 65.3`)
                      GestureDetector(
                        onTap: _openLevelPicker,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: ux(context, 8),
                            vertical: ux(context, 8),
                          ),
                          child: UnitySdfText(
                            _activeLevel.title,
                            unityFontSize: 65.3,
                            material: UnityTextMaterial.levelCounter,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Top-Center `TimerGameplayView.prefab` (`3:00` pill / frozen snow pill / urgent red pill)
                  if (!_activeLevel.timerDisabled) ...[
                    SizedBox(height: ux(context, 38)),
                    _buildTimerGameplayView(context),
                  ],
                ],
              ),
            ),
          ),

          // 6. Bottom Power-Ups Bar + Tutorial Text + Bottom-Right `Icon_Settings.png`
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: ux(context, 28),
                  left: ux(context, 40),
                  right: ux(context, 40),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tutorial Hint Text (`Baloo2_ExtraBold_Tutorial_Text`, Levels 1-3)
                    if (tutorialHint != null && !_hideTutorialBanner)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: ux(context, 28),
                          left: ux(context, 32),
                          right: ux(context, 32),
                        ),
                        child: UnitySdfText(
                          tutorialHint,
                          unityFontSize: 48,
                          material: UnityTextMaterial.tutorialText,
                        ),
                      ),

                    SizedBox(
                      width: double.infinity,
                      height: ux(context, 214),
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Center Pair: `Level Up` & `Time Freeze` (`ux(196)` circles)
                          ListenableBuilder(
                            listenable: widget.progress,
                            builder: (context, _) {
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ValueListenableBuilder<bool>(
                                    valueListenable: _game.canLevelUpNotifier,
                                    builder: (context, canUse, _) {
                                      return _UnityPowerUpButton(
                                        unlockedAsset:
                                            'assets/images/PowerUp_LevelUp.png',
                                        lockedAsset:
                                            'assets/images/PowerUp_LevelUp_Locked.png',
                                        count: widget.progress.levelUpCount,
                                        isLocked: _isLevelUpLocked,
                                        isReady: canUse,
                                        onTap: _handleLevelUpTap,
                                      );
                                    },
                                  ),
                                  SizedBox(width: ux(context, 42)),
                                  ValueListenableBuilder<double>(
                                    valueListenable: _game.timeFreezeNotifier,
                                    builder: (context, freezeLeft, _) {
                                      final canFreeze =
                                          !_isTimeFreezeLocked &&
                                              freezeLeft <= 1.0;
                                      return _UnityPowerUpButton(
                                        unlockedAsset:
                                            'assets/images/PowerUp_TimeFreeze.png',
                                        lockedAsset:
                                            'assets/images/PowerUp_TimeFreeze_Locked.png',
                                        count: widget.progress.timeFreezeCount,
                                        isLocked: _isTimeFreezeLocked,
                                        isReady: canFreeze,
                                        onTap: _handleTimeFreezeTap,
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          ),

                          // Bottom-Right White Gear (`Icon_Settings.png` `ux(84)`)
                          Positioned(
                            right: ux(context, 12),
                            bottom: ux(context, 16),
                            child: UnitySpriteButton(
                              asset: 'Icon_Settings.png',
                              unitySize: 84,
                              onTap: () {
                                widget.audio.playClick();
                                setState(() {
                                  _settingsOpen = !_settingsOpen;
                                  _syncGamePauseState();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 7. Flying `PowerUp_TimeFreeze.png` Clock-to-Timer Burst Animation
          AnimatedBuilder(
            animation: _freezeFlyCtrl,
            builder: (context, _) {
              if (!_freezeFlyCtrl.isAnimating && _freezeFlyCtrl.value == 0.0) {
                return const SizedBox.shrink();
              }
              return _buildTimeFreezeFlightFx(context, _freezeFlyCtrl.value);
            },
          ),

          // 8. Authentic Settings Speed-Dial & Legal Footer (`PauseGameplayView` + `ref_settings.png`)
          if (_settingsOpen) _buildSettingsSpeedDialOverlay(context),

          // 9. `ExitGameplayView.prefab` (`Restart level?` -> `You will lose a life!`)
          if (_showExitRestartPopup)
            ExitGameplayPopup(
              onConfirmRestart: _handleConfirmExitRestart,
              onCancel: () {
                widget.audio.playClick();
                setState(() {
                  _showExitRestartPopup = false;
                  _syncGamePauseState();
                });
              },
            ),

          // 10. `PowerUpBuyView.prefab` (`Buy 200` / `Watch Ad`)
          if (_buyPopupIsLevelUp != null)
            ListenableBuilder(
              listenable: widget.progress,
              builder: (context, _) {
                final isLvUp = _buyPopupIsLevelUp!;
                return PowerUpBuyPopup(
                  isLevelUp: isLvUp,
                  playerCoins: widget.progress.coins,
                  packCost: 200,
                  onBuyPack: () {
                    if (widget.progress.buyPowerUpPack(
                      isLevelUp: isLvUp,
                      cost: 200,
                      count: 3,
                    )) {
                      widget.audio.playCoinCollect();
                      setState(() {
                        _buyPopupIsLevelUp = null;
                        _syncGamePauseState();
                      });
                    } else {
                      widget.audio.hapticBlocked();
                    }
                  },
                  onWatchAd: () {
                    widget.audio.playCoinCollect();
                    widget.progress.grantFreePowerUp(
                      isLevelUp: isLvUp,
                      count: 1,
                    );
                    setState(() {
                      _buyPopupIsLevelUp = null;
                      _syncGamePauseState();
                    });
                  },
                  onClose: () {
                    widget.audio.playClick();
                    setState(() {
                      _buyPopupIsLevelUp = null;
                      _syncGamePauseState();
                    });
                  },
                );
              },
            ),

          // 11. `MechanicFTUE.prefab` / `PowerUpFTUEView.prefab` Full-Screen Unlock Overlay
          if (_activeMechanicModal != null)
            MechanicUnlockDialog(
              info: _activeMechanicModal!,
              onDismiss: () {
                final modal = _activeMechanicModal!;
                widget.audio.playClick();
                widget.progress.markMechanicSeen(modal.id);
                setState(() {
                  _activeMechanicModal = null;
                  _syncGamePauseState();
                });
              },
            ),

          // 12. Two-Stage `WinGameplayView.prefab` (`Level complete!` -> `AMAZING!` + Coin Flight)
          if (_showWinOverlay)
            WinOverlay(
              levelLabel: _activeLevel.title,
              rewardCoins: _activeLevel.coinReward,
              onStage2Shown: widget.audio.playWinAmazing,
              onCoinChunkArrived: (chunk) {
                widget.progress.collectPendingWinCoinChunk(chunk);
                widget.audio.playCoinCollect();
                _coinBounceCtrl.forward(from: 0.0);
              },
              onNextLevel: _handleNextLevelAfterWin,
            ),

          // 12b. Elevated Top-Left `CoinsWidget` during `WinOverlay` (matches `ref1.png` 100%!)
          if (_showWinOverlay)
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: ux(context, 42),
                    top: ux(context, 18),
                  ),
                  child: _buildCoinsWidget(context),
                ),
              ),
            ),

          // 13. Two-Stage `PlayOnPopupView.prefab` -> `LoseGameplayView.prefab`
          if (_showLoseOverlay)
            ListenableBuilder(
              listenable: widget.progress,
              builder: (context, _) {
                return LoseOverlay(
                  levelLabel: _activeLevel.title,
                  playerCoins: widget.progress.coins,
                  remainingLives: widget.progress.lives,
                  playOnCost: 200,
                  onPlayOnCoins: _handlePlayOnCoins,
                  onPlayOnAd: _handlePlayOnAd,
                  onEnterFailedStage: _handleEnterFailedStage,
                  onRetry: _handleRetryLevel,
                );
              },
            ),
        ],
      ),
    );
  }

  /// Authentic `CoinsWidget` (`WidgetBase.png` 9-slice + `Icon_Coin.png` + `Baloo2` counter).
  Widget _buildCoinsWidget(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.progress, _coinBounceCtrl]),
      builder: (context, _) {
        final t = _coinBounceCtrl.value;
        final pulse = 1.0 + 0.14 * math.sin(t * math.pi);

        return GestureDetector(
          onTap: () {
            widget.audio.playCoinCollect();
            widget.progress.addCoins(250);
            _coinBounceCtrl.forward(from: 0.0);
          },
          child: Transform.scale(
            scale: pulse,
            child: SizedBox(
              width: ux(context, 326),
              height: ux(context, 114),
              child: Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: ux(context, 46),
                    right: 0,
                    child: UnityNineSlice(
                      sprite: 'WidgetBase.png',
                      height: ux(context, 84),
                      padding: EdgeInsets.only(
                        left: ux(context, 56),
                        right: ux(context, 20),
                        bottom: ux(context, 4),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${widget.progress.coins}',
                          style: TextStyle(
                            fontFamily: 'Baloo2',
                            fontSize: ux(context, 47),
                            fontWeight: FontWeight.w800,
                            fontVariations: const [FontVariation('wght', 800)],
                            color: Colors.white,
                            height: 1.0,
                            shadows: const [
                              Shadow(
                                color: Color(0x99140858),
                                offset: Offset(0, 1.5),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Image.asset(
                    'assets/images/Icon_Coin.png',
                    width: ux(context, 114),
                    height: ux(context, 114),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Authentic `TimerGameplayView.prefab`:
  /// - Normal: `Shadow.png` + `Circle_01.png` tinted `#0C004F` + `Icon_Timer.png` + `3:00`
  /// - Urgent (`<= 10s`): pulsing `Widget_Timer_Set.png` + `Icon_Timer.png` + `0:09`
  /// - Frozen: `Pill_03.png` + `Snow.png` snow cap + `PowerUp_TimeFreeze.png` + `TimeFreeze_TimerBar.png`
  Widget _buildTimerGameplayView(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _game.timeFreezeNotifier,
      builder: (context, freezeLeft, _) {
        final isFrozen = freezeLeft > 0;
        return ValueListenableBuilder<int>(
          valueListenable: _game.remainingSecondsNotifier,
          builder: (context, secs, _) {
            final isUrgent = secs <= 10 && !isFrozen;
            final pillW = ux(context, 316);
            final pillH = ux(context, 106);

            Widget pillBody;
            if (isFrozen) {
              pillBody = SizedBox(
                width: pillW,
                height: pillH + ux(context, 18),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.none,
                  children: [
                    UnityNineSlice(
                      sprite: 'Pill_03.png',
                      width: pillW,
                      height: pillH,
                      tint: const Color(0xFF1A68C7),
                    ),
                    // `Snow.png` icy snow cap draped across the top of the timer pill
                    Positioned(
                      top: -ux(context, 6),
                      child: Image.asset(
                        'assets/images/Snow.png',
                        width: pillW * 0.94,
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(
                      width: pillW,
                      height: pillH,
                      child: _buildTimerInnerRow(
                        context: context,
                        secs: secs,
                        isFrozen: true,
                        isUrgent: false,
                      ),
                    ),
                  ],
                ),
              );
            } else if (isUrgent) {
              pillBody = AnimatedBuilder(
                animation: _lowTimerPulseCtrl,
                builder: (context, child) => Transform.scale(
                  scale: 1.0 + 0.055 * _lowTimerPulseCtrl.value,
                  child: child,
                ),
                child: UnityNineSlice(
                  sprite: 'Widget_Timer_Set.png',
                  width: pillW,
                  height: pillH,
                  child: _buildTimerInnerRow(
                    context: context,
                    secs: secs,
                    isFrozen: false,
                    isUrgent: true,
                  ),
                ),
              );
            } else {
              pillBody = SizedBox(
                width: pillW,
                height: pillH,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: ux(context, 6),
                      child: UnityNineSlice(
                        sprite: 'Shadow.png',
                        width: pillW,
                        height: pillH,
                        tint: const Color(0x55000522),
                      ),
                    ),
                    UnityNineSlice(
                      sprite: 'Circle_01.png',
                      width: pillW,
                      height: pillH,
                      tint: const Color(0xFF0C024C),
                      child: _buildTimerInnerRow(
                        context: context,
                        secs: secs,
                        isFrozen: false,
                        isUrgent: false,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                pillBody,
                if (isFrozen) ...[
                  SizedBox(height: ux(context, 12)),
                  SizedBox(
                    width: ux(context, 268),
                    height: ux(context, 24),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        UnityNineSlice(
                          sprite: 'TimeFreeze_TimerBar.png',
                          width: ux(context, 268),
                          height: ux(context, 24),
                          tint: const Color(0xFF0A245E),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(ux(context, 12)),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: (freezeLeft /
                                    BlockOrderGame.maxTimeFreezeSeconds)
                                .clamp(0.0, 1.0),
                            child: Container(
                              width: ux(context, 268),
                              height: ux(context, 18),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF67F7FF),
                                    Color(0xFF1CEFFF),
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
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTimerInnerRow({
    required BuildContext context,
    required int secs,
    required bool isFrozen,
    required bool isUrgent,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ux(context, 20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            isFrozen
                ? 'assets/images/PowerUp_TimeFreeze.png'
                : 'assets/images/Icon_Timer.png',
            width: ux(context, isFrozen ? 80 : 74),
            height: ux(context, isFrozen ? 80 : 74),
          ),
          SizedBox(width: ux(context, 20)),
          Text(
            _formatTimer(secs),
            style: TextStyle(
              fontFamily: 'Baloo2',
              fontSize: ux(context, 68),
              fontWeight: FontWeight.w800,
              fontVariations: const [FontVariation('wght', 800)],
              color: isFrozen
                  ? const Color(0xFFD9FBFF)
                  : isUrgent
                      ? const Color(0xFFFFE5EA)
                      : Colors.white,
              letterSpacing: 0.4,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Flying `PowerUp_TimeFreeze.png` clock from bottom button to top-center timer + `Explosion_Halo.png`.
  Widget _buildTimeFreezeFlightFx(BuildContext context, double t) {
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final start = Offset(
      screen.width * 0.5 + ux(context, 118),
      screen.height - pad.bottom - ux(context, 128),
    );
    final end = Offset(
      screen.width * 0.5 - ux(context, 86),
      pad.top + ux(context, 182),
    );

    final flyT = (t / 0.68).clamp(0.0, 1.0);
    final haloT = ((t - 0.58) / 0.42).clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(flyT);

    final ctrl = Offset(screen.width * 0.72, screen.height * 0.48);
    final om = 1.0 - eased;
    final px = om * om * start.dx + 2 * om * eased * ctrl.dx + eased * eased * end.dx;
    final py = om * om * start.dy + 2 * om * eased * ctrl.dy + eased * eased * end.dy;

    return IgnorePointer(
      child: Stack(
        children: [
          if (flyT < 1.0)
            Positioned(
              left: px - ux(context, 75),
              top: py - ux(context, 75),
              child: Transform.scale(
                scale: 1.15 - 0.35 * eased,
                child: Image.asset(
                  'assets/images/PowerUp_TimeFreeze.png',
                  width: ux(context, 150),
                  height: ux(context, 150),
                ),
              ),
            ),
          if (haloT > 0.0 && haloT < 1.0)
            Positioned(
              left: end.dx - ux(context, 180),
              top: end.dy - ux(context, 180),
              child: Transform.scale(
                scale: 0.35 + 1.15 * haloT,
                child: Opacity(
                  opacity: (1.0 - haloT).clamp(0.0, 1.0),
                  child: Image.asset(
                    'assets/images/Explosion_Halo.png',
                    width: ux(context, 360),
                    height: ux(context, 360),
                    color: const Color(0xFF7AF5FF),
                    colorBlendMode: BlendMode.modulate,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Exact `PauseGameplayView.prefab` + `ref_settings.png` Settings Speed-Dial & Footer.
  Widget _buildSettingsSpeedDialOverlay(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.audio.playClick();
        setState(() {
          _settingsOpen = false;
          _syncGamePauseState();
        });
      },
      child: Container(
        color: const Color(0xE00B1837),
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Bottom-Right Speed-Dial Column (`Replay`, `Haptics`, `Music`, `Sounds`, `Gear`)
              Positioned(
                right: ux(context, 26),
                bottom: ux(context, 44),
                child: ListenableBuilder(
                  listenable: widget.audio,
                  builder: (context, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SpeedDialUnityButton(
                          bgAsset: 'assets/images/Button_Circle_Red.png',
                          iconAsset: 'assets/images/Icon_Replay.png',
                          iconUnitySize: 78,
                          isEnabled: true,
                          showDisabledSlash: false,
                          delayMs: 90,
                          onTap: _handleRequestReplayFromSettings,
                        ),
                        SizedBox(height: ux(context, 34)),
                        _SpeedDialUnityButton(
                          bgAsset: 'assets/images/Button_Circle_Green.png',
                          iconAsset: 'assets/images/Icon_Haptics.png',
                          iconUnitySize: 80,
                          isEnabled: widget.audio.hapticsEnabled,
                          showDisabledSlash: true,
                          delayMs: 60,
                          onTap: widget.audio.toggleHaptics,
                        ),
                        SizedBox(height: ux(context, 34)),
                        _SpeedDialUnityButton(
                          bgAsset: 'assets/images/Button_Circle_Green.png',
                          iconAsset: 'assets/images/Icon_Music.png',
                          iconUnitySize: 72,
                          isEnabled: widget.audio.musicEnabled,
                          showDisabledSlash: true,
                          delayMs: 30,
                          onTap: widget.audio.toggleMusic,
                        ),
                        SizedBox(height: ux(context, 34)),
                        _SpeedDialUnityButton(
                          bgAsset: 'assets/images/Button_Circle_Green.png',
                          iconAsset: 'assets/images/Icon_Sounds.png',
                          iconUnitySize: 76,
                          isEnabled: widget.audio.soundEnabled,
                          showDisabledSlash: true,
                          delayMs: 0,
                          onTap: widget.audio.toggleSound,
                        ),
                        SizedBox(height: ux(context, 42)),
                        UnitySpriteButton(
                          asset: 'Icon_Settings.png',
                          unitySize: 84,
                          onTap: () {
                            widget.audio.playClick();
                            setState(() {
                              _settingsOpen = false;
                              _syncGamePauseState();
                            });
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Bottom IDFV / IDFA / Version + `Button_Setting_Smallest.png` (`T&C`, `Privacy`)
              Positioned(
                left: ux(context, 16),
                right: ux(context, 16),
                bottom: ux(context, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'IDFV: 24f01d1c42b37604b18fd2f9fae93dae',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Baloo2',
                              fontSize: ux(context, 34),
                              fontWeight: FontWeight.w600,
                              fontVariations: const [FontVariation('wght', 600)],
                              color: const Color(0xFFD8E7FF),
                              height: 1.25,
                            ),
                          ),
                          SizedBox(height: ux(context, 14)),
                          Text(
                            'IDFA: 995fac9a-0019-4055-9363-65384720a1c8',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Baloo2',
                              fontSize: ux(context, 34),
                              fontWeight: FontWeight.w600,
                              fontVariations: const [FontVariation('wght', 600)],
                              color: const Color(0xFFD8E7FF),
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: ux(context, 14)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _SmallestLegalButton(
                          label: 'T&C',
                          onTap: () {
                            widget.audio.playClick();
                            _showUnityBannerToast('Terms & Conditions');
                          },
                        ),
                        IgnorePointer(
                          child: Text(
                            '0.05.00 (63)',
                            style: TextStyle(
                              fontFamily: 'Baloo2',
                              fontSize: ux(context, 34),
                              fontWeight: FontWeight.w600,
                              fontVariations: const [FontVariation('wght', 600)],
                              color: const Color(0xFFD8E7FF),
                            ),
                          ),
                        ),
                        _SmallestLegalButton(
                          label: 'Privacy',
                          onTap: () {
                            widget.audio.playClick();
                            _showUnityBannerToast('Privacy Policy');
                          },
                        ),
                      ],
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

/// Exact multi-radial Unity gameplay background sampled from `ref_gameplay.png`:
/// - Base royal electric cobalt `#0330AC`
/// - Top-left electric violet glow `#6E2FF9` -> `#492FD4` -> `#0330AC`
/// - Top-right cerulean glow `#2F72E4` -> `#1E55C7` -> `#0330AC`
/// - Bottom-center cyan-cobalt glow `#0366B2` -> `#0330AC`
class _UnityGameplayBackground extends StatelessWidget {
  const _UnityGameplayBackground();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF0330AC)),
          // Top-Right Cerulean Glow
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.96, -1.00),
                radius: 0.95,
                colors: [
                  Color(0xFF2F72E4),
                  Color(0x881E55C7),
                  Color(0x000330AC),
                ],
                stops: [0.0, 0.52, 1.0],
              ),
            ),
          ),
          // Top-Left Electric Violet-Purple Glow
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.80, -1.04),
                radius: 1.32,
                colors: [
                  Color(0xFF6E2FF9),
                  Color(0xCC492FD4),
                  Color(0x552230BE),
                  Color(0x000330AC),
                ],
                stops: [0.0, 0.34, 0.68, 1.0],
              ),
            ),
          ),
          // Bottom-Center Soft Cyan-Cobalt Glow
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, 1.06),
                radius: 0.76,
                colors: [
                  Color(0xAA0366B2),
                  Color(0x000330AC),
                ],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Authentic `TimeFreezeFullScreenEffectView.prefab` using all extracted Unity frost & crystal PNGs.
class _TimeFreezeFullscreenOverlay extends StatelessWidget {
  final double opacity;

  const _TimeFreezeFullscreenOverlay({required this.opacity});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 9-Slice `Frost_Gradient.png` icy vignette frame
            const UnityNineSlice(
              sprite: 'Frost_Gradient.png',
              tint: Color(0xCC99F0FF),
            ),
            // Top & Bottom Ice Strips
            Align(
              alignment: Alignment.topCenter,
              child: Image.asset(
                'assets/images/Ice_Top.png',
                width: double.infinity,
                fit: BoxFit.fitWidth,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Image.asset(
                'assets/images/Ice_Bottom.png',
                width: double.infinity,
                fit: BoxFit.fitWidth,
              ),
            ),
            // 4 Screen Corner Ice Crystals
            Positioned(
              top: 0,
              left: 0,
              child: Image.asset(
                'assets/images/Ice_Corner_TopLeft.png',
                width: ux(context, 280),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Image.asset(
                'assets/images/Ice_Corner_TopRight.png',
                width: ux(context, 280),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              child: Image.asset(
                'assets/images/Ice_Corner_BottomLeft.png',
                width: ux(context, 280),
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Image.asset(
                'assets/images/Ice_Corner_BottomRight.png',
                width: ux(context, 280),
              ),
            ),
            // Foreground Blurry Bokeh Crystals
            Positioned(
              top: ux(context, 60),
              left: 0,
              child: Opacity(
                opacity: 0.72,
                child: Image.asset(
                  'assets/images/Ice_Blurry_TopLeft.png',
                  width: ux(context, 240),
                ),
              ),
            ),
            Positioned(
              bottom: ux(context, 80),
              right: 0,
              child: Opacity(
                opacity: 0.72,
                child: Image.asset(
                  'assets/images/Ice_Blurry_BottomRight.png',
                  width: ux(context, 240),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Authentic Bottom Power-Up Button (`Powerup_Base.png`, `PowerUp_Amount.png`,
/// `PowerUp_Plus.png`, `Icon_Padlock_Silver.png`, matching `ref_gameplay.png` 100%).
class _UnityPowerUpButton extends StatefulWidget {
  final String unlockedAsset;
  final String lockedAsset;
  final int count;
  final bool isLocked;
  final bool isReady;
  final VoidCallback onTap;

  const _UnityPowerUpButton({
    required this.unlockedAsset,
    required this.lockedAsset,
    required this.count,
    required this.isLocked,
    required this.isReady,
    required this.onTap,
  });

  @override
  State<_UnityPowerUpButton> createState() => _UnityPowerUpButtonState();
}

class _UnityPowerUpButtonState extends State<_UnityPowerUpButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final diameter = ux(context, 198);
    final badgeSz = ux(context, 70);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.91 : 1.0,
        duration: const Duration(milliseconds: 85),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Soft cyan aura behind ready unlocked power-ups
              if (!widget.isLocked && widget.isReady && widget.count > 0)
                Image.asset(
                  'assets/images/Glow_02.png',
                  width: ux(context, 236),
                  height: ux(context, 236),
                  color: const Color(0x5536E8FF),
                  colorBlendMode: BlendMode.modulate,
                ),

              // `Powerup_Base.png` circular frame
              Image.asset(
                'assets/images/Powerup_Base.png',
                width: diameter,
                height: diameter,
                fit: BoxFit.contain,
              ),

              // Power-up illustration (`PowerUp_LevelUp.png` or `*_Locked.png`)
              Opacity(
                opacity: (!widget.isLocked && !widget.isReady && widget.count > 0)
                    ? 0.58
                    : 1.0,
                child: Image.asset(
                  widget.isLocked ? widget.lockedAsset : widget.unlockedAsset,
                  width: ux(context, 152),
                  height: ux(context, 152),
                  fit: BoxFit.contain,
                ),
              ),

              // Bottom-Right Badge: Silver Padlock OR Magenta Count (`3`) OR Green Plus (`+`)
              if (widget.isLocked)
                Positioned(
                  right: ux(context, 2),
                  bottom: -ux(context, 4),
                  child: Image.asset(
                    'assets/images/Icon_Padlock_Silver.png',
                    width: ux(context, 76),
                    height: ux(context, 88),
                    fit: BoxFit.contain,
                  ),
                )
              else if (widget.count > 0)
                Positioned(
                  right: ux(context, 4),
                  bottom: 0,
                  child: SizedBox(
                    width: badgeSz,
                    height: badgeSz,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          'assets/images/PowerUp_Amount.png',
                          width: badgeSz,
                          height: badgeSz,
                        ),
                        UnitySdfText(
                          '${widget.count}',
                          unityFontSize: 44,
                          material: UnityTextMaterial.pinkBadge,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Positioned(
                  right: ux(context, 4),
                  bottom: 0,
                  child: Image.asset(
                    'assets/images/PowerUp_Plus.png',
                    width: badgeSz,
                    height: badgeSz,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Authentic Speed-Dial Circle Button (`ref_settings.png` + `PauseGameplayView.prefab`):
/// Includes `#000000(a=0.45)` dim + rotated `Element_Disabled.png` slash when toggled OFF.
class _SpeedDialUnityButton extends StatefulWidget {
  final String bgAsset;
  final String iconAsset;
  final double iconUnitySize;
  final bool isEnabled;
  final bool showDisabledSlash;
  final int delayMs;
  final VoidCallback onTap;

  const _SpeedDialUnityButton({
    required this.bgAsset,
    required this.iconAsset,
    required this.iconUnitySize,
    required this.isEnabled,
    required this.showDisabledSlash,
    required this.delayMs,
    required this.onTap,
  });

  @override
  State<_SpeedDialUnityButton> createState() => _SpeedDialUnityButtonState();
}

class _SpeedDialUnityButtonState extends State<_SpeedDialUnityButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final sz = ux(context, 134);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 210 + widget.delayMs),
      curve: Curves.easeOutBack,
      builder: (context, val, child) => Transform.scale(
        scale: val,
        child: child,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.90 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: SizedBox(
            width: sz,
            height: sz,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset(
                  widget.bgAsset,
                  width: sz,
                  height: sz,
                ),
                Image.asset(
                  widget.iconAsset,
                  width: ux(context, widget.iconUnitySize),
                  height: ux(context, widget.iconUnitySize),
                  fit: BoxFit.contain,
                ),
                if (!widget.isEnabled && widget.showDisabledSlash) ...[
                  Container(
                    width: sz * 0.92,
                    height: sz * 0.92,
                    decoration: const BoxDecoration(
                      color: Color(0x73000000),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Transform.rotate(
                    angle: -math.pi / 4,
                    child: UnityNineSlice(
                      sprite: 'Element_Disabled.png',
                      width: ux(context, 92),
                      height: ux(context, 18),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-left `T&C` and bottom-right `Privacy` buttons (`Button_Setting_Smallest.png` in `ref_settings.png`).
class _SmallestLegalButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _SmallestLegalButton({
    required this.label,
    required this.onTap,
  });

  @override
  State<_SmallestLegalButton> createState() => _SmallestLegalButtonState();
}

class _SmallestLegalButtonState extends State<_SmallestLegalButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final w = ux(context, 202);
    final h = ux(context, 76);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                'assets/images/Button_Setting_Smallest.png',
                width: w,
                height: h,
                fit: BoxFit.fill,
              ),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontSize: ux(context, 38),
                  fontWeight: FontWeight.w700,
                  fontVariations: const [FontVariation('wght', 700)],
                  color: const Color(0xFFDCE8FF),
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
