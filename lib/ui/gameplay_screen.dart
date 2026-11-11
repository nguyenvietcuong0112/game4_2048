import 'dart:async';
import 'dart:math' as math;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../game/block_order_game.dart';
import '../game/vfx_components.dart';
import '../models/level_models.dart';
import '../models/palette.dart';
import '../models/unity_curve.dart';
import '../services/ads_manager.dart';
import '../services/analytics_service.dart';
import '../services/audio_haptics_service.dart';
import '../services/player_progress_service.dart';
import 'exit_gameplay_popup.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late LevelDefinition _activeLevel;
  late final BlockOrderGame _game;

  late final AnimationController _coinBounceCtrl;
  late final AnimationController _freezeFlyCtrl;
  late final AnimationController _lowTimerPulseCtrl;

  bool _showWinOverlay = false;
  bool _showLoseOverlay = false;
  bool _loseInFailedStage = false;
  bool _losePeekingBoard = false;
  int _playOnsUsedInAttempt = 0;
  bool _showExitRestartPopup = false;
  bool? _buyPopupIsLevelUp; // null = closed, true = Level Up, false = Time Freeze
  bool _settingsOpen = false;
  int _tutorialBannerAnimEpoch = 0;
  MechanicUnlockInfo? _activeMechanicModal;

  String? _lockedToastMessage;
  Timer? _lockedToastTimer;
  double _lockedToastOpacity = 0.0;

  /// Exact shipped `game_end_flow.play_on` pricing (`price_coins = 450`, `price_increment = 150`).
  int get _currentPlayOnCost => 450 + 150 * _playOnsUsedInAttempt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeLevel =
        widget.repository.getCampaignLevel(widget.progress.currentLevel);

    _coinBounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _freezeFlyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );

    _lowTimerPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );

    _game = BlockOrderGame(
      initialLevel: _activeLevel,
      palette: widget.palette,
      visualSettings: widget.visualSettings,
      audio: widget.audio,
      onLevelWon: _handleLevelWon,
      onTimeExpired: _handleTimeExpired,
      onFirstAction: () {
        if (_activeLevel.number == 1 && !_activeLevel.isBonus) {
          AnalyticsService.logTutorial(name: 'action_1', value: 2);
        }
      },
    );

    _game.remainingSecondsNotifier.addListener(_syncLowTimerPulseTicker);
    _game.isTimeFrozenNotifier.addListener(_syncLowTimerPulseTicker);
    _syncLowTimerPulseTicker();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNewMechanicOrPowerUpUnlock(_activeLevel);
    });

    AnalyticsService.logLevelStart(level: _activeLevel.number);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockedToastTimer?.cancel();
    _game.remainingSecondsNotifier.removeListener(_syncLowTimerPulseTicker);
    _game.isTimeFrozenNotifier.removeListener(_syncLowTimerPulseTicker);
    _coinBounceCtrl.dispose();
    _freezeFlyCtrl.dispose();
    _lowTimerPulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_showWinOverlay && !_showLoseOverlay) {
        final totalPieces = _activeLevel.initialPieces.length;
        final currentPieces = _game.activePiecesCount;
        AnalyticsService.logLevelReopen(
          level: _activeLevel.number,
          totalItems: totalPieces,
          clearedItems: (totalPieces - currentPieces).clamp(0, totalPieces),
        );
      }
    }
  }

  void _syncLowTimerPulseTicker() {
    final secs = _game.remainingSecondsNotifier.value;
    final shouldPulse = !_activeLevel.timerDisabled &&
        !_game.isModalPaused &&
        !_game.isTimeFrozenNotifier.value &&
        secs > 0 &&
        secs <= 10;
    if (shouldPulse) {
      if (!_lowTimerPulseCtrl.isAnimating) {
        _lowTimerPulseCtrl.repeat(reverse: true);
      }
    } else if (_lowTimerPulseCtrl.isAnimating) {
      _lowTimerPulseCtrl.stop();
      _lowTimerPulseCtrl.value = 0.0;
    }
  }

  void _syncGamePauseState() {
    final modalPaused = _showWinOverlay ||
        _showLoseOverlay ||
        _showExitRestartPopup ||
        _buyPopupIsLevelUp != null ||
        _settingsOpen ||
        _activeMechanicModal != null;
    final canSuspendBoard = _showWinOverlay ||
        (_showLoseOverlay && !_losePeekingBoard) ||
        _showExitRestartPopup ||
        _buyPopupIsLevelUp != null ||
        _settingsOpen;
    _game.setModalPauseState(
      modalPaused: modalPaused,
      canSuspendBoard: canSuspendBoard,
    );
    _syncLowTimerPulseTicker();
  }

  void _checkNewMechanicOrPowerUpUnlock(LevelDefinition lv) {
    if (lv.isBonus) return;
    MechanicUnlockInfo? unlock;
    if (lv.number == PlayerProgressService.levelUpUnlockLevel &&
        !widget.progress
            .hasSeenMechanic(MechanicUnlockInfo.levelUpPowerUp.id)) {
      unlock = MechanicUnlockInfo.levelUpPowerUp;
    } else if (lv.number == PlayerProgressService.timeFreezeUnlockLevel &&
        !widget.progress
            .hasSeenMechanic(MechanicUnlockInfo.timeFreezePowerUp.id)) {
      unlock = MechanicUnlockInfo.timeFreezePowerUp;
    } else if (lv.hasPinned &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.pinned.id)) {
      unlock = MechanicUnlockInfo.pinned;
    } else if (lv.hasArrows &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.arrows.id)) {
      unlock = MechanicUnlockInfo.arrows;
    } else if (lv.hasDud &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.dud.id)) {
      unlock = MechanicUnlockInfo.dud;
    } else if (lv.hasIce &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.ice.id)) {
      unlock = MechanicUnlockInfo.ice;
    }

    if (unlock != null && mounted) {
      if (unlock.isPowerUp) {
        widget.progress.setFreePowerUpPending(unlock.id, true);
      }
      AnalyticsService.logMechanicUnlock(mechanicId: unlock.id, level: lv.number);
      AnalyticsService.logPopupShow(name: 'mechanic_${unlock.id}', level: lv.number);
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
    _freezeFlyCtrl.stop();
    _freezeFlyCtrl.value = 0.0;
    setState(() {
      _activeLevel = level;
      _showWinOverlay = false;
      _showLoseOverlay = false;
      _loseInFailedStage = false;
      _losePeekingBoard = false;
      _playOnsUsedInAttempt = 0;
      _showExitRestartPopup = false;
      _buyPopupIsLevelUp = null;
      _settingsOpen = false;
      _tutorialBannerAnimEpoch++;
      _activeMechanicModal = null;
      _syncGamePauseState();
    });
    _game.loadLevel(level);
    _checkNewMechanicOrPowerUpUnlock(level);
    AnalyticsService.logLevelStart(level: level.number);
    AnalyticsService.updateUserProperties(
      currentLevel: widget.progress.currentLevel,
      highestLevel: widget.progress.highestLevel,
      coins: widget.progress.coins,
    );
    if (level.number == 1 && !level.isBonus) {
      AnalyticsService.logTutorial(name: 'tut_start', value: 1);
    }
  }

  void _handleLevelWon() {
    if (!mounted) return;
    if (_activeLevel.number == 1 && !_activeLevel.isBonus) {
      AnalyticsService.logTutorial(name: 'tut_finish', value: 3);
    }
    AnalyticsService.logLevelEnd(
      level: _activeLevel.number,
      playDuration: _game.elapsedGameTime,
      success: true,
      reason: 'win',
    );
    AnalyticsService.logAfLevelAchieved(level: _activeLevel.number);
    AnalyticsService.logEarnResource(
      level: _activeLevel.number,
      type: 'currency',
      name: 'coins',
      amount: _activeLevel.coinReward.toDouble(),
      reason: 'win_level',
      balance: (widget.progress.coins + _activeLevel.coinReward).toDouble(),
    );
    AnalyticsService.logPopupShow(name: 'win', level: _activeLevel.number);
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
    AnalyticsService.logLevelEnd(
      level: _activeLevel.number,
      playDuration: _game.elapsedGameTime,
      success: false,
      reason: 'timeout',
    );
    AnalyticsService.logPopupShow(name: 'lose', level: _activeLevel.number);
    setState(() {
      _showLoseOverlay = true;
      _loseInFailedStage = false;
      _losePeekingBoard = false;
      _settingsOpen = false;
      _showExitRestartPopup = false;
      _buyPopupIsLevelUp = null;
      _syncGamePauseState();
    });
  }

  void _handleNextLevelAfterWin() {
    widget.progress.flushPendingWinCoins();
    widget.audio.playClick();
    final currentLv = _activeLevel.number;
    AdsManager.showInterEndgame(
      levelNumber: currentLv,
      onCompleted: () {
        if (!mounted) return;
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
      },
    );
  }

  void _handlePlayOnCoins() {
    final cost = _currentPlayOnCost;
    if (!widget.progress.spendCoins(cost)) {
      widget.audio.hapticBlocked();
      return;
    }
    widget.audio.playClick();
    AnalyticsService.logSpendResource(
      level: _activeLevel.number,
      type: 'currency',
      name: 'coins',
      amount: cost.toDouble(),
      reason: 'play_on',
      balance: widget.progress.coins.toDouble(),
    );
    setState(() {
      _playOnsUsedInAttempt++;
      _showLoseOverlay = false;
      _loseInFailedStage = false;
      _losePeekingBoard = false;
      _syncGamePauseState();
    });
    _game.addExtraTime(30);
  }

  void _handlePlayOnAd() {
    AdsManager.showRewardedAd(
      placement: 'lose_continue',
      levelNumber: _activeLevel.number,
      onRewardResult: (success) {
        if (success && mounted) {
          widget.audio.playClick();
          setState(() {
            _playOnsUsedInAttempt++;
            _showLoseOverlay = false;
            _loseInFailedStage = false;
            _losePeekingBoard = false;
            _syncGamePauseState();
          });
          _game.addExtraTime(30);
        }
      },
    );
  }

  void _handleEnterFailedStage() {
    widget.audio.playLevelFailed();
    widget.progress.loseLife();
    if (mounted) {
      setState(() {
        _loseInFailedStage = true;
        _losePeekingBoard = false;
        _syncGamePauseState();
      });
    }
  }

  void _handleRetryLevel() {
    final currentLv = _activeLevel.number;
    AnalyticsService.logLevelRetry(level: currentLv);
    AdsManager.showInterEndgame(
      levelNumber: currentLv,
      onCompleted: () {
        if (!mounted) return;
        widget.audio.playClick();
        widget.progress.ensureAtLeastOneLife();
        _freezeFlyCtrl.stop();
        _freezeFlyCtrl.value = 0.0;
        setState(() {
          _showLoseOverlay = false;
          _loseInFailedStage = false;
          _losePeekingBoard = false;
          _playOnsUsedInAttempt = 0;
          _showWinOverlay = false;
          _showExitRestartPopup = false;
          _settingsOpen = false;
          _tutorialBannerAnimEpoch++;
          _syncGamePauseState();
        });
        _game.restartLevel();
      },
    );
  }

  void _handleRequestReplayFromSettings() {
    widget.audio.playClick();
    AnalyticsService.logPopupShow(name: 'exit_restart', level: _activeLevel.number);
    setState(() {
      _settingsOpen = false;
      _showExitRestartPopup = true;
      _syncGamePauseState();
    });
  }

  void _handleConfirmExitRestart() {
    AnalyticsService.logLevelExit(
      level: _activeLevel.number,
      playDuration: _game.elapsedGameTime,
      reason: 'exit_restart',
    );
    widget.progress.loseLife();
    _handleRetryLevel();
  }

  bool get _isLevelUpUnlocked =>
      widget.progress.isLevelUpUnlockedForLevel(_activeLevel.number);

  bool get _isTimeFreezeUnlocked =>
      widget.progress.isTimeFreezeUnlockedForLevel(_activeLevel.number);

  void _showLockedBoosterToast(int unlockLevel) {
    widget.audio.hapticBlocked();
    _lockedToastTimer?.cancel();
    setState(() {
      _lockedToastMessage = 'Unlock at level $unlockLevel!';
      _lockedToastOpacity = 1.0;
    });
    _lockedToastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() {
          _lockedToastOpacity = 0.0;
        });
      }
    });
  }

  /// Exact `GameplayPresenter.OnClickedPowerUp(PowerUpType.LevelUp)` order:
  /// 1. Show locked toast if `!_isLevelUpUnlocked`
  /// 2. Ignore while `_game.isResolving`
  /// 3. If `!isFree && count <= 0` -> open `PowerUpBuyPopup` (`600` coins) BEFORE checking board pair!
  /// 4. Check `DoesGameStatePermitUsage` (`canLevelUpNotifier.value`)
  /// 5. Consume (`consumeFreePowerUp` or `consumeLevelUp`) & execute `triggerLevelUpPowerUp()`!
  void _handleLevelUpTap({bool fromFtue = false}) {
    if (!_isLevelUpUnlocked) {
      _showLockedBoosterToast(PlayerProgressService.levelUpUnlockLevel);
      return;
    }
    if (_game.isResolving) return;

    final isFree = fromFtue ||
        widget.progress
            .isFreePowerUpPending(MechanicUnlockInfo.levelUpPowerUp.id);
    if (!isFree && widget.progress.levelUpCount <= 0) {
      widget.audio.playClick();
      AnalyticsService.logPopupShow(name: 'buy_level_up', level: _activeLevel.number);
      setState(() {
        _buyPopupIsLevelUp = true;
        _syncGamePauseState();
      });
      return;
    }

    if (!_game.canLevelUpNotifier.value) {
      widget.audio.hapticBlocked();
      return;
    }

    widget.audio.playPowerUpSelect();
    if (_game.triggerLevelUpPowerUp()) {
      if (isFree) {
        widget.progress.consumeFreePowerUp(MechanicUnlockInfo.levelUpPowerUp.id);
      } else {
        widget.progress.consumeLevelUp();
      }
      AnalyticsService.logSpendResource(
        level: _activeLevel.number,
        type: 'booster',
        name: 'level_up',
        amount: 1,
        reason: 'gameplay',
        balance: widget.progress.levelUpCount.toDouble(),
      );
    }
  }

  /// Exact `GameplayPresenter.OnClickedPowerUp(PowerUpType.TimeFreeze)` + `TimeFreezeHandler.UseAsync`:
  /// 1. Show locked toast if `!_isTimeFreezeUnlocked`
  /// 2. Ignore while `_game.isResolving`
  /// 3. If `!isFree && count <= 0` -> open `PowerUpBuyPopup` (`450` coins) BEFORE checking timer started!
  /// 4. Check `DoesGameStatePermitUsage` (`_game.canUseTimeFreeze`, or `!timerDisabled` during FTUE free trial)
  /// 5. Consume (`consumeFreePowerUp` or `consumeTimeFreeze`), fly clock to top timer (`PlayTimeFreezeIntroAsync`),
  ///    and engage `20s` freeze (`StartFreeze(20)`) upon impact!
  void _handleTimeFreezeTap({bool fromFtue = false}) {
    if (!_isTimeFreezeUnlocked) {
      _showLockedBoosterToast(PlayerProgressService.timeFreezeUnlockLevel);
      return;
    }
    if (_game.isResolving) return;

    final isFree = fromFtue ||
        widget.progress
            .isFreePowerUpPending(MechanicUnlockInfo.timeFreezePowerUp.id);
    if (!isFree && widget.progress.timeFreezeCount <= 0) {
      widget.audio.playClick();
      AnalyticsService.logPopupShow(name: 'buy_time_freeze', level: _activeLevel.number);
      setState(() {
        _buyPopupIsLevelUp = false;
        _syncGamePauseState();
      });
      return;
    }

    final permitted = isFree
        ? (!_activeLevel.timerDisabled &&
            !_game.isTimeFrozen &&
            !_game.isTimeFreezeIntroInFlight)
        : _game.canUseTimeFreeze;
    if (!permitted) {
      widget.audio.hapticBlocked();
      return;
    }

    if (isFree) {
      widget.progress
          .consumeFreePowerUp(MechanicUnlockInfo.timeFreezePowerUp.id);
    } else {
      if (!widget.progress.consumeTimeFreeze()) return;
    }
    AnalyticsService.logSpendResource(
      level: _activeLevel.number,
      type: 'booster',
      name: 'time_freeze',
      amount: 1,
      reason: 'gameplay',
      balance: widget.progress.timeFreezeCount.toDouble(),
    );

    widget.audio.playPowerUpSelect();
    _runTimeFreezeIntroAndEngage(allowBeforeTimerStarted: isFree);
  }

  void _runTimeFreezeIntroAndEngage({required bool allowBeforeTimerStarted}) {
    _game.isTimeFreezeIntroInFlight = true;
    final targetLevelNumber = _activeLevel.number;
    bool freezeTriggered = false;

    void onTick() {
      if (!mounted || _activeLevel.number != targetLevelNumber) return;
      if (!freezeTriggered && _freezeFlyCtrl.value >= 0.66) {
        freezeTriggered = true;
        _game.isTimeFreezeIntroInFlight = false;
        _game.triggerTimeFreezePowerUp(
          allowBeforeTimerStarted: allowBeforeTimerStarted,
        );
      }
    }

    _freezeFlyCtrl.addListener(onTick);
    _freezeFlyCtrl.forward(from: 0.0).whenComplete(() {
      _freezeFlyCtrl.removeListener(onTick);
      if (!mounted || _activeLevel.number != targetLevelNumber) return;
      _game.isTimeFreezeIntroInFlight = false;
      if (!freezeTriggered) {
        _game.triggerTimeFreezePowerUp(
          allowBeforeTimerStarted: allowBeforeTimerStarted,
        );
      }
    });
  }

  void _handleActivatePowerUpFromFtue(MechanicUnlockInfo modal) {
    final isLvUp = modal.isLevelUpPowerUp;
    setState(() {
      _activeMechanicModal = null;
      _syncGamePauseState();
    });
    if (isLvUp) {
      _handleLevelUpTap(fromFtue: true);
    } else {
      _handleTimeFreezeTap(fromFtue: true);
    }
  }

  String _formatTimer(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _toggleSettingsPopup() {
    widget.audio.playClick();
    final willOpen = !_settingsOpen;
    if (willOpen) {
      AnalyticsService.logPopupShow(
        name: 'settings',
        level: _activeLevel.number,
      );
    }
    setState(() {
      _settingsOpen = willOpen;
      _syncGamePauseState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tutorialHint = !_activeLevel.isBonus
        ? widget.repository.tutorialHints[_activeLevel.number]
        : null;
    final safePadding = MediaQuery.paddingOf(context);
    _game.updateSafeAreaInsets(
      top: safePadding.top,
      bottom: safePadding.bottom,
    );

    final hideBaseCoins = _showWinOverlay ||
        (_showLoseOverlay && !_loseInFailedStage) ||
        _buyPopupIsLevelUp != null;

    return Scaffold(
      backgroundColor: const Color(0xFF47279B),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Redesigned Purple Gameplay Background (`Background_Core.png`)
          RepaintBoundary(
            child: Image.asset(
              'assets/images/Background_Core.png',
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),

          // 2. Flame 2.5D Board & Block Puzzle Canvas (isolated in dedicated GPU layer!)
          RepaintBoundary(child: GameWidget<BlockOrderGame>(game: _game)),

          // 3. Authentic `TimeFreezeFullScreenEffectView.prefab` Frost & Corner Crystals
          ValueListenableBuilder<double>(
            valueListenable: _game.timeFreezeNotifier,
            child: const RepaintBoundary(child: _TimeFreezeFrostStaticLayer()),
            builder: (context, freezeLeft, staticFrost) {
              if (freezeLeft <= 0.05) return const SizedBox.shrink();
              if (freezeLeft >= 2.5) {
                return IgnorePointer(child: staticFrost);
              }
              final alpha = (freezeLeft / 2.5).clamp(0.0, 1.0);
              return IgnorePointer(
                child: Opacity(
                  opacity: alpha,
                  child: staticFrost,
                ),
              );
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

          // 5. Top HUD (`CoinsWidget` left, `Frame_Level.png` center, `Settings` right, + `TimerGameplayView` below)
          SafeArea(
            child: RepaintBoundary(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: ux(context, 144),
                    child: Stack(
                      alignment: Alignment.topCenter,
                      clipBehavior: Clip.none,
                      children: [
                        // Top-Left `CoinsWidget` (hidden here when elevated above `WinOverlay`, `PlayOnPopupView`, or `PowerUpBuyPopup`)
                        Positioned(
                          left: ux(context, UnityCoinsWidget.hudLeftUnity),
                          top: ux(context, UnityCoinsWidget.hudTopUnity),
                          child: Opacity(
                            opacity: hideBaseCoins ? 0.0 : 1.0,
                            child: IgnorePointer(
                              ignoring: hideBaseCoins,
                              child: _buildCoinsWidget(context),
                            ),
                          ),
                        ),

                        // Top-Center `Frame_Level.png` (`Level 15`)
                        Positioned(
                          top: ux(context, 10),
                          child: IgnorePointer(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: ux(context, 287),
                              ),
                              child: UnityNineSlice(
                                sprite: 'Frame_Level.png',
                                height: ux(context, 125),
                                padding: EdgeInsets.fromLTRB(
                                  ux(context, 34),
                                  ux(context, 6),
                                  ux(context, 34),
                                  ux(context, 12),
                                ),
                                child: UnitySdfText(
                                  _activeLevel.title,
                                  unityFontSize: 52,
                                  material: UnityTextMaterial.levelCounter,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Top-Right Settings Circle Button (`Button_Circle_Blue.png` + `Icon_Settings.png`)
                        Positioned(
                          right: ux(context, 42),
                          top: ux(context, 6),
                          child: UnitySpriteButton(
                            onTap: _toggleSettingsPopup,
                            child: SizedBox(
                              width: ux(context, 133),
                              height: ux(context, 133),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Image.asset(
                                    'assets/images/Button_Circle_Blue.png',
                                    width: ux(context, 133),
                                    height: ux(context, 133),
                                    fit: BoxFit.contain,
                                  ),
                                  Image.asset(
                                    'assets/images/Icon_Settings.png',
                                    width: ux(context, 76),
                                    height: ux(context, 76),
                                    fit: BoxFit.contain,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Top-Center `TimerGameplayView` (hides immediately on level complete so the Magic Sand Jar appears without overlap!)
                  if (!_activeLevel.timerDisabled) ...[
                    SizedBox(height: ux(context, 8)),
                    ValueListenableBuilder<bool>(
                      valueListenable: _game.isWinSequenceActiveNotifier,
                      builder: (context, winActive, child) {
                        return AnimatedScale(
                          scale: winActive ? 0.65 : 1.0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeInBack,
                          child: AnimatedOpacity(
                            opacity: winActive ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeOut,
                            child: IgnorePointer(
                              ignoring: winActive,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: _buildTimerGameplayView(context),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // 5b. Top-Anchored `TutorialText` (Levels 1-3).
          // Stays visible during gameplay on Levels 1-3 and fades out when win sequence starts so the Jar appears cleanly!
          if (tutorialHint != null)
            SafeArea(
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: ux(context, 162),
                      left: ux(context, 35.26),
                      right: ux(context, 35.26),
                    ),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _game.isWinSequenceActiveNotifier,
                      builder: (context, winActive, child) {
                        return AnimatedOpacity(
                          opacity: winActive ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          child: child,
                        );
                      },
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey(
                          'tut_text_${_activeLevel.number}_$_tutorialBannerAnimEpoch',
                        ),
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 520),
                        curve:
                            const Interval(0.30, 1.0, curve: Curves.easeOutBack),
                        builder: (context, anim, child) => Transform.scale(
                          scale: 0.72 + 0.28 * anim,
                          child: Opacity(
                            opacity: anim.clamp(0.0, 1.0),
                            child: child,
                          ),
                        ),
                        child: SizedBox(
                          height: ux(context, 132),
                          child: Center(
                            child: UnitySdfText(
                              tutorialHint,
                              unityFontSize: 47.3,
                              material: UnityTextMaterial.tutorialText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 6. Bottom `Frame_Footer.png` Shelf + Straddling Circular `PowerUps` (`Play_Scene.png`)
          Align(
            alignment: Alignment.bottomCenter,
            child: RepaintBoundary(
              child: SizedBox(
                width: double.infinity,
                height: safePadding.bottom +
                    ux(
                      context,
                      UnityPowerUpHudButton.bottomOffsetUnity +
                          UnityPowerUpHudButton.scaledUnitySize,
                    ),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.none,
                  children: [
                    // Full-width purple footer shelf with golden top trim (`Frame_Footer.png`)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: safePadding.bottom +
                          ux(
                            context,
                            UnityPowerUpHudButton.footerTopLineUnity,
                          ),
                      child: const IgnorePointer(
                        child: UnityNineSlice(
                          sprite: 'Frame_Footer.png',
                        ),
                      ),
                    ),

                    // Left Power-Up (`LevelUp` at `X = -135` Unity px)
                    Positioned(
                      bottom: safePadding.bottom +
                          ux(context, UnityPowerUpHudButton.bottomOffsetUnity),
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          widget.progress,
                          _game.canLevelUpNotifier,
                        ]),
                        builder: (context, _) {
                          final isFree = widget.progress.isFreePowerUpPending(
                            MechanicUnlockInfo.levelUpPowerUp.id,
                          );
                          return Transform.translate(
                            offset: Offset(
                              -ux(
                                context,
                                UnityPowerUpHudButton.horizontalOffsetUnity,
                              ),
                              0,
                            ),
                            child: UnityPowerUpHudButton(
                              key: const ValueKey('hud_level_up_btn'),
                              isLevelUp: true,
                              isUnlocked: _isLevelUpUnlocked,
                              isFree: isFree,
                              count: widget.progress.levelUpCount,
                              isActionable: _game.canLevelUpNotifier.value,
                              onTap: _handleLevelUpTap,
                            ),
                          );
                        },
                      ),
                    ),

                    // Right Power-Up (`TimeFreeze` at `X = +135` Unity px)
                    Positioned(
                      bottom: safePadding.bottom +
                          ux(context, UnityPowerUpHudButton.bottomOffsetUnity),
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          widget.progress,
                          _game.isTimeFrozenNotifier,
                          _game.isTimerStartedNotifier,
                        ]),
                        builder: (context, _) {
                          final isFree = widget.progress.isFreePowerUpPending(
                            MechanicUnlockInfo.timeFreezePowerUp.id,
                          );
                          return Transform.translate(
                            offset: Offset(
                              ux(
                                context,
                                UnityPowerUpHudButton.horizontalOffsetUnity,
                              ),
                              0,
                            ),
                            child: UnityPowerUpHudButton(
                              key: const ValueKey('hud_time_freeze_btn'),
                              isLevelUp: false,
                              isUnlocked: _isTimeFreezeUnlocked,
                              isFree: isFree,
                              count: widget.progress.timeFreezeCount,
                              isActionable: _game.canUseTimeFreeze,
                              onTap: _handleTimeFreezeTap,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 7. Flying `PowerUp_TimeFreeze.png` Clock-to-Timer Burst Animation (`PlayTimeFreezeIntroAsync`)
          AnimatedBuilder(
            animation: _freezeFlyCtrl,
            builder: (context, _) {
              if (!_freezeFlyCtrl.isAnimating && _freezeFlyCtrl.value == 0.0) {
                return const SizedBox.shrink();
              }
              return _buildTimeFreezeFlightFx(context, _freezeFlyCtrl.value);
            },
          ),

          // 8. Redesigned Settings Modal Popup (`PopUp_Setting.png`)
          if (_settingsOpen) _buildSettingsPopupOverlay(context),

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

          // 10. `PowerUpBuyView.prefab` (`600` for LevelUp `x3`, `450` for TimeFreeze `x3`, `Watch` Ad for `x1`)
          if (_buyPopupIsLevelUp != null)
            ListenableBuilder(
              listenable: widget.progress,
              builder: (context, _) {
                final isLvUp = _buyPopupIsLevelUp!;
                final packCost = isLvUp
                    ? PlayerProgressService.levelUpPackCost
                    : PlayerProgressService.timeFreezePackCost;
                return PowerUpBuyPopup(
                  isLevelUp: isLvUp,
                  playerCoins: widget.progress.coins,
                  packCost: packCost,
                  onBuyPack: () {
                    if (widget.progress.buyPowerUpPack(
                      isLevelUp: isLvUp,
                      cost: packCost,
                      count: 3,
                    )) {
                      widget.audio.playCoinCollect();
                      AnalyticsService.logSpendResource(
                        level: _activeLevel.number,
                        type: 'currency',
                        name: 'coins',
                        amount: packCost.toDouble(),
                        reason: 'buy_booster_pack',
                        balance: widget.progress.coins.toDouble(),
                      );
                      AnalyticsService.logEarnResource(
                        level: _activeLevel.number,
                        type: 'booster',
                        name: isLvUp ? 'level_up' : 'time_freeze',
                        amount: 3,
                        reason: 'buy_pack',
                        balance: (isLvUp
                                ? widget.progress.levelUpCount
                                : widget.progress.timeFreezeCount)
                            .toDouble(),
                      );
                      setState(() {
                        _buyPopupIsLevelUp = null;
                        _syncGamePauseState();
                      });
                    } else {
                      widget.audio.hapticBlocked();
                    }
                  },
                  onWatchAd: () {
                    AdsManager.showRewardedAd(
                      placement: isLvUp ? 'booster_levelup' : 'booster_timefreeze',
                      levelNumber: _activeLevel.number,
                      onRewardResult: (success) {
                        if (success && mounted) {
                          widget.audio.playCoinCollect();
                          widget.progress.grantFreePowerUp(
                            isLevelUp: isLvUp,
                            count: 1,
                          );
                          AnalyticsService.logEarnResource(
                            level: _activeLevel.number,
                            type: 'booster',
                            name: isLvUp ? 'level_up' : 'time_freeze',
                            amount: 1,
                            reason: 'rewarded_ad',
                            balance: (isLvUp
                                    ? widget.progress.levelUpCount
                                    : widget.progress.timeFreezeCount)
                                .toDouble(),
                          );
                          setState(() {
                            _buyPopupIsLevelUp = null;
                            _syncGamePauseState();
                          });
                        }
                      },
                    );
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

          // 11. `MechanicFTUE.prefab` (1-step) & `PowerUpFTUEView.prefab` (2-step -> immediate free execution!)
          if (_activeMechanicModal != null)
            if (_activeMechanicModal!.isPowerUp)
              PowerUpFtueOverlay(
                key: ValueKey('ftue_${_activeMechanicModal!.id}'),
                info: _activeMechanicModal!,
                onContinueStep1: widget.audio.playClick,
                onActivateFreePowerUp: () =>
                    _handleActivatePowerUpFromFtue(_activeMechanicModal!),
              )
            else
              MechanicUnlockDialog(
                key: ValueKey('ftue_${_activeMechanicModal!.id}'),
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
              timeFormatted: _game.elapsedTimeFormatted,
              movesCount: _game.movesCount,
              comboCount: _game.highestCombo,
              onStage2Shown: widget.audio.playWinAmazing,
              onCoinChunkArrived: (chunk) {
                widget.progress.collectPendingWinCoinChunk(chunk);
                widget.audio.playCoinCollect();
                _coinBounceCtrl.forward(from: 0.0);
              },
              onNextLevel: _handleNextLevelAfterWin,
            ),

          // 12b. Step 4 Fullscreen Radial Light Wave Bloom (`Hiệu ứng ánh sáng lan ra toàn màn hình, hiện pop up next level`)
          ValueListenableBuilder<double>(
            valueListenable: _game.winScreenFlashNotifier,
            builder: (context, flashIntensity, _) {
              if (flashIntensity <= 0.01) return const SizedBox.shrink();
              final tint = _game.winScreenFlashColorNotifier.value;
              final coreAlpha = (flashIntensity * 0.78).clamp(0.0, 1.0);
              final midAlpha = (flashIntensity * 0.52).clamp(0.0, 1.0);
              final outerAlpha = (flashIntensity * 0.28).clamp(0.0, 1.0);
              return IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.0, -0.36),
                      radius: 1.25,
                      colors: [
                        Colors.white.withValues(alpha: coreAlpha),
                        Color.lerp(tint, Colors.white, 0.55)!
                            .withValues(alpha: midAlpha),
                        tint.withValues(alpha: outerAlpha),
                      ],
                      stops: const [0.0, 0.48, 1.0],
                    ),
                  ),
                ),
              );
            },
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
                  playOnCost: _currentPlayOnCost,
                  extraSeconds: 30,
                  onPlayOnCoins: _handlePlayOnCoins,
                  onPlayOnAd: _handlePlayOnAd,
                  onEnterFailedStage: _handleEnterFailedStage,
                  onPeekingChanged: (peeking) {
                    if (mounted && _losePeekingBoard != peeking) {
                      setState(() {
                        _losePeekingBoard = peeking;
                        _syncGamePauseState();
                      });
                    }
                  },
                  onRetry: _handleRetryLevel,
                );
              },
            ),

          // 14. Elevated Top-Left `CoinsWidget` (`overrideSorting: true` during `WinGameplayView` & `PlayOnPopupView`)
          if (_showWinOverlay || (_showLoseOverlay && !_loseInFailedStage))
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: ux(context, UnityCoinsWidget.hudLeftUnity),
                    top: ux(context, UnityCoinsWidget.hudTopUnity),
                  ),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    opacity: (_showLoseOverlay && _losePeekingBoard) ? 0.0 : 1.0,
                    child: IgnorePointer(
                      ignoring: _showLoseOverlay && _losePeekingBoard,
                      child: _buildCoinsWidget(context),
                    ),
                  ),
                ),
              ),
            ),

          // 15. Floating "Unlock at level X!" toast banner matching media_1794198573830.png
          if (_lockedToastMessage != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _lockedToastOpacity,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    onEnd: () {
                      if (_lockedToastOpacity == 0.0 && mounted) {
                        setState(() {
                          _lockedToastMessage = null;
                        });
                      }
                    },
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: ux(context, 80)),
                      padding: EdgeInsets.symmetric(
                        horizontal: ux(context, 48),
                        vertical: ux(context, 26),
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xB3000000),
                        borderRadius: BorderRadius.circular(ux(context, 34)),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: ux(context, 1.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.40),
                            blurRadius: ux(context, 20),
                            offset: Offset(0, ux(context, 8)),
                          ),
                        ],
                      ),
                      child: Text(
                        _lockedToastMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontSize: ux(context, 46),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                          shadows: const [
                            Shadow(
                              offset: Offset(0, 1.8),
                              blurRadius: 3.5,
                              color: Color(0xBF000000),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Redesigned `CoinsWidget` (`WidgetBase.png` + `Icon_Coin.png` + `PowerUp_Plus.png`).
  Widget _buildCoinsWidget(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.progress, _coinBounceCtrl]),
      builder: (context, _) {
        final t = _coinBounceCtrl.value;
        final pulse = 1.0 + 0.14 * math.sin(t * math.pi);
        return UnityCoinsWidget(
          coins: widget.progress.coins,
          scale: pulse,
        );
      },
    );
  }

  /// Authentic `TimerGameplayView.prefab`:
  /// - Normal: `Shadow.png` + `Circle_01.png` tinted `#24115C` + `Icon_Timer.png` + `3:00`
  /// - Urgent (`<= 10s`): pulsing `Widget_Timer_Set.png` + `Icon_Timer.png` + `0:09`
  /// - Frozen: `Pill_03.png` + `Snow.png` snow cap + `PowerUp_TimeFreeze.png` + `TimeFreeze_TimerBar.png`
  Widget _buildTimerGameplayView(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _game.isTimeFrozenNotifier,
      builder: (context, isFrozen, _) {
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
                        tint: const Color(0x55080224),
                      ),
                    ),
                    UnityNineSlice(
                      sprite: 'Circle_01.png',
                      width: pillW,
                      height: pillH,
                      tint: const Color(0xFF24115C),
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
                          tint: const Color(0xFF191254),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(ux(context, 12)),
                          child: ValueListenableBuilder<double>(
                            valueListenable: _game.timeFreezeNotifier,
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
                            builder: (context, freezeLeft, barChild) {
                              return Align(
                                alignment: Alignment.centerLeft,
                                widthFactor: (freezeLeft /
                                        BlockOrderGame.maxTimeFreezeSeconds)
                                    .clamp(0.0, 1.0),
                                child: barChild,
                              );
                            },
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
      padding: EdgeInsets.symmetric(horizontal: ux(context, 18)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
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
            SizedBox(width: ux(context, 16)),
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
      ),
    );
  }

  /// Flying `PowerUp_TimeFreeze.png` clock from bottom button (`X = +135`) to top-center timer
  /// `ClockTarget` (`X = -86`) + cyan `Explosion_Halo.png` burst upon impact (`t >= 0.66`).
  Widget _buildTimeFreezeFlightFx(BuildContext context, double t) {
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final start = Offset(
      screen.width * 0.5 +
          ux(context, UnityPowerUpHudButton.horizontalOffsetUnity),
      screen.height -
          pad.bottom -
          ux(
            context,
            UnityPowerUpHudButton.bottomOffsetUnity +
                UnityPowerUpHudButton.scaledUnitySize * 0.5,
          ),
    );
    final end = Offset(
      screen.width * 0.5 - ux(context, 86),
      pad.top + ux(context, 205),
    );

    final flyT = (t / 0.66).clamp(0.0, 1.0);
    final haloT = ((t - 0.60) / 0.40).clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(flyT);

    final ctrl = Offset(screen.width * 0.72, screen.height * 0.48);
    final om = 1.0 - eased;
    final px =
        om * om * start.dx + 2 * om * eased * ctrl.dx + eased * eased * end.dx;
    final py =
        om * om * start.dy + 2 * om * eased * ctrl.dy + eased * eased * end.dy;

    return IgnorePointer(
      child: Stack(
        children: [
          if (flyT < 1.0)
            Positioned(
              left: px - ux(context, 84),
              top: py - ux(context, 84),
              child: Transform.scale(
                scale: 1.15 - 0.35 * eased,
                child: Image.asset(
                  'assets/images/PowerUp_TimeFreeze.png',
                  width: ux(context, 168),
                  height: ux(context, 168),
                ),
              ),
            ),
          if (haloT > 0.0 && haloT < 1.0)
            Positioned(
              left: end.dx - ux(context, 190),
              top: end.dy - ux(context, 190),
              child: Transform.scale(
                scale: 0.35 + 1.20 * haloT,
                child: Opacity(
                  opacity: (1.0 - haloT).clamp(0.0, 1.0),
                  child: ColorFiltered(
                    colorFilter: UnityChannelMaskFilters.redChannelTint(
                      const Color(0xFF7AF5FF),
                    ),
                    child: Image.asset(
                      'assets/images/Explosion_Halo.png',
                      width: ux(context, 380),
                      height: ux(context, 380),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _closeSettingsPopup() {
    widget.audio.playClick();
    setState(() {
      _settingsOpen = false;
      _syncGamePauseState();
    });
  }

  /// Centered Settings Modal Popup matching `PopUp_Setting.png` (`884x969` Unity px):
  /// - `Background_Popup.png` (`884x931`) + `Frame_Popup_Title.png` (`558x143`, `"Setting"`)
  /// - Top-right `Button_Close.png` (`139x139`)
  /// - `Panel_Popup.png` (`784x676`) with 3 circle toggles (`Sound`, `Music`, `Vibration`),
  ///   `"Restart"` `Button_CTA.png` (`499x221`), and `'v.1.0.6'` version label.
  Widget _buildSettingsPopupOverlay(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _closeSettingsPopup,
      child: Container(
        color: const Color(0xCC0D0622),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: ux(context, 24)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.88, end: 1.0),
                  duration: const Duration(milliseconds: 210),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) => Transform.scale(
                    scale: scale,
                    child: child,
                  ),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: SizedBox(
                      width: ux(context, 896),
                      height: ux(context, 969),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 1. Gold-Rimmed Blue Popup Shell (`Background_Popup.png`, `884x931`)
                          Positioned(
                            left: 0,
                            top: ux(context, 38),
                            width: ux(context, 884),
                            height: ux(context, 931),
                            child: const UnityNineSlice(
                              sprite: 'Background_Popup.png',
                            ),
                          ),

                          // 2. Cream Inner Content Well (`Panel_Popup.png`, `784x676`)
                          Positioned(
                            left: ux(context, 50),
                            top: ux(context, 184),
                            width: ux(context, 784),
                            height: ux(context, 676),
                            child: UnityNineSlice(
                              sprite: 'Panel_Popup.png',
                              child: ListenableBuilder(
                                listenable: widget.audio,
                                builder: (context, _) {
                                  return Stack(
                                    alignment: Alignment.topCenter,
                                    children: [
                                      // Row of 3 Circle Toggle Buttons (`Sound`, `Music`, `Vibration`)
                                      Positioned(
                                        top: ux(context, 48),
                                        left: 0,
                                        right: 0,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            _SettingsCircleToggleButton(
                                              isEnabled:
                                                  widget.audio.soundEnabled,
                                              enabledIconAsset:
                                                  'assets/images/Icon_Sounds.png',
                                              disabledIconAsset:
                                                  'assets/images/Icon_Sounds_Off.png',
                                              iconUnityWidth: 99,
                                              iconUnityHeight: 85,
                                              onTap: widget.audio.toggleSound,
                                            ),
                                            SizedBox(width: ux(context, 24)),
                                            _SettingsCircleToggleButton(
                                              isEnabled:
                                                  widget.audio.musicEnabled,
                                              enabledIconAsset:
                                                  'assets/images/Icon_Music.png',
                                              disabledIconAsset:
                                                  'assets/images/Icon_Music_Off.png',
                                              iconUnityWidth: 82,
                                              iconUnityHeight: 97,
                                              onTap: widget.audio.toggleMusic,
                                            ),
                                            SizedBox(width: ux(context, 24)),
                                            _SettingsCircleToggleButton(
                                              isEnabled:
                                                  widget.audio.hapticsEnabled,
                                              enabledIconAsset:
                                                  'assets/images/Icon_Haptics.png',
                                              disabledIconAsset:
                                                  'assets/images/Icon_Haptics_Off.png',
                                              iconUnityWidth: 83,
                                              iconUnityHeight: 108,
                                              onTap: widget.audio.toggleHaptics,
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Centered `"Restart"` Pill Button (`Button_CTA.png`, `499x221`)
                                      Positioned(
                                        top: ux(context, 332),
                                        child: UnityCtaButton(
                                          label: 'Restart',
                                          unityWidth: 499,
                                          unityHeight: 221,
                                          unityFontSize: 68,
                                          onTap:
                                              _handleRequestReplayFromSettings,
                                        ),
                                      ),

                                      // Bottom Version Text (`v.1.0.6`)
                                      Positioned(
                                        bottom: ux(context, 28),
                                        child: IgnorePointer(
                                          child: Text(
                                            'v.1.0.6',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontFamily: 'Baloo2',
                                              fontSize: ux(context, 42),
                                              fontWeight: FontWeight.w800,
                                              fontVariations: const [
                                                FontVariation('wght', 800),
                                              ],
                                              color: const Color(0xFF9C5B40),
                                              height: 1.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),

                          // 3. Top Header Ribbon (`Frame_Popup_Title.png`, `558x143`, `"Setting"`)
                          Positioned(
                            left: ux(context, (884 - 558) * 0.5),
                            top: 0,
                            width: ux(context, 558),
                            height: ux(context, 143),
                            child: IgnorePointer(
                              child: UnityNineSlice(
                                sprite: 'Frame_Popup_Title.png',
                                padding: EdgeInsets.fromLTRB(
                                  ux(context, 42),
                                  ux(context, 8),
                                  ux(context, 42),
                                  ux(context, 16),
                                ),
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: UnitySdfText(
                                    'Setting',
                                    unityFontSize: 70,
                                    material: UnityTextMaterial.popupTitle,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 4. Top-Right Red-Gold Close Button (`Button_Close.png`, `139x139`)
                          Positioned(
                            right: 0,
                            top: ux(context, 8),
                            width: ux(context, 139),
                            height: ux(context, 139),
                            child: UnitySpriteButton(
                              asset: 'Button_Close.png',
                              unitySize: 139,
                              onTap: _closeSettingsPopup,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Authentic `TimeFreezeFullScreenEffectView.prefab` using all extracted Unity frost & crystal PNGs.
/// Cached inside a `const RepaintBoundary` so the 9-image stack is rasterized once to a GPU texture.
class _TimeFreezeFrostStaticLayer extends StatelessWidget {
  const _TimeFreezeFrostStaticLayer();

  @override
  Widget build(BuildContext context) {
    return Stack(
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
        // Foreground Blurry Bokeh Crystals (shader-modulated alpha without Opacity saveLayer)
        Positioned(
          top: ux(context, 60),
          left: 0,
          child: Image.asset(
            'assets/images/Ice_Blurry_TopLeft.png',
            width: ux(context, 240),
            opacity: const AlwaysStoppedAnimation<double>(0.72),
          ),
        ),
        Positioned(
          bottom: ux(context, 80),
          right: 0,
          child: Image.asset(
            'assets/images/Ice_Blurry_BottomRight.png',
            width: ux(context, 240),
            opacity: const AlwaysStoppedAnimation<double>(0.72),
          ),
        ),
      ],
    );
  }
}

/// Circular Sound / Music / Vibration Toggle Button inside `PopUp_Setting.png`:
/// - ON: `Button_Circle_Blue.png` + `Icon_*.png`
/// - OFF: `Button_Circle_Gray.png` + `Icon_*_Off.png`
class _SettingsCircleToggleButton extends StatefulWidget {
  final bool isEnabled;
  final String enabledIconAsset;
  final String disabledIconAsset;
  final double iconUnityWidth;
  final double iconUnityHeight;
  final VoidCallback onTap;

  const _SettingsCircleToggleButton({
    required this.isEnabled,
    required this.enabledIconAsset,
    required this.disabledIconAsset,
    required this.iconUnityWidth,
    required this.iconUnityHeight,
    required this.onTap,
  });

  @override
  State<_SettingsCircleToggleButton> createState() =>
      _SettingsCircleToggleButtonState();
}

class _SettingsCircleToggleButtonState
    extends State<_SettingsCircleToggleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final w = ux(context, 212);
    final h = ux(context, 213);

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
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                widget.isEnabled
                    ? 'assets/images/Button_Circle_Blue.png'
                    : 'assets/images/Button_Circle_Gray.png',
                width: w,
                height: h,
                fit: BoxFit.contain,
              ),
              Image.asset(
                widget.isEnabled
                    ? widget.enabledIconAsset
                    : widget.disabledIconAsset,
                width: ux(context, widget.iconUnityWidth),
                height: ux(context, widget.iconUnityHeight),
                fit: BoxFit.contain,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
