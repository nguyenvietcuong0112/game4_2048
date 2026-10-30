import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioHapticsService extends ChangeNotifier {
  static const _kSound = 'bo_sound_enabled';
  static const _kMusic = 'bo_music_enabled';
  static const _kHaptics = 'bo_haptics_enabled';

  bool _soundEnabled = true;
  bool _musicEnabled = true;
  bool _hapticsEnabled = true;
  bool _bgmPlaying = false;
  SharedPreferences? _prefs;

  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;
  bool get hapticsEnabled => _hapticsEnabled;

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
      FlameAudio.bgm.initialize();
      if (_musicEnabled) {
        startBgm();
      }
    } catch (e) {
      debugPrint('Audio preload warning: $e');
    }
  }

  Future<void> startBgm() async {
    if (!_musicEnabled || _bgmPlaying) return;
    try {
      _bgmPlaying = true;
      await FlameAudio.bgm.play('bgm_gameplay.wav', volume: 0.35);
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
      startBgm();
    } else {
      stopBgm();
    }
    playClick();
    notifyListeners();
  }

  void toggleHaptics() {
    _hapticsEnabled = !_hapticsEnabled;
    _prefs?.setBool(_kHaptics, _hapticsEnabled);
    if (_hapticsEnabled) {
      HapticFeedback.mediumImpact();
    }
    playClick();
    notifyListeners();
  }

  void _playSfx(String file, {double volume = 0.85}) {
    if (!_soundEnabled) return;
    try {
      FlameAudio.play(file, volume: volume);
    } catch (_) {}
  }

  void playClick() {
    _playSfx('sfx_button_click.wav', volume: 0.75);
    if (_hapticsEnabled) HapticFeedback.selectionClick();
  }

  void playPowerUpSelect() {
    _playSfx('sfx_pu_select.wav', volume: 0.85);
    if (_hapticsEnabled) HapticFeedback.selectionClick();
  }

  void playGrab() {
    _playSfx('sfx_block_grab.wav', volume: 0.70);
    if (_hapticsEnabled) HapticFeedback.selectionClick();
  }

  void playPut() {
    _playSfx('sfx_block_put.wav', volume: 0.70);
    if (_hapticsEnabled) HapticFeedback.lightImpact();
  }

  void playAttract() {
    _playSfx('sfx_block_attract.wav', volume: 0.65);
    if (_hapticsEnabled) HapticFeedback.selectionClick();
  }

  void playMerge() {
    _playSfx('sfx_block_merge.wav', volume: 0.90);
    if (_hapticsEnabled) HapticFeedback.mediumImpact();
  }

  void playIceBreakSmall() {
    _playSfx('sfx_ice_break_small.wav', volume: 0.80);
    if (_hapticsEnabled) HapticFeedback.lightImpact();
  }

  void playIceBreak() {
    _playSfx('sfx_ice_break_whole.wav', volume: 0.90);
    if (_hapticsEnabled) HapticFeedback.heavyImpact();
  }

  void playLevelUpArrow() {
    _playSfx('sfx_levelup_arrow.wav', volume: 0.80);
  }

  void playLevelUpFly() {
    _playSfx('sfx_levelup_fly.wav', volume: 0.85);
    if (_hapticsEnabled) HapticFeedback.lightImpact();
  }

  void playLevelUpMerge() {
    _playSfx('sfx_levelup_merge.wav', volume: 0.95);
    if (_hapticsEnabled) HapticFeedback.heavyImpact();
  }

  void playTimeFreeze() {
    _playSfx('sfx_time_freeze.wav', volume: 0.95);
    if (_hapticsEnabled) HapticFeedback.mediumImpact();
  }

  /// Stage 1 Win (`LevelCompleteView` golden wave text).
  void playWinComplete() {
    _playSfx('sfx_win_complete.wav', volume: 0.95);
    if (_hapticsEnabled) HapticFeedback.heavyImpact();
  }

  /// Stage 2 Win (`WinContent` `AMAZING!` gold ribbon + reward coin reveal).
  void playWinAmazing() {
    _playSfx('sfx_win_amazing.wav', volume: 0.95);
    if (_hapticsEnabled) HapticFeedback.mediumImpact();
  }

  /// Flying coin landing on top-left `CoinsWidget`.
  void playCoinCollect() {
    _playSfx('sfx_target_collect.wav', volume: 0.82);
    if (_hapticsEnabled) HapticFeedback.selectionClick();
  }

  /// Stage 1 Lose (`PlayOnPopupView` `OUT OF TIME`).
  void playOutOfTime() {
    _playSfx('sfx_lose_timeout.wav', volume: 0.88);
    if (_hapticsEnabled) HapticFeedback.heavyImpact();
  }

  /// Stage 2 Lose (`LoseGameplayView` `Level X failed` + `-1` broken heart).
  void playLevelFailed() {
    _playSfx('sfx_lose_failed.wav', volume: 0.90);
    if (_hapticsEnabled) HapticFeedback.heavyImpact();
  }

  void playWin() => playWinComplete();

  void playLose() => playOutOfTime();

  void hapticBlocked() {
    if (_hapticsEnabled) HapticFeedback.lightImpact();
  }
}
