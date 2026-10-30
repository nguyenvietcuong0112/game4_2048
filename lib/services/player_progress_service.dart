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

  static const int maxLives = 5;

  SharedPreferences? _prefs;

  int _currentLevel = 1;
  int _highestLevel = 20;
  int _coins = 875;
  int _lives = maxLives;
  int _levelUpCount = 3;
  int _timeFreezeCount = 3;
  int _pendingWinCoins = 0;
  Set<String> _seenMechanics = {};

  int get currentLevel => _currentLevel;
  int get highestLevel => _highestLevel;
  int get coins => _coins;
  int get lives => _lives;
  int get levelUpCount => _levelUpCount;
  int get timeFreezeCount => _timeFreezeCount;
  int get pendingWinCoins => _pendingWinCoins;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _currentLevel = _prefs?.getInt(_kCurrentLevel) ?? 1;
    _highestLevel = _prefs?.getInt(_kHighestLevel) ?? 20;
    _coins = _prefs?.getInt(_kCoins) ?? 875;
    _lives = (_prefs?.getInt(_kLives) ?? maxLives).clamp(1, maxLives);
    _levelUpCount = _prefs?.getInt(_kLevelUpCount) ?? 3;
    _timeFreezeCount = _prefs?.getInt(_kTimeFreezeCount) ?? 3;
    _seenMechanics = (_prefs?.getStringList(_kSeenMechanics) ?? []).toSet();
    notifyListeners();
  }

  bool hasSeenMechanic(String id) => _seenMechanics.contains(id);

  void markMechanicSeen(String id) {
    if (_seenMechanics.add(id)) {
      _prefs?.setStringList(_kSeenMechanics, _seenMechanics.toList());
      notifyListeners();
    }
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
    int cost = 200,
    int count = 3,
  }) {
    if (!spendCoins(cost)) return false;
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

  bool buyLevelUpPack({int cost = 200, int count = 3}) =>
      buyPowerUpPack(isLevelUp: true, cost: cost, count: count);

  bool buyTimeFreezePack({int cost = 200, int count = 3}) =>
      buyPowerUpPack(isLevelUp: false, cost: cost, count: count);
}
