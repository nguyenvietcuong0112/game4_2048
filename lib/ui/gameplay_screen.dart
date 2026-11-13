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
import '../services/remote_config_service.dart';
import 'cheat_panel_overlay.dart';
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
  late final Animation<double> _lowTimerVignetteOpacity;

  bool _showWinOverlay = false;
  bool _showLoseOverlay = false;
  bool _loseInFailedStage = false;
  bool _losePeekingBoard = false;
  int _playOnsUsedInAttempt = 0;
  bool _showExitRestartPopup = false;
  bool? _buyPopupIsLevelUp; // null = closed, true = Level Up, false = Time Freeze
  bool _settingsOpen = false;
  bool _cheatOpen = false;
  bool _hideCheatHudButton = false;
  int _lastDisplayComboCount = 1;
  MechanicUnlockInfo? _activeMechanicModal;

  String? _lockedToastMessage;
  Timer? _lockedToastTimer;
  double _lockedToastOpacity = 0.0;
  int _lastLoggedTutMergeStep = 0;
  VaseStepAdvanceResult? _activeVaseAdvanceResult;

  bool _shouldTrackFtueForLevel(LevelDefinition level) =>
      !level.isBonus && level.number == 1 && !widget.progress.isFtueCompleted;

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
      duration: const Duration(milliseconds: 500),
    );
    _lowTimerVignetteOpacity = Tween<double>(
      begin: 0.16,
      end: 0.78,
    ).animate(
      CurvedAnimation(
        parent: _lowTimerPulseCtrl,
        curve: Curves.easeInOutSine,
      ),
    );

    _game = BlockOrderGame(
      initialLevel: _activeLevel,
      palette: widget.palette,
      visualSettings: widget.visualSettings,
      audio: widget.audio,
      onLevelWon: _handleLevelWon,
      onTimeExpired: _handleTimeExpired,
      onTutorialMergeStep: (step) {
        if (_shouldTrackFtueForLevel(_activeLevel) &&
            step > _lastLoggedTutMergeStep) {
          _lastLoggedTutMergeStep = step;
          AnalyticsService.logTutorial(
            name: 'action_$step',
            value: 3 + step,
          );
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
    if (_shouldTrackFtueForLevel(_activeLevel)) {
      _lastLoggedTutMergeStep = 0;
      AnalyticsService.logTutorial(name: 'tut_start', value: 3);
    }
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
        _cheatOpen ||
        _activeMechanicModal != null;
    final canSuspendBoard = _showWinOverlay ||
        (_showLoseOverlay && !_losePeekingBoard) ||
        _showExitRestartPopup ||
        _buyPopupIsLevelUp != null ||
        _settingsOpen ||
        _cheatOpen;
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
    FocusManager.instance.primaryFocus?.unfocus();
    if (!level.isBonus) {
      widget.progress.setCurrentLevel(level.number);
    } else {
      widget.progress.flushPendingWinCoins();
    }
    _freezeFlyCtrl.stop();
    _freezeFlyCtrl.value = 0.0;
    setState(() {
      _activeLevel = level;
      _activeVaseAdvanceResult = null;
      _showWinOverlay = false;
      _showLoseOverlay = false;
      _loseInFailedStage = false;
      _losePeekingBoard = false;
      _playOnsUsedInAttempt = 0;
      _showExitRestartPopup = false;
      _buyPopupIsLevelUp = null;
      _settingsOpen = false;
      _cheatOpen = false;
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
    if (_shouldTrackFtueForLevel(level)) {
      _lastLoggedTutMergeStep = 0;
      AnalyticsService.logTutorial(name: 'tut_start', value: 3);
    }
  }

  void _handleLevelWon() {
    if (!mounted) return;
    if (_shouldTrackFtueForLevel(_activeLevel)) {
      AnalyticsService.logTutorial(
        name: 'tut_finish',
        value: 4 + _lastLoggedTutMergeStep,
      );
      widget.progress.markFtueCompleted();
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
    final vaseAdvance = !_activeLevel.isBonus
        ? widget.progress.recordLevelWonVaseStep(_activeLevel.number)
        : null;
    setState(() {
      _activeVaseAdvanceResult = vaseAdvance;
      _showWinOverlay = true;
      _settingsOpen = false;
      _cheatOpen = false;
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
      _cheatOpen = false;
      _showExitRestartPopup = false;
      _buyPopupIsLevelUp = null;
      _syncGamePauseState();
    });
  }

  void _advanceAfterWinExit() {
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
  }

  void _handleNextLevelAfterWin({bool skipInterstitial = false}) {
    widget.progress.flushPendingWinCoins();
    widget.audio.playClick();
    if (skipInterstitial) {
      _advanceAfterWinExit();
      return;
    }
    final currentLv = _activeLevel.number;
    AdsManager.showInterEndgame(
      levelNumber: currentLv,
      onCompleted: _advanceAfterWinExit,
    );
  }

  Future<bool> _handleWinRewardX2Ad() async {
    bool rewarded = false;
    await AdsManager.showRewardedAd(
      placement: 'win_x2_coins',
      levelNumber: _activeLevel.number,
      onAdFailed: _handleRewardedAdFailed,
      onRewardResult: (success) {
        rewarded = success;
        if (success && mounted) {
          widget.audio.playClick();
          final extraCoins = _activeLevel.coinReward;
          widget.progress.doublePendingWinCoins(extraCoins);
          AnalyticsService.logEarnResource(
            level: _activeLevel.number,
            type: 'currency',
            name: 'coins',
            amount: extraCoins.toDouble(),
            reason: 'win_x2_rewarded_ad',
            balance: (widget.progress.coins + extraCoins * 2).toDouble(),
          );
        }
      },
    );
    return rewarded;
  }

  void _handlePlayOnCoins() {
    final cost = _currentPlayOnCost;
    if (!widget.progress.spendCoins(cost)) {
      _handleInsufficientCoins();
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
      onAdFailed: _handleRewardedAdFailed,
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
          _activeVaseAdvanceResult = null;
          _showWinOverlay = false;
          _showExitRestartPopup = false;
          _settingsOpen = false;
          _syncGamePauseState();
        });
        _game.restartLevel();
        AnalyticsService.logLevelStart(level: currentLv);
        if (_shouldTrackFtueForLevel(_activeLevel)) {
          _lastLoggedTutMergeStep = 0;
        }
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

  void _showGameplayToast(String message, {bool blockedHaptic = true}) {
    if (blockedHaptic) {
      widget.audio.hapticBlocked();
    }
    _lockedToastTimer?.cancel();
    setState(() {
      _lockedToastMessage = message;
      _lockedToastOpacity = 1.0;
    });
    _lockedToastTimer = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) {
        setState(() {
          _lockedToastOpacity = 0.0;
        });
      }
    });
  }

  void _showLockedBoosterToast(int unlockLevel) {
    _showGameplayToast('Unlock at level $unlockLevel!');
  }

  void _handleInsufficientCoins() {
    _showGameplayToast('Not enough coins!');
  }

  void _handleRewardedAdFailed(RewardedAdFailReason reason) {
    if (!mounted) return;
    switch (reason) {
      case RewardedAdFailReason.noInternet:
        _showGameplayToast('No internet connection!');
      case RewardedAdFailReason.noAdsAvailable:
        _showGameplayToast('No ads available right now!');
      case RewardedAdFailReason.closedEarly:
      case RewardedAdFailReason.alreadyShowing:
      case RewardedAdFailReason.none:
        break;
    }
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

    if (!_game.canUseTimeFreeze) {
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
    _runTimeFreezeIntroAndEngage(allowBeforeTimerStarted: true);
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
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
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
    final safePadding = MediaQuery.paddingOf(context);
    _game.updateSafeAreaInsets(
      top: safePadding.top,
      bottom: safePadding.bottom,
    );

    final isTutorialLevel1 =
        !_activeLevel.isBonus && _activeLevel.number == 1;
    final hideBaseCoins = _showWinOverlay ||
        (_showLoseOverlay && !_loseInFailedStage) ||
        _buyPopupIsLevelUp != null;

    return Scaffold(
      backgroundColor: const Color(0xFF47279B),
      resizeToAvoidBottomInset: false,
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

          // 3b. Full-width purple footer shelf (`Frame_Footer.png`) placed below low-time edge vignette
          //     so all 4 outer screen edges glow seamlessly while HUD & booster buttons stay crisp above it.
          if (!isTutorialLevel1)
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
                child: RepaintBoundary(
                  child: UnityNineSlice(
                    sprite: 'Frame_Footer.png',
                  ),
                ),
              ),
            ),

          // 4. Urgent Low-Time (<= 10s) Soft Feathered Red Outer-Edge Vignette Pulse
          //    Cached in a static GPU `RepaintBoundary` below HUD icons (keeping HUD crisp) and pulsed via `FadeTransition`.
          if (!_activeLevel.timerDisabled && !_showWinOverlay && !_showLoseOverlay)
            ValueListenableBuilder<bool>(
              valueListenable: _game.isTimeFrozenNotifier,
              builder: (context, isFrozen, _) {
                if (isFrozen) return const SizedBox.shrink();
                return ValueListenableBuilder<int>(
                  valueListenable: _game.remainingSecondsNotifier,
                  child: FadeTransition(
                    opacity: _lowTimerVignetteOpacity,
                    child: const RepaintBoundary(
                      key: ValueKey('urgent_low_time_vignette'),
                      child: _UrgentLowTimeVignetteLayer(),
                    ),
                  ),
                  builder: (context, secs, vignetteChild) {
                    if (secs <= 0 || secs > 10) {
                      return const SizedBox.shrink();
                    }
                    return Positioned.fill(
                      child: IgnorePointer(child: vignetteChild),
                    );
                  },
                );
              },
            ),

          // 5. Redesigned Top HUD (`Play_Scene.png`: `CoinsWidget` left, `Frame_Level.png` center,
          //    `TimerGameplayView` right, + `ComboProgressBar` centered right below `Frame_Level.png`)
          SafeArea(
            child: RepaintBoundary(
              child: ValueListenableBuilder<bool>(
                valueListenable: _game.isSpotlightTutorialActiveNotifier,
                builder: (context, spotlightActive, hudChild) {
                  return AnimatedOpacity(
                    opacity: spotlightActive ? 0.38 : 1.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: hudChild,
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: ux(context, 140),
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

                          // Top-Right `TimerGameplayView` (`Icon_Clock.png` + `WidgetBase.png` matching `Play_Scene.png`)
                          if (!_activeLevel.timerDisabled)
                            Positioned(
                              right: ux(context, 57),
                              top: ux(context, 4),
                              child: ValueListenableBuilder<bool>(
                                valueListenable:
                                    _game.isWinSequenceActiveNotifier,
                                builder: (context, winActive, child) {
                                  return AnimatedScale(
                                    scale: winActive ? 0.65 : 1.0,
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeInBack,
                                    child: AnimatedOpacity(
                                      opacity: winActive ? 0.0 : 1.0,
                                      duration:
                                          const Duration(milliseconds: 160),
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
                            ),
                        ],
                      ),
                    ),

                    // Top-Center `ComboProgressBar` (`progress_combo_bg.png` + `progress_combo_fg.png`, `Play_Scene.png`)
                    SizedBox(height: ux(context, 10)),
                    _buildComboProgressBar(context),
                  ],
                ),
              ),
            ),
          ),

          // 6. Bottom `Frame_Footer.png` Shelf + Straddling Circular `PowerUps` (`Play_Scene.png`)
          //    Completely hidden on Tutorial Level 1 so zero buttons distract or overlap the tutorial box!
          if (!isTutorialLevel1)
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
                      // Left Power-Up (`LevelUp` at `X = -135` Unity px)
                      Positioned(
                        bottom: safePadding.bottom +
                            ux(
                              context,
                              UnityPowerUpHudButton.bottomOffsetUnity,
                            ),
                        child: ListenableBuilder(
                          listenable: Listenable.merge([
                            widget.progress,
                            _game.canLevelUpNotifier,
                          ]),
                          builder: (context, _) {
                            final isFree =
                                widget.progress.isFreePowerUpPending(
                              MechanicUnlockInfo.levelUpPowerUp.id,
                            );
                            return Transform.translate(
                              offset: Offset(
                                -ux(
                                  context,
                                  UnityPowerUpHudButton
                                      .horizontalOffsetUnity,
                                ),
                                0,
                              ),
                              child: UnityPowerUpHudButton(
                                key: const ValueKey('hud_level_up_btn'),
                                isLevelUp: true,
                                isUnlocked: _isLevelUpUnlocked,
                                unlockLevel:
                                    PlayerProgressService.levelUpUnlockLevel,
                                isFree: isFree,
                                count: widget.progress.levelUpCount,
                                isActionable:
                                    _game.canLevelUpNotifier.value,
                                onTap: _handleLevelUpTap,
                              ),
                            );
                          },
                        ),
                      ),

                      // Right Power-Up (`TimeFreeze` at `X = +135` Unity px)
                      Positioned(
                        bottom: safePadding.bottom +
                            ux(
                              context,
                              UnityPowerUpHudButton.bottomOffsetUnity,
                            ),
                        child: ListenableBuilder(
                          listenable: Listenable.merge([
                            widget.progress,
                            _game.isTimeFrozenNotifier,
                            _game.isTimerStartedNotifier,
                          ]),
                          builder: (context, _) {
                            final isFree =
                                widget.progress.isFreePowerUpPending(
                              MechanicUnlockInfo.timeFreezePowerUp.id,
                            );
                            return Transform.translate(
                              offset: Offset(
                                ux(
                                  context,
                                  UnityPowerUpHudButton
                                      .horizontalOffsetUnity,
                                ),
                                0,
                              ),
                              child: UnityPowerUpHudButton(
                                key:
                                    const ValueKey('hud_time_freeze_btn'),
                                isLevelUp: false,
                                isUnlocked: _isTimeFreezeUnlocked,
                                unlockLevel:
                                    PlayerProgressService.timeFreezeUnlockLevel,
                                isFree: isFree,
                                count: widget.progress.timeFreezeCount,
                                isActionable: _game.canUseTimeFreeze,
                                onTap: _handleTimeFreezeTap,
                              ),
                            );
                          },
                        ),
                      ),

                      // Bottom-Right Settings Circle Button (`Play_Scene.png`: `137x137`, `right = 58`, straddling golden footer trim)
                      Positioned(
                        right: ux(context, 58),
                        bottom: safePadding.bottom + ux(context, 91.5),
                        child: UnitySpriteButton(
                          key: const ValueKey('hud_settings_btn'),
                          onTap: _toggleSettingsPopup,
                          child: SizedBox(
                            width: ux(context, 137),
                            height: ux(context, 137),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/Button_Circle_Blue.png',
                                  width: ux(context, 137),
                                  height: ux(context, 137),
                                  fit: BoxFit.contain,
                                ),
                                Image.asset(
                                  'assets/images/Icon_Settings.png',
                                  width: ux(context, 79),
                                  height: ux(context, 79),
                                  fit: BoxFit.contain,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Bottom-Left Cheat Button (ONLY rendered when `RemoteConfigService.cheatEnable == true`)
                      ValueListenableBuilder<bool>(
                        valueListenable: RemoteConfigService.cheatEnableNotifier,
                        builder: (context, cheatEnabled, _) {
                          if (!cheatEnabled || _hideCheatHudButton) {
                            return const SizedBox.shrink();
                          }
                          return Positioned(
                            left: ux(context, 42),
                            bottom: safePadding.bottom + ux(context, 122),
                            child: CheatHudButton(
                              key: const ValueKey('hud_cheat_btn'),
                              onTap: () {
                                widget.audio.playClick();
                                setState(() {
                                  _cheatOpen = true;
                                  _settingsOpen = false;
                                  _syncGamePauseState();
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 6b. Level 1 Step-by-Step Spotlight Tutorial Banner (`"Drag to move"`)
          ValueListenableBuilder<bool>(
            valueListenable: _game.isSpotlightTutorialActiveNotifier,
            builder: (context, spotlightActive, _) {
              if (!spotlightActive) {
                return const SizedBox.shrink();
              }
              final screenW = MediaQuery.sizeOf(context).width;
              final maxBannerW = math.min(
                ux(context, 650),
                math.max(200.0, screenW - ux(context, 120)),
              );
              return Positioned(
                left: 0,
                right: 0,
                bottom: safePadding.bottom + ux(context, 136),
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      key: const ValueKey('level1_spotlight_banner'),
                      constraints: BoxConstraints(maxWidth: maxBannerW),
                      padding: EdgeInsets.symmetric(
                        horizontal: ux(context, 56),
                        vertical: ux(context, 26),
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFFFFFCF5),
                            Color(0xFFF6EAD4),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(ux(context, 40)),
                        border: Border.all(
                          color: const Color(0xFF2356F6),
                          width: ux(context, 10),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xAA030518),
                            blurRadius: ux(context, 26),
                            offset: Offset(0, ux(context, 10)),
                          ),
                          BoxShadow(
                            color: const Color(0x664B7CFF),
                            blurRadius: ux(context, 14),
                          ),
                        ],
                      ),
                      child: Text(
                        'Drag to move',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Baloo2',
                          fontSize: ux(context, 46),
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          fontVariations: const [FontVariation('wght', 800)],
                          color: const Color(0xFF7B3B11),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
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

          // 8b. Developer / QA Cheat Panel (strictly gated by `RemoteConfigService.cheatEnable`)
          ValueListenableBuilder<bool>(
            valueListenable: RemoteConfigService.cheatEnableNotifier,
            builder: (context, cheatEnabled, _) {
              if (!cheatEnabled || !_cheatOpen) {
                return const SizedBox.shrink();
              }
              return ValueListenableBuilder<int>(
                valueListenable: _game.remainingSecondsNotifier,
                builder: (context, secs, _) {
                  return CheatPanelOverlay(
                    key: const ValueKey('cheat_panel_overlay'),
                    activeLevel: _activeLevel,
                    repository: widget.repository,
                    progress: widget.progress,
                    remainingSeconds: secs,
                    hideHudButton: _hideCheatHudButton,
                    onToggleHideHudButton: (val) {
                      setState(() => _hideCheatHudButton = val);
                    },
                    onJumpToLevel: (targetLv) {
                      widget.audio.playClick();
                      _startLevel(targetLv);
                    },
                    onInstantWinPopup: () {
                      widget.audio.playClick();
                      setState(() {
                        _cheatOpen = false;
                        _syncGamePauseState();
                      });
                      _handleLevelWon();
                    },
                    onWinWithSandSequence: () {
                      widget.audio.playClick();
                      setState(() {
                        _cheatOpen = false;
                        _syncGamePauseState();
                      });
                      _game.cheatWinWithSandSequence();
                    },
                    onInstantLoseTimeout: () {
                      widget.audio.playClick();
                      setState(() {
                        _cheatOpen = false;
                        _syncGamePauseState();
                      });
                      _handleTimeExpired();
                    },
                    onMergeOnePairFree: () {
                      setState(() {
                        _cheatOpen = false;
                        _syncGamePauseState();
                      });
                      if (_game.triggerLevelUpPowerUp()) {
                        widget.audio.playPowerUpSelect();
                      } else {
                        widget.audio.hapticBlocked();
                      }
                    },
                    onUnlockAllBoardObstacles: () {
                      setState(() {
                        _cheatOpen = false;
                        _syncGamePauseState();
                      });
                      _game.cheatUnlockAllBoardObstacles();
                    },
                    onTriggerComboStep: () {
                      setState(() {
                        _cheatOpen = false;
                        _syncGamePauseState();
                      });
                      _game.cheatTriggerComboStep();
                    },
                    onAddTimeSeconds: (extraSecs) {
                      widget.audio.playClick();
                      _game.addExtraTime(extraSecs);
                    },
                    onSetTimeSeconds: (targetSecs) {
                      widget.audio.playClick();
                      setState(() {
                        _cheatOpen = false;
                        _syncGamePauseState();
                      });
                      _game.cheatSetRemainingSeconds(targetSecs);
                    },
                    onTriggerFreeTimeFreeze: () {
                      widget.audio.playPowerUpSelect();
                      setState(() {
                        _cheatOpen = false;
                        _syncGamePauseState();
                      });
                      _runTimeFreezeIntroAndEngage(
                        allowBeforeTimerStarted: true,
                      );
                    },
                    onResetAllProgress: () async {
                      widget.audio.playClick();
                      await widget.progress.cheatResetAllProgress();
                      if (!mounted) return;
                      final lv1 = widget.repository.getCampaignLevel(1);
                      _startLevel(lv1);
                    },
                    onClose: () {
                      widget.audio.playClick();
                      setState(() {
                        _cheatOpen = false;
                        _syncGamePauseState();
                      });
                    },
                  );
                },
              );
            },
          ),

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
                  onInsufficientCoins: _handleInsufficientCoins,
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
                      _handleInsufficientCoins();
                    }
                  },
                  onWatchAd: () {
                    AdsManager.showRewardedAd(
                      placement: isLvUp ? 'booster_levelup' : 'booster_timefreeze',
                      levelNumber: _activeLevel.number,
                      onAdFailed: _handleRewardedAdFailed,
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

          // 12. Two-Stage `WinGameplayView.prefab` (`Level complete!` -> `AMAZING!` + Coin Flight or Garden Metagame)
          if (_showWinOverlay)
            WinOverlay(
              levelNumber: _activeLevel.number,
              levelLabel: _activeLevel.title,
              rewardCoins: _activeLevel.coinReward,
              showRewardX2: widget.progress
                  .isWinRewardX2UnlockedForLevel(_activeLevel.number),
              timeFormatted: _game.elapsedTimeFormatted,
              movesCount: _game.movesCount,
              comboCount: _game.highestCombo,
              gardenResult: _activeVaseAdvanceResult,
              finalBlockNumber: _activeLevel.targetWinNumber,
              onClaimMilestone: () {
                widget.progress.claimCurrentVaseMilestone();
                widget.audio.playCoinCollect();
                _coinBounceCtrl.forward(from: 0.0);
              },
              onStage2Shown: widget.audio.playWinAmazing,
              onCoinChunkArrived: (chunk) {
                widget.progress.collectPendingWinCoinChunk(chunk);
                widget.audio.playCoinCollect();
                _coinBounceCtrl.forward(from: 0.0);
              },
              onWatchRewardX2: _handleWinRewardX2Ad,
              onNextLevelAfterRewardAd: () =>
                  _handleNextLevelAfterWin(skipInterstitial: true),
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
                  onInsufficientCoins: _handleInsufficientCoins,
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

          // 15. Floating Gameplay Toast Banner (locked boosters, insufficient coins, offline / no ads)
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
                      key: const ValueKey('gameplay_toast_banner'),
                      margin: EdgeInsets.symmetric(horizontal: ux(context, 80)),
                      padding: EdgeInsets.symmetric(
                        horizontal: ux(context, 48),
                        vertical: ux(context, 26),
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xDE0B0820),
                        borderRadius: BorderRadius.circular(ux(context, 34)),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.24),
                          width: ux(context, 1.8),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.50),
                            blurRadius: ux(context, 22),
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
    final isTutorialLevel1 =
        !_activeLevel.isBonus && _activeLevel.number == 1;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.progress, _coinBounceCtrl]),
      builder: (context, _) {
        final t = _coinBounceCtrl.value;
        final pulse = 1.0 + 0.14 * math.sin(t * math.pi);
        return UnityCoinsWidget(
          coins: widget.progress.coins,
          scale: pulse,
          showPlusBadge: !isTutorialLevel1 || _showWinOverlay,
        );
      },
    );
  }

  /// Redesigned Top-Center Combo Progress Bar (`Play_Scene.png`):
  /// - Track: `progress_combo_bg.png` (`354x52` gold-rimmed dark-blue capsule)
  /// - Fill: 3-slice `progress_combo_fg.png` (`maxWidth = 332, height = 30`, inset `11px`)
  /// - Label: `'Combo x1'`, `'Combo x2'`, ... centered over the bar
  Widget _buildComboProgressBar(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: Listenable.merge([
            _game.comboCountNotifier,
            _game.isWinSequenceActiveNotifier,
          ]),
          builder: (context, _) {
            final comboCount = _game.comboCountNotifier.value;
            final winActive = _game.isWinSequenceActiveNotifier.value;
            if (comboCount > 0) {
              _lastDisplayComboCount = comboCount;
            }
            final visible = comboCount > 0 && !winActive;
            final displayCombo =
                comboCount > 0 ? comboCount : _lastDisplayComboCount;

            final barW = ux(context, 354);
            final barH = ux(context, 52);
            final maxFillW = ux(context, 332);
            final fillH = ux(context, 30);

            Widget barBody = SizedBox(
              width: barW,
              height: barH,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  UnityNineSlice(
                    sprite: 'progress_combo_bg.png',
                    width: barW,
                    height: barH,
                  ),
                  Positioned(
                    left: ux(context, 11),
                    top: ux(context, 11),
                    width: maxFillW,
                    height: fillH,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(ux(context, 15)),
                      child: ValueListenableBuilder<double>(
                        valueListenable: _game.comboCountdownFractionNotifier,
                        builder: (context, frac, _) {
                          final clamped = frac.clamp(0.0, 1.0);
                          if (clamped <= 0.004) {
                            return const SizedBox.shrink();
                          }
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: maxFillW * clamped,
                              height: fillH,
                              child: const UnityNineSlice(
                                sprite: 'progress_combo_fg.png',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: Offset(0, -ux(context, 1.5)),
                    child: UnitySdfText(
                      'Combo x$displayCombo',
                      unityFontSize: 29,
                      material: UnityTextMaterial.comboBarText,
                    ),
                  ),
                ],
              ),
            );

            if (comboCount > 0) {
              barBody = TweenAnimationBuilder<double>(
                key: ValueKey('combo_bar_pop_$comboCount'),
                tween: Tween<double>(begin: 1.10, end: 1.0),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                builder: (context, popScale, child) => Transform.scale(
                  scale: popScale,
                  child: child,
                ),
                child: barBody,
              );
            }

            return AnimatedScale(
              scale: visible ? 1.0 : 0.82,
              duration: const Duration(milliseconds: 170),
              curve: visible ? Curves.easeOutBack : Curves.easeInCubic,
              child: AnimatedOpacity(
                opacity: visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                child: barBody,
              ),
            );
          },
        ),
      ),
    );
  }

  /// Redesigned Top-Right Stopwatch Timer Pill (`Play_Scene.png`):
  /// - Normal: `WidgetBase.png` (`255x96` on the exact horizontal baseline of `UnityCoinsWidget`)
  ///   + `Icon_Clock.png` (`96x115` golden stopwatch overlapping the left edge) + `'MM:SS'`
  /// - Urgent (`<= 10s`): pulsing crimson-tinted `WidgetBase.png` + `Icon_Clock.png`
  /// - Frozen: ice-tinted `WidgetBase.png` + `Snow.png` snow cap + `PowerUp_TimeFreeze.png` + `TimeFreeze_TimerBar.png`
  Widget _buildTimerGameplayView(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _game.isTimeFrozenNotifier,
      builder: (context, isFrozen, _) {
        return ValueListenableBuilder<int>(
          valueListenable: _game.remainingSecondsNotifier,
          builder: (context, secs, _) {
            final isUrgent = secs <= 10 && !isFrozen;
            final boxW = ux(context, 275);
            final boxH = ux(context, 115);

            final ColorFilter? baseFilter = isFrozen
                ? UnityButtonColorFilters.widgetBaseFrozenIce
                : isUrgent
                    ? UnityButtonColorFilters.widgetBaseUrgentRed
                    : null;

            Widget pillStack = SizedBox(
              width: boxW,
              height: boxH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: ux(context, 20),
                    top: ux(context, 21),
                    width: ux(context, 255),
                    height: ux(context, 96),
                    child: UnityNineSlice(
                      sprite: 'WidgetBase.png',
                      height: ux(context, 96),
                      colorFilter: baseFilter,
                      padding: EdgeInsets.only(
                        left: ux(context, 78),
                        right: ux(context, 20),
                        bottom: ux(context, 4),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _formatTimer(secs),
                          style: TextStyle(
                            fontFamily: 'Baloo2',
                            fontSize: ux(context, 48),
                            fontWeight: FontWeight.w800,
                            fontVariations: const [FontVariation('wght', 800)],
                            color: isFrozen
                                ? const Color(0xFFE6FCFF)
                                : isUrgent
                                    ? const Color(0xFFFFE5EA)
                                    : Colors.white,
                            letterSpacing: 0.3,
                            height: 1.0,
                            shadows: const [
                              Shadow(
                                color: Color(0xAA09042E),
                                offset: Offset(0, 1.5),
                                blurRadius: 2.5,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (isFrozen)
                    Positioned(
                      left: ux(context, 32),
                      top: ux(context, 13),
                      child: Image.asset(
                        'assets/images/Snow.png',
                        width: ux(context, 228),
                        fit: BoxFit.contain,
                      ),
                    ),

                  Positioned(
                    left: 0,
                    top: isFrozen ? ux(context, 12) : 0,
                    width: ux(context, isFrozen ? 98 : 96),
                    height: ux(context, isFrozen ? 98 : 115),
                    child: Image.asset(
                      isFrozen
                          ? 'assets/images/PowerUp_TimeFreeze.png'
                          : 'assets/images/Icon_Clock.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            );

            if (isUrgent) {
              pillStack = AnimatedBuilder(
                animation: _lowTimerPulseCtrl,
                builder: (context, child) => Transform.scale(
                  scale: 1.0 + 0.055 * _lowTimerPulseCtrl.value,
                  child: child,
                ),
                child: pillStack,
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                pillStack,
                if (isFrozen) ...[
                  SizedBox(height: ux(context, 8)),
                  Padding(
                    padding: EdgeInsets.only(right: ux(context, 8)),
                    child: SizedBox(
                      width: ux(context, 240),
                      height: ux(context, 22),
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          UnityNineSlice(
                            sprite: 'TimeFreeze_TimerBar.png',
                            width: ux(context, 240),
                            height: ux(context, 22),
                            tint: const Color(0xFF191254),
                          ),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(ux(context, 11)),
                            child: ValueListenableBuilder<double>(
                              valueListenable: _game.timeFreezeNotifier,
                              child: Container(
                                width: ux(context, 240),
                                height: ux(context, 16),
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
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// Flying `PowerUp_TimeFreeze.png` clock from bottom button (`X = +135`) to top-right
  /// `Icon_Clock.png` stopwatch target + cyan `Explosion_Halo.png` burst upon impact (`t >= 0.66`).
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
      screen.width - ux(context, 284),
      pad.top + ux(context, 66),
    );

    final flyT = (t / 0.66).clamp(0.0, 1.0);
    final haloT = ((t - 0.60) / 0.40).clamp(0.0, 1.0);
    final eased = Curves.easeInOutCubic.transform(flyT);

    final ctrl = Offset(screen.width * 0.88, screen.height * 0.46);
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

                                      // Bottom Version Text (`v.1.0.6` — also acts as secret Cheat Panel trigger when `cheat_enable == true`)
                                      Positioned(
                                        bottom: ux(context, 28),
                                        child: ValueListenableBuilder<bool>(
                                          valueListenable: RemoteConfigService
                                              .cheatEnableNotifier,
                                          builder: (context, cheatEnabled, child) {
                                            if (!cheatEnabled) {
                                              return IgnorePointer(child: child);
                                            }
                                            return GestureDetector(
                                              key: const ValueKey(
                                                'settings_version_cheat_trigger',
                                              ),
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                widget.audio.playClick();
                                                setState(() {
                                                  _settingsOpen = false;
                                                  _cheatOpen = true;
                                                  _syncGamePauseState();
                                                });
                                              },
                                              child: child,
                                            );
                                          },
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

/// Static GPU-cached soft crimson-red outer screen-edge & corner vignette for low time (`<= 10s`).
/// Combines an aspect-adapted elliptical perimeter gradient with a Gaussian-feathered rounded-frame
/// glow so all 4 edges & corners fade smoothly inward without miter seams while keeping the board clear.
class _UrgentLowTimeVignetteLayer extends StatelessWidget {
  const _UrgentLowTimeVignetteLayer();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
      size: Size.infinite,
      painter: _LowTimeRedVignettePainter(),
    );
  }
}

class _LowTimeRedVignettePainter extends CustomPainter {
  const _LowTimeRedVignettePainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1) return;
    final w = size.width;
    final h = size.height;
    final fullRect = Offset.zero & size;

    // 1. Aspect-mapped elliptical outer corner & perimeter crimson vignette (center 74% stays 100% clear)
    canvas.save();
    canvas.scale(w, h);
    const unitRect = Rect.fromLTWH(0, 0, 1, 1);
    final radialPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 0.75,
        colors: [
          Color(0x00FF1834),
          Color(0x00FF1834),
          Color(0x1EF2122E),
          Color(0x4EE80C28),
          Color(0x7AD90620),
        ],
        stops: [0.0, 0.72, 0.86, 0.95, 1.0],
      ).createShader(unitRect);
    canvas.drawRect(unitRect, radialPaint);
    canvas.restore();

    // 2. Subtle continuous Gaussian-feathered SDF rounded-perimeter glow hugging all 4 outer screen edges
    final shortest = math.min(w, h);
    final bandW = shortest * 0.082;
    final blurSigma = shortest * 0.045;
    final inset = -bandW * 0.22;
    final frameRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, w - inset * 2.0, h - inset * 2.0),
      Radius.circular(shortest * 0.11),
    );
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bandW
      ..color = const Color(0xADFF1E38)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);

    canvas.save();
    canvas.clipRect(fullRect);
    canvas.drawRRect(frameRRect, framePaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LowTimeRedVignettePainter oldDelegate) => false;
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
        // 9-Slice `Frost_Gradient.png` R8 mask icy vignette frame (`R = 0` center -> `alpha = 0` crystal clear!)
        UnityNineSlice(
          key: const ValueKey('time_freeze_frost_vignette'),
          sprite: 'Frost_Gradient.png',
          colorFilter: UnityChannelMaskFilters.redChannelAlphaTint(
            const Color(0xCC99F0FF),
            alphaScale: 1.15,
          ),
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
