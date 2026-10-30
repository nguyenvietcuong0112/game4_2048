import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/level_models.dart';
import 'models/palette.dart';
import 'models/unity_curve.dart';
import 'services/audio_haptics_service.dart';
import 'services/player_progress_service.dart';
import 'ui/gameplay_screen.dart';
import 'ui/intro_splash_view.dart';
import 'ui/unity_ui_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
}

class BlockOrder2048App extends StatefulWidget {
  const BlockOrder2048App({super.key});

  @override
  State<BlockOrder2048App> createState() => _BlockOrder2048AppState();
}

class _BlockOrder2048AppState extends State<BlockOrder2048App>
    with WidgetsBindingObserver {
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
    }
  }

  Future<void> _initializeAll() async {
    try {
      final minSplashFuture =
          Future<void>.delayed(const Duration(milliseconds: 700));
      // Preload critical splash bar 9-slice sprites first so the splash bar renders crisply immediately
      await Future.wait([
        UnitySpriteRegistry.loadOne('Splash_Socket_ProgressBar.png'),
        UnitySpriteRegistry.loadOne('Splash_Fill_ProgressBar.png'),
      ]);
      _loadProgress.value = 0.16;

      final spriteFuture = UnitySpriteRegistry.preloadAll(
        onProgress: (p) {
          final mapped = 0.16 + p * 0.68;
          if (mapped > _loadProgress.value) {
            _loadProgress.value = mapped;
          }
        },
      );

      final results = await Future.wait([
        LevelRepository.loadFromAssets(),
        BlockOrderPalette.loadFromAssets(),
        PieceVisualSettings.loadFromAssets(),
        _progress.init(),
        _audio.init(),
        spriteFuture,
      ]);

      _loadProgress.value = 1.0;
      await minSplashFuture;
      if (!mounted) return;
      setState(() {
        _bundle = _BootBundle(
          repository: results[0] as LevelRepository,
          palette: results[1] as BlockOrderPalette,
          visualSettings: results[2] as PieceVisualSettings,
        );
      });
    } catch (e) {
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
