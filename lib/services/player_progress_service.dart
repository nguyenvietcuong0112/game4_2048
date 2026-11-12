import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerProgressService extends ChangeNotifier {
  static const _kCurrentLevel = 'bo_current_level';
  static const _kHighestLevel = 'bo_highest_level';
  static const _kCoins = 'bo_coins';
  static const _kLives = 'bo_lives';
  static const _kLevelUpCount = 'bo_pu_level_up';
  static const _kTimeFreezeCount = 'bo_pu_time_freeze';
  static const _kSeenMechanics = 'bo_seen_mechanics';
  static const _kFreePowerUpsPending = 'bo_free_pu_pending';

  static const int maxLives = 5;

  /// Exact Unity `remote_config.json` power-up progression & economy settings:
  /// - `LevelUp` (`type = 0`): `unlock_level = 17`, `initial_inventory = 3`, `price_coins = 600` (`x3`)
  /// - `TimeFreeze` (`type = 1`): `unlock_level = 27`, `initial_inventory = 3`, `price_coins = 450` (`x3`), `duration = 20s`
  static const int levelUpUnlockLevel = 17;
  static const int timeFreezeUnlockLevel = 27;
  static const int levelUpPackCost = 600;
  static const int timeFreezePackCost = 450;
  static const int initialPowerUpInventory = 3;

  SharedPreferences? _prefs;

  int _currentLevel = 1;
  int _highestLevel = 1;
  int _coins = 875;
  int _lives = maxLives;
  int _levelUpCount = initialPowerUpInventory;
  int _timeFreezeCount = initialPowerUpInventory;
  int _pendingWinCoins = 0;
  Set<String> _seenMechanics = {};
  Set<String> _freePowerUpsPending = {};

  int get currentLevel => _currentLevel;
  int get highestLevel => _highestLevel;
  int get coins => _coins;
  int get lives => _lives;
  int get levelUpCount => _levelUpCount;
  int get timeFreezeCount => _timeFreezeCount;
  int get pendingWinCoins => _pendingWinCoins;

  /// Exact `PowerUpService.IsUnlockLevelReached(type)` checked against active campaign level
  /// (`levelNumber >= 17` for `LevelUp`, `levelNumber >= 27` for `TimeFreeze`).
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
    _lives = (_prefs?.getInt(_kLives) ?? maxLives).clamp(1, maxLives);
    _levelUpCount =
        _prefs?.getInt(_kLevelUpCount) ?? initialPowerUpInventory;
    _timeFreezeCount =
        _prefs?.getInt(_kTimeFreezeCount) ?? initialPowerUpInventory;
    _seenMechanics = (_prefs?.getStringList(_kSeenMechanics) ?? []).toSet();
    _freePowerUpsPending =
        (_prefs?.getStringList(_kFreePowerUpsPending) ?? []).toSet();
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
    _prefs?.setInt(_kCoins, _coins + _pendingWinCoins);
    if (!isBonus) {
      final next = _currentLevel + 1;
      if (next > _highestLevel) {
        _highestLevel = next;
        _prefs?.setInt(_kHighestLevel, _highestLevel);
      }
    }
    notifyListeners();
  }

  /// Credits a chunk of pending win coins during the flying-coin collect animation.
  void collectPendingWinCoinChunk(int amount) {
    if (_pendingWinCoins <= 0) return;
    final delta = amount.clamp(0, _pendingWinCoins);
    _pendingWinCoins -= delta;
    _coins += delta;
    _prefs?.setInt(_kCoins, _coins + _pendingWinCoins);
    notifyListeners();
  }

  void flushPendingWinCoins() {
    if (_pendingWinCoins <= 0) return;
    _coins += _pendingWinCoins;
    _pendingWinCoins = 0;
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

  void loseLife() {
    if (_lives > 0) {
      _lives--;
      _prefs?.setInt(_kLives, _lives);
      notifyListeners();
    }
  }

  void ensureAtLeastOneLife() {
    if (_lives <= 0) {
      _lives = maxLives;
      _prefs?.setInt(_kLives, _lives);
      notifyListeners();
    }
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
    flushPendingWinCoins();
    _coins += amount;
    _prefs?.setInt(_kCoins, _coins);
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
    final resolvedCost =
        cost ?? (isLevelUp ? levelUpPackCost : timeFreezePackCost);
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

  bool buyLevelUpPack({int cost = levelUpPackCost, int count = 3}) =>
      buyPowerUpPack(isLevelUp: true, cost: cost, count: count);

  bool buyTimeFreezePack({int cost = timeFreezePackCost, int count = 3}) =>
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

  void cheatSetLives(int livesCount) {
    _lives = livesCount.clamp(0, maxLives);
    _prefs?.setInt(_kLives, _lives);
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

  Future<void> cheatResetAllProgress() async {
    flushPendingWinCoins();
    _currentLevel = 1;
    _highestLevel = 1;
    _coins = 875;
    _lives = maxLives;
    _levelUpCount = initialPowerUpInventory;
    _timeFreezeCount = initialPowerUpInventory;
    _seenMechanics.clear();
    _freePowerUpsPending.clear();
    await _prefs?.setInt(_kCurrentLevel, _currentLevel);
    await _prefs?.setInt(_kHighestLevel, _highestLevel);
    await _prefs?.setInt(_kCoins, _coins);
    await _prefs?.setInt(_kLives, _lives);
    await _prefs?.setInt(_kLevelUpCount, _levelUpCount);
    await _prefs?.setInt(_kTimeFreezeCount, _timeFreezeCount);
    await _prefs?.setStringList(_kSeenMechanics, const []);
    await _prefs?.setStringList(_kFreePowerUpsPending, const []);
    notifyListeners();
  }
}
