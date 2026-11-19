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
  static const _kSeenMechanics = 'bo_seen_mechanics';
  static const _kFreePowerUpsPending = 'bo_free_pu_pending';
  static const _kFtueLoadingLogged = 'bo_ftue_loading_logged';
  static const _kFtueCompleted = 'bo_ftue_completed';
  static const _kVaseCurrentId = 'bo_vase_current_id';
  static const _kVaseStepCount = 'bo_vase_step_count';
  static const _kVaseClaimedIds = 'bo_vase_claimed_ids';
  static const _kVaseUnlockedIds = 'bo_vase_unlocked_ids';

  static const int maxLives = 5;
  static const int lifeRegenSeconds = 15 * 60; // 1 Heart per 15 minutes (900s)
  static const int refillLivesCost = 900;

  /// Exact Unity `remote_config.json` power-up progression & economy settings:
  /// - `LevelUp` (`type = 0`): `unlock_level = 17`, `initial_inventory = 3`, `price_coins = 600` (`x3`)
  /// - `TimeFreeze` (`type = 1`): `unlock_level = 27`, `initial_inventory = 3`, `price_coins = 450` (`x3`), `duration = 20s`
  static const int winRewardX2UnlockLevel = 7;
  static const int levelUpUnlockLevel = 17;
  static const int timeFreezeUnlockLevel = 27;
  static const int levelUpPackCost = 600;
  static const int timeFreezePackCost = 450;
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

  bool buyPowerUpPack({
    required bool isLevelUp,
    int? cost,
    int count = 3,
  }) {
    final resolvedCost = cost ??
        (isLevelUp
            ? RemoteConfigService.boosterLevelUpPrice
            : RemoteConfigService.boosterTimeFreezePrice);
    if (!spendCoins(resolvedCost)) return false;
    if (isLevelUp) {
      _levelUpCount += count;
      _prefs?.setInt(_kLevelUpCount, _levelUpCount);
    } else {
      _timeFreezeCount += count;
      _prefs?.setInt(_kTimeFreezeCount, _timeFreezeCount);
    }
    notifyListeners();
    return true;
  }

  void grantFreePowerUp({
    required bool isLevelUp,
    int count = 1,
  }) {
    if (isLevelUp) {
      _levelUpCount += count;
      _prefs?.setInt(_kLevelUpCount, _levelUpCount);
    } else {
      _timeFreezeCount += count;
      _prefs?.setInt(_kTimeFreezeCount, _timeFreezeCount);
    }
    notifyListeners();
  }

  /// Returns current inventory count for any booster by feature [powerUpId].
  int powerUpCountById(String powerUpId) => switch (powerUpId) {
        'pu_level_up' => _levelUpCount,
        'pu_time_freeze' => _timeFreezeCount,
        _ => 0,
      };

  /// Grants [count] units of a booster identified by [powerUpId].
  void grantPowerUpById(String powerUpId, {int count = 1}) {
    if (count <= 0) return;
    switch (powerUpId) {
      case 'pu_level_up':
        grantFreePowerUp(isLevelUp: true, count: count);
      case 'pu_time_freeze':
        grantFreePowerUp(isLevelUp: false, count: count);
    }
  }

  bool buyLevelUpPack({int? cost, int count = 3}) =>
      buyPowerUpPack(isLevelUp: true, cost: cost, count: count);

  bool buyTimeFreezePack({int? cost, int count = 3}) =>
      buyPowerUpPack(isLevelUp: false, cost: cost, count: count);

  // ── Cheat / QA Helpers (Gated by `RemoteConfigService.cheatEnable`) ────────

  void cheatSetCoins(int amount) {
    flushPendingWinCoins();
    _coins = amount.clamp(0, 999999999);
    _prefs?.setInt(_kCoins, _coins);
    notifyListeners();
  }

  void cheatSetPowerUps({int? levelUp, int? timeFreeze}) {
    if (levelUp != null) {
      _levelUpCount = levelUp.clamp(0, 9999);
      _prefs?.setInt(_kLevelUpCount, _levelUpCount);
    }
    if (timeFreeze != null) {
      _timeFreezeCount = timeFreeze.clamp(0, 9999);
      _prefs?.setInt(_kTimeFreezeCount, _timeFreezeCount);
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
      'pu_level_up',
      'pu_time_freeze',
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

  VaseMilestoneConfig _completeVaseClaimMetadata() {
    final cfg = currentVaseConfig;
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
        cfg.unlockMechanicId != 'pu_level_up' &&
        cfg.unlockMechanicId != 'pu_time_freeze') {
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
  void claimCurrentVaseMilestone() {
    final cfg = _completeVaseClaimMetadata();
    if (cfg.rewardCoins > 0) {
      addCoins(cfg.rewardCoins);
    }
    notifyListeners();
  }

  /// Stages current vase milestone reward into `_pendingMilestoneCoins` so the Claim button's
  /// flying coins visibly tick the HUD balance up while persisting full total to disk for safety.
  int stageCurrentVaseMilestoneClaim() {
    final cfg = _completeVaseClaimMetadata();
    if (cfg.rewardCoins > 0) {
      _pendingMilestoneCoins += cfg.rewardCoins;
      _prefs?.setInt(
        _kCoins,
        _coins + _pendingWinCoins + _pendingMilestoneCoins,
      );
    }
    notifyListeners();
    return cfg.rewardCoins;
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
    _seenMechanics.clear();
    _freePowerUpsPending.clear();
    _vaseCurrentId = 1;
    _vaseStepCount = 0;
    _vaseClaimedIds.clear();
    _vaseUnlockedIds.clear();
    await _prefs?.setInt(_kCurrentLevel, _currentLevel);
    await _prefs?.setInt(_kHighestLevel, _highestLevel);
    await _prefs?.setInt(_kCoins, _coins);
    await _prefs?.setInt(_kLives, _lives);
    await _prefs?.remove(_kMaxHearts);
    await _prefs?.remove(_kLastLifeRegenMs);
    await _prefs?.remove(_kInfinityExpireMs);
    await _prefs?.setInt(_kLevelUpCount, _levelUpCount);
    await _prefs?.setInt(_kTimeFreezeCount, _timeFreezeCount);
    await _prefs?.setStringList(_kSeenMechanics, const []);
    await _prefs?.setStringList(_kFreePowerUpsPending, const []);
    await _prefs?.setInt(_kVaseCurrentId, 1);
    await _prefs?.setInt(_kVaseStepCount, 0);
    await _prefs?.setStringList(_kVaseClaimedIds, const []);
    await _prefs?.setStringList(_kVaseUnlockedIds, const []);
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

  /// Exact unlock schedule verified against `all_121_levels.json` and `PlayerProgressService`:
  /// Ice (Lv 7) -> Stone Blocker (Lv 14) -> Level Up (Lv 17) ->
  /// Arrow Block (Lv 22) -> Time Freeze (Lv 27) -> Screwed Block (Lv 42).
  static const List<MechanicUnlockMilestone> schedule = [
    MechanicUnlockMilestone(
      startLevel: 1,
      unlockLevel: 7,
      mechanicId: 'ice',
      title: 'Ice Blocks',
      note: 'Unlocks at Level 7!',
    ),
    MechanicUnlockMilestone(
      startLevel: 7,
      unlockLevel: 14,
      mechanicId: 'dud',
      title: 'Stone Blocker',
      note: 'Unlocks at Level 14!',
    ),
    MechanicUnlockMilestone(
      startLevel: 14,
      unlockLevel: PlayerProgressService.levelUpUnlockLevel,
      mechanicId: 'pu_level_up',
      title: 'Level Up',
      note: 'Booster unlocks at Level 17!',
    ),
    MechanicUnlockMilestone(
      startLevel: PlayerProgressService.levelUpUnlockLevel,
      unlockLevel: 22,
      mechanicId: 'arrows',
      title: 'Arrow Block',
      note: 'Unlocks at Level 22!',
    ),
    MechanicUnlockMilestone(
      startLevel: 22,
      unlockLevel: PlayerProgressService.timeFreezeUnlockLevel,
      mechanicId: 'pu_time_freeze',
      title: 'Time Freeze',
      note: 'Booster unlocks at Level 27!',
    ),
    MechanicUnlockMilestone(
      startLevel: PlayerProgressService.timeFreezeUnlockLevel,
      unlockLevel: 42,
      mechanicId: 'pinned',
      title: 'Screwed Block',
      note: 'Unlocks at Level 42!',
    ),
  ];
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
