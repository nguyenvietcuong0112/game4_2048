import 'package:flutter/material.dart';
import 'unity_ui_kit.dart';

/// Authentic replica of Unity `ExitGameplayView.prefab`:
/// - `#05000D(a=0.94)` backdrop
/// - `UnityPopupCard` (`Background_Popup.png` + `Panel_Popup.png` + `Button_Close.png`)
/// - Title: `"Restart level?"`
/// - `Icon_BrokenLife.png` + `"-1"` (`Baloo2_ExtraBold_Navigation_Bar_Label_Brown`)
/// - `"You will lose a life!"` (`#07279A`)
/// - Red 9-slice `Button_Red.png` `"Restart"` CTA
class ExitGameplayPopup extends StatelessWidget {
  final VoidCallback onConfirmRestart;
  final VoidCallback onCancel;

  const ExitGameplayPopup({
    super.key,
    required this.onConfirmRestart,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xF005000D),
      alignment: Alignment.center,
      child: SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.78, end: 1.0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            child: child,
          ),
          child: UnityPopupCard(
            title: 'Restart level?',
            unityWidth: 880,
            onClose: onCancel,
            panelChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: ux(context, 280),
                  height: ux(context, 236),
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      Image.asset(
                        'assets/images/Icon_BrokenLife.png',
                        width: ux(context, 244),
                        height: ux(context, 218),
                        fit: BoxFit.contain,
                      ),
                      Positioned(
                        right: ux(context, 4),
                        bottom: ux(context, 4),
                        child: const UnitySdfText(
                          '-1',
                          unityFontSize: 94,
                          material: UnityTextMaterial.brownCounter,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: ux(context, 20)),
                Text(
                  'You will lose a life!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontSize: ux(context, 52),
                    fontWeight: FontWeight.w800,
                    fontVariations: const [FontVariation('wght', 800)],
                    color: const Color(0xFF07279A),
                    height: 1.15,
                  ),
                ),
              ],
            ),
            footerChild: UnityCtaButton(
              skin: UnityButtonSkin.red,
              label: 'Restart',
              unityWidth: 590,
              unityHeight: 158,
              unityFontSize: 82,
              onTap: onConfirmRestart,
            ),
          ),
        ),
      ),
    );
  }
}
