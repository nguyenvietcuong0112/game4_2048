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
import '../services/app_version_service.dart';
import '../services/audio_haptics_service.dart';
import '../services/player_progress_service.dart';
import '../services/remote_config_service.dart';
import 'cheat_panel_overlay.dart';
import 'exit_gameplay_popup.dart';
import 'lose_overlay.dart';
import 'mechanic_unlock_dialog.dart';
import 'more_lives_dialog.dart';
import 'powerup_buy_popup.dart';
import 'unity_ui_kit.dart';
import 'win_overlay.dart';

class GameplayScreen extends StatefulWidget {
  final LevelRepository repository;
  final BlockOrderPalette palette;
  final PieceVisualSettings visualSettings;
  final AudioHapticsService audio;
  final PlayerProgressService progress;
  final VoidCallback? onExitToHome;

  const GameplayScreen({
    super.key,
    required this.repository,
    required this.palette,
    required this.visualSettings,
    required this.audio,
    required this.progress,
    this.onExitToHome,
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
  late final AnimationController _shuffleFlyCtrl;
  late final AnimationController _lowTimerPulseCtrl;
  late final Animation<double> _lowTimerVignetteOpacity;
  late final AnimationController _levelTransitionCtrl;

  bool _showWinOverlay = false;
  bool _showLoseOverlay = false;
  bool _loseInFailedStage = false;
  bool _losePeekingBoard = false;
  int _playOnsUsedInAttempt = 0;
  bool _showExitRestartPopup = false;
  bool _showMoreLivesModal = false;
  bool _moreLivesPendingRetry = false;
  bool _heartSpentForCurrentAttempt = false;
  BoosterType? _buyPopupBooster; // null = closed, or active booster buy popup
  bool _settingsOpen = false;
  bool _cheatOpen = false;
  bool _hideCheatHudButton = false;
  int _lastDisplayComboCount = 1;
  MechanicUnlockInfo? _activeMechanicModal;
  MechanicUnlockInfo? _activeBoosterArrowHint;

  String? _lockedToastMessage;
  Timer? _lockedToastTimer;
  Timer? _specialBannerTimer;
  Timer? _lifeRegenTimer;
  double _lockedToastOpacity = 0.0;
  double _specialBannerOpacity = 0.0;
  int _lastLoggedTutMergeStep = 0;
  VaseStepAdvanceResult? _activeVaseAdvanceResult;

  bool _shouldTrackFtueForLevel(LevelDefinition level) =>
      !level.isBonus && level.number == 1 && !widget.progress.isFtueCompleted;

  /// Configurable `game_end_flow.play_on` pricing (defaults: `450` + `150` per extra revive).
  int get _currentPlayOnCost =>
      RemoteConfigService.playOnBasePrice +
      RemoteConfigService.playOnIncrementPrice * _playOnsUsedInAttempt;

  /// Configurable win-level coin reward (`RemoteConfigService.keyWinLevelCoinReward`, default `25`).
  /// Special Hard levels award `3x` coins (default `75`, or `150` with Reward x2)!
  int get _currentWinCoinReward {
    final base = RemoteConfigService.winLevelCoinReward;
    return _activeLevel.isSpecial ? base * 3 : base;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(AppVersionService.init());
    widget.progress.syncLivesRegen();
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

    _shuffleFlyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
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

    _levelTransitionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: 0.0,
    );

    _game = BlockOrderGame(
      initialLevel: _activeLevel,
      palette: widget.palette,
      visualSettings: widget.visualSettings,
      audio: widget.audio,
      onFirstAction: _handleFirstActionInAttempt,
      onLevelWon: _handleLevelWon,
      onTimeExpired: _handleTimeExpired,
      onHammerApplied: _handleHammerApplied,
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
    widget.progress.addListener(_syncLifeRegenTicker);
    RemoteConfigService.boosterUnlockOrderNotifier
        .addListener(_handleRemoteBoosterOrderChanged);
    _syncLowTimerPulseTicker();
    _syncLifeRegenTicker();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.progress.syncLivesRegen();
      if (!widget.progress.canPlay()) {
        setState(() {
          _showMoreLivesModal = true;
          _moreLivesPendingRetry = true;
          _syncGamePauseState();
        });
        return;
      }
      _checkNewMechanicOrPowerUpUnlock(_activeLevel);
      if (_activeLevel.isSpecial) {
        _triggerSpecialLevelBanner();
      }
    });

    AnalyticsService.logLevelStart(level: _activeLevel.number);
    if (_shouldTrackFtueForLevel(_activeLevel)) {
      _lastLoggedTutMergeStep = 0;
      AnalyticsService.logTutorial(name: 'tut_start', value: 3);
    }
  }

  /// Mirrors `HeartService.StartInteractiveLevel()`:
  /// Spends 1 heart immediately upon first board touch or booster activation so force-closing
  /// mid-level cannot bypass heart loss. Skips deduction when Infinity Hearts are active.
  void _handleFirstActionInAttempt() {
    if (!mounted || _heartSpentForCurrentAttempt) return;
    if (!widget.progress.isInfinityLives() &&
        widget.progress.trySpendHeart(amount: 1)) {
      _heartSpentForCurrentAttempt = true;
      _syncLifeRegenTicker();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockedToastTimer?.cancel();
    _specialBannerTimer?.cancel();
    _lifeRegenTimer?.cancel();
    widget.progress.removeListener(_syncLifeRegenTicker);
    RemoteConfigService.boosterUnlockOrderNotifier
        .removeListener(_handleRemoteBoosterOrderChanged);
    _game.remainingSecondsNotifier.removeListener(_syncLowTimerPulseTicker);
    _game.isTimeFrozenNotifier.removeListener(_syncLowTimerPulseTicker);
    _coinBounceCtrl.dispose();
    _freezeFlyCtrl.dispose();
    _shuffleFlyCtrl.dispose();
    _lowTimerPulseCtrl.dispose();
    _levelTransitionCtrl.dispose();
    super.dispose();
  }

  void _syncLifeRegenTicker() {
    final needsRegen = widget.progress.isInfinityLives() ||
        widget.progress.lives < widget.progress.currentMaxLives;
    if (needsRegen && _lifeRegenTimer == null) {
      _lifeRegenTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final gained = widget.progress.syncLivesRegen();
        if (gained > 0 &&
            _showMoreLivesModal &&
            _moreLivesPendingRetry &&
            widget.progress.canPlay()) {
          _completePendingMoreLivesRetry();
        }
      });
    } else if (!needsRegen && _lifeRegenTimer != null) {
      _lifeRegenTimer?.cancel();
      _lifeRegenTimer = null;
    }
  }

  void _playLevelRevealTransition() {
    if (!mounted) return;
    _levelTransitionCtrl.value = 1.0;
    _levelTransitionCtrl.animateTo(
      0.0,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.progress.syncLivesRegen();
      if (_showMoreLivesModal &&
          _moreLivesPendingRetry &&
          widget.progress.canPlay()) {
        _completePendingMoreLivesRetry();
      }
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
        _showMoreLivesModal ||
        _buyPopupBooster != null ||
        _settingsOpen ||
        _cheatOpen ||
        _activeMechanicModal != null;
    final canSuspendBoard = _showWinOverlay ||
        (_showLoseOverlay && !_losePeekingBoard) ||
        _showExitRestartPopup ||
        _showMoreLivesModal ||
        _buyPopupBooster != null ||
        _settingsOpen ||
        _cheatOpen;
    _game.setModalPauseState(
      modalPaused: modalPaused,
      canSuspendBoard: canSuspendBoard,
    );
    _syncLowTimerPulseTicker();
  }

  double _boosterHudOffsetUnity(String powerUpId) {
    final slot = RemoteConfigService.hudSlotIndexForBooster(powerUpId);
    const offsets = UnityPowerUpHudButton.slotOffsetsUnity;
    return offsets[slot.clamp(0, offsets.length - 1)];
  }

  void _handleRemoteBoosterOrderChanged() {
    if (!mounted) return;
    setState(() {});
    if (_activeMechanicModal == null &&
        !_showWinOverlay &&
        !_showLoseOverlay &&
        !_showMoreLivesModal) {
      _checkNewMechanicOrPowerUpUnlock(_activeLevel);
    }
  }

  void _checkNewMechanicOrPowerUpUnlock(LevelDefinition lv) {
    if (lv.isBonus) return;
    MechanicUnlockInfo? unlock;
    for (final entry in RemoteConfigService.boosterUnlockOrder) {
      if (lv.number == entry.unlockLevel &&
          !widget.progress.hasSeenMechanic(entry.id)) {
        unlock = MechanicUnlockInfo.forBoosterType(entry.type);
        break;
      }
    }
    if (unlock == null &&
        lv.hasToggleWalls &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.toggleWalls.id)) {
      unlock = MechanicUnlockInfo.toggleWalls;
    } else if (unlock == null &&
        lv.hasDispensers &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.dispenser.id)) {
      unlock = MechanicUnlockInfo.dispenser;
    } else if (unlock == null &&
        lv.hasClockBonus &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.clockBonus.id)) {
      unlock = MechanicUnlockInfo.clockBonus;
    } else if (unlock == null &&
        lv.hasLimitedMove &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.limitedMove.id)) {
      unlock = MechanicUnlockInfo.limitedMove;
    } else if (unlock == null &&
        lv.hasSwap &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.swap.id)) {
      unlock = MechanicUnlockInfo.swap;
    } else if (unlock == null &&
        lv.hasKeyLock &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.keyLock.id)) {
      unlock = MechanicUnlockInfo.keyLock;
    } else if (unlock == null &&
        lv.hasOneWayArrow &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.oneWayArrow.id)) {
      unlock = MechanicUnlockInfo.oneWayArrow;
    } else if (unlock == null &&
        lv.hasPinned &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.pinned.id)) {
      unlock = MechanicUnlockInfo.pinned;
    } else if (unlock == null &&
        lv.hasMystery &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.mystery.id)) {
      unlock = MechanicUnlockInfo.mystery;
    } else if (unlock == null &&
        lv.hasArrows &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.arrows.id)) {
      unlock = MechanicUnlockInfo.arrows;
    } else if (unlock == null &&
        lv.hasDud &&
        !widget.progress.hasSeenMechanic(MechanicUnlockInfo.dud.id)) {
      unlock = MechanicUnlockInfo.dud;
    } else if (unlock == null &&
        lv.hasIce &&
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

  void _triggerSpecialLevelBanner() {
    _specialBannerTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _specialBannerOpacity = 1.0;
    });
    _specialBannerTimer = Timer(const Duration(milliseconds: 2300), () {
      if (mounted) {
        setState(() {
          _specialBannerOpacity = 0.0;
        });
      }
    });
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
    _shuffleFlyCtrl.stop();
    _shuffleFlyCtrl.value = 0.0;
    _specialBannerTimer?.cancel();
    setState(() {
      _activeLevel = level;
      _activeVaseAdvanceResult = null;
      _showWinOverlay = false;
      _showLoseOverlay = false;
      _loseInFailedStage = false;
      _losePeekingBoard = false;
      _playOnsUsedInAttempt = 0;
      _showExitRestartPopup = false;
      _heartSpentForCurrentAttempt = false;
      _buyPopupBooster = null;
      _settingsOpen = false;
      _cheatOpen = false;
      _activeMechanicModal = null;
      _activeBoosterArrowHint = null;
      _specialBannerOpacity = 0.0;
      _syncGamePauseState();
    });
    _playLevelRevealTransition();
    _game.loadLevel(level);
    _checkNewMechanicOrPowerUpUnlock(level);
    if (level.isSpecial) {
      _triggerSpecialLevelBanner();
    }
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
    if (_heartSpentForCurrentAttempt) {
      widget.progress.refundAttemptHeart();
      _heartSpentForCurrentAttempt = false;
      _syncLifeRegenTicker();
    }
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
    final winCoins = _currentWinCoinReward;
    AnalyticsService.logEarnResource(
      level: _activeLevel.number,
      type: 'currency',
      name: 'coins',
      amount: winCoins.toDouble(),
      reason: 'win_level',
      balance: (widget.progress.coins + winCoins).toDouble(),
    );
    AnalyticsService.logPopupShow(name: 'win', level: _activeLevel.number);
    widget.progress.stageLevelWinReward(
      rewardCoins: winCoins,
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
      _buyPopupBooster = null;
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
      _buyPopupBooster = null;
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

  Future<int> _handleMilestoneRewardX2Ad() async {
    int stagedCoins = 0;
    await AdsManager.showRewardedAd(
      placement: 'flower_bloom_x2',
      levelNumber: _activeLevel.number,
      onAdFailed: _handleRewardedAdFailed,
      onRewardResult: (success) {
        if (success && mounted) {
          widget.audio.playClick();
          stagedCoins =
              widget.progress.stageCurrentVaseMilestoneClaim(multiplier: 2);
          if (stagedCoins > 0) {
            AnalyticsService.logEarnResource(
              level: _activeLevel.number,
              type: 'currency',
              name: 'coins',
              amount: stagedCoins.toDouble(),
              reason: 'flower_bloom_x2_ad',
              balance: (widget.progress.coins + stagedCoins).toDouble(),
            );
          }
        }
      },
    );
    return stagedCoins;
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
          final extraCoins = _currentWinCoinReward;
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
    if (!_heartSpentForCurrentAttempt &&
        !widget.progress.isInfinityLives() &&
        widget.progress.trySpendHeart(amount: 1)) {
      _heartSpentForCurrentAttempt = true;
    }
    _syncLifeRegenTicker();
    if (mounted) {
      setState(() {
        _loseInFailedStage = true;
        _losePeekingBoard = false;
        _syncGamePauseState();
      });
    }
  }

  void _executeRestartLevelNow() {
    if (!mounted) return;
    final currentLv = _activeLevel.number;
    widget.audio.playClick();
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
      _heartSpentForCurrentAttempt = false;
      _settingsOpen = false;
      _showMoreLivesModal = false;
      _moreLivesPendingRetry = false;
      _syncGamePauseState();
    });
    _syncLifeRegenTicker();
    _playLevelRevealTransition();
    _game.restartLevel();
    AnalyticsService.logLevelStart(level: currentLv);
    if (_shouldTrackFtueForLevel(_activeLevel)) {
      _lastLoggedTutMergeStep = 0;
    }
  }

  void _completePendingMoreLivesRetry() {
    if (!mounted || !widget.progress.canPlay()) return;
    final shouldRestart = _moreLivesPendingRetry;
    setState(() {
      _showMoreLivesModal = false;
      _moreLivesPendingRetry = false;
      _syncGamePauseState();
    });
    _syncLifeRegenTicker();
    if (shouldRestart) {
      _executeRestartLevelNow();
    }
  }

  void _handleMoreLivesWatchAd() {
    widget.audio.playClick();
    AdsManager.showRewardedAd(
      placement: 'more_lives_add_one',
      levelNumber: _activeLevel.number,
      onAdFailed: _handleRewardedAdFailed,
      onRewardResult: (success) {
        if (success && mounted) {
          widget.progress.addOneLife();
          _showGameplayToast('+1 Life!');
          _completePendingMoreLivesRetry();
        }
      },
    );
  }

  void _handleMoreLivesRefillCoins() {
    widget.audio.playClick();
    if (widget.progress.lives >= widget.progress.currentMaxLives) {
      _completePendingMoreLivesRetry();
      return;
    }
    if (widget.progress.refillLivesWithCoins()) {
      _showGameplayToast('Lives Refilled!');
      _completePendingMoreLivesRetry();
    } else {
      _handleInsufficientCoins();
    }
  }

  void _handleCloseMoreLives() {
    widget.audio.playClick();
    widget.progress.syncLivesRegen();
    if (widget.progress.canPlay()) {
      _completePendingMoreLivesRetry();
      return;
    }
    // Cannot enter/play a level when Hearts == 0; return to Failed overlay or Home.
    if (_showLoseOverlay) {
      setState(() {
        _showMoreLivesModal = false;
        _moreLivesPendingRetry = false;
        _syncGamePauseState();
      });
    } else if (widget.onExitToHome != null) {
      setState(() {
        _showMoreLivesModal = false;
        _moreLivesPendingRetry = false;
        _syncGamePauseState();
      });
      widget.onExitToHome!();
    } else {
      _showGameplayToast('No lives left! Watch an ad or refill!');
    }
  }

  void _handleRetryLevel() {
    widget.progress.syncLivesRegen();
    _syncLifeRegenTicker();
    if (!widget.progress.canPlay()) {
      widget.audio.playClick();
      AnalyticsService.logPopupShow(
        name: 'more_lives',
        level: _activeLevel.number,
      );
      setState(() {
        _showExitRestartPopup = false;
        _settingsOpen = false;
        _showMoreLivesModal = true;
        _moreLivesPendingRetry = true;
        _syncGamePauseState();
      });
      return;
    }

    final currentLv = _activeLevel.number;
    AnalyticsService.logLevelRetry(level: currentLv);
    AdsManager.showInterEndgame(
      levelNumber: currentLv,
      onCompleted: _executeRestartLevelNow,
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
    // Note: Khi user chưa thao tác gì lên board -> retry ko mất tim.
    if (_game.hasPlayerInteracted &&
        !_heartSpentForCurrentAttempt &&
        !widget.progress.isInfinityLives() &&
        widget.progress.trySpendHeart(amount: 1)) {
      _heartSpentForCurrentAttempt = true;
    }
    _syncLifeRegenTicker();
    _handleRetryLevel();
  }

  void _handleQuitFromSettings() {
    widget.audio.playClick();
    AnalyticsService.logLevelExit(
      level: _activeLevel.number,
      playDuration: _game.elapsedGameTime,
      reason: 'settings_quit',
    );
    // User quit giữa chừng -> đảm bảo trừ 1 tim (nếu chưa trừ lúc chạm) và hiển thị popup Level Failed (-1).
    if (!_showWinOverlay && !_showLoseOverlay) {
      widget.audio.playLevelFailed();
      if (!_heartSpentForCurrentAttempt &&
          !widget.progress.isInfinityLives() &&
          widget.progress.trySpendHeart(amount: 1)) {
        _heartSpentForCurrentAttempt = true;
      }
      _syncLifeRegenTicker();
    }
    setState(() {
      _settingsOpen = false;
      _showExitRestartPopup = false;
      _showLoseOverlay = true;
      _loseInFailedStage = true;
      _losePeekingBoard = false;
      _syncGamePauseState();
    });
  }

  void _handleCloseLoseFailedToHome() {
    widget.audio.playClick();
    final onExitToHome = widget.onExitToHome;
    if (onExitToHome != null) {
      onExitToHome();
    } else {
      _handleRetryLevel();
    }
  }

  bool get _isLevelUpUnlocked =>
      widget.progress.isLevelUpUnlockedForLevel(_activeLevel.number);

  bool get _isTimeFreezeUnlocked =>
      widget.progress.isTimeFreezeUnlockedForLevel(_activeLevel.number);

  bool get _isShuffleUnlocked =>
      widget.progress.isShuffleUnlockedForLevel(_activeLevel.number);

  bool get _isHammerUnlocked =>
      widget.progress.isHammerUnlockedForLevel(_activeLevel.number);

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
  void _clearBoosterArrowHint(String powerUpId) {
    if (_activeBoosterArrowHint?.id == powerUpId) {
      setState(() => _activeBoosterArrowHint = null);
    }
  }

  void _handleLevelUpTap({bool fromFtue = false}) {
    if (!_isLevelUpUnlocked) {
      _showLockedBoosterToast(PlayerProgressService.levelUpUnlockLevel);
      return;
    }
    _clearBoosterArrowHint(MechanicUnlockInfo.levelUpPowerUp.id);
    if (_game.isResolving) return;
    _game.cancelHammerTargeting();

    final isFree = fromFtue ||
        widget.progress
            .isFreePowerUpPending(MechanicUnlockInfo.levelUpPowerUp.id);
    if (!isFree && widget.progress.levelUpCount <= 0) {
      widget.audio.playClick();
      AnalyticsService.logPopupShow(
        name: 'buy_level_up',
        level: _activeLevel.number,
      );
      setState(() {
        _buyPopupBooster = BoosterType.levelUp;
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
    _clearBoosterArrowHint(MechanicUnlockInfo.timeFreezePowerUp.id);
    if (_game.isResolving) return;
    _game.cancelHammerTargeting();

    final isFree = fromFtue ||
        widget.progress
            .isFreePowerUpPending(MechanicUnlockInfo.timeFreezePowerUp.id);
    if (!isFree && widget.progress.timeFreezeCount <= 0) {
      widget.audio.playClick();
      AnalyticsService.logPopupShow(
        name: 'buy_time_freeze',
        level: _activeLevel.number,
      );
      setState(() {
        _buyPopupBooster = BoosterType.timeFreeze;
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

  /// Smart Shuffle booster (`pu_shuffle`):
  /// Shuffles `number` values across unlocked numbered blocks (conserving exact multiset
  /// with zero polyomino overlap / zero softlock!) to create fresh adjacent merges.
  void _handleShuffleTap({bool fromFtue = false}) {
    if (!_isShuffleUnlocked) {
      _showLockedBoosterToast(PlayerProgressService.shuffleUnlockLevel);
      return;
    }
    _clearBoosterArrowHint(MechanicUnlockInfo.shufflePowerUp.id);
    if (_game.isResolving) return;
    _game.cancelHammerTargeting();

    final isFree = fromFtue ||
        widget.progress
            .isFreePowerUpPending(MechanicUnlockInfo.shufflePowerUp.id);
    if (!isFree && widget.progress.shuffleCount <= 0) {
      widget.audio.playClick();
      AnalyticsService.logPopupShow(
        name: 'buy_shuffle',
        level: _activeLevel.number,
      );
      setState(() {
        _buyPopupBooster = BoosterType.shuffle;
        _syncGamePauseState();
      });
      return;
    }

    if (!_game.canShuffleNotifier.value) {
      _showGameplayToast('Need at least 2 different unlocked blocks!');
      return;
    }

    if (isFree) {
      widget.progress.consumeFreePowerUp(MechanicUnlockInfo.shufflePowerUp.id);
    } else {
      if (!widget.progress.consumeShuffle()) return;
    }
    AnalyticsService.logSpendResource(
      level: _activeLevel.number,
      type: 'booster',
      name: 'shuffle',
      amount: 1,
      reason: 'gameplay',
      balance: widget.progress.shuffleCount.toDouble(),
    );

    widget.audio.playPowerUpSelect();
    _runShuffleIntroAndTrigger();
  }

  void _runShuffleIntroAndTrigger() {
    _game.isShuffleIntroInFlight = true;
    final targetLevelNumber = _activeLevel.number;
    bool shuffled = false;

    void onTick() {
      if (!mounted || _activeLevel.number != targetLevelNumber) return;
      if (!shuffled && _shuffleFlyCtrl.value >= 0.48) {
        shuffled = true;
        _game.isShuffleIntroInFlight = false;
        _game.triggerShufflePowerUp();
      }
    }

    _shuffleFlyCtrl.addListener(onTick);
    _shuffleFlyCtrl.forward(from: 0.0).whenComplete(() {
      _shuffleFlyCtrl.removeListener(onTick);
      if (!mounted || _activeLevel.number != targetLevelNumber) return;
      _game.isShuffleIntroInFlight = false;
      if (!shuffled) {
        _game.triggerShufflePowerUp();
      }
    });
  }

  Offset _boosterHudCenterScreen(BuildContext context, String boosterId) {
    final screen = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    return Offset(
      screen.width * 0.5 + ux(context, _boosterHudOffsetUnity(boosterId)),
      screen.height -
          pad.bottom -
          ux(
            context,
            UnityPowerUpHudButton.bottomOffsetUnity +
                UnityPowerUpHudButton.scaledUnitySize * 0.5,
          ),
    );
  }

  /// Obstacle Breaker Hammer booster (`pu_hammer`):
  /// Enters targeting mode highlighting every splittable block (`>= 4`).
  /// Only consumes the booster (or `FREE` turn) once the player taps a valid block!
  void _handleHammerTap({bool fromFtue = false}) {
    if (!_isHammerUnlocked) {
      _showLockedBoosterToast(PlayerProgressService.hammerUnlockLevel);
      return;
    }
    _clearBoosterArrowHint(MechanicUnlockInfo.hammerPowerUp.id);
    if (_game.isResolving) return;

    if (_game.isHammerTargetingNotifier.value) {
      widget.audio.playClick();
      _game.cancelHammerTargeting();
      return;
    }

    final isFree = fromFtue ||
        widget.progress
            .isFreePowerUpPending(MechanicUnlockInfo.hammerPowerUp.id);
    if (!isFree && widget.progress.hammerCount <= 0) {
      widget.audio.playClick();
      AnalyticsService.logPopupShow(
        name: 'buy_hammer',
        level: _activeLevel.number,
      );
      setState(() {
        _buyPopupBooster = BoosterType.hammer;
        _syncGamePauseState();
      });
      return;
    }

    if (!_game.canHammerNotifier.value) {
      _showGameplayToast('No blocks can be split right now!');
      return;
    }

    final hudOrigin = _boosterHudCenterScreen(
      context,
      MechanicUnlockInfo.hammerPowerUp.id,
    );
    _game.enterHammerTargeting(
      isFree: isFree,
      hammerOriginWorld: Vector2(hudOrigin.dx, hudOrigin.dy),
    );
  }

  void _handleHammerApplied(bool wasFree) {
    if (!mounted) return;
    if (wasFree) {
      widget.progress.consumeFreePowerUp(MechanicUnlockInfo.hammerPowerUp.id);
    } else {
      widget.progress.consumeHammer();
    }
    AnalyticsService.logSpendResource(
      level: _activeLevel.number,
      type: 'booster',
      name: 'hammer',
      amount: 1,
      reason: 'gameplay',
      balance: widget.progress.hammerCount.toDouble(),
    );
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

  void _handleActivatePowerUpFromUnlockOverlay(MechanicUnlockInfo modal) {
    final type = modal.boosterType ??
        (modal.isLevelUpPowerUp ? BoosterType.levelUp : BoosterType.timeFreeze);
    widget.progress.markMechanicSeen(modal.id);
    setState(() {
      _activeMechanicModal = null;
      _activeBoosterArrowHint = null;
      _syncGamePauseState();
    });
    switch (type) {
      case BoosterType.levelUp:
        _handleLevelUpTap(fromFtue: true);
      case BoosterType.timeFreeze:
        _handleTimeFreezeTap(fromFtue: true);
      case BoosterType.shuffle:
        _handleShuffleTap(fromFtue: true);
      case BoosterType.hammer:
        _handleHammerTap(fromFtue: true);
    }
  }

  void _dismissBoosterUnlockKeepFree() {
    final modal = _activeMechanicModal;
    if (modal == null || !modal.isPowerUp) return;
    widget.audio.playClick();
    // Keep the granted 1 FREE booster turn pending on the HUD if the user clicks outside.
    widget.progress.setFreePowerUpPending(modal.id, true);
    widget.progress.markMechanicSeen(modal.id);
    setState(() {
      _activeMechanicModal = null;
      _activeBoosterArrowHint = null;
      _syncGamePauseState();
    });
  }

  void _dismissMechanicUnlockModal() {
    final modal = _activeMechanicModal;
    if (modal == null) return;
    widget.audio.playClick();
    widget.progress.markMechanicSeen(modal.id);
    setState(() {
      _activeMechanicModal = null;
      _activeBoosterArrowHint = null;
      _syncGamePauseState();
    });
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
        _buyPopupBooster != null ||
        _showMoreLivesModal;

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
          ValueListenableBuilder<bool>(
            valueListenable: _game.isTimeFrozenNotifier,
            child: FadeTransition(
              opacity: _TimeFreezeFadeAnimation(_game.timeFreezeNotifier),
              child: const RepaintBoundary(child: _TimeFreezeFrostStaticLayer()),
            ),
            builder: (context, isFrozen, frostLayer) {
              if (!isFrozen) return const SizedBox.shrink();
              return IgnorePointer(child: frostLayer);
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
          //    Smoothly hides when the final merge water-into-jar sequence starts so nothing overlaps the jar!
          SafeArea(
            child: RepaintBoundary(
              child: ValueListenableBuilder<bool>(
                valueListenable: _game.isWinSequenceActiveNotifier,
                builder: (context, winActive, topHudChild) {
                  return IgnorePointer(
                    ignoring: winActive,
                    child: AnimatedSlide(
                      key: const ValueKey('gameplay_top_header_hud'),
                      offset:
                          winActive ? const Offset(0, -0.35) : Offset.zero,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: winActive ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOut,
                        child: topHudChild,
                      ),
                    ),
                  );
                },
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
                            // Top-Left `CoinsWidget` (hidden on Tutorial Level 1 and when elevated above `WinOverlay`, `PlayOnPopupView`, `PowerUpBuyPopup`, or `MoreLivesDialog`)
                            if (!isTutorialLevel1)
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

                            // Top-Center `Frame_Level.png` (hidden on Tutorial Level 1)
                            if (!isTutorialLevel1)
                              Positioned(
                                top: ux(context, 10),
                                child: IgnorePointer(
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.topCenter,
                                    children: [
                                      ConstrainedBox(
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
                                            material:
                                                UnityTextMaterial.levelCounter,
                                          ),
                                        ),
                                      ),
                                      if (_activeLevel.isSpecial)
                                        Positioned(
                                          bottom: -ux(context, 22),
                                          child: Container(
                                            key: const ValueKey(
                                              'special_hard_hud_badge',
                                            ),
                                            padding: EdgeInsets.symmetric(
                                              horizontal: ux(context, 22),
                                              vertical: ux(context, 5),
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Color(0xFFFF4D6D),
                                                  Color(0xFFB91C1C),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                ux(context, 22),
                                              ),
                                              border: Border.all(
                                                color: const Color(0xFFFDE047),
                                                width: ux(context, 3.2),
                                              ),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x993B0816),
                                                  blurRadius: 6,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.local_fire_department_rounded,
                                                  size: ux(context, 26),
                                                  color:
                                                      const Color(0xFFFDE047),
                                                ),
                                                SizedBox(width: ux(context, 6)),
                                                Text(
                                                  'SPECIAL HARD · +$_currentWinCoinReward',
                                                  style: TextStyle(
                                                    fontFamily: 'Baloo2',
                                                    fontSize: ux(context, 24),
                                                    fontWeight: FontWeight.w900,
                                                    color: Colors.white,
                                                    height: 1.05,
                                                    letterSpacing: 0.4,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),

                            // Top-Right `TimerGameplayView` (`Icon_Clock.png` + `WidgetBase.png` matching `Play_Scene.png`)
                            if (!_activeLevel.timerDisabled)
                              Positioned(
                                right: ux(context, 57),
                                top: ux(context, 4),
                                child: _buildTimerGameplayView(context),
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
                      // Power-Up 1 (`LevelUp`, HUD slot follows `RemoteConfigService.boosterUnlockOrder`)
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
                            RemoteConfigService.boosterUnlockOrderNotifier,
                          ]),
                          builder: (context, _) {
                            final isFree =
                                widget.progress.isFreePowerUpPending(
                              MechanicUnlockInfo.levelUpPowerUp.id,
                            );
                            final offsetX = _boosterHudOffsetUnity(
                              MechanicUnlockInfo.levelUpPowerUp.id,
                            );
                            return Transform.translate(
                              offset: Offset(ux(context, offsetX), 0),
                              child: UnityPowerUpHudButton(
                                key: const ValueKey('hud_level_up_btn'),
                                boosterType: BoosterType.levelUp,
                                isLevelUp: true,
                                isUnlocked: _isLevelUpUnlocked,
                                unlockLevel:
                                    PlayerProgressService.levelUpUnlockLevel,
                                isFree: isFree,
                                count: widget.progress.levelUpCount,
                                isActionable:
                                    _game.canLevelUpNotifier.value,
                                isHighlighted: _activeBoosterArrowHint?.id ==
                                    MechanicUnlockInfo.levelUpPowerUp.id,
                                onTap: _handleLevelUpTap,
                              ),
                            );
                          },
                        ),
                      ),

                      // Power-Up 2 (`TimeFreeze`, HUD slot follows `RemoteConfigService.boosterUnlockOrder`)
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
                            RemoteConfigService.boosterUnlockOrderNotifier,
                          ]),
                          builder: (context, _) {
                            final isFree =
                                widget.progress.isFreePowerUpPending(
                              MechanicUnlockInfo.timeFreezePowerUp.id,
                            );
                            final offsetX = _boosterHudOffsetUnity(
                              MechanicUnlockInfo.timeFreezePowerUp.id,
                            );
                            return Transform.translate(
                              offset: Offset(ux(context, offsetX), 0),
                              child: UnityPowerUpHudButton(
                                key:
                                    const ValueKey('hud_time_freeze_btn'),
                                boosterType: BoosterType.timeFreeze,
                                isLevelUp: false,
                                isUnlocked: _isTimeFreezeUnlocked,
                                unlockLevel:
                                    PlayerProgressService.timeFreezeUnlockLevel,
                                isFree: isFree,
                                count: widget.progress.timeFreezeCount,
                                isActionable: _game.canUseTimeFreeze,
                                isHighlighted: _activeBoosterArrowHint?.id ==
                                    MechanicUnlockInfo.timeFreezePowerUp.id,
                                onTap: _handleTimeFreezeTap,
                              ),
                            );
                          },
                        ),
                      ),

                      // Power-Up 3 (`Shuffle`, HUD slot follows `RemoteConfigService.boosterUnlockOrder`)
                      Positioned(
                        bottom: safePadding.bottom +
                            ux(
                              context,
                              UnityPowerUpHudButton.bottomOffsetUnity,
                            ),
                        child: ListenableBuilder(
                          listenable: Listenable.merge([
                            widget.progress,
                            _game.canShuffleNotifier,
                            RemoteConfigService.boosterUnlockOrderNotifier,
                          ]),
                          builder: (context, _) {
                            final isFree =
                                widget.progress.isFreePowerUpPending(
                              MechanicUnlockInfo.shufflePowerUp.id,
                            );
                            final offsetX = _boosterHudOffsetUnity(
                              MechanicUnlockInfo.shufflePowerUp.id,
                            );
                            return Transform.translate(
                              offset: Offset(ux(context, offsetX), 0),
                              child: UnityPowerUpHudButton(
                                key: const ValueKey('hud_shuffle_btn'),
                                boosterType: BoosterType.shuffle,
                                isLevelUp: false,
                                isUnlocked: _isShuffleUnlocked,
                                unlockLevel:
                                    PlayerProgressService.shuffleUnlockLevel,
                                isFree: isFree,
                                count: widget.progress.shuffleCount,
                                isActionable:
                                    _game.canShuffleNotifier.value,
                                isHighlighted: _activeBoosterArrowHint?.id ==
                                    MechanicUnlockInfo.shufflePowerUp.id,
                                onTap: _handleShuffleTap,
                              ),
                            );
                          },
                        ),
                      ),

                      // Power-Up 4 (`Hammer`, HUD slot follows `RemoteConfigService.boosterUnlockOrder`)
                      Positioned(
                        bottom: safePadding.bottom +
                            ux(
                              context,
                              UnityPowerUpHudButton.bottomOffsetUnity,
                            ),
                        child: ListenableBuilder(
                          listenable: Listenable.merge([
                            widget.progress,
                            _game.canHammerNotifier,
                            _game.isHammerTargetingNotifier,
                            RemoteConfigService.boosterUnlockOrderNotifier,
                          ]),
                          builder: (context, _) {
                            final isFree =
                                widget.progress.isFreePowerUpPending(
                              MechanicUnlockInfo.hammerPowerUp.id,
                            );
                            final offsetX = _boosterHudOffsetUnity(
                              MechanicUnlockInfo.hammerPowerUp.id,
                            );
                            return Transform.translate(
                              offset: Offset(ux(context, offsetX), 0),
                              child: UnityPowerUpHudButton(
                                key: const ValueKey('hud_hammer_btn'),
                                boosterType: BoosterType.hammer,
                                isLevelUp: false,
                                isUnlocked: _isHammerUnlocked,
                                unlockLevel:
                                    PlayerProgressService.hammerUnlockLevel,
                                isFree: isFree,
                                count: widget.progress.hammerCount,
                                isActionable:
                                    _game.canHammerNotifier.value,
                                isHighlighted: _activeBoosterArrowHint?.id ==
                                    MechanicUnlockInfo.hammerPowerUp.id,
                                isActiveTargeting:
                                    _game.isHammerTargetingNotifier.value,
                                onTap: _handleHammerTap,
                              ),
                            );
                          },
                        ),
                      ),

                      if (_activeBoosterArrowHint != null &&
                          _activeMechanicModal == null &&
                          !_showWinOverlay &&
                          !_showLoseOverlay &&
                          _buyPopupBooster == null &&
                          !_settingsOpen &&
                          !_cheatOpen &&
                          !_showExitRestartPopup)
                        Positioned(
                          bottom: safePadding.bottom +
                              ux(
                                context,
                                UnityPowerUpHudButton.bottomOffsetUnity +
                                    UnityPowerUpHudButton.scaledUnitySize +
                                    14,
                              ),
                          child: PowerUpHudArrowHint(
                            key: const ValueKey('booster_hud_arrow_hint'),
                            horizontalOffsetUnity: _boosterHudOffsetUnity(
                              _activeBoosterArrowHint!.id,
                            ),
                          ),
                        ),

                      // Bottom-Right Settings Circle Button (`btn_setting.png`: `137x137`, `right = 58`, straddling golden footer trim)
                      Positioned(
                        right: ux(context, 58),
                        bottom: safePadding.bottom + ux(context, 91.5),
                        child: UnitySpriteButton(
                          key: const ValueKey('hud_settings_btn'),
                          onTap: _toggleSettingsPopup,
                          child: Image.asset(
                            'assets/images/UI Home/Home/btn_setting.png',
                            width: ux(context, 137),
                            height: ux(context, 137),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 6a. Floating Developer Cheat Button (positioned cleanly above Bottom-Right Settings when `cheat_enable == true`)
          if (!isTutorialLevel1)
            Positioned(
              right: ux(context, 28),
              bottom: safePadding.bottom + ux(context, 256),
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  RemoteConfigService.cheatEnableNotifier,
                  _game.isHammerTargetingNotifier,
                ]),
                builder: (context, _) {
                  if (!RemoteConfigService.cheatEnable ||
                      _hideCheatHudButton ||
                      _game.isHammerTargetingNotifier.value) {
                    return const SizedBox.shrink();
                  }
                  return CheatHudButton(
                    key: const ValueKey('hud_cheat_btn'),
                    onTap: () {
                      widget.audio.playClick();
                      setState(() {
                        _cheatOpen = true;
                        _settingsOpen = false;
                        _syncGamePauseState();
                      });
                    },
                  );
                },
              ),
            ),

          // 6b. Dramatic Non-Blocking Special Hard Level Intro Ribbon (2.3s fade-out)
          if (_activeLevel.isSpecial)
            Positioned(
              top: safePadding.top + ux(context, 236),
              left: ux(context, 48),
              right: ux(context, 48),
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _specialBannerOpacity,
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutCubic,
                  child: Center(
                    child: Container(
                      key: const ValueKey('special_hard_intro_banner'),
                      padding: EdgeInsets.symmetric(
                        horizontal: ux(context, 44),
                        vertical: ux(context, 20),
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xF57F1D1D),
                            Color(0xF5450A0A),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(ux(context, 36)),
                        border: Border.all(
                          color: const Color(0xFFFDE047),
                          width: ux(context, 4.5),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xAA000000),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.whatshot_rounded,
                                size: ux(context, 48),
                                color: const Color(0xFFFDE047),
                              ),
                              SizedBox(width: ux(context, 12)),
                              Text(
                                'SPECIAL LEVEL',
                                style: TextStyle(
                                  fontFamily: 'PoetsenOne',
                                  fontSize: ux(context, 46),
                                  color: const Color(0xFFFDE047),
                                  height: 1.05,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0xFF3B0816),
                                      blurRadius: 6,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: ux(context, 12)),
                              Icon(
                                Icons.whatshot_rounded,
                                size: ux(context, 48),
                                color: const Color(0xFFFDE047),
                              ),
                            ],
                          ),
                          SizedBox(height: ux(context, 4)),
                          Text(
                            'HARD CHALLENGE · WIN +$_currentWinCoinReward COINS',
                            style: TextStyle(
                              fontFamily: 'Baloo2',
                              fontSize: ux(context, 30),
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 6c. Interactive `Hammer` Targeting Mode Banner (non-blocking so player taps any obstacle directly!)
          ValueListenableBuilder<bool>(
            valueListenable: _game.isHammerTargetingNotifier,
            builder: (context, targeting, _) {
              if (!targeting) return const SizedBox.shrink();
              return Positioned(
                left: ux(context, 48),
                right: ux(context, 48),
                bottom: safePadding.bottom + ux(context, 266),
                child: Center(
                  child: Container(
                    key: const ValueKey('hammer_targeting_banner'),
                    padding: EdgeInsets.symmetric(
                      horizontal: ux(context, 28),
                      vertical: ux(context, 16),
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xF53B1D7A),
                          Color(0xF51D1048),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(ux(context, 42)),
                      border: Border.all(
                        color: const Color(0xFFFFCA28),
                        width: ux(context, 5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.48),
                          blurRadius: ux(context, 20),
                          offset: Offset(0, ux(context, 8)),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BoosterIconWidget(
                          type: BoosterType.hammer,
                          size: ux(context, 54),
                        ),
                        SizedBox(width: ux(context, 14)),
                        Flexible(
                          child: Text(
                            'Tap a block to split in half!',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Baloo2',
                              fontSize: ux(context, 38),
                              fontWeight: FontWeight.w800,
                              fontVariations: const [
                                FontVariation('wght', 800),
                              ],
                              color: Colors.white,
                              height: 1.05,
                            ),
                          ),
                        ),
                        SizedBox(width: ux(context, 18)),
                        GestureDetector(
                          key: const ValueKey('hammer_targeting_cancel_btn'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            widget.audio.playClick();
                            _game.cancelHammerTargeting();
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ux(context, 22),
                              vertical: ux(context, 10),
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFFFF6B6B),
                                  Color(0xFFD32F2F),
                                ],
                              ),
                              borderRadius:
                                  BorderRadius.circular(ux(context, 26)),
                              border: Border.all(
                                color: const Color(0xFFFFE082),
                                width: ux(context, 3),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontFamily: 'Baloo2',
                                fontSize: ux(context, 32),
                                fontWeight: FontWeight.w800,
                                fontVariations: const [
                                  FontVariation('wght', 800),
                                ],
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
            },
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

          // 7b. Flying & Spinning `PowerUp_Shuffle.png` + Gentle Full-Screen Ripple Mist FX
          AnimatedBuilder(
            animation: _shuffleFlyCtrl,
            builder: (context, _) {
              if (!_shuffleFlyCtrl.isAnimating && _shuffleFlyCtrl.value == 0.0) {
                return const SizedBox.shrink();
              }
              return _buildShuffleFlightFx(context, _shuffleFlyCtrl.value);
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
                      if (!targetLv.isBonus) {
                        widget.progress.cheatSyncVaseToLevel(targetLv.number);
                      }
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
              willLoseLife: _game.hasPlayerInteracted &&
                  !widget.progress.isInfinityLives(),
              onConfirmRestart: _handleConfirmExitRestart,
              onCancel: () {
                widget.audio.playClick();
                setState(() {
                  _showExitRestartPopup = false;
                  _syncGamePauseState();
                });
              },
            ),

          // 10. `PowerUpBuyView.prefab` (`x3` Coin Pack / `Watch` Ad `x1` for all 4 boosters)
          if (_buyPopupBooster != null)
            ListenableBuilder(
              listenable: widget.progress,
              builder: (context, _) {
                final type = _buyPopupBooster!;
                final packCost = RemoteConfigService.priceForBooster(type);
                final placementName = switch (type) {
                  BoosterType.levelUp => 'booster_levelup',
                  BoosterType.timeFreeze => 'booster_timefreeze',
                  BoosterType.shuffle => 'booster_shuffle',
                  BoosterType.hammer => 'booster_hammer',
                };
                return PowerUpBuyPopup(
                  boosterType: type,
                  isLevelUp: type == BoosterType.levelUp,
                  playerCoins: widget.progress.coins,
                  packCost: packCost,
                  onInsufficientCoins: _handleInsufficientCoins,
                  onBuyPack: () {
                    if (widget.progress.buyPowerUpPack(
                      boosterType: type,
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
                        name: type.analyticsName,
                        amount: 3,
                        reason: 'buy_pack',
                        balance: widget.progress.boosterCount(type).toDouble(),
                      );
                      setState(() {
                        _buyPopupBooster = null;
                        _syncGamePauseState();
                      });
                    } else {
                      _handleInsufficientCoins();
                    }
                  },
                  onWatchAd: () {
                    AdsManager.showRewardedAd(
                      placement: placementName,
                      levelNumber: _activeLevel.number,
                      onAdFailed: _handleRewardedAdFailed,
                      onRewardResult: (success) {
                        if (success && mounted) {
                          widget.audio.playCoinCollect();
                          widget.progress.grantFreePowerUp(
                            boosterType: type,
                            count: 1,
                          );
                          AnalyticsService.logEarnResource(
                            level: _activeLevel.number,
                            type: 'booster',
                            name: type.analyticsName,
                            amount: 1,
                            reason: 'rewarded_ad',
                            balance:
                                widget.progress.boosterCount(type).toDouble(),
                          );
                          setState(() {
                            _buyPopupBooster = null;
                            _syncGamePauseState();
                          });
                        }
                      },
                    );
                  },
                  onClose: () {
                    widget.audio.playClick();
                    setState(() {
                      _buyPopupBooster = null;
                      _syncGamePauseState();
                    });
                  },
                );
              },
            ),

          // 11. Unlock Overlays:
          //     - Boosters (`isPowerUp == true`): `PowerUpFreeUnlockOverlay` granting 1 FREE turn
          //       (tap highlighted FREE booster to use immediately; tap outside to dismiss & keep FREE on HUD)
          //     - Mechanics (`isPowerUp == false`): `MechanicUnlockDialog` (`New Mechanic` + `Next Level`)
          if (_activeMechanicModal != null)
            if (_activeMechanicModal!.isPowerUp)
              PowerUpFreeUnlockOverlay(
                key: ValueKey('ftue_${_activeMechanicModal!.id}'),
                info: _activeMechanicModal!,
                currentCount: widget.progress
                    .powerUpCountById(_activeMechanicModal!.id),
                hudHorizontalOffsetUnity:
                    _boosterHudOffsetUnity(_activeMechanicModal!.id),
                onUseFreePowerUp: () =>
                    _handleActivatePowerUpFromUnlockOverlay(
                      _activeMechanicModal!,
                    ),
                onDismissOutside: _dismissBoosterUnlockKeepFree,
              )
            else
              MechanicUnlockDialog(
                key: ValueKey('ftue_${_activeMechanicModal!.id}'),
                info: _activeMechanicModal!,
                onClaim: _dismissMechanicUnlockModal,
                onNextLevel: _dismissMechanicUnlockModal,
                onClose: _dismissMechanicUnlockModal,
                onDismiss: _dismissMechanicUnlockModal,
              ),

          // 12. Two-Stage `WinGameplayView.prefab` (`Level complete!` -> `AMAZING!` + Coin Flight or Garden Metagame)
          if (_showWinOverlay)
            WinOverlay(
              levelNumber: _activeLevel.number,
              levelLabel: _activeLevel.title,
              rewardCoins: _currentWinCoinReward,
              showRewardX2: widget.progress
                  .isWinRewardX2UnlockedForLevel(_activeLevel.number),
              timeFormatted: _game.elapsedTimeFormatted,
              movesCount: _game.movesCount,
              comboCount: _game.highestCombo,
              gardenResult: _activeVaseAdvanceResult,
              finalBlockNumber: _activeLevel.targetWinNumber,
              audio: widget.audio,
              onClaimMilestone: () {
                widget.progress.claimCurrentVaseMilestone();
                widget.audio.playCoinCollect();
                _coinBounceCtrl.forward(from: 0.0);
              },
              onStageMilestoneClaim: () {
                widget.audio.playClick();
                final amount = widget.progress.stageCurrentVaseMilestoneClaim();
                if (amount > 0) {
                  AnalyticsService.logEarnResource(
                    level: _activeLevel.number,
                    type: 'currency',
                    name: 'coins',
                    amount: amount.toDouble(),
                    reason: 'flower_bloom_reward',
                    balance: (widget.progress.coins + amount).toDouble(),
                  );
                }
                return amount;
              },
              onWatchMilestoneRewardX2: _handleMilestoneRewardX2Ad,
              onBloomCongratsShown: () {
                AnalyticsService.logPopupShow(
                  name: 'flower_bloom_congrats',
                  level: _activeLevel.number,
                );
              },
              onMilestoneCoinChunkArrived: (chunk) {
                widget.progress.collectPendingMilestoneCoinChunk(chunk);
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
                  startInFailedStage: _loseInFailedStage,
                  onPlayOnCoins: _handlePlayOnCoins,
                  onInsufficientCoins: _handleInsufficientCoins,
                  onPlayOnAd: _handlePlayOnAd,
                  onEnterFailedStage: _handleEnterFailedStage,
                  onCloseToHome: _handleCloseLoseFailedToHome,
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

          // 13b. `More Lives?` Popup when Heart == 0
          if (_showMoreLivesModal)
            MoreLivesDialog(
              progress: widget.progress,
              onWatchAdForOneLife: _handleMoreLivesWatchAd,
              onRefillWithCoins: _handleMoreLivesRefillCoins,
              onInsufficientCoins: _handleInsufficientCoins,
              onLifeRecovered: _completePendingMoreLivesRetry,
              onClose: _handleCloseMoreLives,
            ),

          // 14. Elevated Top-Left `CoinsWidget` (`overrideSorting: true` during `WinGameplayView`, `LoseOverlay`, & `MoreLivesDialog`)
          if (_showWinOverlay || _showLoseOverlay || _showMoreLivesModal)
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

          // 14b. Smooth non-blocking crossfade veil bridging Win/Lose/Retry into new board settle
          AnimatedBuilder(
            animation: _levelTransitionCtrl,
            builder: (context, _) {
              final v = _levelTransitionCtrl.value;
              if (v <= 0.005) return const SizedBox.shrink();
              final alpha =
                  (Curves.easeOutCubic.transform(v) * 0.90).clamp(0.0, 1.0);
              return Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    key: const ValueKey('level_transition_veil'),
                    color: Color.fromRGBO(12, 8, 34, alpha),
                  ),
                ),
              );
            },
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
                            child: ClipRect(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                widthFactor: clamped,
                                child: SizedBox(
                                  width: maxFillW,
                                  height: fillH,
                                  child: const UnityNineSlice(
                                    sprite: 'progress_combo_fg.png',
                                  ),
                                ),
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
              final popBegin = 1.04 + 0.015 * comboCount.clamp(1, 5);
              barBody = TweenAnimationBuilder<double>(
                key: ValueKey('combo_bar_pop_$comboCount'),
                tween: Tween<double>(begin: popBegin, end: 1.0),
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
          ux(
            context,
            _boosterHudOffsetUnity(MechanicUnlockInfo.timeFreezePowerUp.id),
          ),
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

  /// Flying & spinning `PowerUp_Shuffle.png` from bottom Shuffle HUD button to screen center
  /// paired with a light, dreamy full-screen spreading mist & soft pastel ripple wave.
  Widget _buildShuffleFlightFx(BuildContext context, double t) {
    final screen = MediaQuery.sizeOf(context);
    final start = _boosterHudCenterScreen(
      context,
      MechanicUnlockInfo.shufflePowerUp.id,
    );
    final center = Offset(screen.width * 0.5, screen.height * 0.46);

    // Stage 1 (`0.00 -> 0.30`): Fly smoothly up from HUD button to center
    final flyT = (t / 0.30).clamp(0.0, 1.0);
    final flyEased = Curves.easeOutCubic.transform(flyT);
    final ctrl = Offset(
      start.dx + (center.dx - start.dx) * 0.35 + ux(context, 70),
      center.dy + (start.dy - center.dy) * 0.42,
    );
    final om = 1.0 - flyEased;
    final px = om * om * start.dx +
        2 * om * flyEased * ctrl.dx +
        flyEased * flyEased * center.dx;
    final py = om * om * start.dy +
        2 * om * flyEased * ctrl.dy +
        flyEased * flyEased * center.dy;

    // Spin smoothly ~2 full clockwise turns across the flight & peak dwell
    final spinEase = Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
    final rotationRad = spinEase * math.pi * 4.0;

    // Scale: pop up smoothly from HUD -> juicy float at center -> soft shrink out
    double scale;
    double logoAlpha = 1.0;
    if (t < 0.30) {
      scale = 0.58 + 0.96 * flyEased;
    } else if (t < 0.72) {
      final dwellT = ((t - 0.30) / 0.42).clamp(0.0, 1.0);
      scale = 1.54 + 0.16 * math.sin(dwellT * math.pi);
    } else {
      final outT = ((t - 0.72) / 0.28).clamp(0.0, 1.0);
      final outEase = Curves.easeInCubic.transform(outT);
      scale = 1.54 - 0.96 * outEase;
      logoAlpha = (1.0 - outEase).clamp(0.0, 1.0);
    }

    // Soft spreading wave starts right as the logo arrives at center (`t >= 0.24`)
    final waveT = ((t - 0.24) / 0.76).clamp(0.0, 1.0);
    final iconBasePx = ux(context, 168);

    return IgnorePointer(
      child: Stack(
        children: [
          if (waveT > 0.0)
            Positioned.fill(
              child: CustomPaint(
                key: const ValueKey('shuffle_screen_wave_fx'),
                painter: _ShuffleScreenWavePainter(
                  center: center,
                  progress: waveT,
                  spinRad: rotationRad * 0.35,
                ),
              ),
            ),
          if (logoAlpha > 0.01)
            Positioned(
              left: px - iconBasePx * 0.5,
              top: py - iconBasePx * 0.5,
              child: Opacity(
                opacity: logoAlpha,
                child: Transform.rotate(
                  angle: rotationRad,
                  child: Transform.scale(
                    scale: scale,
                    child: Image.asset(
                      'assets/images/PowerUp_Shuffle.png',
                      key: const ValueKey('shuffle_flying_logo'),
                      width: iconBasePx,
                      height: iconBasePx,
                      fit: BoxFit.contain,
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
  ///   `"Restart"` `Button_CTA.png` (`499x221`), and `'v.1.0.0'` version label.
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

                                      // Action CTAs: Left Red `Quit` + Right Green `Restart`
                                      Positioned(
                                        top: ux(context, 344),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _SettingsAssetActionButton(
                                              key: const ValueKey(
                                                'settings_quit_btn',
                                              ),
                                              assetPath:
                                                  'assets/images/UI Home/btn_red_setting.png',
                                              label: 'Quit',
                                              textMaterial:
                                                  UnityTextMaterial.ctaRed,
                                              onTap: _handleQuitFromSettings,
                                            ),
                                            SizedBox(width: ux(context, 24)),
                                            _SettingsAssetActionButton(
                                              key: const ValueKey(
                                                'settings_restart_btn',
                                              ),
                                              assetPath:
                                                  'assets/images/UI Home/btn_green_setting 2.png',
                                              label: 'Restart',
                                              textMaterial:
                                                  UnityTextMaterial.ctaGreen,
                                              onTap:
                                                  _handleRequestReplayFromSettings,
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Bottom Version Text (auto-detected from app version — also acts as secret Cheat Panel trigger when `cheat_enable == true`)
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
                                          child: ValueListenableBuilder<String>(
                                            valueListenable: AppVersionService
                                                .versionNotifier,
                                            builder: (context, _, _) => Text(
                                              AppVersionService.displayLabel,
                                              key: const ValueKey(
                                                'gameplay_settings_version_text',
                                              ),
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

    // 2. Smooth 4-edge gradient vignette glow without full-screen MaskFilter.blur
    final shortest = math.min(w, h);
    final bandW = shortest * 0.11;
    const edgeColors = [
      Color(0x88FF1632),
      Color(0x36FF1A36),
      Color(0x00FF1E38),
    ];
    const edgeStops = [0.0, 0.42, 1.0];

    final topRect = Rect.fromLTWH(0, 0, w, bandW);
    canvas.drawRect(
      topRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: edgeColors,
          stops: edgeStops,
        ).createShader(topRect),
    );
    final botRect = Rect.fromLTWH(0, h - bandW, w, bandW);
    canvas.drawRect(
      botRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: edgeColors,
          stops: edgeStops,
        ).createShader(botRect),
    );
    final leftRect = Rect.fromLTWH(0, 0, bandW, h);
    canvas.drawRect(
      leftRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: edgeColors,
          stops: edgeStops,
        ).createShader(leftRect),
    );
    final rightRect = Rect.fromLTWH(w - bandW, 0, bandW, h);
    canvas.drawRect(
      rightRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
          colors: edgeColors,
          stops: edgeStops,
        ).createShader(rightRect),
    );
  }

  @override
  bool shouldRepaint(covariant _LowTimeRedVignettePainter oldDelegate) => false;
}

class _TimeFreezeFadeAnimation extends Animation<double> {
  final ValueNotifier<double> _source;

  _TimeFreezeFadeAnimation(this._source);

  @override
  void addListener(VoidCallback listener) => _source.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _source.removeListener(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) {}

  @override
  void removeStatusListener(AnimationStatusListener listener) {}

  @override
  AnimationStatus get status => _source.value > 0.05
      ? AnimationStatus.forward
      : AnimationStatus.dismissed;

  @override
  double get value {
    final v = _source.value;
    if (v <= 0.05) return 0.0;
    if (v >= 2.5) return 1.0;
    return (v / 2.5).clamp(0.0, 1.0);
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

class _SettingsAssetActionButton extends StatefulWidget {
  final String assetPath;
  final String label;
  final UnityTextMaterial textMaterial;
  final VoidCallback onTap;

  const _SettingsAssetActionButton({
    super.key,
    required this.assetPath,
    required this.label,
    required this.textMaterial,
    required this.onTap,
  });

  @override
  State<_SettingsAssetActionButton> createState() =>
      _SettingsAssetActionButtonState();
}

class _SettingsAssetActionButtonState
    extends State<_SettingsAssetActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final w = ux(context, 312);
    final h = ux(context, 175);

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
          width: w,
          height: h,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.asset(
                widget.assetPath,
                width: w,
                height: h,
                fit: BoxFit.contain,
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: ux(context, 24),
                  right: ux(context, 24),
                  bottom: ux(context, 10),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: UnitySdfText(
                    widget.label,
                    unityFontSize: 60,
                    material: widget.textMaterial,
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

/// Delicate, airy full-screen spreading mist & pastel concentric ripple FX behind
/// the spinning `PowerUp_Shuffle.png` emblem (intentionally subtle & non-glaring).
class _ShuffleScreenWavePainter extends CustomPainter {
  final Offset center;
  final double progress;
  final double spinRad;

  const _ShuffleScreenWavePainter({
    required this.center,
    required this.progress,
    required this.spinRad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.clamp(0.0, 1.0);
    if (t <= 0.0 || t >= 1.0) return;

    final maxR = math.sqrt(size.width * size.width + size.height * size.height) * 0.72;
    final expand = Curves.easeOutCubic.transform(t);
    final envelope = t < 0.22
        ? Curves.easeOut.transform(t / 0.22)
        : (1.0 - Curves.easeInQuad.transform(((t - 0.22) / 0.78).clamp(0.0, 1.0)));

    // 1. Light full-screen luminous mist wash spreading outward from center
    final mistR = maxR * (0.18 + 0.96 * expand);
    final mistRect = Rect.fromCircle(center: center, radius: mistR);
    canvas.drawCircle(
      center,
      mistR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF6D6).withValues(alpha: 0.22 * envelope),
            const Color(0xFFA5F3FC).withValues(alpha: 0.14 * envelope),
            const Color(0xFFFFE4A0).withValues(alpha: 0.07 * envelope),
            const Color(0x00FFFFFF),
          ],
          stops: const [0.0, 0.42, 0.78, 1.0],
        ).createShader(mistRect),
    );

    // 2. Soft rotating 8-petal warm-gold aura right behind the spinning Shuffle icon
    if (t < 0.75) {
      final auraFade = (1.0 - (t / 0.75)).clamp(0.0, 1.0);
      final auraAlpha = (envelope * auraFade * 0.24).clamp(0.0, 1.0);
      final rayR = math.min(size.width, size.height) * (0.20 + 0.26 * expand);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(spinRad);
      final rayPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF3B0).withValues(alpha: auraAlpha),
            const Color(0x00FFF3B0),
          ],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: rayR));
      for (int i = 0; i < 8; i++) {
        canvas.save();
        canvas.rotate(i * (math.pi / 4.0));
        final petal = Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(-rayR * 0.16, -rayR * 0.52, 0, -rayR)
          ..quadraticBezierTo(rayR * 0.16, -rayR * 0.52, 0, 0)
          ..close();
        canvas.drawPath(petal, rayPaint);
        canvas.restore();
      }
      canvas.restore();
    }

    // 3. Primary & secondary delicate expanding ripple rings covering the whole screen
    final ring1R = maxR * (0.10 + 0.96 * expand);
    final ring1Alpha = (0.34 * envelope).clamp(0.0, 1.0);
    canvas.drawCircle(
      center,
      ring1R,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (18.0 * (1.0 - t * 0.55)).clamp(4.0, 18.0)
        ..color = const Color(0xFFFFEEAD).withValues(alpha: ring1Alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0),
    );

    final ring2T = ((t - 0.10) / 0.90).clamp(0.0, 1.0);
    if (ring2T > 0.0) {
      final ring2Expand = Curves.easeOutCubic.transform(ring2T);
      final ring2R = maxR * (0.06 + 0.92 * ring2Expand);
      final ring2Alpha = (0.26 * (1.0 - ring2T)).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        ring2R,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (10.0 * (1.0 - ring2T * 0.5)).clamp(2.5, 10.0)
          ..color = const Color(0xFF99F6FF).withValues(alpha: ring2Alpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
      );
    }

    // 4. 14 tiny delicate glints drifting gently outward along the soft wave
    const glintCount = 14;
    for (int i = 0; i < glintCount; i++) {
      final angle = (i / glintCount) * math.pi * 2.0 + spinRad * 0.45 + (i.isEven ? 0.14 : -0.10);
      final radialScale = 0.24 + (i % 3) * 0.18 + expand * (0.58 + (i % 4) * 0.10);
      final dist = maxR * 0.85 * radialScale;
      final pt = Offset(
        center.dx + math.cos(angle) * dist,
        center.dy + math.sin(angle) * dist,
      );
      final starR = (5.0 + (i % 3) * 2.5) * (0.7 + 0.3 * envelope);
      final starAlpha = (0.48 * envelope).clamp(0.0, 1.0);
      final p = Path()
        ..moveTo(pt.dx, pt.dy - starR)
        ..quadraticBezierTo(pt.dx + starR * 0.20, pt.dy - starR * 0.20, pt.dx + starR, pt.dy)
        ..quadraticBezierTo(pt.dx + starR * 0.20, pt.dy + starR * 0.20, pt.dx, pt.dy + starR)
        ..quadraticBezierTo(pt.dx - starR * 0.20, pt.dy + starR * 0.20, pt.dx - starR, pt.dy)
        ..quadraticBezierTo(pt.dx - starR * 0.20, pt.dy - starR * 0.20, pt.dx, pt.dy - starR)
        ..close();
      canvas.drawPath(
        p,
        Paint()
          ..color = (i.isEven ? const Color(0xFFFFF7CC) : const Color(0xFFCFFAFE))
              .withValues(alpha: starAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ShuffleScreenWavePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.spinRad != spinRad ||
      oldDelegate.center != center;
}

