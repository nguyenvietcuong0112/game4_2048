import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'remote_config_service.dart';

class PlayerProgressService extends ChangeNotifier {
  static const _kCurrentLevel = 'bo_current_level';
  static const _kHighestLevel = 'bo_highest_level';
  static const _kCoins = 'bo_coins';
  static const _kLives = 'bo_lives';
  static const _kLastLifeRegenMs = 'bo_last_life_regen_ms';
  static const _kInfinityExpireMs = 'bo_infinity_expire_ms';
  static const _kMaxHearts = 'bo_max_hearts';
  static const _kLevelUpCount = 'bo_pu_level_up';
  static const _kTimeFreezeCount = 'bo_pu_time_freeze';
  static const _kShuffleCount = 'bo_pu_shuffle';
  static const _kHammerCount = 'bo_pu_hammer';
  static const _kSeenMechanics = 'bo_seen_mechanics';
  static const _kFreePowerUpsPending = 'bo_free_pu_pending';
  static const _kFtueLoadingLogged = 'bo_ftue_loading_logged';
  static const _kFtueCompleted = 'bo_ftue_completed';
  static const _kVaseCurrentId = 'bo_vase_current_id';
  static const _kVaseStepCount = 'bo_vase_step_count';
  static const _kVaseClaimedIds = 'bo_vase_claimed_ids';
  static const _kVaseUnlockedIds = 'bo_vase_unlocked_ids';
  static const _kNoAdsPurchased = 'bo_no_ads_purchased';
  static const _kPurchasedPackIds = 'bo_purchased_pack_ids';
  static const _kJourneyUnlockedSeen = 'bo_journey_unlocked_seen';
  static const _kPendingJourneyShowcase = 'bo_pending_journey_showcase';
  static const _kClaimedJourneyLevels = 'bo_claimed_journey_levels';
  static const _kSelectedJourneyBgId = 'bo_selected_journey_bg_id';

  static const int journeyUnlockLevel = 20;
  static const int maxLives = 5;
  static const int lifeRegenSeconds = 15 * 60; // 1 Heart per 15 minutes (900s)
  static const int refillLivesCost = 900;

  /// Power-up progression & economy settings (unlock order/levels driven by
  /// `RemoteConfigService.boosterUnlockOrder`):
  static const int winRewardX2UnlockLevel = 7;
  static int get levelUpUnlockLevel =>
      RemoteConfigService.boosterLevelUpUnlockLevel;
  static int get timeFreezeUnlockLevel =>
      RemoteConfigService.boosterTimeFreezeUnlockLevel;
  static int get shuffleUnlockLevel =>
      RemoteConfigService.boosterShuffleUnlockLevel;
  static int get hammerUnlockLevel =>
      RemoteConfigService.boosterHammerUnlockLevel;
  static const int levelUpPackCost = 600;
  static const int timeFreezePackCost = 450;
  static const int shufflePackCost = 450;
  static const int hammerPackCost = 550;
  static const int initialPowerUpInventory = 3;

  SharedPreferences? _prefs;

  int _currentLevel = 1;
  int _highestLevel = 1;
  int _coins = 875;
  int _maxLives = maxLives;
  int _lives = maxLives;
  int? _lastLifeRegenMs;
  int? _infinityExpireMs;
  int _levelUpCount = initialPowerUpInventory;
  int _timeFreezeCount = initialPowerUpInventory;
  int _shuffleCount = initialPowerUpInventory;
  int _hammerCount = initialPowerUpInventory;
  int _pendingWinCoins = 0;
  int _pendingMilestoneCoins = 0;
  Set<String> _seenMechanics = {};
  Set<String> _freePowerUpsPending = {};
  bool _ftueLoadingLogged = false;
  bool _ftueCompleted = false;

  int _vaseCurrentId = 1;
  int _vaseStepCount = 0;
  Set<int> _vaseClaimedIds = {};
  Set<int> _vaseUnlockedIds = {};

  bool _noAdsPurchased = false;
  Set<String> _purchasedPackIds = {};
  bool _journeyUnlockedSeen = false;
  bool _pendingJourneyUnlockShowcase = false;
  Set<int> _claimedJourneyLevels = {};
  int _selectedJourneyBgId = 0;

  int get currentLevel => _currentLevel;
  int get highestLevel => _highestLevel;
  int get coins => _coins;
  int get currentMaxLives => _maxLives;
  int get lives => _lives;
  int? get lastLifeRegenMs => _lastLifeRegenMs;
  int? get infinityExpireMs => _infinityExpireMs;
  bool get isHeartsMax => _lives >= _maxLives;
  int get levelUpCount => _levelUpCount;
  int get timeFreezeCount => _timeFreezeCount;
  int get shuffleCount => _shuffleCount;
  int get hammerCount => _hammerCount;
  int get pendingWinCoins => _pendingWinCoins;
  int get pendingMilestoneCoins => _pendingMilestoneCoins;
  bool get isFtueCompleted => _ftueCompleted;

  int get vaseCurrentId => _vaseCurrentId;
  int get vaseStepCount => _vaseStepCount;
  VaseMilestoneConfig get currentVaseConfig =>
      VaseMilestoneConfig.getForVaseId(_vaseCurrentId);
  double get currentVaseProgress =>
      (_vaseStepCount / currentVaseConfig.totalSteps).clamp(0.0, 1.0);
  bool get isCurrentVaseReadyToClaim =>
      _vaseStepCount >= currentVaseConfig.totalSteps &&
      !_vaseClaimedIds.contains(_vaseCurrentId);
  bool hasClaimedVase(int id) => _vaseClaimedIds.contains(id);
  bool isVaseUnlocked(int id) => _vaseUnlockedIds.contains(id);

  bool get noAdsPurchased => _noAdsPurchased;
  bool hasPurchasedPack(String productId) =>
      _purchasedPackIds.contains(productId);
  bool get isJourneyUnlocked =>
      _highestLevel > journeyUnlockLevel || _journeyUnlockedSeen;
  bool get journeyUnlockedSeen => _journeyUnlockedSeen;
  bool get pendingJourneyUnlockShowcase => _pendingJourneyUnlockShowcase;
  Set<int> get claimedJourneyLevels => Set.unmodifiable(_claimedJourneyLevels);
  int get selectedJourneyBgId => _selectedJourneyBgId;
  JourneyBgTheme get selectedJourneyBgTheme =>
      JourneyBgTheme.byId(_selectedJourneyBgId);

  /// Whether a milestone at [unlockLevel] has been reached by completing it.
  bool isJourneyMilestoneUnlocked(int unlockLevel) =>
      unlockLevel <= 1 || _highestLevel > unlockLevel;

  bool hasClaimedJourneyMilestone(int unlockLevel) =>
      _claimedJourneyLevels.contains(unlockLevel);

  bool isJourneyBgUnlocked(int bgId) {
    if (bgId <= 0) return true;
    final milestone = JourneyMilestoneConfig.forBgId(bgId);
    if (milestone == null) return false;
    return hasClaimedJourneyMilestone(milestone.levelUnlock);
  }

  /// True when at least one Journey milestone is unlocked & waiting to be claimed.
  bool get hasClaimableJourneyReward {
    if (!isJourneyUnlocked) return false;
    for (final m in JourneyMilestoneConfig.schedule) {
      if (isJourneyMilestoneUnlocked(m.levelUnlock) &&
          !hasClaimedJourneyMilestone(m.levelUnlock)) {
        return true;
      }
    }
    return false;
  }

  /// Exact `PowerUpService.IsUnlockLevelReached(type)` checked against active campaign level
  /// (`levelNumber >= 17` for `LevelUp`, `levelNumber >= 27` for `TimeFreeze`).
  bool isWinRewardX2UnlockedForLevel(int levelNumber) {
    final effective = levelNumber >= 1000 ? _highestLevel : levelNumber;
    return effective >= winRewardX2UnlockLevel;
  }

  bool isLevelUpUnlockedForLevel(int levelNumber) {
    final effective = levelNumber >= 1000 ? _highestLevel : levelNumber;
    return effective >= levelUpUnlockLevel;
  }

  bool isTimeFreezeUnlockedForLevel(int levelNumber) {
    final effective = levelNumber >= 1000 ? _highestLevel : levelNumber;
    return effective >= timeFreezeUnlockLevel;
  }

  bool isShuffleUnlockedForLevel(int levelNumber) {
    final effective = levelNumber >= 1000 ? _highestLevel : levelNumber;
    return effective >= shuffleUnlockLevel;
  }

  bool isHammerUnlockedForLevel(int levelNumber) {
    final effective = levelNumber >= 1000 ? _highestLevel : levelNumber;
    return effective >= hammerUnlockLevel;
  }

  bool isBoosterUnlockedForLevel(BoosterType type, int levelNumber) =>
      switch (type) {
        BoosterType.levelUp => isLevelUpUnlockedForLevel(levelNumber),
        BoosterType.timeFreeze => isTimeFreezeUnlockedForLevel(levelNumber),
        BoosterType.shuffle => isShuffleUnlockedForLevel(levelNumber),
        BoosterType.hammer => isHammerUnlockedForLevel(levelNumber),
      };

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _currentLevel = _prefs?.getInt(_kCurrentLevel) ?? 1;
    _highestLevel = _prefs?.getInt(_kHighestLevel) ?? _currentLevel;
    if (_highestLevel < _currentLevel && _currentLevel < 1000) {
      _highestLevel = _currentLevel;
    }
    _coins = _prefs?.getInt(_kCoins) ?? 875;
    _maxLives = math.max(1, _prefs?.getInt(_kMaxHearts) ?? maxLives);
    _lives = math.max(0, _prefs?.getInt(_kLives) ?? _maxLives);
    _lastLifeRegenMs = _prefs?.getInt(_kLastLifeRegenMs);
    _infinityExpireMs = _prefs?.getInt(_kInfinityExpireMs);
    _levelUpCount =
        _prefs?.getInt(_kLevelUpCount) ?? initialPowerUpInventory;
    _timeFreezeCount =
        _prefs?.getInt(_kTimeFreezeCount) ?? initialPowerUpInventory;
    _shuffleCount =
        _prefs?.getInt(_kShuffleCount) ?? initialPowerUpInventory;
    _hammerCount =
        _prefs?.getInt(_kHammerCount) ?? initialPowerUpInventory;
    _seenMechanics = (_prefs?.getStringList(_kSeenMechanics) ?? []).toSet();
    _freePowerUpsPending =
        (_prefs?.getStringList(_kFreePowerUpsPending) ?? []).toSet();
    _ftueCompleted =
        (_prefs?.getBool(_kFtueCompleted) ?? false) || _highestLevel > 1;
    _ftueLoadingLogged =
        (_prefs?.getBool(_kFtueLoadingLogged) ?? false) || _ftueCompleted;
    final savedVaseId = _prefs?.getInt(_kVaseCurrentId);
    _vaseCurrentId = savedVaseId ?? VaseMilestoneConfig.determineInitialVaseId(_highestLevel);
    _vaseStepCount = _prefs?.getInt(_kVaseStepCount) ?? 0;
    _vaseClaimedIds = (_prefs?.getStringList(_kVaseClaimedIds) ?? [])
        .map((s) => int.tryParse(s) ?? 0)
        .where((id) => id > 0)
        .toSet();
    _vaseUnlockedIds = (_prefs?.getStringList(_kVaseUnlockedIds) ?? [])
        .map((s) => int.tryParse(s) ?? 0)
        .where((id) => id > 0)
        .toSet();
    _noAdsPurchased = _prefs?.getBool(_kNoAdsPurchased) ?? false;
    _purchasedPackIds =
        (_prefs?.getStringList(_kPurchasedPackIds) ?? []).toSet();
    _journeyUnlockedSeen =
        (_prefs?.getBool(_kJourneyUnlockedSeen) ?? false) ||
            _highestLevel > journeyUnlockLevel;
    _pendingJourneyUnlockShowcase =
        _prefs?.getBool(_kPendingJourneyShowcase) ?? false;
    _claimedJourneyLevels =
        (_prefs?.getStringList(_kClaimedJourneyLevels) ?? [])
            .map((s) => int.tryParse(s) ?? 0)
            .where((lv) => lv > 0)
            .toSet();
    _selectedJourneyBgId =
        (_prefs?.getInt(_kSelectedJourneyBgId) ?? 0).clamp(0, 3);
    syncLivesRegen();
    notifyListeners();
  }

  /// Marks first-time boot loading (`ftue_loading_start` / `ftue_loading_finish`) as claimed
  /// and returns `true` iff this session is the player's FTUE splash load.
  bool consumeFtueLoadingIfPending() {
    if (_ftueCompleted ||
        _ftueLoadingLogged ||
        _currentLevel != 1 ||
        _highestLevel > 1) {
      return false;
    }
    _ftueLoadingLogged = true;
    _prefs?.setBool(_kFtueLoadingLogged, true);
    return true;
  }

  /// Marks Level 1 FTUE tutorial completed so `tut_action` does not re-fire on later sessions.
  void markFtueCompleted() {
    if (_ftueCompleted) return;
    _ftueCompleted = true;
    _ftueLoadingLogged = true;
    _prefs?.setBool(_kFtueCompleted, true);
    _prefs?.setBool(_kFtueLoadingLogged, true);
    notifyListeners();
  }

  bool hasSeenMechanic(String id) => _seenMechanics.contains(id);

  void markMechanicSeen(String id) {
    if (_seenMechanics.add(id)) {
      _prefs?.setStringList(_kSeenMechanics, _seenMechanics.toList());
      notifyListeners();
    }
  }

  bool isFreePowerUpPending(String id) => _freePowerUpsPending.contains(id);

  void setFreePowerUpPending(String id, bool pending) {
    final changed = pending
        ? _freePowerUpsPending.add(id)
        : _freePowerUpsPending.remove(id);
    if (changed) {
      _prefs?.setStringList(
        _kFreePowerUpsPending,
        _freePowerUpsPending.toList(),
      );
      notifyListeners();
    }
  }

  /// Consumes the free FTUE trial usage (`PowerUpService.ConsumeFreeUsage`) without
  /// decrementing the player's `3` initial inventory!
  bool consumeFreePowerUp(String id) {
    final removed = _freePowerUpsPending.remove(id);
    final seenAdded = _seenMechanics.add(id);
    if (removed) {
      _prefs?.setStringList(
        _kFreePowerUpsPending,
        _freePowerUpsPending.toList(),
      );
    }
    if (seenAdded) {
      _prefs?.setStringList(_kSeenMechanics, _seenMechanics.toList());
    }
    if (removed || seenAdded) {
      notifyListeners();
    }
    return removed;
  }

  void setCurrentLevel(int level) {
    flushPendingWinCoins();
    _currentLevel = level;
    if (level > _highestLevel && level < 1000) {
      _highestLevel = level;
      _prefs?.setInt(_kHighestLevel, _highestLevel);
    }
    _prefs?.setInt(_kCurrentLevel, _currentLevel);
    notifyListeners();
  }

  /// Marks level progression unlocked while holding [rewardCoins] in `_pendingWinCoins`
  /// so the top-left `CoinsWidget` ticks up live as the flying reward coins arrive!
  void stageLevelWinReward({required int rewardCoins, required bool isBonus}) {
    flushPendingWinCoins();
    _pendingWinCoins = rewardCoins;
    // Persist total coins immediately on disk so closing mid-win never loses reward
    _prefs?.setInt(_kCoins, _coins + _pendingWinCoins + _pendingMilestoneCoins);
    if (!isBonus) {
      final next = _currentLevel + 1;
      if (next > _highestLevel) {
        _highestLevel = next;
        _prefs?.setInt(_kHighestLevel, _highestLevel);
      }
    }
    notifyListeners();
  }

  /// Adds [extraCoins] to `_pendingWinCoins` when the player watches a Rewarded Ad
  /// for `x2` Level Complete coins, persisting immediately on disk for crash safety.
  void doublePendingWinCoins(int extraCoins) {
    if (extraCoins <= 0) return;
    _pendingWinCoins += extraCoins;
    _prefs?.setInt(_kCoins, _coins + _pendingWinCoins + _pendingMilestoneCoins);
    notifyListeners();
  }

  /// Credits a chunk of pending win coins during the flying-coin collect animation.
  void collectPendingWinCoinChunk(int amount) {
    if (_pendingWinCoins <= 0) return;
    final delta = amount.clamp(0, _pendingWinCoins);
    _pendingWinCoins -= delta;
    _coins += delta;
    _prefs?.setInt(_kCoins, _coins + _pendingWinCoins + _pendingMilestoneCoins);
    notifyListeners();
  }

  /// Credits a chunk of pending vase-milestone coins during the Claim flying-coin animation.
  void collectPendingMilestoneCoinChunk(int amount) {
    if (_pendingMilestoneCoins <= 0) return;
    final delta = amount.clamp(0, _pendingMilestoneCoins);
    _pendingMilestoneCoins -= delta;
    _coins += delta;
    _prefs?.setInt(_kCoins, _coins + _pendingWinCoins + _pendingMilestoneCoins);
    notifyListeners();
  }

  void flushPendingWinCoins() {
    if (_pendingWinCoins <= 0 && _pendingMilestoneCoins <= 0) return;
    _coins += _pendingWinCoins + _pendingMilestoneCoins;
    _pendingWinCoins = 0;
    _pendingMilestoneCoins = 0;
    _prefs?.setInt(_kCoins, _coins);
    notifyListeners();
  }

  void completeLevelAndReward({required int rewardCoins, required bool isBonus}) {
    flushPendingWinCoins();
    _coins += rewardCoins;
    _prefs?.setInt(_kCoins, _coins);
    if (!isBonus) {
      final next = _currentLevel + 1;
      if (next > _highestLevel) {
        _highestLevel = next;
        _prefs?.setInt(_kHighestLevel, _highestLevel);
      }
    }
    notifyListeners();
  }

  void advanceToNextCampaignLevel() {
    flushPendingWinCoins();
    _currentLevel = _currentLevel + 1;
    if (_currentLevel > _highestLevel) {
      _highestLevel = _currentLevel;
      _prefs?.setInt(_kHighestLevel, _highestLevel);
    }
    _prefs?.setInt(_kCurrentLevel, _currentLevel);
    notifyListeners();
  }

  void _persistLivesAndAnchor() {
    _prefs?.setInt(_kLives, _lives);
    _prefs?.setInt(_kMaxHearts, _maxLives);
    if (_lastLifeRegenMs != null) {
      _prefs?.setInt(_kLastLifeRegenMs, _lastLifeRegenMs!);
    } else {
      _prefs?.remove(_kLastLifeRegenMs);
    }
    if (_infinityExpireMs != null) {
      _prefs?.setInt(_kInfinityExpireMs, _infinityExpireMs!);
    } else {
      _prefs?.remove(_kInfinityExpireMs);
    }
  }

  bool isInfinityLives({DateTime? now}) {
    final expireMs = _infinityExpireMs;
    if (expireMs == null) return false;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return nowMs < expireMs;
  }

  int infinitySecondsLeft({DateTime? now}) {
    final expireMs = _infinityExpireMs;
    if (expireMs == null) return 0;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    if (nowMs >= expireMs) return 0;
    return ((expireMs - nowMs) / 1000.0).ceil();
  }

  bool canPlay({DateTime? now}) =>
      isInfinityLives(now: now) || _lives > 0;

  /// Synchronizes Infinity expiry & Heart recovery (`HeartService.CalculateOfflineRecovery` + `Tick`).
  /// - If Infinity expired while offline or ticking: freezes/resumes regen anchor from `_infinityExpireMs`
  ///   when `_lives < _maxLives`, clears `_infinityExpireMs`, then runs normal 15:00 regen.
  /// - While Infinity is active: skips normal regen.
  /// - Preserves surplus hearts (`> _maxLives`) granted via `isFromBuy: true`.
  int syncLivesRegen({DateTime? now}) {
    final clockNow = now ?? DateTime.now();
    final nowMs = clockNow.millisecondsSinceEpoch;
    bool stateChanged = false;

    // 1. Handle expired Infinity mode cleanly (advance regen anchor to infinity expiry time).
    if (_infinityExpireMs != null && nowMs >= _infinityExpireMs!) {
      if (_lives < _maxLives &&
          (_lastLifeRegenMs == null || _lastLifeRegenMs! < _infinityExpireMs!)) {
        _lastLifeRegenMs = _infinityExpireMs!;
      }
      _infinityExpireMs = null;
      stateChanged = true;
    }

    // 2. Active Infinity pauses normal heart regeneration.
    if (_infinityExpireMs != null && nowMs < _infinityExpireMs!) {
      if (stateChanged) {
        _persistLivesAndAnchor();
        notifyListeners();
      }
      return 0;
    }

    // 3. Full (or surplus bought) hearts -> no active regen timer needed.
    if (_lives >= _maxLives) {
      if (_lastLifeRegenMs != null) {
        _lastLifeRegenMs = null;
        stateChanged = true;
      }
      if (stateChanged) {
        _persistLivesAndAnchor();
        notifyListeners();
      }
      return 0;
    }

    // 4. Normal regeneration (`RECOVERY_INTERVAL_SECONDS = 900`)
    if (_lastLifeRegenMs == null) {
      _lastLifeRegenMs = nowMs;
      _persistLivesAndAnchor();
      notifyListeners();
      return 0;
    }

    final elapsedMs = nowMs - _lastLifeRegenMs!;
    if (elapsedMs < 0) {
      _lastLifeRegenMs = nowMs;
      _persistLivesAndAnchor();
      if (stateChanged) notifyListeners();
      return 0;
    }

    const int intervalMs = lifeRegenSeconds * 1000;
    if (elapsedMs < intervalMs) {
      if (stateChanged) {
        _persistLivesAndAnchor();
        notifyListeners();
      }
      return 0;
    }

    final int recovered = elapsedMs ~/ intervalMs;
    final int oldLives = _lives;
    _lives = math.min(_maxLives, _lives + recovered);
    if (_lives >= _maxLives) {
      _lastLifeRegenMs = null;
    } else {
      _lastLifeRegenMs = _lastLifeRegenMs! + recovered * intervalMs;
    }
    _persistLivesAndAnchor();
    notifyListeners();
    return _lives - oldLives;
  }

  /// Remaining time until the next Heart regenerates, or `null` if already full/infinity.
  Duration? timeUntilNextLife({DateTime? now}) {
    if (isInfinityLives(now: now)) {
      final expireMs = _infinityExpireMs!;
      final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
      return Duration(milliseconds: math.max(0, expireMs - nowMs));
    }
    if (_lives >= _maxLives) return null;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final anchorMs = _lastLifeRegenMs ?? nowMs;
    const int intervalMs = lifeRegenSeconds * 1000;
    final elapsedMs = (nowMs - anchorMs).clamp(0, intervalMs);
    final remMs = (intervalMs - elapsedMs).clamp(0, intervalMs);
    return Duration(milliseconds: remMs);
  }

  /// Formats timer matching `HeartService.FormatTime`:
  /// - Infinity: `Xd Xh` (>24h), `HH:MM:SS` (>=1h), or `MM:SS` (<1h).
  /// - Regen: `MM:SS` countdown until next heart, or `'Full'` when >= `_maxLives`.
  String formattedNextLifeCountdown({DateTime? now}) {
    final clockNow = now ?? DateTime.now();
    if (isInfinityLives(now: clockNow)) {
      final secs = infinitySecondsLeft(now: clockNow);
      return formatHeartTimerSeconds(secs);
    }
    if (_lives >= _maxLives) return 'Full';
    final rem = timeUntilNextLife(now: clockNow)!;
    final totalSecs = (rem.inMilliseconds / 1000.0).ceil().clamp(0, lifeRegenSeconds);
    return formatHeartTimerSeconds(totalSecs);
  }

  static String formatHeartTimerSeconds(int sec) {
    final s = math.max(0, sec);
    const int secPerDay = 86400;
    const int secPerHour = 3600;
    const int secPerMin = 60;
    if (s > secPerDay) {
      final days = s ~/ secPerDay;
      final hours = (s % secPerDay) ~/ secPerHour;
      return '${days}d ${hours}h';
    }
    if (s >= secPerHour) {
      final hours = (s ~/ secPerHour).toString().padLeft(2, '0');
      final mins = ((s % secPerHour) ~/ secPerMin).toString().padLeft(2, '0');
      final secs = (s % secPerMin).toString().padLeft(2, '0');
      return '$hours:$mins:$secs';
    }
    final mins = (s ~/ secPerMin).toString().padLeft(2, '0');
    final secs = (s % secPerMin).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _setLivesCount(
    int nextLives, {
    required int nowMs,
    bool allowOverMax = false,
  }) {
    _lives = allowOverMax ? math.max(0, nextLives) : nextLives.clamp(0, _maxLives);
    if (_lives >= _maxLives) {
      _lastLifeRegenMs = null;
    } else {
      _lastLifeRegenMs ??= nowMs;
    }
    _persistLivesAndAnchor();
    notifyListeners();
  }

  /// Mirrors `HeartService.TrySpendHeart(amount)`:
  /// - Returns `true` immediately during Infinity mode without deducting hearts.
  /// - Returns `false` if `_lives <= 0`.
  /// - Starts regen anchor when dropping from `_maxLives` and deducts `amount`.
  bool trySpendHeart({int amount = 1, DateTime? now}) {
    if (amount <= 0) return true;
    final clockNow = now ?? DateTime.now();
    syncLivesRegen(now: clockNow);
    if (isInfinityLives(now: clockNow)) return true;
    if (_lives <= 0) return false;
    final nextLives = math.max(0, _lives - amount);
    if (_lives >= _maxLives && nextLives < _maxLives) {
      _lastLifeRegenMs = clockNow.millisecondsSinceEpoch;
    }
    _lives = nextLives;
    if (_lives >= _maxLives) {
      _lastLifeRegenMs = null;
    } else {
      _lastLifeRegenMs ??= clockNow.millisecondsSinceEpoch;
    }
    _persistLivesAndAnchor();
    notifyListeners();
    return true;
  }

  /// Mirrors `HeartService.AddInfinity(seconds)`: freezes `_lastLifeRegenMs`.
  void addInfinityLives(Duration duration, {DateTime? now}) {
    if (duration <= Duration.zero) return;
    final clockNow = now ?? DateTime.now();
    final nowMs = clockNow.millisecondsSinceEpoch;
    syncLivesRegen(now: clockNow);
    if (isInfinityLives(now: clockNow)) {
      _infinityExpireMs = _infinityExpireMs! + duration.inMilliseconds;
    } else {
      _infinityExpireMs = nowMs + duration.inMilliseconds;
    }
    _persistLivesAndAnchor();
    notifyListeners();
  }

  /// Mirrors `HeartService.AddHearts(amount, isFromBuy)` returning actual delta granted.
  int addHearts(int amount, {bool isFromBuy = false, DateTime? now}) {
    if (amount <= 0) return 0;
    final clockNow = now ?? DateTime.now();
    syncLivesRegen(now: clockNow);
    final oldLives = _lives;
    final target = isFromBuy
        ? (_lives + amount)
        : math.min(_maxLives, _lives + amount);
    _setLivesCount(
      target,
      nowMs: clockNow.millisecondsSinceEpoch,
      allowOverMax: isFromBuy,
    );
    return _lives - oldLives;
  }

  /// Mirrors `HeartService.SetMaxHeart(maxHeart)` returning delta granted.
  int setMaxHearts(int nextMax, {DateTime? now}) {
    _maxLives = math.max(1, nextMax);
    _prefs?.setInt(_kMaxHearts, _maxLives);
    return addHearts(_maxLives, now: now);
  }

  void loseLife({DateTime? now}) {
    trySpendHeart(amount: 1, now: now);
  }

  void addOneLife({DateTime? now}) {
    addHearts(1, isFromBuy: false, now: now);
  }

  /// Restores the single attempt heart held at first interaction when winning a level.
  void refundAttemptHeart({DateTime? now}) {
    addHearts(1, isFromBuy: false, now: now);
  }

  bool refillLivesWithCoins({int? cost}) {
    final resolvedCost = cost ?? RemoteConfigService.liveHeartRefillPrice;
    if (_lives >= _maxLives) return false;
    if (!spendCoins(resolvedCost)) return false;
    _setLivesCount(_maxLives, nowMs: DateTime.now().millisecondsSinceEpoch);
    return true;
  }

  bool spendCoins(int amount) {
    flushPendingWinCoins();
    if (_coins < amount) return false;
    _coins -= amount;
    _prefs?.setInt(_kCoins, _coins);
    notifyListeners();
    return true;
  }

  void addCoins(int amount) {
    _coins += amount;
    _prefs?.setInt(_kCoins, _coins + _pendingWinCoins + _pendingMilestoneCoins);
    notifyListeners();
  }

  bool consumeLevelUp() {
    if (_levelUpCount <= 0) return false;
    _levelUpCount--;
    _prefs?.setInt(_kLevelUpCount, _levelUpCount);
    notifyListeners();
    return true;
  }

  bool consumeTimeFreeze() {
    if (_timeFreezeCount <= 0) return false;
    _timeFreezeCount--;
    _prefs?.setInt(_kTimeFreezeCount, _timeFreezeCount);
    notifyListeners();
    return true;
  }

  bool consumeShuffle() {
    if (_shuffleCount <= 0) return false;
    _shuffleCount--;
    _prefs?.setInt(_kShuffleCount, _shuffleCount);
    notifyListeners();
    return true;
  }

  bool consumeHammer() {
    if (_hammerCount <= 0) return false;
    _hammerCount--;
    _prefs?.setInt(_kHammerCount, _hammerCount);
    notifyListeners();
    return true;
  }

  bool consumeBooster(BoosterType type) => switch (type) {
        BoosterType.levelUp => consumeLevelUp(),
        BoosterType.timeFreeze => consumeTimeFreeze(),
        BoosterType.shuffle => consumeShuffle(),
        BoosterType.hammer => consumeHammer(),
      };

  int boosterCount(BoosterType type) => switch (type) {
        BoosterType.levelUp => _levelUpCount,
        BoosterType.timeFreeze => _timeFreezeCount,
        BoosterType.shuffle => _shuffleCount,
        BoosterType.hammer => _hammerCount,
      };

  bool buyPowerUpPack({
    bool? isLevelUp,
    BoosterType? boosterType,
    int? cost,
    int count = 3,
  }) {
    final resolvedType = boosterType ??
        ((isLevelUp ?? true) ? BoosterType.levelUp : BoosterType.timeFreeze);
    final resolvedCost = cost ?? RemoteConfigService.priceForBooster(resolvedType);
    if (!spendCoins(resolvedCost)) return false;
    _addBoosterInventory(resolvedType, count);
    notifyListeners();
    return true;
  }

  void _addBoosterInventory(BoosterType type, int count) {
    switch (type) {
      case BoosterType.levelUp:
        _levelUpCount += count;
        _prefs?.setInt(_kLevelUpCount, _levelUpCount);
      case BoosterType.timeFreeze:
        _timeFreezeCount += count;
        _prefs?.setInt(_kTimeFreezeCount, _timeFreezeCount);
      case BoosterType.shuffle:
        _shuffleCount += count;
        _prefs?.setInt(_kShuffleCount, _shuffleCount);
      case BoosterType.hammer:
        _hammerCount += count;
        _prefs?.setInt(_kHammerCount, _hammerCount);
    }
  }

  void grantFreePowerUp({
    bool? isLevelUp,
    BoosterType? boosterType,
    int count = 1,
  }) {
    if (count <= 0) return;
    final resolvedType = boosterType ??
        ((isLevelUp ?? true) ? BoosterType.levelUp : BoosterType.timeFreeze);
    _addBoosterInventory(resolvedType, count);
    notifyListeners();
  }

  /// Returns current inventory count for any booster by feature [powerUpId].
  int powerUpCountById(String powerUpId) {
    final type = BoosterType.fromId(powerUpId);
    if (type == null) return 0;
    return boosterCount(type);
  }

  /// Grants [count] units of a booster identified by [powerUpId].
  void grantPowerUpById(String powerUpId, {int count = 1}) {
    if (count <= 0) return;
    final type = BoosterType.fromId(powerUpId);
    if (type == null) return;
    grantFreePowerUp(boosterType: type, count: count);
  }

  bool buyLevelUpPack({int? cost, int count = 3}) =>
      buyPowerUpPack(boosterType: BoosterType.levelUp, cost: cost, count: count);

  bool buyTimeFreezePack({int? cost, int count = 3}) =>
      buyPowerUpPack(boosterType: BoosterType.timeFreeze, cost: cost, count: count);

  bool buyShufflePack({int? cost, int count = 3}) =>
      buyPowerUpPack(boosterType: BoosterType.shuffle, cost: cost, count: count);

  bool buyHammerPack({int? cost, int count = 3}) =>
      buyPowerUpPack(boosterType: BoosterType.hammer, cost: cost, count: count);

  // ── Cheat / QA Helpers (Gated by `RemoteConfigService.cheatEnable`) ────────

  void cheatSetCoins(int amount) {
    flushPendingWinCoins();
    _coins = amount.clamp(0, 999999999);
    _prefs?.setInt(_kCoins, _coins);
    notifyListeners();
  }

  void cheatSetPowerUps({
    int? levelUp,
    int? timeFreeze,
    int? shuffle,
    int? hammer,
  }) {
    if (levelUp != null) {
      _levelUpCount = levelUp.clamp(0, 9999);
      _prefs?.setInt(_kLevelUpCount, _levelUpCount);
    }
    if (timeFreeze != null) {
      _timeFreezeCount = timeFreeze.clamp(0, 9999);
      _prefs?.setInt(_kTimeFreezeCount, _timeFreezeCount);
    }
    if (shuffle != null) {
      _shuffleCount = shuffle.clamp(0, 9999);
      _prefs?.setInt(_kShuffleCount, _shuffleCount);
    }
    if (hammer != null) {
      _hammerCount = hammer.clamp(0, 9999);
      _prefs?.setInt(_kHammerCount, _hammerCount);
    }
    notifyListeners();
  }

  void cheatSetLives(int livesCount, {DateTime? now}) {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final clamped = livesCount.clamp(0, _maxLives);
    _lives = clamped;
    if (_lives >= _maxLives) {
      _lastLifeRegenMs = null;
    } else {
      _lastLifeRegenMs ??= nowMs;
    }
    _persistLivesAndAnchor();
    notifyListeners();
  }

  void cheatUnlockAllBoostersAndMechanics({int minHighestLevel = 50}) {
    if (_highestLevel < minHighestLevel) {
      _highestLevel = minHighestLevel;
      _prefs?.setInt(_kHighestLevel, _highestLevel);
    }
    _seenMechanics.addAll(const [
      'ice',
      'dud',
      'pinned',
      'arrows',
      'clock_bonus',
      'mystery',
      'key_lock',
      'toggle_walls',
      'dispenser',
      'swap',
      'one_way_arrow',
      'limited_move',
      'pu_level_up',
      'pu_time_freeze',
      'pu_shuffle',
      'pu_hammer',
    ]);
    _prefs?.setStringList(_kSeenMechanics, _seenMechanics.toList());
    notifyListeners();
  }

  /// Clears seen tutorial flags for gameplay mechanics (preserving boosters)
  /// so QA can re-trigger `MechanicUnlockDialog` popups when testing mechanic levels.
  void cheatResetSeenMechanics() {
    _seenMechanics.removeAll(const [
      'ice',
      'dud',
      'pinned',
      'arrows',
      'clock_bonus',
      'mystery',
      'key_lock',
      'toggle_walls',
      'dispenser',
      'swap',
      'one_way_arrow',
      'limited_move',
    ]);
    _prefs?.setStringList(_kSeenMechanics, _seenMechanics.toList());
    notifyListeners();
  }

  /// Computes deterministic progress toward unlocking the next gameplay mechanic/booster
  /// after winning campaign level [wonLevelNumber], aligned with actual level data:
  /// - Lv 1 -> 7: `ice` (6 wins: Lv 1..6)
  /// - Lv 7 -> 14: `dud` (7 wins: Lv 7..13)
  /// - Lv 14 -> 17: `pu_level_up` (3 wins: Lv 14..16 -> unlocks on Lv 17!)
  /// - Lv 17 -> 22: `arrows` (5 wins: Lv 17..21)
  /// - Lv 22 -> 27: `pu_time_freeze` (5 wins: Lv 22..26 -> unlocks on Lv 27!)
  /// - Lv 27 -> 42: `pinned` (15 wins: Lv 27..41)
  /// Returns `null` once all campaign mechanics are unlocked (`wonLevelNumber >= 42`).
  static MechanicUnlockProgressResult? computeMechanicAdvance(
    int wonLevelNumber,
  ) {
    if (wonLevelNumber <= 0) return null;
    for (final m in MechanicUnlockMilestone.schedule) {
      if (wonLevelNumber >= m.startLevel && wonLevelNumber < m.unlockLevel) {
        final totalSteps = (m.unlockLevel - m.startLevel).clamp(1, 999);
        final oldStep = (wonLevelNumber - m.startLevel).clamp(0, totalSteps);
        final newStep = (oldStep + 1).clamp(0, totalSteps);
        return MechanicUnlockProgressResult(
          milestone: m,
          wonLevelNumber: wonLevelNumber,
          oldStep: oldStep,
          newStep: newStep,
          totalSteps: totalSteps,
          oldProgress: (oldStep / totalSteps).clamp(0.0, 1.0),
          newProgress: (newStep / totalSteps).clamp(0.0, 1.0),
          didUnlockNext: wonLevelNumber + 1 >= m.unlockLevel,
        );
      }
    }
    return null;
  }

  /// Records a won level step and returns animation data for both the blooming Flower Vase
  /// and the `"xx% to unlock"` next-mechanic countdown bar.
  VaseStepAdvanceResult recordLevelWonVaseStep(int wonLevelNumber) {
    final cfg = currentVaseConfig;
    final oldStep = _vaseStepCount;
    final totalSteps = cfg.totalSteps;
    final oldProg = (oldStep / totalSteps).clamp(0.0, 1.0);

    // Increment step up to totalSteps
    final nextStep = (oldStep + 1).clamp(0, totalSteps);
    _vaseStepCount = nextStep;
    _prefs?.setInt(_kVaseStepCount, _vaseStepCount);

    final newProg = (nextStep / totalSteps).clamp(0.0, 1.0);
    final did100 = nextStep >= totalSteps;
    if (did100) {
      _vaseUnlockedIds.add(cfg.vaseId);
      _prefs?.setStringList(
        _kVaseUnlockedIds,
        _vaseUnlockedIds.map((i) => i.toString()).toList(),
      );
    }
    notifyListeners();

    return VaseStepAdvanceResult(
      vaseId: cfg.vaseId,
      oldStep: oldStep,
      newStep: nextStep,
      totalSteps: totalSteps,
      oldProgress: oldProg,
      newProgress: newProg,
      didReach100Percent: did100,
      config: cfg,
      mechanicProgress: computeMechanicAdvance(wonLevelNumber),
    );
  }

  VaseMilestoneConfig? _completeVaseClaimMetadata() {
    final cfg = currentVaseConfig;
    if (_vaseClaimedIds.contains(cfg.vaseId)) {
      return null;
    }
    _vaseClaimedIds.add(cfg.vaseId);
    _vaseUnlockedIds.add(cfg.vaseId);
    _prefs?.setStringList(
      _kVaseClaimedIds,
      _vaseClaimedIds.map((i) => i.toString()).toList(),
    );
    _prefs?.setStringList(
      _kVaseUnlockedIds,
      _vaseUnlockedIds.map((i) => i.toString()).toList(),
    );

    // Mark non-booster mechanic milestones seen upon vase claim;
    // in-game boosters present their "New Feature" popup (Claim / Claim X2)
    // upon entering their unlock level.
    if (cfg.unlockMechanicId != null &&
        BoosterType.fromId(cfg.unlockMechanicId) == null) {
      markMechanicSeen(cfg.unlockMechanicId!);
    }

    // Advance to next vase
    _vaseCurrentId++;
    _vaseStepCount = 0;
    _prefs?.setInt(_kVaseCurrentId, _vaseCurrentId);
    _prefs?.setInt(_kVaseStepCount, _vaseStepCount);
    return cfg;
  }

  /// Claims current vase milestone reward immediately (used by direct callers/unit tests).
  void claimCurrentVaseMilestone({int multiplier = 1}) {
    final safeMult = multiplier.clamp(1, 10);
    final cfg = _completeVaseClaimMetadata();
    if (cfg == null) return;
    final total = cfg.rewardCoins * safeMult;
    if (total > 0) {
      addCoins(total);
    }
    notifyListeners();
  }

  /// Stages current vase milestone reward into `_pendingMilestoneCoins` so the Claim button's
  /// flying coins visibly tick the HUD balance up while persisting full total to disk for safety.
  int stageCurrentVaseMilestoneClaim({int multiplier = 1}) {
    final safeMult = multiplier.clamp(1, 10);
    final cfg = _completeVaseClaimMetadata();
    if (cfg == null) return 0;
    final total = cfg.rewardCoins * safeMult;
    if (total > 0) {
      _pendingMilestoneCoins += total;
      _prefs?.setInt(
        _kCoins,
        _coins + _pendingWinCoins + _pendingMilestoneCoins,
      );
    }
    notifyListeners();
    return total;
  }

  void cheatAdvanceVaseToFull() {
    final cfg = currentVaseConfig;
    _vaseStepCount = cfg.totalSteps;
    _vaseUnlockedIds.add(cfg.vaseId);
    _prefs?.setInt(_kVaseStepCount, _vaseStepCount);
    _prefs?.setStringList(
      _kVaseUnlockedIds,
      _vaseUnlockedIds.map((i) => i.toString()).toList(),
    );
    notifyListeners();
  }

  /// Syncs the vase milestone & step to match a campaign [level] jumped to in QA/Cheat.
  void cheatSyncVaseToLevel(int level) {
    final targetVaseId = VaseMilestoneConfig.determineInitialVaseId(level);
    final cfg = VaseMilestoneConfig.getForVaseId(targetVaseId);
    _vaseCurrentId = targetVaseId;
    _vaseStepCount = (level - cfg.startLevel).clamp(0, cfg.totalSteps - 1);
    _prefs?.setInt(_kVaseCurrentId, _vaseCurrentId);
    _prefs?.setInt(_kVaseStepCount, _vaseStepCount);
    notifyListeners();
  }

  /// Sets current vase progress to `totalSteps - 1` so winning the next level immediately triggers 100% bloom.
  void cheatPrepareNextWinBloom() {
    final cfg = currentVaseConfig;
    _vaseStepCount = (cfg.totalSteps - 1).clamp(0, cfg.totalSteps);
    _vaseClaimedIds.remove(cfg.vaseId);
    _prefs?.setInt(_kVaseStepCount, _vaseStepCount);
    _prefs?.setStringList(
      _kVaseClaimedIds,
      _vaseClaimedIds.map((i) => i.toString()).toList(),
    );
    notifyListeners();
  }

  /// Cycles to the next vase (`1 -> 2 -> 3 -> 4 -> 5 -> 1`) at step 0 for quick flower testing.
  void cheatCycleVaseFlower() {
    _vaseCurrentId = (_vaseCurrentId % 5) + 1;
    _vaseStepCount = 0;
    _vaseClaimedIds.remove(_vaseCurrentId);
    _prefs?.setInt(_kVaseCurrentId, _vaseCurrentId);
    _prefs?.setInt(_kVaseStepCount, _vaseStepCount);
    _prefs?.setStringList(
      _kVaseClaimedIds,
      _vaseClaimedIds.map((i) => i.toString()).toList(),
    );
    notifyListeners();
  }

  /// Grants or updates non-consumable No Ads ownership cleanly.
  void setNoAdsPurchased(bool purchased) {
    if (_noAdsPurchased == purchased) return;
    _noAdsPurchased = purchased;
    _prefs?.setBool(_kNoAdsPurchased, purchased);
    notifyListeners();
  }

  /// Records a purchased IAP pack [productId] for one-time / badge tracking.
  void markPackPurchased(String productId) {
    if (_purchasedPackIds.add(productId)) {
      _prefs?.setStringList(_kPurchasedPackIds, _purchasedPackIds.toList());
      notifyListeners();
    }
  }

  /// Marks that the player has seen the unlocked Journey feature showcase.
  void markJourneyUnlockedSeen() {
    if (_journeyUnlockedSeen) return;
    _journeyUnlockedSeen = true;
    _prefs?.setBool(_kJourneyUnlockedSeen, true);
    notifyListeners();
  }

  /// Flags that winning Level 20 should showcase Journey immediately upon returning Home.
  void markPendingJourneyUnlockShowcase() {
    if (_journeyUnlockedSeen && _pendingJourneyUnlockShowcase) return;
    _journeyUnlockedSeen = true;
    _pendingJourneyUnlockShowcase = true;
    _prefs?.setBool(_kJourneyUnlockedSeen, true);
    _prefs?.setBool(_kPendingJourneyShowcase, true);
    notifyListeners();
  }

  /// Consumes the pending Level-20 -> Home Journey showcase trigger cleanly.
  bool consumePendingJourneyUnlockShowcase() {
    if (!_pendingJourneyUnlockShowcase) return false;
    _pendingJourneyUnlockShowcase = false;
    _prefs?.setBool(_kPendingJourneyShowcase, false);
    notifyListeners();
    return true;
  }

  /// Claims a Journey milestone reward if unlocked and not already claimed.
  /// Returns `true` when rewards were granted.
  bool claimJourneyMilestone(JourneyMilestoneConfig milestone) {
    if (!isJourneyMilestoneUnlocked(milestone.levelUnlock)) return false;
    if (!_claimedJourneyLevels.add(milestone.levelUnlock)) return false;

    if (milestone.coins > 0) {
      _coins += milestone.coins;
      _prefs?.setInt(_kCoins, _coins);
    }
    if (milestone.boosterType != null && milestone.boosterCount > 0) {
      grantFreePowerUp(
        boosterType: milestone.boosterType!,
        count: milestone.boosterCount,
      );
    }
    if (milestone.infinityMinutes > 0) {
      addInfinityLives(Duration(minutes: milestone.infinityMinutes));
    }
    if (milestone.bgId != null && milestone.bgId! > 0) {
      // Automatically preview/select newly unlocked background or leave selectable.
      _selectedJourneyBgId = milestone.bgId!;
      _prefs?.setInt(_kSelectedJourneyBgId, _selectedJourneyBgId);
    }

    _prefs?.setStringList(
      _kClaimedJourneyLevels,
      _claimedJourneyLevels.map((lv) => lv.toString()).toList(),
    );
    notifyListeners();
    return true;
  }

  /// Equips an unlocked Journey Gallery background (`0 = Base`, `1 = Frozen`, `2 = Jungle`, `3 = Desert`).
  bool selectJourneyBg(int bgId) {
    if (!isJourneyBgUnlocked(bgId)) return false;
    if (_selectedJourneyBgId == bgId) return true;
    _selectedJourneyBgId = bgId.clamp(0, 3);
    _prefs?.setInt(_kSelectedJourneyBgId, _selectedJourneyBgId);
    notifyListeners();
    return true;
  }

  Future<void> cheatResetAllProgress() async {
    flushPendingWinCoins();
    _currentLevel = 1;
    _highestLevel = 1;
    _coins = 875;
    _maxLives = maxLives;
    _lives = _maxLives;
    _lastLifeRegenMs = null;
    _infinityExpireMs = null;
    _levelUpCount = initialPowerUpInventory;
    _timeFreezeCount = initialPowerUpInventory;
    _shuffleCount = initialPowerUpInventory;
    _hammerCount = initialPowerUpInventory;
    _seenMechanics.clear();
    _freePowerUpsPending.clear();
    _vaseCurrentId = 1;
    _vaseStepCount = 0;
    _vaseClaimedIds.clear();
    _vaseUnlockedIds.clear();
    _purchasedPackIds.clear();
    _noAdsPurchased = false;
    _journeyUnlockedSeen = false;
    _pendingJourneyUnlockShowcase = false;
    _claimedJourneyLevels.clear();
    _selectedJourneyBgId = 0;
    await _prefs?.setInt(_kCurrentLevel, _currentLevel);
    await _prefs?.setInt(_kHighestLevel, _highestLevel);
    await _prefs?.setInt(_kCoins, _coins);
    await _prefs?.setInt(_kLives, _lives);
    await _prefs?.remove(_kMaxHearts);
    await _prefs?.remove(_kLastLifeRegenMs);
    await _prefs?.remove(_kInfinityExpireMs);
    await _prefs?.setInt(_kLevelUpCount, _levelUpCount);
    await _prefs?.setInt(_kTimeFreezeCount, _timeFreezeCount);
    await _prefs?.setInt(_kShuffleCount, _shuffleCount);
    await _prefs?.setInt(_kHammerCount, _hammerCount);
    await _prefs?.setStringList(_kSeenMechanics, const []);
    await _prefs?.setStringList(_kFreePowerUpsPending, const []);
    await _prefs?.setInt(_kVaseCurrentId, 1);
    await _prefs?.setInt(_kVaseStepCount, 0);
    await _prefs?.setStringList(_kVaseClaimedIds, const []);
    await _prefs?.setStringList(_kVaseUnlockedIds, const []);
    await _prefs?.setStringList(_kPurchasedPackIds, const []);
    await _prefs?.setBool(_kNoAdsPurchased, false);
    await _prefs?.setBool(_kJourneyUnlockedSeen, false);
    await _prefs?.setBool(_kPendingJourneyShowcase, false);
    await _prefs?.setStringList(_kClaimedJourneyLevels, const []);
    await _prefs?.setInt(_kSelectedJourneyBgId, 0);
    notifyListeners();
  }
}

enum VaseShapeType {
  fishbowl,
  ovalCeramic,
  flutedCrystal,
  royalTall,
  prismLotus,
}

enum FlowerType {
  tulipPink,
  trioDaisy,
  sunflower,
  scarletPoppy,
  crystalLotus,
}

class VaseMilestoneConfig {
  final int vaseId;
  final String title;
  final String flowerTitle;
  final VaseShapeType shapeType;
  final FlowerType flowerType;
  final int startLevel;
  final int endLevel;
  final int totalSteps;
  final String? unlockMechanicId;
  final String rewardTitle;
  final int rewardCoins;
  final String? rewardNote;

  const VaseMilestoneConfig({
    required this.vaseId,
    required this.title,
    required this.flowerTitle,
    required this.shapeType,
    required this.flowerType,
    required this.startLevel,
    required this.endLevel,
    required this.totalSteps,
    this.unlockMechanicId,
    required this.rewardTitle,
    this.rewardCoins = 150,
    this.rewardNote,
  });

  static const List<VaseMilestoneConfig> milestones = [
    VaseMilestoneConfig(
      vaseId: 1,
      title: 'Crystal Fishbowl',
      flowerTitle: 'Pink Tulip',
      shapeType: VaseShapeType.fishbowl,
      flowerType: FlowerType.tulipPink,
      startLevel: 1,
      endLevel: 3,
      totalSteps: 3,
      unlockMechanicId: null,
      rewardTitle: 'Starter Gift',
      rewardCoins: 150,
      rewardNote: '+150 Coins & New Crystal Vase!',
    ),
    VaseMilestoneConfig(
      vaseId: 2,
      title: 'Azure Ceramic Vase',
      flowerTitle: 'Trio Daisies',
      shapeType: VaseShapeType.ovalCeramic,
      flowerType: FlowerType.trioDaisy,
      startLevel: 4,
      endLevel: 8,
      totalSteps: 5,
      unlockMechanicId: null,
      rewardTitle: 'Trio Daisies Chest',
      rewardCoins: 200,
      rewardNote: '+200 Coins & Next Crystal Vase!',
    ),
    VaseMilestoneConfig(
      vaseId: 3,
      title: 'Fluted Crystal Vase',
      flowerTitle: 'Golden Sunflowers',
      shapeType: VaseShapeType.flutedCrystal,
      flowerType: FlowerType.sunflower,
      startLevel: 9,
      endLevel: 16,
      totalSteps: 8,
      unlockMechanicId: null,
      rewardTitle: 'Sunflower Chest',
      rewardCoins: 250,
      rewardNote: '+250 Coins & Next Crystal Vase!',
    ),
    VaseMilestoneConfig(
      vaseId: 4,
      title: 'Royal Amphora Vase',
      flowerTitle: 'Scarlet Poppies',
      shapeType: VaseShapeType.royalTall,
      flowerType: FlowerType.scarletPoppy,
      startLevel: 17,
      endLevel: 26,
      totalSteps: 10,
      unlockMechanicId: null,
      rewardTitle: 'Scarlet Poppy Chest',
      rewardCoins: 300,
      rewardNote: '+300 Coins & Next Crystal Vase!',
    ),
  ];

  static VaseMilestoneConfig getForVaseId(int id) {
    if (id <= 4 && id >= 1) {
      return milestones[id - 1];
    }
    // High-level looping milestones (10 levels per vase):
    // Vase 5 is Crystal Lotus; Vase 6+ rotates cleanly across all 5 flowers & vase shapes.
    final cycle = (id - 5).clamp(0, 1000000);
    final start = 27 + cycle * 10;
    final slot = cycle % 5;
    if (slot == 0) {
      return VaseMilestoneConfig(
        vaseId: id,
        title: 'Prism Lotus Vase',
        flowerTitle: 'Crystal Lotus',
        shapeType: VaseShapeType.prismLotus,
        flowerType: FlowerType.crystalLotus,
        startLevel: start,
        endLevel: start + 9,
        totalSteps: 10,
        unlockMechanicId: null,
        rewardTitle: 'Crystal Bloom Chest',
        rewardCoins: 500,
        rewardNote: '+500 Coins & Next Crystal Vase!',
      );
    }
    final template = milestones[slot - 1];
    return VaseMilestoneConfig(
      vaseId: id,
      title: template.title,
      flowerTitle: template.flowerTitle,
      shapeType: template.shapeType,
      flowerType: template.flowerType,
      startLevel: start,
      endLevel: start + 9,
      totalSteps: 10,
      unlockMechanicId: null,
      rewardTitle: '${template.flowerTitle} Chest',
      rewardCoins: 500,
      rewardNote: '+500 Coins & Next Crystal Vase!',
    );
  }

  static int determineInitialVaseId(int level) {
    if (level <= 3) return 1;
    if (level <= 8) return 2;
    if (level <= 16) return 3;
    if (level <= 26) return 4;
    return 5 + ((level - 27) ~/ 10);
  }
}

class MechanicUnlockMilestone {
  final int startLevel;
  final int unlockLevel;
  final String mechanicId;
  final String title;
  final String note;

  const MechanicUnlockMilestone({
    required this.startLevel,
    required this.unlockLevel,
    required this.mechanicId,
    required this.title,
    required this.note,
  });

  /// Dynamic unlock schedule merging the 12 campaign mechanics
  /// (`ice: 7`, `dud: 14`, `arrows: 22`, `mystery: 33`, `pinned: 42`,
  /// `one_way_arrow: 50`, `key_lock: 58`, `swap: 70`, `limited_move: 83`,
  /// `clock_bonus: 95`, `dispenser: 108`, `toggle_walls: 133`) with Remote
  /// Config's `booster_unlock_order` (default: `pu_level_up: 17`,
  /// `pu_time_freeze: 27`, `pu_shuffle: 32`, `pu_hammer: 38`).
  static List<MechanicUnlockMilestone> get schedule {
    final raw = <({
      int unlockLevel,
      int sortTieOrder,
      String mechanicId,
      String title,
      String note,
    })>[
      const (
        unlockLevel: 7,
        sortTieOrder: 100,
        mechanicId: 'ice',
        title: 'Ice Blocks',
        note: 'Unlocks at Level 7!',
      ),
      const (
        unlockLevel: 14,
        sortTieOrder: 101,
        mechanicId: 'dud',
        title: 'Stone Blocker',
        note: 'Unlocks at Level 14!',
      ),
      const (
        unlockLevel: 22,
        sortTieOrder: 102,
        mechanicId: 'arrows',
        title: 'Arrow Block',
        note: 'Unlocks at Level 22!',
      ),
      const (
        unlockLevel: 33,
        sortTieOrder: 103,
        mechanicId: 'mystery',
        title: 'Mystery Blocks',
        note: 'Unlocks at Level 33!',
      ),
      const (
        unlockLevel: 42,
        sortTieOrder: 104,
        mechanicId: 'pinned',
        title: 'Screwed Block',
        note: 'Unlocks at Level 42!',
      ),
      const (
        unlockLevel: 50,
        sortTieOrder: 105,
        mechanicId: 'one_way_arrow',
        title: 'One-Way Arrows',
        note: 'Unlocks at Level 50!',
      ),
      const (
        unlockLevel: 58,
        sortTieOrder: 106,
        mechanicId: 'key_lock',
        title: 'Key & Lock',
        note: 'Unlocks at Level 58!',
      ),
      const (
        unlockLevel: 70,
        sortTieOrder: 107,
        mechanicId: 'swap',
        title: 'Swap Blocks',
        note: 'Unlocks at Level 70!',
      ),
      const (
        unlockLevel: 83,
        sortTieOrder: 108,
        mechanicId: 'limited_move',
        title: 'Fragile Blocks',
        note: 'Unlocks at Level 83!',
      ),
      const (
        unlockLevel: 95,
        sortTieOrder: 109,
        mechanicId: 'clock_bonus',
        title: 'Clock Bonus',
        note: 'Unlocks at Level 95!',
      ),
      const (
        unlockLevel: 108,
        sortTieOrder: 110,
        mechanicId: 'dispenser',
        title: 'Pipe Dispenser',
        note: 'Unlocks at Level 108!',
      ),
      const (
        unlockLevel: 133,
        sortTieOrder: 111,
        mechanicId: 'toggle_walls',
        title: 'Toggle Walls',
        note: 'Unlocks at Level 133!',
      ),
    ];

    final boosters = RemoteConfigService.boosterUnlockOrder;
    for (int i = 0; i < boosters.length; i++) {
      final b = boosters[i];
      raw.add((
        unlockLevel: b.unlockLevel,
        sortTieOrder: i, // Boosters keep their Remote Config order on ties
        mechanicId: b.id,
        title: b.type.displayTitle,
        note: 'Booster unlocks at Level ${b.unlockLevel}!',
      ));
    }

    raw.sort((a, b) {
      final lvCmp = a.unlockLevel.compareTo(b.unlockLevel);
      if (lvCmp != 0) return lvCmp;
      return a.sortTieOrder.compareTo(b.sortTieOrder);
    });

    final result = <MechanicUnlockMilestone>[];
    int prevStart = 1;
    int prevUnlock = 1;
    for (int i = 0; i < raw.length; i++) {
      final item = raw[i];
      final startLevel =
          i == 0 ? 1 : (item.unlockLevel > prevUnlock ? prevUnlock : prevStart);
      result.add(
        MechanicUnlockMilestone(
          startLevel: startLevel,
          unlockLevel: item.unlockLevel,
          mechanicId: item.mechanicId,
          title: item.title,
          note: item.note,
        ),
      );
      if (item.unlockLevel > prevUnlock) {
        prevStart = startLevel;
        prevUnlock = item.unlockLevel;
      }
    }
    return List<MechanicUnlockMilestone>.unmodifiable(result);
  }
}

class MechanicUnlockProgressResult {
  final MechanicUnlockMilestone milestone;
  final int wonLevelNumber;
  final int oldStep;
  final int newStep;
  final int totalSteps;
  final double oldProgress;
  final double newProgress;
  final bool didUnlockNext;

  const MechanicUnlockProgressResult({
    required this.milestone,
    required this.wonLevelNumber,
    required this.oldStep,
    required this.newStep,
    required this.totalSteps,
    required this.oldProgress,
    required this.newProgress,
    required this.didUnlockNext,
  });

  int get remainingPercent =>
      (100 - (newProgress * 100).round()).clamp(0, 100);
}

class VaseStepAdvanceResult {
  final int vaseId;
  final int oldStep;
  final int newStep;
  final int totalSteps;
  final double oldProgress;
  final double newProgress;
  final bool didReach100Percent;
  final VaseMilestoneConfig config;
  final MechanicUnlockProgressResult? mechanicProgress;

  const VaseStepAdvanceResult({
    required this.vaseId,
    required this.oldStep,
    required this.newStep,
    required this.totalSteps,
    required this.oldProgress,
    required this.newProgress,
    required this.didReach100Percent,
    required this.config,
    this.mechanicProgress,
  });
}

/// Visual theme unlocked via Journey Gallery milestones (`0 = Base`, `1 = Frozen`, `2 = Jungle`, `3 = Desert`).
class JourneyBgTheme {
  final int id;
  final String title;
  final String galleryCardAsset;
  final String fullBgAsset;

  const JourneyBgTheme({
    required this.id,
    required this.title,
    required this.galleryCardAsset,
    required this.fullBgAsset,
  });

  static const List<JourneyBgTheme> all = [
    JourneyBgTheme(
      id: 0,
      title: 'Base',
      galleryCardAsset: 'assets/images/Journey/Gallery_Boat.webp',
      fullBgAsset: 'assets/images/Background_Core.png',
    ),
    JourneyBgTheme(
      id: 1,
      title: 'Frozen',
      galleryCardAsset: 'assets/images/Journey/Gallery_NorthPole.webp',
      fullBgAsset: 'assets/images/Journey/BG_NorthPole.webp',
    ),
    JourneyBgTheme(
      id: 2,
      title: 'Jungle',
      galleryCardAsset: 'assets/images/Journey/Gallery_Jungle.webp',
      fullBgAsset: 'assets/images/Journey/BG_Jungle.webp',
    ),
    JourneyBgTheme(
      id: 3,
      title: 'Desert',
      galleryCardAsset: 'assets/images/Journey/Gallery_Desert.webp',
      fullBgAsset: 'assets/images/Journey/BG_Desert.webp',
    ),
  ];

  static JourneyBgTheme byId(int id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return all.first;
  }
}

/// Single milestone row on the vertical Journey progression track.
class JourneyMilestoneConfig {
  final int levelUnlock;
  final String landTitle;
  final String rewardLabel;
  final int? bgId;
  final int coins;
  final BoosterType? boosterType;
  final int boosterCount;
  final int infinityMinutes;

  const JourneyMilestoneConfig({
    required this.levelUnlock,
    required this.landTitle,
    required this.rewardLabel,
    this.bgId,
    this.coins = 0,
    this.boosterType,
    this.boosterCount = 0,
    this.infinityMinutes = 0,
  });

  bool get isBgMilestone => bgId != null;

  JourneyBgTheme? get bgTheme => bgId == null ? null : JourneyBgTheme.byId(bgId!);

  /// Full progression schedule matching the Journey specification spreadsheet:
  /// Lv 1 (BG base), 15, 20 (Frozen BG), 30, 40, 50 (Jungle BG), 60, 75, 90,
  /// 100 (Desert BG), 125, 150, 175.
  static const List<JourneyMilestoneConfig> schedule = [
    JourneyMilestoneConfig(
      levelUnlock: 1,
      landTitle: 'Base',
      rewardLabel: 'Base BG',
      bgId: 0,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 15,
      landTitle: 'Base',
      rewardLabel: '15m',
      infinityMinutes: 15,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 20,
      landTitle: 'Frozen',
      rewardLabel: 'Frozen BG',
      bgId: 1,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 30,
      landTitle: 'Frozen',
      rewardLabel: '50',
      coins: 50,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 40,
      landTitle: 'Frozen',
      rewardLabel: '15m',
      infinityMinutes: 15,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 50,
      landTitle: 'Jungle',
      rewardLabel: 'Jungle BG',
      bgId: 2,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 60,
      landTitle: 'Jungle',
      rewardLabel: 'x1',
      boosterType: BoosterType.shuffle,
      boosterCount: 1,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 75,
      landTitle: 'Jungle',
      rewardLabel: '100',
      coins: 100,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 90,
      landTitle: 'Jungle',
      rewardLabel: '30m',
      infinityMinutes: 30,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 100,
      landTitle: 'Desert',
      rewardLabel: 'Desert BG',
      bgId: 3,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 125,
      landTitle: 'Desert',
      rewardLabel: '100',
      coins: 100,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 150,
      landTitle: 'Desert',
      rewardLabel: '30m',
      infinityMinutes: 30,
    ),
    JourneyMilestoneConfig(
      levelUnlock: 175,
      landTitle: 'Desert',
      rewardLabel: 'x1',
      boosterType: BoosterType.levelUp,
      boosterCount: 1,
    ),
  ];

  static JourneyMilestoneConfig? forBgId(int bgId) {
    for (final m in schedule) {
      if (m.bgId == bgId) return m;
    }
    return null;
  }
}

