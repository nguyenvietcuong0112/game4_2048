import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'unity_ui_kit.dart';

/// Redesigned Loading Screen matching `assets/UI Bo Sung/Loading Screen/Loading Screen.png` (`1080x2160`):
/// - Full-bleed background: `assets/images/BG.png` (`1080x2160` Water Block character merging `1024 + 1024 -> 2048`)
/// - Top Hero Logo: `assets/images/Logo.png` (`808x496` `Water BLOCK - Number Merge`)
/// - `"Loading..."` label above the progress bar
/// - Gold-rimmed blue capsule track: `Loading_BG.png` (`771x86`)
/// - Glossy green capsule fill bar: `Loading_Progress.png` (`height = 60`, `inset = 13px`)
class IntroSplashView extends StatelessWidget {
  final double progress;

  const IntroSplashView({
    super.key,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final barOuterW = ux(context, 771);
    final barOuterH = ux(context, 86);
    final inset = ux(context, 13);
    final fillH = ux(context, 60);
    final maxFillW = math.max(0.0, barOuterW - inset * 2);
    // Keep fill wide enough for clean 3-slice rounded caps once started
    final minCapW = ux(context, 60);
    final fillW = clamped <= 0.01
        ? 0.0
        : math.max(minCapW, maxFillW * clamped).clamp(0.0, maxFillW);

    return Scaffold(
      backgroundColor: const Color(0xFF0A32B8),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/BG.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                // Redesigned `Logo.png` (`808x496` `Water BLOCK - Number Merge`)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: ux(context, 96)),
                  child: Image.asset(
                    'assets/images/Logo.png',
                    width: ux(context, 808),
                    fit: BoxFit.contain,
                  ),
                ),
                const Spacer(flex: 9),

                // `"Loading..."` (`Baloo2_ExtraBold_DarkStroke`)
                const UnitySdfText(
                  'Loading...',
                  unityFontSize: 52,
                  material: UnityTextMaterial.darkStroke,
                ),
                SizedBox(height: ux(context, 14)),

                // 3-Slice `Loading_BG.png` (`771x86`) + `Loading_Progress.png` (`height = 60`, `inset = 13`)
                SizedBox(
                  width: barOuterW,
                  height: barOuterH,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      UnityNineSlice(
                        sprite: 'Loading_BG.png',
                        width: barOuterW,
                        height: barOuterH,
                      ),
                      if (fillW > 1.0)
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: inset),
                          child: UnityNineSlice(
                            sprite: 'Loading_Progress.png',
                            width: fillW,
                            height: fillH,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(height: ux(context, 92)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
