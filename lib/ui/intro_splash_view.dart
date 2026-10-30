import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'unity_ui_kit.dart';

/// Authentic replica of Unity `IntroView.prefab` & `TransitionView.prefab`:
/// - `Splash_Background.png` full-bleed cover
/// - `Blocked-In_Logo.png` hero title logo
/// - 9-slice `Splash_Socket_ProgressBar.png` + `Splash_Fill_ProgressBar.png`
/// - `Baloo2_ExtraBold_DarkStroke` `"Loading  XX%"`
class IntroSplashView extends StatelessWidget {
  final double progress;

  const IntroSplashView({
    super.key,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final pct = (clamped * 100).round().clamp(0, 100);
    final barOuterW = ux(context, 840);
    final barOuterH = ux(context, 82);
    final inset = ux(context, 10);
    final maxFillW = math.max(0.0, barOuterW - inset * 2);
    // Keep fill wide enough for clean 9-slice rounded caps once started
    final minCapW = ux(context, 62);
    final fillW = clamped <= 0.01
        ? 0.0
        : math.max(minCapW, maxFillW * clamped).clamp(0.0, maxFillW);

    return Scaffold(
      backgroundColor: const Color(0xFF04228C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/Splash_Background.png',
            fit: BoxFit.cover,
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                // Authentic Unity `Blocked-In_Logo.png`
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: ux(context, 96)),
                  child: Image.asset(
                    'assets/images/Blocked-In_Logo.png',
                    width: ux(context, 840),
                    fit: BoxFit.contain,
                  ),
                ),
                const Spacer(flex: 5),

                // `Loading  XX%` (`Baloo2_ExtraBold_DarkStroke`, `sz = 60.87`)
                UnitySdfText(
                  'Loading  $pct%',
                  unityFontSize: 60.87,
                  material: UnityTextMaterial.darkStroke,
                ),
                SizedBox(height: ux(context, 24)),

                // 9-Slice `Splash_Socket_ProgressBar.png` + `Splash_Fill_ProgressBar.png`
                SizedBox(
                  width: barOuterW,
                  height: barOuterH,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      UnityNineSlice(
                        sprite: 'Splash_Socket_ProgressBar.png',
                        width: barOuterW,
                        height: barOuterH,
                      ),
                      if (fillW > 1.0)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: inset),
                          child: UnityNineSlice(
                            sprite: 'Splash_Fill_ProgressBar.png',
                            width: fillW,
                            height: barOuterH - inset * 2,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: ux(context, 130)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
