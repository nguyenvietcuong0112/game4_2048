import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:funtap_global_sdk/funtap_global_sdk.dart';

/// All 4 supported in-game Boosters.
enum BoosterType {
  levelUp,
  timeFreeze,
  shuffle,
  hammer;

  String get id => switch (this) {
        BoosterType.levelUp => RemoteConfigService.boosterIdLevelUp,
        BoosterType.timeFreeze => RemoteConfigService.boosterIdTimeFreeze,
        BoosterType.shuffle => RemoteConfigService.boosterIdShuffle,
        BoosterType.hammer => RemoteConfigService.boosterIdHammer,
      };

  String get analyticsName => switch (this) {
        BoosterType.levelUp => 'level_up',
        BoosterType.timeFreeze => 'time_freeze',
        BoosterType.shuffle => 'shuffle',
        BoosterType.hammer => 'hammer',
      };

  String get displayTitle => switch (this) {
        BoosterType.levelUp => 'Level Up',
        BoosterType.timeFreeze => 'Time Freeze',
        BoosterType.shuffle => 'Shuffle',
        BoosterType.hammer => 'Hammer',
      };

  String get uppercaseTitle => displayTitle.toUpperCase();

  String get description => switch (this) {
        BoosterType.levelUp =>
          'Merge a matching pair instantly, wherever they are!',
        BoosterType.timeFreeze => 'Freezes the timer for 20 seconds',
        BoosterType.shuffle =>
          'Shuffles numbers across free blocks to open fresh merges!',
        BoosterType.hammer =>
          'Split a block (4+) into two 1x1 half-value blocks!',
      };

  int get defaultUnlockLevel => switch (this) {
        BoosterType.levelUp => RemoteConfigService.defaultLevelUpUnlockLevel,
        BoosterType.timeFreeze =>
          RemoteConfigService.defaultTimeFreezeUnlockLevel,
        BoosterType.shuffle => RemoteConfigService.defaultShuffleUnlockLevel,
        BoosterType.hammer => RemoteConfigService.defaultHammerUnlockLevel,
      };

  static BoosterType? fromId(String? raw) {
    final canonical = RemoteConfigService.normalizeBoosterId(raw);
    return switch (canonical) {
      RemoteConfigService.boosterIdLevelUp => BoosterType.levelUp,
      RemoteConfigService.boosterIdTimeFreeze => BoosterType.timeFreeze,
      RemoteConfigService.boosterIdShuffle => BoosterType.shuffle,
      RemoteConfigService.boosterIdHammer => BoosterType.hammer,
      _ => null,
    };
  }
}

/// Represents a booster's unlock order entry resolved from Remote Config (`game_config.unlock_booster` / `booster_unlock_order`).
class BoosterUnlockEntry {
  final String id; // Canonical ID: 'pu_level_up', 'pu_time_freeze', 'pu_shuffle', 'pu_hammer'
  final int unlockLevel;

  const BoosterUnlockEntry({
    required this.id,
    required this.unlockLevel,
  });

  BoosterType get type => BoosterType.fromId(id) ?? BoosterType.levelUp;

  @override
  bool operator ==(Object other) =>
      other is BoosterUnlockEntry &&
      other.id == id &&
      other.unlockLevel == unlockLevel;

  @override
  int get hashCode => Object.hash(id, unlockLevel);

  @override
  String toString() => 'BoosterUnlockEntry($id: Lv.$unlockLevel)';
}

/// Remote Config Service for Block Order 2048 Ads & Gameplay parameters.
/// Reads values from Funtap Global SDK with robust defaults matching the ad spec.
class RemoteConfigService {
  RemoteConfigService._();

  static const String boosterIdLevelUp = 'pu_level_up';
  static const String boosterIdTimeFreeze = 'pu_time_freeze';
  static const String boosterIdShuffle = 'pu_shuffle';
  static const String boosterIdHammer = 'pu_hammer';

  // Unified JSON Object Remote Config key bundling 3 gameplay/monetization groups:
  // `ads`, `coin`, and `unlock_booster`.
  // NOTE: `cheat_enable` is intentionally kept as a separate standalone Remote Config key
  // so it can be gated independently via Firebase App Version conditions without risking
  // live store builds or touching `game_config`.
  static const String keyGameConfig = 'game_config';

  // Legacy flat keys (kept as fallback for backward compatibility)
  static const String keyInterLevelX = 'Inter_level_x';
  static const String keyAdsInterval = 'Ads_interval';
  static const String keyAoaFormat = 'Aoa_format';
  static const String keyAdsReplay = 'Ads_replay';
  static const String keyAdsResume = 'Ads_resume';
  static const String keyCheatEnable = 'cheat_enable';

  // Economy / Coin Price & Reward Remote Config keys
  static const String keyBoosterLevelUpPrice = 'booster_level_up_price';
  static const String keyBoosterTimeFreezePrice = 'booster_time_freeze_price';
  static const String keyBoosterShufflePrice = 'booster_shuffle_price';
  static const String keyBoosterHammerPrice = 'booster_hammer_price';
  static const String keyLiveHeartRefillPrice = 'live_heart_refill_price';
  static const String keyPlayOnBasePrice = 'play_on_base_price';
  static const String keyPlayOnIncrementPrice = 'play_on_increment_price';
  static const String keyWinLevelCoinReward = 'win_level_coin_reward';

  // Booster Unlock Order Remote Config key.
  static const String keyBoosterUnlockOrder = 'booster_unlock_order';

  static const int defaultBoosterLevelUpPrice = 600;
  static const int defaultBoosterTimeFreezePrice = 450;
  static const int defaultBoosterShufflePrice = 450;
  static const int defaultBoosterHammerPrice = 550;
  static const int defaultLiveHeartRefillPrice = 900;
  static const int defaultPlayOnBasePrice = 450;
  static const int defaultPlayOnIncrementPrice = 150;
  static const int defaultWinLevelCoinReward = 25;
  static const int defaultLevelUpUnlockLevel = 17;
  static const int defaultTimeFreezeUnlockLevel = 27;
  static const int defaultShuffleUnlockLevel = 32;
  static const int defaultHammerUnlockLevel = 38;
  static const int minBoosterUnlockLevel = 2;

  static const List<int> _defaultBoosterSlotLevels = [
    defaultLevelUpUnlockLevel,
    defaultTimeFreezeUnlockLevel,
    defaultShuffleUnlockLevel,
    defaultHammerUnlockLevel,
  ];

  static const List<BoosterUnlockEntry> defaultBoosterUnlockOrder = [
    BoosterUnlockEntry(
      id: boosterIdLevelUp,
      unlockLevel: defaultLevelUpUnlockLevel,
    ),
    BoosterUnlockEntry(
      id: boosterIdTimeFreeze,
      unlockLevel: defaultTimeFreezeUnlockLevel,
    ),
    BoosterUnlockEntry(
      id: boosterIdShuffle,
      unlockLevel: defaultShuffleUnlockLevel,
    ),
    BoosterUnlockEntry(
      id: boosterIdHammer,
      unlockLevel: defaultHammerUnlockLevel,
    ),
  ];

  // Cached values with defaults (`cheat_enable` defaults to `false` for store safety!)
  static int _interLevelX = 2; // Show inter from Level 2 onwards
  static int _adsInterval = 25; // 25s cooldown between interstitials
  static bool _aoaFormat = false; // false = AdMob, true = MAX
  static bool _adsReplay = false; // false = Inter, true = Native full screen
  static bool _adsResume = false; // false = AOA, true = Inter
  static int _boosterLevelUpPrice = defaultBoosterLevelUpPrice;
  static int _boosterTimeFreezePrice = defaultBoosterTimeFreezePrice;
  static int _boosterShufflePrice = defaultBoosterShufflePrice;
  static int _boosterHammerPrice = defaultBoosterHammerPrice;
  static int _liveHeartRefillPrice = defaultLiveHeartRefillPrice;
  static int _playOnBasePrice = defaultPlayOnBasePrice;
  static int _playOnIncrementPrice = defaultPlayOnIncrementPrice;
  static int _winLevelCoinReward = defaultWinLevelCoinReward;
  static bool _isListening = false;
  static final ValueNotifier<bool> cheatEnableNotifier =
      ValueNotifier<bool>(false);
  static final ValueNotifier<List<BoosterUnlockEntry>>
      boosterUnlockOrderNotifier =
      ValueNotifier<List<BoosterUnlockEntry>>(defaultBoosterUnlockOrder);

  static int get interLevelX => _interLevelX;
  static int get adsInterval => _adsInterval;
  static bool get aoaFormat => _aoaFormat;
  static bool get adsReplay => _adsReplay;
  static bool get adsResume => _adsResume;
  static bool get cheatEnable => cheatEnableNotifier.value;
  static int get boosterLevelUpPrice => _boosterLevelUpPrice;
  static int get boosterTimeFreezePrice => _boosterTimeFreezePrice;
  static int get boosterShufflePrice => _boosterShufflePrice;
  static int get boosterHammerPrice => _boosterHammerPrice;
  static int get liveHeartRefillPrice => _liveHeartRefillPrice;
  static int get playOnBasePrice => _playOnBasePrice;
  static int get playOnIncrementPrice => _playOnIncrementPrice;
  static int get winLevelCoinReward => _winLevelCoinReward;
  static List<BoosterUnlockEntry> get boosterUnlockOrder =>
      boosterUnlockOrderNotifier.value;
  static int get boosterLevelUpUnlockLevel =>
      unlockLevelForBooster(boosterIdLevelUp);
  static int get boosterTimeFreezeUnlockLevel =>
      unlockLevelForBooster(boosterIdTimeFreeze);
  static int get boosterShuffleUnlockLevel =>
      unlockLevelForBooster(boosterIdShuffle);
  static int get boosterHammerUnlockLevel =>
      unlockLevelForBooster(boosterIdHammer);

  static int priceForBooster(BoosterType type) => switch (type) {
        BoosterType.levelUp => _boosterLevelUpPrice,
        BoosterType.timeFreeze => _boosterTimeFreezePrice,
        BoosterType.shuffle => _boosterShufflePrice,
        BoosterType.hammer => _boosterHammerPrice,
      };

  static int unlockLevelForBoosterType(BoosterType type) =>
      unlockLevelForBooster(type.id);

  static int defaultUnlockLevelForBoosterId(String boosterId) {
    final canonical = normalizeBoosterId(boosterId) ?? boosterId;
    return switch (canonical) {
      boosterIdTimeFreeze => defaultTimeFreezeUnlockLevel,
      boosterIdShuffle => defaultShuffleUnlockLevel,
      boosterIdHammer => defaultHammerUnlockLevel,
      _ => defaultLevelUpUnlockLevel,
    };
  }

  static int unlockLevelForBooster(String boosterId) {
    final canonical = normalizeBoosterId(boosterId) ?? boosterId;
    for (final entry in boosterUnlockOrderNotifier.value) {
      if (entry.id == canonical) return entry.unlockLevel;
    }
    return defaultUnlockLevelForBoosterId(canonical);
  }

  /// Returns `0..3` HUD slot index ordered ascending by unlock level (`0` = leftmost, `3` = rightmost).
  static int hudSlotIndexForBooster(String boosterId) {
    final canonical = normalizeBoosterId(boosterId) ?? boosterId;
    final list = boosterUnlockOrderNotifier.value;
    for (int i = 0; i < list.length; i++) {
      if (list[i].id == canonical) return i;
    }
    return switch (canonical) {
      boosterIdLevelUp => 0,
      boosterIdTimeFreeze => 1,
      boosterIdShuffle => 2,
      boosterIdHammer => 3,
      _ => 0,
    };
  }

  /// Normalizes booster aliases (`pu_level_up`, `level_up`, `pu_time_freeze`,
  /// `time_freeze`, `pu_shuffle`, `shuffle`, `pu_hammer`, `hammer`) to canonical IDs.
  static String? normalizeBoosterId(String? raw) {
    if (raw == null) return null;
    final norm = raw.trim().toLowerCase().replaceAll(RegExp(r'[\s\-]+'), '_');
    return switch (norm) {
      'pu_level_up' || 'level_up' || 'levelup' || '0' => boosterIdLevelUp,
      'pu_time_freeze' ||
      'time_freeze' ||
      'timefreeze' ||
      '1' =>
        boosterIdTimeFreeze,
      'pu_shuffle' || 'shuffle' || '2' => boosterIdShuffle,
      'pu_hammer' || 'hammer' || '3' => boosterIdHammer,
      _ => null,
    };
  }

  static void _applyBoosterUnlockOrder(List<BoosterUnlockEntry> next) {
    final cur = boosterUnlockOrderNotifier.value;
    if (listEquals(cur, next)) return;
    boosterUnlockOrderNotifier.value = List<BoosterUnlockEntry>.unmodifiable(
      next,
    );
  }

  static dynamic _lookupIgnoreCase(Map<dynamic, dynamic> map, List<String> names) {
    for (final name in names) {
      if (map.containsKey(name)) return map[name];
    }
    final normalizedTargets = {
      for (final n in names) n.toLowerCase(),
    };
    for (final entry in map.entries) {
      final key = entry.key.toString().trim().toLowerCase();
      if (normalizedTargets.contains(key)) {
        return entry.value;
      }
    }
    return null;
  }

  static bool? _parseBoolDynamic(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final s = value.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return null;
  }

  static int? _parseIntDynamic(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static int? _parseNonNegativeIntDynamic(dynamic value) {
    final parsed = _parseIntDynamic(value);
    return (parsed != null && parsed >= 0) ? parsed : null;
  }

  static List<BoosterUnlockEntry>? _tryParseBoosterUnlockDynamic(dynamic decoded) {
    if (decoded == null) return null;
    if (decoded is String) {
      final s = decoded.trim();
      if (s.isEmpty) return null;
      return parseBoosterUnlockOrder(s);
    }

    final parsedEntries = <({String id, int? level})>[];
    if (decoded is List) {
      for (final item in decoded) {
        if (item is String) {
          final id = normalizeBoosterId(item);
          if (id != null) parsedEntries.add((id: id, level: null));
        } else if (item is Map) {
          final rawId = _lookupIgnoreCase(
            item,
            const ['id', 'booster', 'type', 'name'],
          )?.toString();
          final id = normalizeBoosterId(rawId);
          if (id == null) continue;
          final rawLevel = _lookupIgnoreCase(
            item,
            const ['level', 'unlock_level', 'unlockLevel'],
          );
          final lv = _parseIntDynamic(rawLevel);
          parsedEntries.add((id: id, level: lv));
        }
      }
    } else if (decoded is Map) {
      // Support wrapped object form:
      // e.g. `{"unlock_booster": [...]}`, `{"boosters": [...]}`, `{"order": [...]}`
      final wrapped = _lookupIgnoreCase(
        decoded,
        const ['unlock_booster', 'booster_unlock_order', 'unlockBooster', 'boosters', 'order', 'items'],
      );
      if (wrapped != null && !identical(wrapped, decoded)) {
        return _tryParseBoosterUnlockDynamic(wrapped);
      }

      for (final entry in decoded.entries) {
        final id = normalizeBoosterId(entry.key.toString());
        if (id == null) continue;
        final lv = _parseIntDynamic(entry.value);
        parsedEntries.add((id: id, level: lv));
      }
    }

    if (parsedEntries.isEmpty) return null;
    return _finalizeBoosterUnlockEntries(parsedEntries);
  }

  static List<BoosterUnlockEntry> _finalizeBoosterUnlockEntries(
    List<({String id, int? level})> parsedEntries,
  ) {
    if (parsedEntries.isEmpty) return defaultBoosterUnlockOrder;

    // Deduplicate while preserving configured order
    final seenIds = <String>{};
    final unique = <({String id, int? level})>[];
    for (final e in parsedEntries) {
      if (seenIds.add(e.id)) {
        unique.add(e);
      }
    }

    final hasAnyExplicitLevel = unique.any((e) => e.level != null);
    final resolved = <({String id, int unlockLevel, int configIdx})>[];

    for (int i = 0; i < unique.length; i++) {
      final item = unique[i];
      final int rawLv;
      if (item.level != null) {
        rawLv = item.level!;
      } else if (!hasAnyExplicitLevel && i < _defaultBoosterSlotLevels.length) {
        // Order-only format (e.g. "time_freeze,level_up") maps onto default slot levels [17, 27]
        rawLv = _defaultBoosterSlotLevels[i];
      } else {
        rawLv = defaultUnlockLevelForBoosterId(item.id);
      }
      final clampedLv = rawLv < minBoosterUnlockLevel
          ? minBoosterUnlockLevel
          : rawLv;
      resolved.add((id: item.id, unlockLevel: clampedLv, configIdx: i));
    }

    // Ensure every known booster is present even if Remote Config only listed one
    for (final def in defaultBoosterUnlockOrder) {
      if (!seenIds.contains(def.id)) {
        final slotIdx = resolved.length;
        final fallbackLv =
            (!hasAnyExplicitLevel && slotIdx < _defaultBoosterSlotLevels.length)
                ? _defaultBoosterSlotLevels[slotIdx]
                : def.unlockLevel;
        resolved.add((
          id: def.id,
          unlockLevel: fallbackLv,
          configIdx: slotIdx,
        ));
      }
    }

    // Sort ascending by unlockLevel with stable tie-break on configured order
    resolved.sort((a, b) {
      final lvCmp = a.unlockLevel.compareTo(b.unlockLevel);
      if (lvCmp != 0) return lvCmp;
      return a.configIdx.compareTo(b.configIdx);
    });

    return List<BoosterUnlockEntry>.unmodifiable([
      for (final r in resolved)
        BoosterUnlockEntry(id: r.id, unlockLevel: r.unlockLevel),
    ]);
  }

  /// Parses `booster_unlock_order` / `unlock_booster` from JSON (object, wrapped object,
  /// or array) or compact CSV into a validated, deduplicated, unlock-level-sorted list.
  static List<BoosterUnlockEntry> parseBoosterUnlockOrder(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return defaultBoosterUnlockOrder;

    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        final parsed = _tryParseBoosterUnlockDynamic(decoded);
        if (parsed != null) return parsed;
        return defaultBoosterUnlockOrder;
      } catch (_) {
        // Fall through to CSV parser
      }
    }

    final parsedEntries = <({String id, int? level})>[];
    final tokens = trimmed.split(RegExp(r'[,;|]+'));
    for (final token in tokens) {
      final t = token.trim();
      if (t.isEmpty) continue;
      final parts = t.split(RegExp(r'[:=]'));
      final id = normalizeBoosterId(parts.first);
      if (id == null) continue;
      int? lv;
      if (parts.length >= 2) {
        lv = int.tryParse(parts[1].trim());
      }
      parsedEntries.add((id: id, level: lv));
    }

    return _finalizeBoosterUnlockEntries(parsedEntries);
  }

  /// Parses and applies the unified `game_config` JSON object bundling
  /// `ads`, `coin`, and `unlock_booster` (`cheat_enable` is strictly fetched standalone).
  /// Returns `true` if valid JSON object.
  static bool applyGameConfigJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return false;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return false;

      // 1. `ads` section
      final adsRaw = _lookupIgnoreCase(decoded, const ['ads', 'ads_config', 'ad_config']);
      if (adsRaw is Map) {
        final interLv = _parseIntDynamic(
          _lookupIgnoreCase(adsRaw, const ['Inter_level_x', 'inter_level_x', 'interLevelX']),
        );
        if (interLv != null) _interLevelX = interLv;

        final interval = _parseIntDynamic(
          _lookupIgnoreCase(adsRaw, const ['Ads_interval', 'ads_interval', 'adsInterval']),
        );
        if (interval != null) _adsInterval = interval;

        final aoa = _parseBoolDynamic(
          _lookupIgnoreCase(adsRaw, const ['Aoa_format', 'aoa_format', 'aoaFormat']),
        );
        if (aoa != null) _aoaFormat = aoa;

        final replay = _parseBoolDynamic(
          _lookupIgnoreCase(adsRaw, const ['Ads_replay', 'ads_replay', 'adsReplay']),
        );
        if (replay != null) _adsReplay = replay;

        final resume = _parseBoolDynamic(
          _lookupIgnoreCase(adsRaw, const ['Ads_resume', 'ads_resume', 'adsResume']),
        );
        if (resume != null) _adsResume = resume;
      }

      // 2. `coin` section
      final coinRaw = _lookupIgnoreCase(decoded, const ['coin', 'coins', 'coin_config', 'economy']);
      if (coinRaw is Map) {
        final lvUpPrice = _parseNonNegativeIntDynamic(
          _lookupIgnoreCase(coinRaw, const ['booster_level_up_price', 'boosterLevelUpPrice']),
        );
        if (lvUpPrice != null) _boosterLevelUpPrice = lvUpPrice;

        final tfPrice = _parseNonNegativeIntDynamic(
          _lookupIgnoreCase(coinRaw, const ['booster_time_freeze_price', 'boosterTimeFreezePrice']),
        );
        if (tfPrice != null) _boosterTimeFreezePrice = tfPrice;

        final shufflePrice = _parseNonNegativeIntDynamic(
          _lookupIgnoreCase(coinRaw, const ['booster_shuffle_price', 'boosterShufflePrice']),
        );
        if (shufflePrice != null) _boosterShufflePrice = shufflePrice;

        final hammerPrice = _parseNonNegativeIntDynamic(
          _lookupIgnoreCase(coinRaw, const ['booster_hammer_price', 'boosterHammerPrice']),
        );
        if (hammerPrice != null) _boosterHammerPrice = hammerPrice;

        final heartPrice = _parseNonNegativeIntDynamic(
          _lookupIgnoreCase(coinRaw, const ['live_heart_refill_price', 'liveHeartRefillPrice']),
        );
        if (heartPrice != null) _liveHeartRefillPrice = heartPrice;

        final playOnBase = _parseNonNegativeIntDynamic(
          _lookupIgnoreCase(coinRaw, const ['play_on_base_price', 'playOnBasePrice']),
        );
        if (playOnBase != null) _playOnBasePrice = playOnBase;

        final playOnInc = _parseNonNegativeIntDynamic(
          _lookupIgnoreCase(coinRaw, const ['play_on_increment_price', 'playOnIncrementPrice']),
        );
        if (playOnInc != null) _playOnIncrementPrice = playOnInc;

        final winReward = _parseNonNegativeIntDynamic(
          _lookupIgnoreCase(coinRaw, const ['win_level_coin_reward', 'winLevelCoinReward']),
        );
        if (winReward != null) _winLevelCoinReward = winReward;
      }

      // 3. `unlock_booster` section
      final boosterRaw = _lookupIgnoreCase(
        decoded,
        const ['unlock_booster', 'booster_unlock_order', 'unlockBooster', 'boosters'],
      );
      final parsedOrder = _tryParseBoosterUnlockDynamic(boosterRaw);
      if (parsedOrder != null) {
        _applyBoosterUnlockOrder(parsedOrder);
      }

      return true;
    } catch (e) {
      debugPrint('[RemoteConfig] Invalid game_config JSON: $e');
      return false;
    }
  }

  /// Initializes RemoteConfigService and fetches remote configs immediately.
  /// Safe to call regardless of whether `AdsManager.enableAds` is true or false.
  static void init() {
    listenToUpdates();
    fetchConfigs();
  }

  /// Fetch all Remote Configs from FGSDK
  static Future<void> fetchConfigs() async {
    try {
      final isReady = await FGSDK.isRemoteConfigReady();
      debugPrint('[RemoteConfig] isRemoteConfigReady: $isReady');

      _interLevelX = await _fetchInt(keyInterLevelX, 2);
      _adsInterval = await _fetchInt(keyAdsInterval, 25);
      _aoaFormat = await _fetchBool(keyAoaFormat, false);
      _adsReplay = await _fetchBool(keyAdsReplay, false);
      _adsResume = await _fetchBool(keyAdsResume, false);
      _boosterLevelUpPrice = await _fetchNonNegativeInt(
        keyBoosterLevelUpPrice,
        defaultBoosterLevelUpPrice,
      );
      _boosterTimeFreezePrice = await _fetchNonNegativeInt(
        keyBoosterTimeFreezePrice,
        defaultBoosterTimeFreezePrice,
      );
      _boosterShufflePrice = await _fetchNonNegativeInt(
        keyBoosterShufflePrice,
        defaultBoosterShufflePrice,
      );
      _boosterHammerPrice = await _fetchNonNegativeInt(
        keyBoosterHammerPrice,
        defaultBoosterHammerPrice,
      );
      _liveHeartRefillPrice = await _fetchNonNegativeInt(
        keyLiveHeartRefillPrice,
        defaultLiveHeartRefillPrice,
      );
      _playOnBasePrice = await _fetchNonNegativeInt(
        keyPlayOnBasePrice,
        defaultPlayOnBasePrice,
      );
      _playOnIncrementPrice = await _fetchNonNegativeInt(
        keyPlayOnIncrementPrice,
        defaultPlayOnIncrementPrice,
      );
      _winLevelCoinReward = await _fetchNonNegativeInt(
        keyWinLevelCoinReward,
        defaultWinLevelCoinReward,
      );
      final rawBoosterOrder = await _fetchString(keyBoosterUnlockOrder, '');
      _applyBoosterUnlockOrder(parseBoosterUnlockOrder(rawBoosterOrder));
      final fetchedCheat = await _fetchBool(
        keyCheatEnable,
        await _fetchBool('Cheat_enable', false),
      );
      if (cheatEnableNotifier.value != fetchedCheat) {
        cheatEnableNotifier.value = fetchedCheat;
      }

      // Unified JSON object (`game_config`) overrides legacy flat keys when configured on Firebase
      final rawGameConfig = await _fetchString(keyGameConfig, '');
      final usedBundledConfig = applyGameConfigJson(rawGameConfig);

      debugPrint(
        '[RemoteConfig] Configs loaded (game_config=$usedBundledConfig) -> '
        'interLevelX: $_interLevelX, '
        'adsInterval: ${_adsInterval}s, '
        'aoaFormat: $_aoaFormat, '
        'adsReplay: $_adsReplay, '
        'adsResume: $_adsResume, '
        'boosterLevelUpPrice: $_boosterLevelUpPrice, '
        'boosterTimeFreezePrice: $_boosterTimeFreezePrice, '
        'boosterShufflePrice: $_boosterShufflePrice, '
        'boosterHammerPrice: $_boosterHammerPrice, '
        'liveHeartRefillPrice: $_liveHeartRefillPrice, '
        'playOnBasePrice: $_playOnBasePrice, '
        'playOnIncrementPrice: $_playOnIncrementPrice, '
        'winLevelCoinReward: $_winLevelCoinReward, '
        'boosterUnlockOrder: $boosterUnlockOrder, '
        'cheat_enable: ${cheatEnableNotifier.value}',
      );
    } catch (e) {
      debugPrint('[RemoteConfig] Error fetching remote configs: $e');
    }
  }

  /// Listen to real-time remote config fetched event
  static void listenToUpdates() {
    if (_isListening) return;
    _isListening = true;
    try {
      FGSDK.onRemoteConfigFetched.listen((_) {
        debugPrint('[RemoteConfig] onRemoteConfigFetched triggered, refreshing...');
        fetchConfigs();
      });
    } catch (e) {
      debugPrint('[RemoteConfig] listenToUpdates error: $e');
    }
  }

  @visibleForTesting
  static void setMockValues({
    int? interLevelX,
    int? adsInterval,
    bool? aoaFormat,
    bool? adsReplay,
    bool? adsResume,
    bool? cheatEnable,
    int? boosterLevelUpPrice,
    int? boosterTimeFreezePrice,
    int? boosterShufflePrice,
    int? boosterHammerPrice,
    int? liveHeartRefillPrice,
    int? playOnBasePrice,
    int? playOnIncrementPrice,
    int? winLevelCoinReward,
    String? boosterUnlockOrderRaw,
    List<BoosterUnlockEntry>? boosterUnlockOrder,
  }) {
    if (interLevelX != null) _interLevelX = interLevelX;
    if (adsInterval != null) _adsInterval = adsInterval;
    if (aoaFormat != null) _aoaFormat = aoaFormat;
    if (adsReplay != null) _adsReplay = adsReplay;
    if (adsResume != null) _adsResume = adsResume;
    if (cheatEnable != null) cheatEnableNotifier.value = cheatEnable;
    if (boosterLevelUpPrice != null && boosterLevelUpPrice >= 0) {
      _boosterLevelUpPrice = boosterLevelUpPrice;
    }
    if (boosterTimeFreezePrice != null && boosterTimeFreezePrice >= 0) {
      _boosterTimeFreezePrice = boosterTimeFreezePrice;
    }
    if (boosterShufflePrice != null && boosterShufflePrice >= 0) {
      _boosterShufflePrice = boosterShufflePrice;
    }
    if (boosterHammerPrice != null && boosterHammerPrice >= 0) {
      _boosterHammerPrice = boosterHammerPrice;
    }
    if (liveHeartRefillPrice != null && liveHeartRefillPrice >= 0) {
      _liveHeartRefillPrice = liveHeartRefillPrice;
    }
    if (playOnBasePrice != null && playOnBasePrice >= 0) {
      _playOnBasePrice = playOnBasePrice;
    }
    if (playOnIncrementPrice != null && playOnIncrementPrice >= 0) {
      _playOnIncrementPrice = playOnIncrementPrice;
    }
    if (winLevelCoinReward != null && winLevelCoinReward >= 0) {
      _winLevelCoinReward = winLevelCoinReward;
    }
    if (boosterUnlockOrderRaw != null) {
      _applyBoosterUnlockOrder(parseBoosterUnlockOrder(boosterUnlockOrderRaw));
    } else if (boosterUnlockOrder != null && boosterUnlockOrder.isNotEmpty) {
      _applyBoosterUnlockOrder(boosterUnlockOrder);
    }
  }

  @visibleForTesting
  static void resetDefaultsForTest() {
    _interLevelX = 2;
    _adsInterval = 25;
    _aoaFormat = false;
    _adsReplay = false;
    _adsResume = false;
    _boosterLevelUpPrice = defaultBoosterLevelUpPrice;
    _boosterTimeFreezePrice = defaultBoosterTimeFreezePrice;
    _boosterShufflePrice = defaultBoosterShufflePrice;
    _boosterHammerPrice = defaultBoosterHammerPrice;
    _liveHeartRefillPrice = defaultLiveHeartRefillPrice;
    _playOnBasePrice = defaultPlayOnBasePrice;
    _playOnIncrementPrice = defaultPlayOnIncrementPrice;
    _winLevelCoinReward = defaultWinLevelCoinReward;
    _applyBoosterUnlockOrder(defaultBoosterUnlockOrder);
    cheatEnableNotifier.value = false;
  }

  static Future<String> _fetchString(String key, String defaultValue) async {
    try {
      final s = (await FGSDK.getRemoteConfigString(key, '')).trim();
      return s.isEmpty ? defaultValue : s;
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<bool> _fetchBool(String key, bool defaultValue) async {
    try {
      final s = (await FGSDK.getRemoteConfigString(key, '')).toLowerCase().trim();
      if (s.isEmpty) return defaultValue;
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
      return await FGSDK.getRemoteConfigBool(key, defaultValue);
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<int> _fetchInt(String key, int defaultValue) async {
    try {
      final s = (await FGSDK.getRemoteConfigString(key, '')).trim();
      if (s.isEmpty) return defaultValue;
      final parsed = int.tryParse(s);
      if (parsed != null) return parsed;
      return await FGSDK.getRemoteConfigInt(key, defaultValue);
    } catch (_) {
      return defaultValue;
    }
  }

  static Future<int> _fetchNonNegativeInt(String key, int defaultValue) async {
    final value = await _fetchInt(key, defaultValue);
    return value >= 0 ? value : defaultValue;
  }
}
