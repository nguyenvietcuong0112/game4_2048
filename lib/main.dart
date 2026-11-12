import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/level_models.dart';
import 'models/palette.dart';
import 'models/unity_curve.dart';
import 'services/ads_manager.dart';
import 'services/analytics_service.dart';
import 'services/audio_haptics_service.dart';
import 'services/player_progress_service.dart';
import 'ui/gameplay_screen.dart';
import 'ui/intro_splash_view.dart';
import 'ui/unity_ui_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Align high-frequency touch digitizer samples with 90Hz/120Hz display VSync timestamps
  GestureBinding.instance.resamplingEnabled = true;
  PaintingBinding.instance.imageCache.maximumSize = 256;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 160 << 20;

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const BlockOrder2048App());
  unawaited(AnalyticsService.initialize());
}

class BlockOrder2048App extends StatefulWidget {
  /// Minimum visual duration for the boot loading bar to smoothly fill `0% -> 100%`
  /// so the player sees a pleasant, deliberate loading animation instead of an abrupt jump.
  static Duration minSplashDuration = const Duration(milliseconds: 1550);

  const BlockOrder2048App({super.key});

  @override
  State<BlockOrder2048App> createState() => _BlockOrder2048AppState();
}

class _BlockOrder2048AppState extends State<BlockOrder2048App>
    with WidgetsBindingObserver {
  static const List<String> _criticalUiAssetImages = [
    'assets/images/Background_Core.png',
    'assets/images/BG.png',
    'assets/images/Logo.png',
    'assets/images/Loading_BG.png',
    'assets/images/Loading_Progress.png',
    'assets/images/Icon_Coin.png',
    'assets/images/Icon_Clock.png',
    'assets/images/Icon_Timer.png',
    'assets/images/Icon_Settings.png',
    'assets/images/progress_combo_bg.png',
    'assets/images/progress_combo_fg.png',
    'assets/images/text_newfeature.png',
    'assets/images/effect_outerglow.png',
    'assets/images/effect_star.png',
    'assets/images/btn_green.png',
    'assets/images/popup_bg.png',
    'assets/images/frame_content.png',
    'assets/images/Button_Green.png',
    'assets/images/Button_Yellow.png',
    'assets/images/Icon_Ads.png',
    'assets/images/Button_Circle_Blue.png',
    'assets/images/Button_Circle_Gray.png',
    'assets/images/Powerup_Base.png',
    'assets/images/Powerup_Base_Locked.png',
    'assets/images/Icon_Padlock_Silver.png',
    'assets/images/PowerUp_LevelUp.png',
    'assets/images/PowerUp_TimeFreeze.png',
    'assets/images/PowerUp_Amount.png',
    'assets/images/PowerUp_Plus.png',
    'assets/images/PowerUp_Free.png',
    'assets/images/Button_Close.png',
    'assets/images/Icon_Sounds.png',
    'assets/images/Icon_Sounds_Off.png',
    'assets/images/Icon_Music.png',
    'assets/images/Icon_Music_Off.png',
    'assets/images/Icon_Haptics.png',
    'assets/images/Icon_Haptics_Off.png',
    'assets/images/Icon_Ad.png',
    'assets/images/Reward_Coin.png',
    'assets/images/Icon_BrokenLife.png',
    'assets/images/Snow.png',
    'assets/images/Ice_Top.png',
    'assets/images/Ice_Bottom.png',
    'assets/images/Ice_Corner_TopLeft.png',
    'assets/images/Ice_Corner_TopRight.png',
    'assets/images/Ice_Corner_BottomLeft.png',
    'assets/images/Ice_Corner_BottomRight.png',
    'assets/images/Ice_Blurry_TopLeft.png',
    'assets/images/Ice_Blurry_BottomRight.png',
  ];

  final AudioHapticsService _audio = AudioHapticsService();
  final PlayerProgressService _progress = PlayerProgressService();
  final ValueNotifier<double> _loadProgress = ValueNotifier<double>(0.08);

  _BootBundle? _bundle;
  Object? _bootError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadProgress.dispose();
    _audio.stopBgm();
    _audio.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _progress.flushPendingWinCoins();
      _audio.stopBgm();
    } else if (state == AppLifecycleState.resumed) {
      if (_audio.musicEnabled) {
        _audio.startBgm();
      }
      AdsManager.handleAppResume(currentLevel: _progress.currentLevel);
    }
  }

  Future<void> _prewarmUiImageCache() async {
    const cfg = ImageConfiguration.empty;
    for (final assetPath in _criticalUiAssetImages) {
      try {
        final stream = AssetImage(assetPath).resolve(cfg);
        final completer = Completer<void>();
        late final ImageStreamListener listener;
        listener = ImageStreamListener(
          (_, _) {
            stream.removeListener(listener);
            if (!completer.isCompleted) completer.complete();
          },
          onError: (_, _) {
            stream.removeListener(listener);
            if (!completer.isCompleted) completer.complete();
          },
        );
        stream.addListener(listener);
        await completer.future;
      } catch (_) {}
    }
  }

  Future<void> _initializeAll() async {
    final splashWatch = Stopwatch()..start();
    // Initialize persisted player progress upfront (< 3ms) so FTUE status is known
    // before emitting `loading_start` and `ftue_loading_start`.
    try {
      await _progress.init();
    } catch (_) {}
    final logFtueLoading = _progress.consumeFtueLoadingIfPending();
    AnalyticsService.logLoadingStart(placement: 'splash');
    if (logFtueLoading) {
      AnalyticsService.logTutorial(name: 'ftue_loading_start', value: 1);
    }
    try {
      // Preload critical splash bar 9-slice sprites first so the splash bar renders crisply immediately
      await Future.wait([
        UnitySpriteRegistry.loadOne('Loading_BG.png'),
        UnitySpriteRegistry.loadOne('Loading_Progress.png'),
      ]);
      _loadProgress.value = 0.04;

      double realAssetProgress = 0.04;
      final spriteFuture = UnitySpriteRegistry.preloadAll(
        onProgress: (p) {
          final mapped = 0.08 + p * 0.78;
          if (mapped > realAssetProgress) {
            realAssetProgress = mapped;
          }
        },
      );

      bool assetsDone = false;
      Object? loadError;
      List<Object?>? results;

      unawaited(
        Future.wait([
          LevelRepository.loadFromAssets(),
          BlockOrderPalette.loadFromAssets(),
          PieceVisualSettings.loadFromAssets(),
          _audio.init(),
          spriteFuture,
          _prewarmUiImageCache(),
        ]).then((loaded) {
          results = loaded;
          realAssetProgress = 1.0;
          assetsDone = true;
        }).catchError((Object e) {
          loadError = e;
          assetsDone = true;
        }),
      );

      final targetMs = math.max(
        1,
        BlockOrder2048App.minSplashDuration.inMilliseconds,
      );

      // Drive a smooth 60fps progress fill (`0% -> 100%`) so the green capsule bar
      // visibly animates instead of snapping instantaneously to 100%.
      while (mounted &&
          (!assetsDone || splashWatch.elapsedMilliseconds < targetMs)) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (loadError != null) break;

        final elapsedFraction =
            (splashWatch.elapsedMilliseconds / targetMs).clamp(0.0, 1.0);
        final timeCurve = Curves.easeInOutCubic.transform(elapsedFraction);
        final visualTarget = assetsDone
            ? timeCurve
            : math.min(0.92, math.max(timeCurve * 0.92, realAssetProgress * 0.90));
        if (visualTarget > _loadProgress.value) {
          _loadProgress.value = visualTarget;
        }
      }

      if (loadError != null) {
        throw loadError!;
      }
      if (!mounted || results == null) return;

      _loadProgress.value = 1.0;
      // Hold briefly at 100% so the completed green bar registers visually before cross-fading
      if (targetMs >= 400) {
        await Future<void>.delayed(const Duration(milliseconds: 160));
      }

      AnalyticsService.logLoadingFinish(
        placement: 'splash',
        success: true,
        value: splashWatch.elapsedMilliseconds / 1000.0,
      );
      if (logFtueLoading) {
        AnalyticsService.logTutorial(name: 'ftue_loading_finish', value: 2);
      }
      AdsManager.init();
      if (!mounted) return;
      setState(() {
        _bundle = _BootBundle(
          repository: results![0] as LevelRepository,
          palette: results![1] as BlockOrderPalette,
          visualSettings: results![2] as PieceVisualSettings,
        );
      });
      unawaited(AdsManager.showSplashAd());
    } catch (e) {
      AnalyticsService.logLoadingFinish(
        placement: 'splash',
        success: false,
        value: splashWatch.elapsedMilliseconds / 1000.0,
      );
      if (!mounted) return;
      setState(() => _bootError = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Block Order 2048',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Baloo2',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0330AC),
          brightness: Brightness.dark,
        ),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_bootError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0330AC),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load game assets:\n$_bootError',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      );
    }

    final bundle = _bundle;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: bundle == null
          ? ValueListenableBuilder<double>(
              key: const ValueKey('intro_splash'),
              valueListenable: _loadProgress,
              builder: (context, prog, _) => IntroSplashView(progress: prog),
            )
          : GameplayScreen(
              key: const ValueKey('gameplay_screen'),
              repository: bundle.repository,
              palette: bundle.palette,
              visualSettings: bundle.visualSettings,
              audio: _audio,
              progress: _progress,
            ),
    );
  }
}

class _BootBundle {
  final LevelRepository repository;
  final BlockOrderPalette palette;
  final PieceVisualSettings visualSettings;

  const _BootBundle({
    required this.repository,
    required this.palette,
    required this.visualSettings,
  });
}
