import 'dart:async';
import 'dart:collection';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SfxSpec {
  final int voices;
  final int minGapMs;
  final double gain;

  const _SfxSpec({
    required this.voices,
    required this.minGapMs,
    required this.gain,
  });
}

class _SfxVoiceSlot {
  final AudioPlayer player;
  bool dirty = false;
  double lastVolume;
  Future<void> _queue = Future<void>.value();

  _SfxVoiceSlot(this.player, {this.lastVolume = 1.0});

  Future<void> trigger(double volume) {
    final next = _queue.catchError((_) {}).then((_) async {
      try {
        if (dirty) {
          await player.stop();
        }
        if ((lastVolume - volume).abs() > 0.015) {
          lastVolume = volume;
          await player.setVolume(volume);
        }
        dirty = true;
        await player.resume();
      } catch (_) {}
    });
    _queue = next;
    return next;
  }

  Future<void> dispose() async {
    try {
      await player.dispose();
    } catch (_) {}
  }
}

class _LowLatencySfxBank {
  final String file;
  final _SfxSpec spec;
  final List<_SfxVoiceSlot> _slots = <_SfxVoiceSlot>[];
  int _cursor = 0;

  _LowLatencySfxBank({required this.file, required this.spec});

  bool get isReady => _slots.isNotEmpty;

  void addSlot(_SfxVoiceSlot slot) {
    _slots.add(slot);
  }

  void trigger(double volume) {
    if (_slots.isEmpty) return;
    final slot = _slots[_cursor];
    _cursor = (_cursor + 1) % _slots.length;
    unawaited(slot.trigger(volume));
  }

  Future<void> dispose() async {
    for (final slot in _slots) {
      await slot.dispose();
    }
    _slots.clear();
  }
}

class AudioHapticsService extends ChangeNotifier {
  static const _kSound = 'bo_sound_enabled';
  static const _kMusic = 'bo_music_enabled';
  static const _kHaptics = 'bo_haptics_enabled';

  /// Balanced BGM volume so `0 dBFS`-mastered `bgm_gameplay.mp3` sits cleanly
  /// underneath calibrated gameplay SFX without competing in the mixer.
  static const double _bgmVolume = 0.20;
  static const int maxComboSfxIndex = 13;
  static const int _burstWindowMs = 180;

  static AudioContext _buildGameAudioContext({
    required AndroidContentType contentType,
  }) {
    final base = AudioContextConfig(
      focus: AudioContextConfigFocus.mixWithOthers,
    ).build();
    return AudioContext(
      android: base.android.copy(
        contentType: contentType,
        usageType: AndroidUsageType.game,
        audioFocus: AndroidAudioFocus.none,
      ),
      iOS: base.iOS,
    );
  }

  static final AudioContext _sfxAudioContext = _buildGameAudioContext(
    contentType: AndroidContentType.sonification,
  );
  static final AudioContext _bgmAudioContext = _buildGameAudioContext(
    contentType: AndroidContentType.music,
  );

  /// Peak-calibrated voice specs keeping solo SFX crisp (~ -6..-11 dBFS)
  /// and preventing digital clipping ("rè rè") during multi-SFX overlap.
  static const Map<String, _SfxSpec> _sfxSpecs = {
    'sfx_block_grab.wav': _SfxSpec(voices: 2, minGapMs: 40, gain: 0.90),
    'sfx_block_put.wav': _SfxSpec(voices: 2, minGapMs: 45, gain: 0.68),
    'sfx_block_attract.wav': _SfxSpec(voices: 2, minGapMs: 75, gain: 0.95),
    'sfx_block_merge.wav': _SfxSpec(voices: 2, minGapMs: 45, gain: 0.85),
    'sfx_ice_break_small.wav': _SfxSpec(voices: 2, minGapMs: 95, gain: 0.68),
    'sfx_ice_break_whole.wav': _SfxSpec(voices: 2, minGapMs: 80, gain: 0.60),
    'sfx_button_click.wav': _SfxSpec(voices: 2, minGapMs: 45, gain: 0.58),
    'sfx_pu_select.wav': _SfxSpec(voices: 1, minGapMs: 70, gain: 0.62),
    'sfx_levelup_arrow.wav': _SfxSpec(voices: 1, minGapMs: 60, gain: 1.00),
    'sfx_levelup_fly.wav': _SfxSpec(voices: 1, minGapMs: 60, gain: 1.00),
    'sfx_levelup_merge.wav': _SfxSpec(voices: 2, minGapMs: 55, gain: 1.00),
    'sfx_target_collect.wav': _SfxSpec(voices: 3, minGapMs: 55, gain: 0.58),
    'sfx_time_freeze.wav': _SfxSpec(voices: 1, minGapMs: 120, gain: 0.56),
    'sfx_water_stream.wav': _SfxSpec(voices: 1, minGapMs: 120, gain: 0.56),
    'sfx_win_complete.wav': _SfxSpec(voices: 1, minGapMs: 150, gain: 0.58),
    'sfx_win_amazing.wav': _SfxSpec(voices: 1, minGapMs: 150, gain: 0.58),
    'sfx_lose_timeout.wav': _SfxSpec(voices: 1, minGapMs: 150, gain: 0.58),
    'sfx_lose_failed.wav': _SfxSpec(voices: 1, minGapMs: 150, gain: 0.56),
    'new_1.mp3': _SfxSpec(voices: 2, minGapMs: 55, gain: 0.78),
    'new_2.mp3': _SfxSpec(voices: 2, minGapMs: 55, gain: 0.78),
    'new_3.mp3': _SfxSpec(voices: 2, minGapMs: 55, gain: 0.78),
    'new_4.mp3': _SfxSpec(voices: 2, minGapMs: 55, gain: 0.78),
    'new_5.mp3': _SfxSpec(voices: 1, minGapMs: 55, gain: 0.76),
    'new_6.mp3': _SfxSpec(voices: 1, minGapMs: 55, gain: 0.76),
    'new_7.mp3': _SfxSpec(voices: 1, minGapMs: 55, gain: 0.76),
    'new_8.mp3': _SfxSpec(voices: 1, minGapMs: 55, gain: 0.76),
    'new_9.mp3': _SfxSpec(voices: 1, minGapMs: 55, gain: 0.76),
    'new_10.mp3': _SfxSpec(voices: 1, minGapMs: 55, gain: 0.76),
    'new_11.mp3': _SfxSpec(voices: 1, minGapMs: 55, gain: 0.76),
    'new_12.mp3': _SfxSpec(voices: 1, minGapMs: 55, gain: 0.76),
    'new_13.mp3': _SfxSpec(voices: 1, minGapMs: 55, gain: 0.76),
  };

  bool _soundEnabled = true;
  bool _musicEnabled = true;
  bool _hapticsEnabled = true;
  bool _bgmPlaying = false;
  SharedPreferences? _prefs;
  final Map<String, _LowLatencySfxBank> _banks = {};
  final Map<String, int> _lastPlayedAtMs = {};
  final ListQueue<int> _recentTriggerMs = ListQueue<int>();
  final Stopwatch _clock = Stopwatch()..start();
  int _lastHapticMs = -100;
  int _lastHapticPriority = 0;

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
    _lastPlayedAtMs.clear();
    _recentTriggerMs.clear();
    _lastHapticMs = -100;
    _lastHapticPriority = 0;
  }

  /// Computes peak-safe SFX gain adjusted for simultaneous active voices.
  @visibleForTesting
  static double computeMixGain(
    String file, {
    double volume = 1.0,
    int concurrentCount = 1,
  }) {
    final specGain = _sfxSpecs[file]?.gain ?? 0.72;
    final double polyScale;
    if (concurrentCount <= 1) {
      polyScale = 1.00;
    } else if (concurrentCount == 2) {
      polyScale = 0.88;
    } else if (concurrentCount == 3) {
      polyScale = 0.78;
    } else {
      polyScale = 0.68;
    }
    return (volume * specGain * polyScale).clamp(0.05, 0.92);
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _soundEnabled = _prefs?.getBool(_kSound) ?? true;
    _musicEnabled = _prefs?.getBool(_kMusic) ?? true;
    _hapticsEnabled = _prefs?.getBool(_kHaptics) ?? true;

    try {
      await FlameAudio.audioCache.loadAll([
        'bgm_gameplay.mp3',
        ..._sfxSpecs.keys,
      ]);

      // Pass 1: warm the primary SoundPool slot for every SFX so native PCM decoding
      // completes once in background before any secondary voice slots share the soundId.
      await Future.wait(
        _sfxSpecs.entries.map((entry) async {
          final bank = _LowLatencySfxBank(file: entry.key, spec: entry.value);
          _banks[entry.key] = bank;
          final primary = await _createLowLatencySlot(
            entry.key,
            initialVolume: entry.value.gain,
          );
          if (primary != null) {
            bank.addSlot(primary);
          }
        }),
      );

      // Pass 2: add secondary polyphonic slots (instant native soundId reuse on Android SoundPool).
      await Future.wait(
        _sfxSpecs.entries.where((e) => e.value.voices > 1).map((entry) async {
          final bank = _banks[entry.key];
          if (bank == null || !bank.isReady) return;
          for (int i = 1; i < entry.value.voices; i++) {
            final extra = await _createLowLatencySlot(
              entry.key,
              initialVolume: entry.value.gain,
            );
            if (extra != null) {
              bank.addSlot(extra);
            }
          }
        }),
      );

      await FlameAudio.bgm.initialize(audioContext: _bgmAudioContext);
      FlameAudio.bgm.audioPlayer.positionUpdater = _DisabledPositionUpdater();
      if (_musicEnabled) {
        unawaited(startBgm());
      }
    } catch (e) {
      debugPrint('Audio preload warning: $e');
    }
  }

  Future<_SfxVoiceSlot?> _createLowLatencySlot(
    String file, {
    required double initialVolume,
  }) async {
    final player = AudioPlayer();
    try {
      player.positionUpdater = _DisabledPositionUpdater();
      player.audioCache = FlameAudio.audioCache;
      await player.setPlayerMode(PlayerMode.lowLatency);
      await player.setAudioContext(_sfxAudioContext);
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setSource(AssetSource(file));
      await player.setVolume(initialVolume);
      return _SfxVoiceSlot(player, lastVolume: initialVolume);
    } catch (_) {
      try {
        await player.dispose();
      } catch (_) {}
      return null;
    }
  }

  Future<void> startBgm() async {
    if (!_musicEnabled || _bgmPlaying) return;
    try {
      _bgmPlaying = true;
      FlameAudio.bgm.audioPlayer.positionUpdater = _DisabledPositionUpdater();
      await FlameAudio.bgm.play('bgm_gameplay.mp3', volume: _bgmVolume);
      FlameAudio.bgm.audioPlayer.positionUpdater = _DisabledPositionUpdater();
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
      _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
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
    final nowMs = _clock.elapsedMilliseconds;
    final priority = switch (tag) {
      'vibrate' => 4,
      'heavyImpact' => 3,
      'mediumImpact' => 2,
      _ => 1,
    };
    if ((nowMs - _lastHapticMs) < 20 && priority <= _lastHapticPriority) {
      return;
    }
    _lastHapticMs = nowMs;
    _lastHapticPriority = priority;
    try {
      unawaited(action());
    } catch (_) {}
  }

  void _playSfx(String file, {double volume = 1.0}) {
    if (!_soundEnabled) return;
    final nowMs = _clock.elapsedMilliseconds;
    final spec = _sfxSpecs[file];
    final minGapMs = spec?.minGapMs ?? 45;
    final prevMs = _lastPlayedAtMs[file];
    if (prevMs != null && (nowMs - prevMs) < minGapMs) {
      return;
    }
    _lastPlayedAtMs[file] = nowMs;

    while (_recentTriggerMs.isNotEmpty &&
        (nowMs - _recentTriggerMs.first) > _burstWindowMs) {
      _recentTriggerMs.removeFirst();
    }
    _recentTriggerMs.addLast(nowMs);
    final mixedVol = computeMixGain(
      file,
      volume: volume,
      concurrentCount: _recentTriggerMs.length,
    );

    _recordDebugLog(debugPlayedSfxLog, file);
    final bank = _banks[file];
    if (bank != null && bank.isReady) {
      bank.trigger(mixedVol);
    } else {
      unawaited(_playFallbackAsync(file, mixedVol));
    }
  }

  Future<void> _playFallbackAsync(String file, double volume) async {
    try {
      await FlameAudio.play(
        file,
        volume: volume,
        audioContext: _sfxAudioContext,
      );
    } catch (_) {}
  }

  void playClick() {
    _playSfx('sfx_button_click.wav', volume: 1.0);
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
  }

  void playPowerUpSelect() {
    _playSfx('sfx_pu_select.wav', volume: 1.0);
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
  }

  /// Exact `GameplayState::OnMovementStarted`: `PlaySfx("block_grab", vol: 1.0)` + `TriggerPiecePickUp`.
  void playGrab() {
    _playSfx('sfx_block_grab.wav', volume: 1.0);
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
  }

  /// Exact `GameplayState::OnMovementEnded` (`TriggerPieceDrop`) + `OnMovementCompleted` (`PlaySfx("block_put", vol: 1.0)`).
  void playPut() {
    _playSfx('sfx_block_put.wav', volume: 1.0);
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
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
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
  }

  /// Exact `HapticService::TriggerMerge` (`BoardView.cs:494`) fired when `RemovePiecesAsync`
  /// triggers `PlayMergeSplash` & survivor bounce right after `SyncPiecePositionAsync`.
  void hapticMergeImpact() {
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
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
    _triggerHaptic('vibrate', HapticFeedback.vibrate);
  }

  /// Progressive multi-pulse haptic aftershock for `mergedNumber >= 32` driven by game `update(dt)`.
  void hapticHighTierAftershock(int mergedNumber) {
    if (mergedNumber < 32) return;
    _triggerHaptic('vibrate', HapticFeedback.vibrate);
  }

  /// Ascending combo chime (`new_1.mp3 .. new_13.mp3`) for consecutive merge combos (`1x..13x+`).
  void playComboPraise(int comboCount) {
    final idx = comboCount.clamp(1, maxComboSfxIndex);
    final comboVol = (0.86 + 0.012 * (idx - 1)).clamp(0.86, 1.0);
    _playSfx('new_$idx.mp3', volume: comboVol);
    if (comboCount >= 4) {
      _triggerHaptic('vibrate', HapticFeedback.vibrate);
    } else if (comboCount >= 2) {
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
    _triggerHaptic('vibrate', HapticFeedback.vibrate);
  }

  void playLevelUpArrow() {
    _playSfx('sfx_levelup_arrow.wav', volume: 1.0);
  }

  void playLevelUpFly() {
    _playSfx('sfx_levelup_fly.wav', volume: 1.0);
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
  }

  void playLevelUpMerge() {
    _playSfx('sfx_levelup_merge.wav', volume: 1.0);
    _triggerHaptic('vibrate', HapticFeedback.vibrate);
  }

  void playTimeFreeze() {
    _playSfx('sfx_time_freeze.wav', volume: 1.0);
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
  }

  /// Sound of continuous rushing/flowing water when the winning block merges and
  /// streams upward into the potion pouch jar (`BoardSandStreamToJarVfx`).
  void playWaterStreamFlow() {
    _playSfx('sfx_water_stream.wav', volume: 1.0);
  }

  /// Stage 1 Win (`LevelCompleteView` golden wave text).
  void playWinComplete() {
    _playSfx('sfx_win_complete.wav', volume: 1.0);
    _triggerHaptic('vibrate', HapticFeedback.vibrate);
  }

  /// Stage 2 Win (`WinContent` `AMAZING!` gold ribbon + reward coin reveal).
  void playWinAmazing() {
    _playSfx('sfx_win_amazing.wav', volume: 1.0);
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
  }

  /// Flying coin landing on top-left `CoinsWidget`.
  void playCoinCollect() {
    _playSfx('sfx_target_collect.wav', volume: 1.0);
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
  }

  /// Water Garden pouring potion into crystal vase.
  void playGardenPour() {
    _playSfx('sfx_water_stream.wav', volume: 0.92);
  }

  /// Soft botanical growth chime + tactile pop as the flower swells or evolves a stage.
  void playGardenFlowerGrow({bool majorStage = false}) {
    _playSfx(
      majorStage ? 'new_8.mp3' : 'new_5.mp3',
      volume: majorStage ? 0.88 : 0.72,
    );
    _triggerHaptic(
      majorStage ? 'mediumImpact' : 'lightImpact',
      majorStage ? HapticFeedback.mediumImpact : HapticFeedback.lightImpact,
    );
  }

  /// Celebratory layered bloom fanfare when the vase hits 100% and the bouquet bursts open.
  void playGardenFullBloom() {
    _playSfx('sfx_win_complete.wav', volume: 0.92);
    _playSfx('new_11.mp3', volume: 0.84);
    _triggerHaptic('vibrate', HapticFeedback.vibrate);
  }

  /// Bright chime when claiming a milestone chest and unveiling the next crystal vase.
  void playGardenNewVaseReveal() {
    _playSfx('new_9.mp3', volume: 0.85);
    _triggerHaptic('mediumImpact', HapticFeedback.mediumImpact);
  }

  /// Stage 1 Lose (`PlayOnPopupView` `OUT OF TIME`).
  void playOutOfTime() {
    _playSfx('sfx_lose_timeout.wav', volume: 1.0);
    _triggerHaptic('vibrate', HapticFeedback.vibrate);
  }

  /// Stage 2 Lose (`LoseGameplayView` `Level X failed` + `-1` broken heart).
  void playLevelFailed() {
    _playSfx('sfx_lose_failed.wav', volume: 1.0);
    _triggerHaptic('vibrate', HapticFeedback.vibrate);
  }

  void playWin() => playWinComplete();

  void playLose() => playOutOfTime();

  void hapticBlocked() {
    _triggerHaptic('heavyImpact', HapticFeedback.heavyImpact);
  }

  @override
  void dispose() {
    unawaited(stopBgm());
    for (final bank in _banks.values) {
      unawaited(bank.dispose());
    }
    _banks.clear();
    super.dispose();
  }
}

/// No-op position updater that eliminates high-frequency (60fps) JNI polling
/// (`V/MediaPlayer-JNI: getCurrentPosition: ...`) on Android devices.
class _DisabledPositionUpdater extends PositionUpdater {
  _DisabledPositionUpdater() : super(getPosition: () async => null);

  @override
  void start() {}

  @override
  void stop() {}
}

