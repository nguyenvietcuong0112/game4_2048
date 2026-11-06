import 'dart:async';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioHapticsService extends ChangeNotifier {
  static const _kSound = 'bo_sound_enabled';
  static const _kMusic = 'bo_music_enabled';
  static const _kHaptics = 'bo_haptics_enabled';

  /// Balanced BGM volume so `0 dBFS`-mastered `BO_BGM_Gameplay_02_Loop` sits cleanly
  /// underneath `-10..-18 dBFS` tactile gameplay SFX (`AudioEntry.volume = 1.0`).
  static const double _bgmVolume = 0.22;

  static const Map<String, (int minPlayers, int maxPlayers)> _pooledSfxSpecs = {
    'sfx_block_grab.wav': (2, 4),
    'sfx_block_put.wav': (2, 4),
    'sfx_block_attract.wav': (2, 4),
    'sfx_block_merge.wav': (2, 5),
    'sfx_ice_break_small.wav': (1, 3),
    'sfx_ice_break_whole.wav': (1, 3),
    'sfx_button_click.wav': (1, 3),
    'sfx_pu_select.wav': (1, 2),
    'sfx_levelup_arrow.wav': (1, 2),
    'sfx_levelup_fly.wav': (1, 2),
    'sfx_levelup_merge.wav': (1, 2),
    'sfx_target_collect.wav': (2, 6),
    'sfx_time_freeze.wav': (1, 2),
    'sfx_win_complete.wav': (1, 2),
    'sfx_win_amazing.wav': (1, 2),
    'sfx_lose_timeout.wav': (1, 2),
    'sfx_lose_failed.wav': (1, 2),
  };

  bool _soundEnabled = true;
  bool _musicEnabled = true;
  bool _hapticsEnabled = true;
  bool _bgmPlaying = false;
  SharedPreferences? _prefs;
  final Map<String, AudioPool> _pools = {};

  @visibleForTesting
  final List<String> debugPlayedSfxLog = [];

  @visibleForTesting
  final List<String> debugHapticsLog = [];

  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;
  bool get hapticsEnabled => _hapticsEnabled;

  @visibleForTesting
  void clearDebugLogs() {
    debugPlayedSfxLog.clear();
    debugHapticsLog.clear();
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _soundEnabled = _prefs?.getBool(_kSound) ?? true;
    _musicEnabled = _prefs?.getBool(_kMusic) ?? true;
    _hapticsEnabled = _prefs?.getBool(_kHaptics) ?? true;

    try {
      await FlameAudio.audioCache.loadAll([
        'bgm_gameplay.wav',
        'sfx_block_attract.wav',
        'sfx_block_grab.wav',
        'sfx_block_merge.wav',
        'sfx_block_put.wav',
        'sfx_levelup_arrow.wav',
        'sfx_levelup_fly.wav',
        'sfx_levelup_merge.wav',
        'sfx_ice_break_small.wav',
        'sfx_ice_break_whole.wav',
        'sfx_lose_timeout.wav',
        'sfx_lose_failed.wav',
        'sfx_win_complete.wav',
        'sfx_win_amazing.wav',
        'sfx_pu_select.wav',
        'sfx_time_freeze.wav',
        'sfx_button_click.wav',
        'sfx_target_collect.wav',
      ]);

      await Future.wait(
        _pooledSfxSpecs.entries.map((entry) async {
          try {
            final pool = await FlameAudio.createPool(
              entry.key,
              minPlayers: entry.value.$1,
              maxPlayers: entry.value.$2,
            );
            _pools[entry.key] = pool;
          } catch (_) {}
        }),
      );

      FlameAudio.bgm.initialize();
      if (_musicEnabled) {
        unawaited(startBgm());
      }
    } catch (e) {
      debugPrint('Audio preload warning: $e');
    }
  }

  Future<void> startBgm() async {
    if (!_musicEnabled || _bgmPlaying) return;
    try {
      _bgmPlaying = true;
      await FlameAudio.bgm.play('bgm_gameplay.wav', volume: _bgmVolume);
    } catch (_) {
      _bgmPlaying = false;
    }
  }

  Future<void> stopBgm() async {
    _bgmPlaying = false;
    try {
      await FlameAudio.bgm.stop();
    } catch (_) {}
  }

  void toggleSound() {
    _soundEnabled = !_soundEnabled;
    _prefs?.setBool(_kSound, _soundEnabled);
    playClick();
    notifyListeners();
  }

  void toggleMusic() {
    _musicEnabled = !_musicEnabled;
    _prefs?.setBool(_kMusic, _musicEnabled);
    if (_musicEnabled) {
      unawaited(startBgm());
    } else {
      unawaited(stopBgm());
    }
    playClick();
    notifyListeners();
  }

  void toggleHaptics() {
    _hapticsEnabled = !_hapticsEnabled;
    _prefs?.setBool(_kHaptics, _hapticsEnabled);
    if (_hapticsEnabled) {
      _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
    }
    playClick();
    notifyListeners();
  }

  void _recordDebugLog(List<String> log, String entry) {
    if (log.length >= 64) {
      log.removeAt(0);
    }
    log.add(entry);
  }

  void _triggerHaptic(String tag, Future<void> Function() action) {
    if (!_hapticsEnabled) return;
    _recordDebugLog(debugHapticsLog, tag);
    try {
      unawaited(action());
    } catch (_) {}
  }

  void _playSfx(String file, {double volume = 1.0}) {
    if (!_soundEnabled) return;
    _recordDebugLog(debugPlayedSfxLog, file);
    unawaited(_startSfxAsync(file, volume));
  }

  Future<void> _startSfxAsync(String file, double volume) async {
    try {
      final pool = _pools[file];
      if (pool != null) {
        await pool.start(volume: volume);
      } else {
        await FlameAudio.play(file, volume: volume);
      }
    } catch (_) {}
  }

  void playClick() {
    _playSfx('sfx_button_click.wav', volume: 1.0);
    _triggerHaptic('selectionClick', HapticFeedback.selectionClick);
  }

  void playPowerUpSelect() {
    _playSfx('sfx_pu_select.wav', volume: 1.0);
    _triggerHaptic('selectionClick', HapticFeedback.selectionClick);
  }

  /// Exact `GameplayState::OnMovementStarted`: `PlaySfx("block_grab", vol: 1.0)` + `TriggerPiecePickUp`.
  void playGrab() {
    _playSfx('sfx_block_grab.wav', volume: 1.0);
    _triggerHaptic('selectionClick', HapticFeedback.selectionClick);
  }

  /// Exact `GameplayState::OnMovementEnded` (`TriggerPieceDrop`) + `OnMovementCompleted` (`PlaySfx("block_put", vol: 1.0)`).
  void playPut() {
    _playSfx('sfx_block_put.wav', volume: 1.0);
    _triggerHaptic('lightImpact', HapticFeedback.lightImpact);
  }

  /// Exact `BoardView::SetMergeCandidate` (`BoardView.cs:1193`): `PlaySfx("block_attract", vol: 1.0)` with NO haptic.
  void playAttract() {
    _playSfx('sfx_block_attract.wav', volume: 1.0);
  }

  /// Exact `GameplayState::<ResolveMovementAsync>d__38` (`GameplayState.cs:244`):
  /// `PlaySfx("block_merge", vol: 1.0)` layered immediately alongside `block_put` on finger release.
  void playMerge() {
    _playSfx('sfx_block_merge.wav', volume: 1.0);
  }

  /// Exact `HapticService::TriggerPieceDrop` when dropping a lifted block back onto its start cell.
  void hapticDrop() {
    _triggerHaptic('lightImpact', HapticFeedback.lightImpact);
  }

  /// Exact `HapticService::TriggerMerge` (`BoardView.cs:494`) fired when `RemovePiecesAsync`
  /// triggers `PlayMergeSplash` & survivor bounce right after `SyncPiecePositionAsync`.
  void hapticMergeImpact() {
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
  }

  /// Progressive audio punch for high-value merges (`mergedNumber >= 32`).
  void playHighTierMergeBoost(int mergedNumber) {
    if (mergedNumber < 32) return;
    int tier = 0;
    int v = mergedNumber;
    while (v >= 32) {
      tier++;
      v ~/= 2;
    }
    final boostVol = (0.30 + 0.10 * tier).clamp(0.35, 0.95);
    _playSfx('sfx_levelup_merge.wav', volume: boostVol);
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
  }

  /// Progressive multi-pulse haptic aftershock for `mergedNumber >= 32` driven by game `update(dt)`.
  void hapticHighTierAftershock(int mergedNumber) {
    if (mergedNumber < 32) return;
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
  }

  /// Progressive audio & haptic feedback for consecutive merge combos (`x2, x3, x4...`).
  void playComboPraise(int comboCount) {
    if (comboCount <= 1) return;
    if (comboCount == 2) {
      _playSfx('sfx_target_collect.wav', volume: 0.65);
      _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
    } else if (comboCount == 3) {
      _playSfx('sfx_target_collect.wav', volume: 0.85);
      _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
    } else if (comboCount == 4) {
      _playSfx('sfx_levelup_merge.wav', volume: 0.58);
      _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
    } else if (comboCount == 5) {
      _playSfx('sfx_levelup_merge.wav', volume: 0.78);
      _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
    } else {
      _playSfx('sfx_win_amazing.wav', volume: 0.72);
      _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
    }
  }

  /// Exact `IceComponentView::PopThenUpdateCountAsync`: `PlaySfx("ice_small_break", vol: 1.0)` (no haptic).
  void playIceBreakSmall() {
    _playSfx('sfx_ice_break_small.wav', volume: 1.0);
  }

  /// Exact `IceComponentView::BreakIce` (`IceComponentView.cs:165-166`):
  /// `PlaySfx("ice_whole_break", vol: 1.0)` + `TriggerIceBreak`.
  void playIceBreak() {
    _playSfx('sfx_ice_break_whole.wav', volume: 1.0);
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
  }

  void playLevelUpArrow() {
    _playSfx('sfx_levelup_arrow.wav', volume: 1.0);
  }

  void playLevelUpFly() {
    _playSfx('sfx_levelup_fly.wav', volume: 1.0);
    _triggerHaptic('lightImpact', HapticFeedback.lightImpact);
  }

  void playLevelUpMerge() {
    _playSfx('sfx_levelup_merge.wav', volume: 1.0);
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
  }

  void playTimeFreeze() {
    _playSfx('sfx_time_freeze.wav', volume: 1.0);
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
  }

  /// Stage 1 Win (`LevelCompleteView` golden wave text).
  void playWinComplete() {
    _playSfx('sfx_win_complete.wav', volume: 1.0);
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
  }

  /// Stage 2 Win (`WinContent` `AMAZING!` gold ribbon + reward coin reveal).
  void playWinAmazing() {
    _playSfx('sfx_win_amazing.wav', volume: 1.0);
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
  }

  /// Flying coin landing on top-left `CoinsWidget`.
  void playCoinCollect() {
    _playSfx('sfx_target_collect.wav', volume: 1.0);
    _triggerHaptic('selectionClick', HapticFeedback.selectionClick);
  }

  /// Stage 1 Lose (`PlayOnPopupView` `OUT OF TIME`).
  void playOutOfTime() {
    _playSfx('sfx_lose_timeout.wav', volume: 1.0);
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
  }

  /// Stage 2 Lose (`LoseGameplayView` `Level X failed` + `-1` broken heart).
  void playLevelFailed() {
    _playSfx('sfx_lose_failed.wav', volume: 1.0);
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
  }

  void playWin() => playWinComplete();

  void playLose() => playOutOfTime();

  void hapticBlocked() {
    _triggerHaptic('lightImpact', HapticFeedback.lightImpact);
  }
}
