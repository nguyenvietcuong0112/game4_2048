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
  static const _kFtueLoadingLogged = 'bo_ftue_loading_logged';
  static const _kFtueCompleted = 'bo_ftue_completed';
  static const _kVaseCurrentId = 'bo_vase_current_id';
  static const _kVaseStepCount = 'bo_vase_step_count';
  static const _kVaseClaimedIds = 'bo_vase_claimed_ids';
  static const _kVaseUnlockedIds = 'bo_vase_unlocked_ids';

  static const int maxLives = 5;

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
  int _lives = maxLives;
  int _levelUpCount = initialPowerUpInventory;
  int _timeFreezeCount = initialPowerUpInventory;
  int _pendingWinCoins = 0;
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
  int get lives => _lives;
  int get levelUpCount => _levelUpCount;
  int get timeFreezeCount => _timeFreezeCount;
  int get pendingWinCoins => _pendingWinCoins;
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
    _lives = (_prefs?.getInt(_kLives) ?? maxLives).clamp(1, maxLives);
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

  /// Adds [extraCoins] to `_pendingWinCoins` when the player watches a Rewarded Ad
  /// for `x2` Level Complete coins, persisting immediately on disk for crash safety.
  void doublePendingWinCoins(int extraCoins) {
    if (extraCoins <= 0) return;
    _pendingWinCoins += extraCoins;
    _prefs?.setInt(_kCoins, _coins + _pendingWinCoins);
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

  /// Records a won level step and returns animation data (oldProgress -> newProgress).
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
    );
  }

  /// Claims current vase milestone reward and advances to the next vase!
  void claimCurrentVaseMilestone() {
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

    // Reward coins
    if (cfg.rewardCoins > 0) {
      addCoins(cfg.rewardCoins);
    }

    // Unlock mechanic if applicable
    if (cfg.unlockMechanicId != null) {
      markMechanicSeen(cfg.unlockMechanicId!);
      if (cfg.unlockMechanicId == 'pu_level_up' ||
          cfg.unlockMechanicId == 'pu_time_freeze') {
        setFreePowerUpPending(cfg.unlockMechanicId!, true);
      }
    }

    // Advance to next vase
    _vaseCurrentId++;
    _vaseStepCount = 0;
    _prefs?.setInt(_kVaseCurrentId, _vaseCurrentId);
    _prefs?.setInt(_kVaseStepCount, _vaseStepCount);
    notifyListeners();
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
    _vaseCurrentId = 1;
    _vaseStepCount = 0;
    _vaseClaimedIds.clear();
    _vaseUnlockedIds.clear();
    await _prefs?.setInt(_kCurrentLevel, _currentLevel);
    await _prefs?.setInt(_kHighestLevel, _highestLevel);
    await _prefs?.setInt(_kCoins, _coins);
    await _prefs?.setInt(_kLives, _lives);
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
      unlockMechanicId: 'ice',
      rewardTitle: 'Ice Blocks',
      rewardCoins: 200,
      rewardNote: 'Unlocks at Level 9!',
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
      unlockMechanicId: 'pu_level_up',
      rewardTitle: 'Level Up',
      rewardCoins: 250,
      rewardNote: 'Booster unlocks at Level 17!',
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
      unlockMechanicId: 'pu_time_freeze',
      rewardTitle: 'Time Freeze',
      rewardCoins: 300,
      rewardNote: 'Booster unlocks at Level 27!',
    ),
  ];

  static VaseMilestoneConfig getForVaseId(int id) {
    if (id <= 4 && id >= 1) {
      return milestones[id - 1];
    }
    // High-level looping milestones (10 levels per vase)
    final cycle = (id - 5);
    final start = 27 + cycle * 10;
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

  static int determineInitialVaseId(int level) {
    if (level <= 3) return 1;
    if (level <= 8) return 2;
    if (level <= 16) return 3;
    if (level <= 26) return 4;
    return 5 + ((level - 27) ~/ 10);
  }
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

  const VaseStepAdvanceResult({
    required this.vaseId,
    required this.oldStep,
    required this.newStep,
    required this.totalSteps,
    required this.oldProgress,
    required this.newProgress,
    required this.didReach100Percent,
    required this.config,
  });
}
