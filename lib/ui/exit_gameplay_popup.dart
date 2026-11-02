import 'package:flutter/material.dart';
import 'unity_ui_kit.dart';

/// 100% Pixel-Exact Replica of Unity `ExitGameplayView.prefab`:
/// - `DarkOverlay`: `rgba(0.020, 0.000, 0.051, 0.949)` (`Color.fromRGBO(5, 0, 13, 0.949)`)
/// - `PopupContainer`: `1106.25 x 1337.91` at `sc = 0.816` (`UnityPopupCard`)
///   - `Header`: `"Restart level?"` (`localTitleFontSize = 116.7`) + `CloseButton` (`Button_Close.png`)
///   - `Panel` (`1026.50 x 734.23` local, center `(513.25, 367.115)`):
///     - `LifeIcon`: `Icon_BrokenLife.png` (`415.91 x 441.98` local at `pos = (0, +76.01)`), `BoxFit.contain`
///       - `LifeAmount` (child of `LifeIcon` at `pos = (0, +4.50)`): `"-1"`, `localFontSize = 224.9`,
///         `Baloo2_ExtraBold_Navigation_Bar_Label_Brown`
///     - `RegularText`: `"You will lose a life!"` at `pos = (0, -248.00)` (`946.50 x 205.85` local),
///       `localFontSize = 80.2`, `#07279A` (`rgba(0.027, 0.153, 0.604, 1.0)`), `lineSpacing = -32.0`
///   - `Footer`: `Button_CTA` (`585.20 x 217.44` local, `Button_Red.png`, `ppuMult = 0.82`,
///     `"Restart"`, `localFontSize = 116.6`, `Baloo2_ExtraBold_CTA_Red_Text`).
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
    const double panelCx = UnityPopupCard.localInnerWidth * 0.5; // 513.25
    const double panelCy = UnityPopupCard.localPanelHeight * 0.5; // 367.115

    // `LifeIcon`: `sz = (-610.59, -292.25)` -> `415.91 x 441.98`, `pos = (0, +76.01)`
    const double iconW = 415.91;
    const double iconH = 441.98;
    const double iconCy = panelCy - 76.01; // 291.105

    // `RegularText`: `sz = (-80.00, -528.38)` -> `946.50 x 205.85`, `pos = (0, -248.00)`
    const double textW = 946.50;
    const double textH = 205.85;
    const double textCy = panelCy + 248.00; // 615.115

    return ColoredBox(
      color: const Color.fromRGBO(5, 0, 13, 0.949),
      child: SafeArea(
        child: Center(
          child: UnityPopupCard(
            title: 'Restart level?',
            localTitleFontSize: 116.7,
            onClose: onCancel,
            panelChild: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. `LifeIcon` (`Icon_BrokenLife.png`, `415.91 x 441.98` local)
                Positioned(
                  left: ppx(context, panelCx - iconW * 0.5),
                  top: ppx(context, iconCy - iconH * 0.5),
                  width: ppx(context, iconW),
                  height: ppx(context, iconH),
                  child: Image.asset(
                    'assets/images/Icon_BrokenLife.png',
                    fit: BoxFit.contain,
                  ),
                ),

                // 2. `LifeAmount` (`"-1"`, child of `LifeIcon` at `pos = (0, +4.50)`, `fontSize = 224.9`)
                Positioned(
                  left: ppx(context, panelCx - 160.0),
                  top: ppx(context, (iconCy - 4.50) - 130.0),
                  width: ppx(context, 320.0),
                  height: ppx(context, 260.0),
                  child: Center(
                    child: UnitySdfText(
                      '-1',
                      unityFontSize: 224.9 * kUnityPopupScale,
                      material: UnityTextMaterial.brownCounter,
                    ),
                  ),
                ),

                // 3. `RegularText` (`"You will lose a life!"`, `fontSize = 80.2`, `#07279A`)
                Positioned(
                  left: ppx(context, panelCx - textW * 0.5),
                  top: ppx(context, textCy - textH * 0.5),
                  width: ppx(context, textW),
                  height: ppx(context, textH),
                  child: Center(
                    child: Text(
                      'You will lose a life!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Baloo2',
                        fontSize: ppx(context, 80.2),
                        fontWeight: FontWeight.w800,
                        fontVariations: const [FontVariation('wght', 800)],
                        color: const Color(0xFF07279A),
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            footerChild: UnityPopupCtaButton(
              skin: UnityButtonSkin.red,
              label: 'Restart',
              onTap: onConfirmRestart,
            ),
          ),
        ),
      ),
    );
  }
}
