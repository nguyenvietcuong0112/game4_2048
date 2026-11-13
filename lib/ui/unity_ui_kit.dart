import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Exact Unity `CanvasScaler` (`ReferenceResolution = 1080x1920`, `ScreenMatchMode = Expand`).
/// Converts any Unity `1080x1920` reference pixel/font-size value into logical Flutter pixels.
double ux(BuildContext context, double px1080) {
  final size = MediaQuery.sizeOf(context);
  final scale = math.min(size.width / 1080.0, size.height / 1920.0);
  return px1080 * scale;
}

double uxScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return math.min(size.width / 1080.0, size.height / 1920.0);
}

/// Exact Unity `PopupContainer` `m_LocalScale = (0.816, 0.816)` used across `PlayOnPopupView`,
/// `LoseGameplayView`, `ExitGameplayView`, `NoLivesPopupView`, and `PopupView`.
const double kUnityPopupScale = 0.816;

/// Converts a `PopupContainer`-local `RectTransform` unit into logical Flutter pixels.
double ppx(BuildContext context, double popupLocalPx) {
  return ux(context, popupLocalPx * kUnityPopupScale);
}

/// Unity 9-slice border specification `(left, bottom, right, top)` from `sprites.json`.
class UnitySliceSpec {
  final double left;
  final double bottom;
  final double right;
  final double top;

  const UnitySliceSpec(this.left, this.bottom, this.right, this.top);
}

/// Preloads and caches raw [ui.Image] textures for GPU 9-slice rendering with zero frame hitches.
class UnitySpriteRegistry {
  UnitySpriteRegistry._();

  static final Map<String, ui.Image> _cache = {};

  /// Exact 9-slice borders for UI sprites in `assets/images/`.
  static const Map<String, UnitySliceSpec> slices = {
    'Background_Popup.png': UnitySliceSpec(175, 175, 175, 175),
    'Panel_Popup.png': UnitySliceSpec(56, 56, 56, 56),
    'Frame_Popup_Title.png': UnitySliceSpec(52, 0, 52, 0),
    'Frame_Level.png': UnitySliceSpec(52, 0, 52, 0),
    'Frame_Footer.png': UnitySliceSpec(24, 8, 24, 30),
    'Panel_PlayOn.png': UnitySliceSpec(61, 67, 59, 48),
    'Box_Text.png': UnitySliceSpec(62, 69, 65, 51),
    'Banner.png': UnitySliceSpec(50, 57, 50, 37),
    'Label_Level.png': UnitySliceSpec(90, 0, 90, 0),
    'WidgetBase.png': UnitySliceSpec(42, 0, 42, 0),
    'Button_CTA.png': UnitySliceSpec(110, 0, 110, 0),
    'Button_CTA_Disabled.png': UnitySliceSpec(72, 70, 72, 56),
    'Button_Blue.png': UnitySliceSpec(72, 70, 72, 56),
    'Button_Red.png': UnitySliceSpec(72, 70, 72, 56),
    'Button_Secondary_Small.png': UnitySliceSpec(64, 71, 63, 56),
    'Inset_Button_CTA.png': UnitySliceSpec(28, 0, 28, 28),
    'Inset_Button_CTA_Red.png': UnitySliceSpec(28, 0, 28, 28),
    'Widget_Timer_Set.png': UnitySliceSpec(45, 0, 45, 0),
    'Pill_03.png': UnitySliceSpec(47, 0, 47, 0),
    'Pill_01.png': UnitySliceSpec(73, 0, 74, 0),
    'Circle_01.png': UnitySliceSpec(128, 128, 128, 128),
    'Shadow.png': UnitySliceSpec(124, 124, 124, 124),
    'TimeFreeze_TimerBar.png': UnitySliceSpec(39, 0, 39, 0),
    'Splash_Socket_ProgressBar.png': UnitySliceSpec(39, 40, 40, 40),
    'Splash_Fill_ProgressBar.png': UnitySliceSpec(30, 30, 30, 30),
    'Frost_Gradient.png': UnitySliceSpec(51, 53, 51, 53),
    'Element_Disabled.png': UnitySliceSpec(14, 0, 14, 0),
    'Panel_SpeechBubble.png': UnitySliceSpec(61, 67, 59, 48),
    'progress_combo_bg.png': UnitySliceSpec(26, 0, 26, 0),
    'progress_combo_fg.png': UnitySliceSpec(16, 0, 16, 0),
    'Loading_BG.png': UnitySliceSpec(43, 0, 43, 0),
    'Loading_Progress.png': UnitySliceSpec(30, 0, 30, 0),
    'popup_bg.png': UnitySliceSpec(175, 175, 175, 175),
    'frame_content.png': UnitySliceSpec(56, 56, 56, 56),
    'Button_Green.png': UnitySliceSpec(110, 0, 110, 0),
    'Button_Yellow.png': UnitySliceSpec(110, 0, 110, 0),
    'btn_green.png': UnitySliceSpec(110, 0, 110, 0),
  };

  static ui.Image? get(String spriteName) => _cache[spriteName];

  static Future<ui.Image> loadOne(String spriteName) async {
    final existing = _cache[spriteName];
    if (existing != null) return existing;
    final data = await rootBundle.load('assets/images/$spriteName');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    _cache[spriteName] = frame.image;
    return frame.image;
  }

  static Future<void> preloadAll({void Function(double progress)? onProgress}) async {
    final keys = slices.keys.toList();
    int done = 0;
    for (final k in keys) {
      try {
        await loadOne(k);
      } catch (e) {
        debugPrint('UnitySpriteRegistry preload warning for $k: $e');
      }
      done++;
      onProgress?.call(done / keys.length);
    }
  }
}

/// GPU 9-Slice Sprite Renderer matching `UnityEngine.UI.Image (Image.Type.Sliced)`.
/// Automatically handles 3-slice capsules (`T == 0 && B == 0`), degenerate circle-to-pill
/// seams (`L + R == W`), proportional corner scaling when smaller than borders, and tint modulation.
class UnityNineSlice extends StatefulWidget {
  final String sprite;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final Widget? child;
  final Color? tint;
  final ColorFilter? colorFilter;
  final AlignmentGeometry alignment;
  final double pixelMultiplier;

  const UnityNineSlice({
    super.key,
    required this.sprite,
    this.width,
    this.height,
    this.padding,
    this.child,
    this.tint,
    this.colorFilter,
    this.alignment = Alignment.center,
    this.pixelMultiplier = 1.0,
  });

  @override
  State<UnityNineSlice> createState() => _UnityNineSliceState();
}

class _UnityNineSliceState extends State<UnityNineSlice> {
  ui.Image? _img;

  @override
  void initState() {
    super.initState();
    _resolveSprite();
  }

  @override
  void didUpdateWidget(covariant UnityNineSlice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sprite != widget.sprite) {
      _resolveSprite();
    }
  }

  void _resolveSprite() {
    final cached = UnitySpriteRegistry.get(widget.sprite);
    if (cached != null) {
      _img = cached;
      return;
    }
    UnitySpriteRegistry.loadOne(widget.sprite).then((loaded) {
      if (mounted) {
        setState(() => _img = loaded);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = UnitySpriteRegistry.slices[widget.sprite] ??
        const UnitySliceSpec(0, 0, 0, 0);
    final canvasScale = uxScale(context) * widget.pixelMultiplier;

    Widget content = CustomPaint(
      painter: _UnityNineSlicePainter(
        image: _img,
        spec: spec,
        canvasScale: canvasScale,
        tint: widget.tint,
        colorFilter: widget.colorFilter,
      ),
      child: Padding(
        padding: widget.padding ?? EdgeInsets.zero,
        child: widget.child != null
            ? Align(
                alignment: widget.alignment,
                widthFactor: widget.width == null ? 1.0 : null,
                heightFactor: widget.height == null ? 1.0 : null,
                child: widget.child,
              )
            : const SizedBox.expand(),
      ),
    );

    if (widget.width != null || widget.height != null) {
      content = SizedBox(
        width: widget.width,
        height: widget.height,
        child: content,
      );
    }
    return content;
  }
}

class _UnityNineSlicePainter extends CustomPainter {
  final ui.Image? image;
  final UnitySliceSpec spec;
  final double canvasScale;
  final Color? tint;
  final ColorFilter? colorFilter;

  const _UnityNineSlicePainter({
    required this.image,
    required this.spec,
    required this.canvasScale,
    this.tint,
    this.colorFilter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null || size.width <= 0.5 || size.height <= 0.5) return;

    final iw = img.width.toDouble();
    final ih = img.height.toDouble();

    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (colorFilter != null) {
      paint.colorFilter = colorFilter;
    } else if (tint != null) {
      paint.colorFilter = ColorFilter.mode(tint!, BlendMode.modulate);
    }

    // Simple un-sliced fallback if all borders are 0
    if (spec.left <= 0 && spec.right <= 0 && spec.top <= 0 && spec.bottom <= 0) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, iw, ih),
        Rect.fromLTWH(0, 0, size.width, size.height),
        paint,
      );
      return;
    }

    // Source cut coordinates in image pixels (note Unity border.bottom is at bottom y = ih - bottom)
    double srcL = spec.left;
    double srcR = iw - spec.right;
    if (srcR <= srcL) {
      final midX = iw * 0.5;
      srcL = (midX - 0.5).clamp(0.0, iw);
      srcR = (midX + 0.5).clamp(0.0, iw);
    }

    double srcT = spec.top;
    double srcB = ih - spec.bottom;
    if (srcB <= srcT) {
      final midY = ih * 0.5;
      srcT = (midY - 0.5).clamp(0.0, ih);
      srcB = (midY + 0.5).clamp(0.0, ih);
    }

    // Destination border widths in logical pixels
    final isHorizontal3Slice = spec.top == 0 && spec.bottom == 0;
    final isVertical3Slice = spec.left == 0 && spec.right == 0;

    double dstL;
    double dstR;
    double dstT;
    double dstB;

    if (isHorizontal3Slice) {
      final hRatio = size.height / ih;
      dstL = spec.left * hRatio;
      dstR = spec.right * hRatio;
      dstT = 0.0;
      dstB = 0.0;
    } else if (isVertical3Slice) {
      final wRatio = size.width / iw;
      dstL = 0.0;
      dstR = 0.0;
      dstT = spec.top * wRatio;
      dstB = spec.bottom * wRatio;
    } else {
      dstL = spec.left * canvasScale;
      dstR = spec.right * canvasScale;
      dstT = spec.top * canvasScale;
      dstB = spec.bottom * canvasScale;
    }

    if (dstL + dstR > size.width && (dstL + dstR) > 0) {
      final f = size.width / (dstL + dstR);
      dstL *= f;
      dstR *= f;
    }
    if (dstT + dstB > size.height && (dstT + dstB) > 0) {
      final f = size.height / (dstT + dstB);
      dstT *= f;
      dstB *= f;
    }

    final sx = [0.0, srcL, srcR, iw];
    final sy = [0.0, srcT, srcB, ih];
    final dx = [0.0, dstL, size.width - dstR, size.width];
    final dy = [0.0, dstT, size.height - dstB, size.height];

    for (int r = 0; r < 3; r++) {
      final sh = sy[r + 1] - sy[r];
      final dh = dy[r + 1] - dy[r];
      if (sh <= 0.01 || dh <= 0.01) continue;
      for (int c = 0; c < 3; c++) {
        final sw = sx[c + 1] - sx[c];
        final dw = dx[c + 1] - dx[c];
        if (sw <= 0.01 || dw <= 0.01) continue;
        // Slight 0.25px overlap on inner seams prevents sub-pixel hairlines on GPU
        final padR = (c < 2 && dx[c + 2] - dx[c + 1] > 0.01) ? 0.25 : 0.0;
        final padB = (r < 2 && dy[r + 2] - dy[r + 1] > 0.01) ? 0.25 : 0.0;
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(sx[c], sy[r], sw, sh),
          Rect.fromLTWH(dx[c], dy[r], dw + padR, dh + padB),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UnityNineSlicePainter old) {
    return old.image != image ||
        old.canvasScale != canvasScale ||
        old.tint != tint ||
        old.colorFilter != colorFilter ||
        old.spec != spec;
  }
}

/// Exact TextMeshPro SDF Material presets extracted from `extracted_assets/Materials/Baloo2_*.json`.
class UnityTextMaterial {
  final Color faceTop;
  final Color faceBottom;
  final Color strokeColor;
  final double strokeRatio; // relative to fontSize
  final Color? outerStrokeColor;
  final double outerStrokeRatio;
  final Color underlayColor;
  final double underlayYRatio;
  final double letterSpacing;
  final String fontFamily;
  final FontWeight fontWeight;

  const UnityTextMaterial({
    this.faceTop = Colors.white,
    this.faceBottom = Colors.white,
    required this.strokeColor,
    this.strokeRatio = 0.16,
    this.outerStrokeColor,
    this.outerStrokeRatio = 0.0,
    required this.underlayColor,
    this.underlayYRatio = 0.065,
    this.letterSpacing = 0.2,
    this.fontFamily = 'Baloo2',
    this.fontWeight = FontWeight.w800,
  });

  /// `Baloo2_ExtraBold_Popup_Title` (`_FaceColor=#FFFFFF`, `_OutlineColor=#043C92` `w=0.075`,
  /// `_UnderlayColor=#01358C` `dilate=0.095` `offsetY=-0.127`).
  static const popupTitle = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF043C92),
    strokeRatio: 0.145,
    underlayColor: Color(0xFF01358C),
    underlayYRatio: 0.062,
  );

  /// `Baloo2_ExtraBold_OutOfTime` (`_FaceColor=#FFFFFF`, `_OutlineColor=#285FB9` `w=0.085`,
  /// `_UnderlayColor=#000000` `offsetY=-0.13`).
  static const outOfTime = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF285FB9),
    strokeRatio: 0.155,
    underlayColor: Color(0xFF000000),
    underlayYRatio: 0.065,
  );

  /// `Baloo2_ExtraBold_LevelCounter.json` (`Level 20` top-right HUD)
  static const levelCounter = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFD9E8FF),
    strokeColor: Color(0xFF043C92),
    strokeRatio: 0.145,
    underlayColor: Color(0xB800144A),
    underlayYRatio: 0.065,
  );

  /// `Baloo2_ExtraBold_CTA_Green_Text` (`_OutlineColor=#027C05` `w=0.08`, `_UnderlayDilate=0.221`, `_UnderlayOffsetY=-0.358`)
  static const ctaGreen = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF027C05),
    strokeRatio: 0.165,
    underlayColor: Color(0xFF027C05),
    underlayYRatio: 0.105,
  );

  /// `Baloo2_ExtraBold_CTA_Blue_Text` (`_OutlineColor=#295FB9` `w=0.08`, `_UnderlayDilate=0.221`, `_UnderlayOffsetY=-0.358`)
  static const ctaBlue = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF295FB9),
    strokeRatio: 0.165,
    underlayColor: Color(0xFF2A5FB9),
    underlayYRatio: 0.105,
  );

  /// `Baloo2_ExtraBold_CTA_Red_Text` (`_OutlineColor=#83001E` `w=0.08`, `_UnderlayDilate=0.089`, `_UnderlayOffsetY=-0.179`)
  static const ctaRed = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF83001E),
    strokeRatio: 0.165,
    underlayColor: Color(0xFF83001E),
    underlayYRatio: 0.082,
  );

  /// `Baloo2_ExtraBold_CTA_Gray_Text` (`_OutlineColor=#354953` `w=0.08`, `_UnderlayDilate=0.221`, `_UnderlayOffsetY=-0.358`)
  static const ctaGray = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF354953),
    strokeRatio: 0.165,
    underlayColor: Color(0xFF354953),
    underlayYRatio: 0.105,
  );

  /// `Baloo2_ExtraBold_CTA_Yellow_Text.json` (`Ice Blocks`, `Dud Blocks`, `Level Up` FTUE title)
  static const ctaYellow = UnityTextMaterial(
    faceTop: Color(0xFFFFF886),
    faceBottom: Color(0xFFFFC900),
    strokeColor: Color(0xFFDC6310),
    strokeRatio: 0.175,
    outerStrokeColor: Color(0xFFA12C01),
    outerStrokeRatio: 0.22,
    underlayColor: Color(0xCC5A1200),
    underlayYRatio: 0.095,
  );

  /// `Baloo2_ExtraBold_Brown_Text.json` + `Gradient_Title_Light.png` (`AMAZING!` on `Banner_Gold.png`)
  /// Exact `_OutlineWidth: 0.061` thin crisp `#761400` stroke + `-0.173` `#621100` underlay!
  static const bannerBrown = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFE5B4),
    strokeColor: Color(0xFF761400),
    strokeRatio: 0.118,
    underlayColor: Color(0xFF621100),
    underlayYRatio: 0.070,
    letterSpacing: 0.4,
  );

  /// `Level complete!` Win wave text (`PoetsenOne` font + original golden SDF stroke & gradient)
  static const levelCompleteWave = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFDE82),
    strokeColor: Color(0xFFDD6237),
    strokeRatio: 0.135,
    outerStrokeColor: Color(0xFF9F1B00),
    outerStrokeRatio: 0.185,
    underlayColor: Color(0xE0000000),
    underlayYRatio: 0.105,
    fontFamily: 'PoetsenOne',
    fontWeight: FontWeight.w400,
  );

  /// `Baloo2_ExtraBold_Label.json` (`Level X` inside `Label_Level.png`)
  static const blueLabel = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF0436C4),
    strokeRatio: 0.185,
    underlayColor: Color(0x66011C6E),
    underlayYRatio: 0.035,
  );

  /// Red power-up count badge (`PowerUp_Amount.png`)
  static const pinkBadge = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF7B0C0C),
    strokeRatio: 0.16,
    underlayColor: Color(0xAA400202),
    underlayYRatio: 0.06,
  );

  /// Win coin pile amount (`60` on `Victory.png`)
  static const winCoinAmount = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFF8EA),
    strokeColor: Color(0xFF3A200B),
    strokeRatio: 0.175,
    underlayColor: Color(0xCC241104),
    underlayYRatio: 0.065,
  );

  /// `Baloo2_ExtraBold_Navigation_Bar_Label_Brown` (`-1` on `Icon_BrokenLife.png`:
  /// `_OutlineColor=#610000` `w=0.12`, `_UnderlayColor=#470009` `dilate=0.15` `offsetY=-0.399`)
  static const brownCounter = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF610000),
    strokeRatio: 0.195,
    underlayColor: Color(0xFF470009),
    underlayYRatio: 0.115,
  );

  /// `Baloo2_ExtraBold_Tutorial_Text.json` (Tutorial text & FTUE subtitles)
  static const tutorialText = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFF2F7FF),
    strokeColor: Color(0xFF295FB9),
    strokeRatio: 0.17,
    outerStrokeColor: Color(0xFF031037),
    outerStrokeRatio: 0.23,
    underlayColor: Color(0xCC000938),
    underlayYRatio: 0.085,
  );

  /// `Baloo2_ExtraBold_DarkStroke.json` (`Loading 56%` on Splash / Transition)
  static const darkStroke = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFEAF2FF),
    strokeColor: Color(0xCC000000),
    strokeRatio: 0.18,
    underlayColor: Color(0x88000000),
    underlayYRatio: 0.06,
  );

  /// Top-Center Combo Progress Bar label (`Combo x1` on `progress_combo_bg.png` / `progress_combo_fg.png`)
  static const comboBarText = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF04143D),
    strokeRatio: 0.19,
    underlayColor: Color(0xCC000824),
    underlayYRatio: 0.08,
    letterSpacing: 0.2,
  );

  /// Golden-orange CTA button text (`"Continue"` on `Button_Yellow.png` in `Out of time.png`)
  static const ctaYellowButton = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFF8B4200),
    strokeRatio: 0.165,
    underlayColor: Color(0xFF6B3100),
    underlayYRatio: 0.095,
  );
}

/// Multi-layer SDF Text widget replicating Unity's TextMeshPro SDF shaders (multi-outline,
/// drop underlay, and top-to-bottom face gradient).
class UnitySdfText extends StatelessWidget {
  final String text;
  final double unityFontSize;
  final UnityTextMaterial material;
  final TextAlign textAlign;
  final int? maxLines;
  final double? letterSpacing;
  final bool singleTextNode;

  const UnitySdfText(
    this.text, {
    super.key,
    required this.unityFontSize,
    this.material = UnityTextMaterial.popupTitle,
    this.textAlign = TextAlign.center,
    this.maxLines,
    this.letterSpacing,
    this.singleTextNode = false,
  });

  @override
  Widget build(BuildContext context) {
    final fs = ux(context, unityFontSize);
    final weightVal = material.fontWeight.value.toDouble();
    final variations = material.fontFamily == 'Baloo2'
        ? [FontVariation('wght', weightVal)]
        : null;

    TextStyle baseStyle({Paint? foreground, Color? color}) => TextStyle(
          fontFamily: material.fontFamily,
          fontSize: fs,
          fontWeight: material.fontWeight,
          fontVariations: variations,
          letterSpacing: letterSpacing ?? material.letterSpacing,
          height: 1.08,
          foreground: foreground,
          color: color,
        );

    final innerSw = (fs * material.strokeRatio).clamp(1.2, 22.0);
    final outerSw = material.outerStrokeColor != null
        ? (fs * material.outerStrokeRatio).clamp(innerSw + 0.8, 28.0)
        : innerSw;
    final dropY = fs * material.underlayYRatio;

    final Widget faceText;
    if (material.faceTop != material.faceBottom) {
      faceText = Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        style: baseStyle(
          foreground: Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, fs * 0.12),
              Offset(0, fs * 0.98),
              [material.faceTop, material.faceBottom],
            ),
        ),
      );
    } else {
      faceText = Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        style: baseStyle(color: material.faceTop),
      );
    }

    if (singleTextNode) {
      return CustomPaint(
        painter: _UnitySdfOutlinePainter(
          text: text,
          fontSize: fs,
          material: material,
          letterSpacing: letterSpacing ?? material.letterSpacing,
        ),
        child: faceText,
      );
    }

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // 1. 3D Drop Underlay
        if (dropY > 0.2)
          Transform.translate(
            offset: Offset(0, dropY),
            child: Text(
              text,
              textAlign: textAlign,
              maxLines: maxLines,
              style: baseStyle(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = outerSw
                  ..strokeJoin = StrokeJoin.round
                  ..color = material.underlayColor,
              ),
            ),
          ),

        // 2. Optional Outer Stroke (`_OutlineColor2`)
        if (material.outerStrokeColor != null)
          Text(
            text,
            textAlign: textAlign,
            maxLines: maxLines,
            style: baseStyle(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = outerSw
                ..strokeJoin = StrokeJoin.round
                ..color = material.outerStrokeColor!,
            ),
          ),

        // 3. Primary Inner Stroke (`_OutlineColor`)
        Text(
          text,
          textAlign: textAlign,
          maxLines: maxLines,
          style: baseStyle(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = innerSw
              ..strokeJoin = StrokeJoin.round
              ..color = material.strokeColor,
          ),
        ),

        // 4. Crisp Gradient / Solid Face
        faceText,
      ],
    );
  }
}

class _UnitySdfOutlinePainter extends CustomPainter {
  final String text;
  final double fontSize;
  final UnityTextMaterial material;
  final double letterSpacing;

  const _UnitySdfOutlinePainter({
    required this.text,
    required this.fontSize,
    required this.material,
    required this.letterSpacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (text.isEmpty) return;
    final weightVal = material.fontWeight.value.toDouble();
    final variations = material.fontFamily == 'Baloo2'
        ? [FontVariation('wght', weightVal)]
        : null;

    final innerSw = (fontSize * material.strokeRatio).clamp(1.2, 22.0);
    final outerSw = material.outerStrokeColor != null
        ? (fontSize * material.outerStrokeRatio).clamp(innerSw + 0.8, 28.0)
        : innerSw;
    final dropY = fontSize * material.underlayYRatio;

    TextStyle strokeStyle(double width, Color color) => TextStyle(
          fontFamily: material.fontFamily,
          fontSize: fontSize,
          fontWeight: material.fontWeight,
          fontVariations: variations,
          letterSpacing: letterSpacing,
          height: 1.08,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeJoin = StrokeJoin.round
            ..color = color,
        );

    final tp = TextPainter(textDirection: TextDirection.ltr);

    void paintLayer(double width, Color color, double dy) {
      tp.text = TextSpan(text: text, style: strokeStyle(width, color));
      tp.layout();
      tp.paint(
        canvas,
        Offset(
          (size.width - tp.width) * 0.5,
          (size.height - tp.height) * 0.5 + dy,
        ),
      );
    }

    if (dropY > 0.2) {
      paintLayer(outerSw, material.underlayColor, dropY);
    }
    if (material.outerStrokeColor != null) {
      paintLayer(outerSw, material.outerStrokeColor!, 0.0);
    }
    paintLayer(innerSw, material.strokeColor, 0.0);
  }

  @override
  bool shouldRepaint(covariant _UnitySdfOutlinePainter old) {
    return old.text != text ||
        old.fontSize != fontSize ||
        old.material != material ||
        old.letterSpacing != letterSpacing;
  }
}

enum UnityButtonSkin { green, blue, red }

/// GPU color-matrix filters that transform the green body of `Button_CTA.png` (`499x221`)
/// into Royal Blue, Crimson Red, or Metallic Disabled Silver while preserving the exact
/// golden outer rim (`#FFB715`) across all button skins.
class UnityButtonColorFilters {
  UnityButtonColorFilters._();

  /// Turns green inner body into royal blue while keeping `#FFB715` gold border intact.
  static const ColorFilter blueWithGoldRim = ColorFilter.matrix(<double>[
    0.96, 0.05, 0.00, 0, 0,
    0.31, 0.57, 0.00, 0, 0,
    -0.82, 1.25, 0.10, 0, 0,
    0.00, 0.00, 0.00, 1, 0,
  ]);

  /// Turns green inner body into crimson red while keeping `#FFB715` gold border intact.
  static const ColorFilter redWithGoldRim = ColorFilter.matrix(<double>[
    0.18, 1.14, 0.00, 0, 0,
    0.62, 0.14, 0.00, 0, 0,
    -0.12, 0.28, 0.10, 0, 0,
    0.00, 0.00, 0.00, 1, 0,
  ]);

  /// Desaturates `Button_CTA.png` into metallic silver-grey matching `Button_Circle_Gray.png`.
  static const ColorFilter disabledSilver = ColorFilter.matrix(<double>[
    0.28, 0.58, 0.14, 0, 12,
    0.28, 0.58, 0.14, 0, 14,
    0.28, 0.58, 0.14, 0, 18,
    0.00, 0.00, 0.00, 1, 0,
  ]);

  /// Shifts dark-blue inner body of `WidgetBase.png` (`Frame_Coin.png`) into urgent crimson red
  /// while keeping its `#FFB715` golden outer rim pure gold.
  static const ColorFilter widgetBaseUrgentRed = ColorFilter.matrix(<double>[
    1.00, 0.00, 1.45, 0, 0,
    0.00, 1.00, -0.32, 0, 0,
    0.00, 0.00, 0.25, 0, 0,
    0.00, 0.00, 0.00, 1, 0,
  ]);

  /// Shifts dark-blue inner body of `WidgetBase.png` (`Frame_Coin.png`) into frosty ice-cyan
  /// while keeping its `#FFB715` golden outer rim intact.
  static const ColorFilter widgetBaseFrozenIce = ColorFilter.matrix(<double>[
    1.00, 0.00, 0.18, 0, 0,
    0.00, 1.00, 1.05, 0, 0,
    0.00, 0.00, 1.85, 0, 0,
    0.00, 0.00, 0.00, 1, 0,
  ]);

  /// Shifts green `Inset_Button_CTA.png` into warm recessed amber-brown matching `Button_Yellow.png`.
  static const ColorFilter amberInsetFromGreen = ColorFilter.matrix(<double>[
    0.15, 0.88, 0.00, 0, 14,
    0.05, 0.40, 0.00, 0, 4,
    0.00, 0.04, 0.04, 0, 0,
    0.00, 0.00, 0.00, 1, 0,
  ]);

  static ColorFilter? forSkin(UnityButtonSkin skin, {required bool enabled}) {
    if (!enabled) return disabledSilver;
    return switch (skin) {
      UnityButtonSkin.green => null,
      UnityButtonSkin.blue => blueWithGoldRim,
      UnityButtonSkin.red => redWithGoldRim,
    };
  }
}

/// Gold-rimmed 3-Slice Pill CTA Button (`Button_CTA.png`) with spring scale squish and
/// optional `Inset_Button_CTA.png` coin price box or `Icon_Ad.png` badge.
class UnityCtaButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final UnityButtonSkin skin;
  final double unityWidth;
  final double unityHeight;
  final double unityFontSize;
  final double sliceScale;
  final int? coinPrice;
  final bool showAdBadge;
  final Widget? trailingBadge;

  const UnityCtaButton({
    super.key,
    required this.label,
    required this.onTap,
    this.skin = UnityButtonSkin.green,
    this.unityWidth = 499,
    this.unityHeight = 221,
    this.unityFontSize = 68,
    this.sliceScale = 1.0,
    this.coinPrice,
    this.showAdBadge = false,
    this.trailingBadge,
  });

  @override
  State<UnityCtaButton> createState() => _UnityCtaButtonState();
}

class _UnityCtaButtonState extends State<UnityCtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final filter = UnityButtonColorFilters.forSkin(
      widget.skin,
      enabled: enabled,
    );

    final textMat = !enabled
        ? UnityTextMaterial.ctaGray
        : switch (widget.skin) {
            UnityButtonSkin.green => UnityTextMaterial.ctaGreen,
            UnityButtonSkin.blue => UnityTextMaterial.ctaBlue,
            UnityButtonSkin.red => UnityTextMaterial.ctaRed,
          };

    final w = ux(context, widget.unityWidth);
    final h = ux(context, widget.unityHeight);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed && enabled ? 0.935 : 1.0,
        duration: const Duration(milliseconds: 85),
        curve: Curves.easeOutCubic,
        child: UnityNineSlice(
          sprite: 'Button_CTA.png',
          width: w,
          height: h,
          pixelMultiplier: widget.sliceScale,
          colorFilter: filter,
          padding: EdgeInsets.only(
            left: ux(context, 38 * widget.sliceScale),
            right: ux(context, 38 * widget.sliceScale),
            bottom: ux(context, 10 * widget.sliceScale),
          ),
          child: _buildInnerContent(context, textMat, enabled),
        ),
      ),
    );
  }

  Widget _buildInnerContent(
    BuildContext context,
    UnityTextMaterial textMat,
    bool enabled,
  ) {
    if (widget.coinPrice != null) {
      final insetSprite = widget.skin == UnityButtonSkin.red
          ? 'Inset_Button_CTA_Red.png'
          : 'Inset_Button_CTA.png';
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(left: ux(context, 12)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: UnitySdfText(
                  widget.label,
                  unityFontSize: widget.unityFontSize,
                  material: textMat,
                ),
              ),
            ),
          ),
          SizedBox(width: ux(context, 16)),
          UnityNineSlice(
            sprite: insetSprite,
            height: ux(context, 90),
            padding: EdgeInsets.symmetric(
              horizontal: ux(context, 22),
              vertical: ux(context, 8),
            ),
            tint: enabled ? null : const Color(0xFF99A3B0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/Icon_Coin.png',
                  width: ux(context, 62),
                  height: ux(context, 62),
                ),
                SizedBox(width: ux(context, 10)),
                UnitySdfText(
                  '${widget.coinPrice}',
                  unityFontSize: widget.unityFontSize * 0.94,
                  material: textMat,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (widget.showAdBadge || widget.trailingBadge != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showAdBadge) ...[
            Image.asset(
              'assets/images/Icon_Ad.png',
              width: ux(context, 72),
              height: ux(context, 72),
            ),
            SizedBox(width: ux(context, 18)),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: UnitySdfText(
                widget.label,
                unityFontSize: widget.unityFontSize,
                material: textMat,
              ),
            ),
          ),
          if (widget.trailingBadge != null) ...[
            SizedBox(width: ux(context, 16)),
            widget.trailingBadge!,
          ],
        ],
      );
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: UnitySdfText(
        widget.label,
        unityFontSize: widget.unityFontSize,
        material: textMat,
      ),
    );
  }
}

/// Reusable 3-Slice Stacked Green Coin CTA Button (`Button_CTA.png` / `Button_Green.png` + `Inset_Button_CTA.png`):
/// - Preserves circular `1:1` gold capsule end-caps via [UnityNineSlice] (`UnitySliceSpec(110, 0, 110, 0)`)
///   so the button never distorts across single-button or dual-button widths!
/// - Top line: [label] (`UnityTextMaterial.ctaGreen`)
/// - Bottom recessed socket: `Inset_Button_CTA.png` (`Icon_Coin.png` + [coinLabel])
class UnityStackedCoinCtaButton extends StatefulWidget {
  final String label;
  final String coinLabel;
  final VoidCallback? onTap;
  final String sprite;
  final double? unityWidth;
  final double unityHeight;
  final double unityFontSize;
  final double insetUnityWidth;
  final double insetUnityHeight;

  const UnityStackedCoinCtaButton({
    super.key,
    required this.label,
    required this.coinLabel,
    required this.onTap,
    this.sprite = 'Button_CTA.png',
    this.unityWidth,
    this.unityHeight = 221,
    this.unityFontSize = 54,
    this.insetUnityWidth = 224,
    this.insetUnityHeight = 58,
  });

  @override
  State<UnityStackedCoinCtaButton> createState() =>
      _UnityStackedCoinCtaButtonState();
}

class _UnityStackedCoinCtaButtonState extends State<UnityStackedCoinCtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final textMat =
        enabled ? UnityTextMaterial.ctaGreen : UnityTextMaterial.ctaGray;
    final w = widget.unityWidth != null ? ux(context, widget.unityWidth!) : null;
    final h = ux(context, widget.unityHeight);
    final hRatio = widget.unityHeight / 221.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              if (_pressed) setState(() => _pressed = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed && enabled ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: UnityNineSlice(
          sprite: widget.sprite,
          width: w,
          height: h,
          colorFilter:
              enabled ? null : UnityButtonColorFilters.disabledSilver,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Upper Primary Label (`"Next Level"`)
              Positioned(
                left: ux(context, 38),
                right: ux(context, 38),
                top: ux(context, 20 * hRatio),
                bottom: ux(context, (22 + widget.insetUnityHeight) * hRatio),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: UnitySdfText(
                      widget.label,
                      unityFontSize: widget.unityFontSize,
                      material: textMat,
                      singleTextNode: true,
                    ),
                  ),
                ),
              ),

              // Bottom-Docked Recessed Arch Socket (`Inset_Button_CTA.png` flush on inner gold rim)
              Positioned(
                bottom: ux(context, 22 * hRatio),
                child: UnityNineSlice(
                  sprite: 'Inset_Button_CTA.png',
                  width: ux(context, widget.insetUnityWidth),
                  height: ux(context, widget.insetUnityHeight * hRatio),
                  tint: enabled ? null : const Color(0xFF99A3B0),
                  padding: EdgeInsets.fromLTRB(
                    ux(context, 20),
                    ux(context, 4 * hRatio),
                    ux(context, 20),
                    ux(context, 2 * hRatio),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/Icon_Coin.png',
                        width: ux(context, 44 * hRatio),
                        height: ux(context, 44 * hRatio),
                        fit: BoxFit.contain,
                      ),
                      SizedBox(width: ux(context, 8)),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: UnitySdfText(
                            widget.coinLabel,
                            unityFontSize: widget.unityFontSize * 0.82,
                            material: textMat,
                            singleTextNode: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable 3-Slice Stacked Golden-Yellow Rewarded-Ad CTA Button (`Button_Yellow.png` + `Icon_Ads.png`):
/// - Preserves circular `1:1` gold capsule end-caps via [UnityNineSlice] (`UnitySliceSpec(110, 0, 110, 0)`)!
/// - Overlapping top-left 3D clapperboard badge `Icon_Ads.png` matching `LoseOverlay` (`Out of time!`).
/// - Recessed amber `Inset_Button_CTA.png` socket (`Icon_Coin.png` + [coinLabel]).
class UnityStackedAdCtaButton extends StatefulWidget {
  final String label;
  final String coinLabel;
  final VoidCallback? onTap;
  final double shimmerPhase;
  final double? unityWidth;
  final double unityHeight;
  final double unityFontSize;
  final double insetUnityWidth;
  final double insetUnityHeight;

  const UnityStackedAdCtaButton({
    super.key,
    required this.label,
    required this.coinLabel,
    required this.onTap,
    this.shimmerPhase = 0.0,
    this.unityWidth,
    this.unityHeight = 221,
    this.unityFontSize = 54,
    this.insetUnityWidth = 224,
    this.insetUnityHeight = 58,
  });

  @override
  State<UnityStackedAdCtaButton> createState() =>
      _UnityStackedAdCtaButtonState();
}

class _UnityStackedAdCtaButtonState extends State<UnityStackedAdCtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final textMat = enabled
        ? UnityTextMaterial.ctaYellowButton
        : UnityTextMaterial.ctaGray;
    final w = widget.unityWidth != null ? ux(context, widget.unityWidth!) : null;
    final h = ux(context, widget.unityHeight);
    final hRatio = widget.unityHeight / 221.0;
    final breath = _pressed
        ? 0.94
        : (enabled
            ? (1.0 + 0.014 * math.sin(widget.shimmerPhase * math.pi * 4.0))
            : 1.0);

    Widget body = SizedBox(
      width: w,
      height: h,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 1. 3-Slice Golden-Orange Pill (`Button_Yellow.png` — zero cap distortion!)
          Positioned.fill(
            child: UnityNineSlice(
              sprite: 'Button_Yellow.png',
              colorFilter:
                  enabled ? null : UnityButtonColorFilters.disabledSilver,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Upper Primary Label (`"Reward x2"`)
                  Positioned(
                    left: ux(context, 52),
                    right: ux(context, 36),
                    top: ux(context, 20 * hRatio),
                    bottom:
                        ux(context, (22 + widget.insetUnityHeight) * hRatio),
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: UnitySdfText(
                          widget.label,
                          unityFontSize: widget.unityFontSize,
                          material: textMat,
                          singleTextNode: true,
                        ),
                      ),
                    ),
                  ),

                  // Bottom-Docked Recessed Arch Socket (`Inset_Button_CTA.png` flush on inner gold rim)
                  Positioned(
                    bottom: ux(context, 22 * hRatio),
                    child: UnityNineSlice(
                      sprite: 'Inset_Button_CTA.png',
                      width: ux(context, widget.insetUnityWidth),
                      height: ux(context, widget.insetUnityHeight * hRatio),
                      colorFilter: enabled
                          ? UnityButtonColorFilters.amberInsetFromGreen
                          : UnityButtonColorFilters.disabledSilver,
                      padding: EdgeInsets.fromLTRB(
                        ux(context, 20),
                        ux(context, 4 * hRatio),
                        ux(context, 20),
                        ux(context, 2 * hRatio),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/Icon_Coin.png',
                            width: ux(context, 44 * hRatio),
                            height: ux(context, 44 * hRatio),
                            fit: BoxFit.contain,
                          ),
                          SizedBox(width: ux(context, 8)),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: UnitySdfText(
                                widget.coinLabel,
                                unityFontSize: widget.unityFontSize * 0.82,
                                material: textMat,
                                singleTextNode: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 2. Subtle Diagonal Shimmer Sweep inside the inner button face
          if (enabled)
            Positioned(
              left: ux(context, 24),
              right: ux(context, 24),
              top: ux(context, 16),
              bottom: ux(context, 28),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(h * 0.42),
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _UnityCtaShimmerPainter(
                      phase: (widget.shimmerPhase * 2.0) % 1.0,
                    ),
                  ),
                ),
              ),
            ),

          // 3. Overlapping Top-Left 3D Clapperboard Badge (`Icon_Ads.png` — exact match with `LoseOverlay`)
          Positioned(
            left: -ux(context, 8),
            top: -ux(context, 38),
            width: ux(context, 114),
            height: ux(context, 119),
            child: IgnorePointer(
              child: Opacity(
                opacity: enabled ? 1.0 : 0.65,
                child: Image.asset(
                  'assets/images/Icon_Ads.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              if (_pressed) setState(() => _pressed = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: Transform.scale(
        scale: breath,
        child: body,
      ),
    );
  }
}

class _UnityCtaShimmerPainter extends CustomPainter {
  final double phase;

  const _UnityCtaShimmerPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    if (phase > 0.52) return;
    final t = (phase / 0.52).clamp(0.0, 1.0);
    final sweepX = ui.lerpDouble(-size.width * 0.45, size.width * 1.35, t)!;
    final bandW = size.width * 0.30;

    final path = Path()
      ..moveTo(sweepX, 0)
      ..lineTo(sweepX + bandW, 0)
      ..lineTo(sweepX + bandW - 18, size.height)
      ..lineTo(sweepX - 18, size.height)
      ..close();

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white
      ..shader = ui.Gradient.linear(
        Offset(sweepX - 10, 0),
        Offset(sweepX + bandW, 0),
        const [
          Color(0x00FFFFFF),
          Color(0x40FFFDE7),
          Color(0x00FFFFFF),
        ],
        const [0.0, 0.5, 1.0],
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _UnityCtaShimmerPainter old) =>
      old.phase != phase;
}

/// Interactive spring-squish sprite button (`Button_Close.png`, `Button_Circle_Green.png`, etc.).
class UnitySpriteButton extends StatefulWidget {
  final Widget? child;
  final String? asset;
  final double? unitySize;
  final VoidCallback? onTap;

  const UnitySpriteButton({
    super.key,
    this.child,
    this.asset,
    this.unitySize,
    required this.onTap,
  }) : assert(child != null || asset != null);

  @override
  State<UnitySpriteButton> createState() => _UnitySpriteButtonState();
}

class _UnitySpriteButtonState extends State<UnitySpriteButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final resolvedChild = widget.child ??
        Image.asset(
          widget.asset!.startsWith('assets/')
              ? widget.asset!
              : 'assets/images/${widget.asset!}',
          width: ux(context, widget.unitySize ?? 96),
          height: ux(context, widget.unitySize ?? 96),
          fit: BoxFit.contain,
        );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed && enabled ? 0.91 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: resolvedChild,
      ),
    );
  }
}

/// Exact 1:1 replica of Unity's shared `PopupContainer` (`sz = (1106.25, 1337.91)`, `sc = (0.816, 0.816)`
/// -> `902.70 x 1091.73` in 1080x1920 reference space) used by `PlayOnPopupView`, `LoseGameplayView`,
/// `ExitGameplayView`, and `PopupView`:
/// - `Background` (`Background_Popup.png`, `ppuMult = 1.0`): `pos = (0, -35), sz = (+70, +80)` -> `1176.25 x 1417.91`
/// - `Header`: `amin=(0,1) amax=(1,1) pos=(0.12, -120) sz=(-79.75, 195)` -> `1026.50 x 195.00` at `top = 22.50`
///   - `CloseButton`: `amin=(1,1) amax=(1,1) pos=(11.10, -16.91) sz=(153.90, 155.18)` -> child `Button_Close.png`
///     `pos=(0, -7.50) sz=(+20, +15)` -> `173.90 x 170.18` centered at `(1077.60, 46.91)`
/// - `Panel`: `amin=(0,0) amax=(1,1) pos=(0.12, 75.47) sz=(-79.75, -603.68)` -> `1026.50 x 734.23` at `top = 226.37`
///   - `Image` (`Panel_Popup.png`, `ppuMult = 1.0`): `pos=(0, -2.50) sz=(+10, +25)` -> `1036.50 x 759.23`
/// - `Footer` / `ButtonsContainer`: `1026.50 x 290.00` at `top = 988.91` (center `204.00` above bottom).
class UnityPopupCard extends StatelessWidget {
  static const double localWidth = 1106.25;
  static const double localHeight = 1337.91;
  static const double localInnerWidth = 1026.50;
  static const double localPanelHeight = 734.23;

  final String title;
  final double localTitleFontSize;
  final VoidCallback? onClose;
  final Widget panelChild;
  final Widget footerChild;
  final bool animateEntrance;

  const UnityPopupCard({
    super.key,
    required this.title,
    this.localTitleFontSize = 116.5,
    this.onClose,
    required this.panelChild,
    required this.footerChild,
    this.animateEntrance = true,
  });

  static const double _hitPadX = 60.0;
  static const double _hitPadY = 75.0;

  @override
  Widget build(BuildContext context) {
    Widget shell = SizedBox(
      width: ppx(context, localWidth + _hitPadX * 2.0),
      height: ppx(context, localHeight + _hitPadY * 2.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. `Background` (`Background_Popup.png` gold-rimmed blue shell)
          // Absorbs pointer hits inside the visual card body so taps on the card
          // never leak through to `DarkOverlay` hold-to-peek.
          Positioned(
            left: ppx(context, _hitPadX - 18.0),
            right: ppx(context, _hitPadX - 18.0),
            top: ppx(context, _hitPadY + 42.0),
            bottom: ppx(context, _hitPadY - 65.0),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: const UnityNineSlice(
                sprite: 'Background_Popup.png',
                pixelMultiplier: kUnityPopupScale,
              ),
            ),
          ),

          // 2. `Header` (`Frame_Popup_Title.png` gold-rimmed blue ribbon sitting over top edge)
          Positioned(
            left: ppx(context, _hitPadX + 160.0),
            right: ppx(context, _hitPadX + 160.0),
            top: ppx(context, _hitPadY - 6.0),
            height: ppx(context, 182.0),
            child: IgnorePointer(
              child: UnityNineSlice(
                sprite: 'Frame_Popup_Title.png',
                pixelMultiplier: kUnityPopupScale,
                padding: EdgeInsets.fromLTRB(
                  ppx(context, 48.0),
                  ppx(context, 6.0),
                  ppx(context, 48.0),
                  ppx(context, 16.0),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: UnitySdfText(
                    title,
                    unityFontSize: localTitleFontSize * 0.80 * kUnityPopupScale,
                    material: UnityTextMaterial.popupTitle,
                  ),
                ),
              ),
            ),
          ),

          // 3. `Panel` (`1026.50 x 734.23` at `left = 40.00, top = 216.00`)
          Positioned(
            left: ppx(context, _hitPadX + 44.00),
            top: ppx(context, _hitPadY + 216.00),
            width: ppx(context, localInnerWidth - 8.0),
            height: ppx(context, localPanelHeight),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // `Panel/Image` (`Panel_Popup.png` cream content well)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: const IgnorePointer(
                    child: UnityNineSlice(
                      sprite: 'Panel_Popup.png',
                      pixelMultiplier: kUnityPopupScale,
                    ),
                  ),
                ),

                // Exact `1026.50 x 734.23` local content box
                Positioned.fill(child: panelChild),
              ],
            ),
          ),

          // 4. `Footer / ButtonsContainer` (`1026.50 x 290.00` centered at `cy = 1133.91`)
          Positioned(
            left: ppx(context, _hitPadX + 40.00),
            top: ppx(context, _hitPadY + 982.00),
            width: ppx(context, localInnerWidth),
            height: ppx(context, 290.00),
            child: Center(child: footerChild),
          ),

          // 5. `Header / CloseButton` (`Button_Close.png` overlapping top-right corner)
          if (onClose != null)
            Positioned(
              right: ppx(context, _hitPadX - 30.0),
              top: ppx(context, _hitPadY + 2.0),
              width: ppx(context, 168.0),
              height: ppx(context, 168.0),
              child: UnitySpriteButton(
                onTap: onClose,
                child: Image.asset(
                  'assets/images/Button_Close.png',
                  width: ppx(context, 168.0),
                  height: ppx(context, 168.0),
                  fit: BoxFit.contain,
                ),
              ),
            ),
        ],
      ),
    );

    if (!animateEntrance) {
      return shell;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.90, end: 1.0),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: child,
      ),
      child: shell,
    );
  }
}

/// Gold-rimmed `PopupContainer`-scale single CTA button (`LoseGameplayView` `"Try Again"` &
/// `ExitGameplayView` `"Restart"`).
class UnityPopupCtaButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final UnityButtonSkin skin;
  final double localWidth;
  final double localHeight;
  final double localFontSize;

  const UnityPopupCtaButton({
    super.key,
    required this.label,
    required this.onTap,
    this.skin = UnityButtonSkin.green,
    this.localWidth = 585.20,
    this.localHeight = 232.0,
    this.localFontSize = 96.0,
  });

  @override
  State<UnityPopupCtaButton> createState() => _UnityPopupCtaButtonState();
}

class _UnityPopupCtaButtonState extends State<UnityPopupCtaButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final filter = UnityButtonColorFilters.forSkin(
      widget.skin,
      enabled: enabled,
    );
    final textMat = !enabled
        ? UnityTextMaterial.ctaGray
        : switch (widget.skin) {
            UnityButtonSkin.green => UnityTextMaterial.ctaGreen,
            UnityButtonSkin.blue => UnityTextMaterial.ctaBlue,
            UnityButtonSkin.red => UnityTextMaterial.ctaRed,
          };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedScale(
        scale: _pressed && enabled ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: ppx(context, widget.localWidth),
          height: ppx(context, widget.localHeight),
          child: UnityNineSlice(
            sprite: 'Button_CTA.png',
            colorFilter: filter,
            pixelMultiplier: kUnityPopupScale,
            padding: EdgeInsets.fromLTRB(
              ppx(context, 42.0),
              ppx(context, 12.0),
              ppx(context, 42.0),
              ppx(context, 22.0),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: UnitySdfText(
                widget.label,
                unityFontSize: widget.localFontSize * kUnityPopupScale,
                material: textMat,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared Top-Left `CoinsWidget` (`Play_Scene.png` / `Play_Scene 2.png`):
/// - `WidgetBase.png` (`255x96` gold-rimmed dark-blue pill)
/// - `Icon_Coin.png` (`97x101` golden crown coin on the left)
/// - `PowerUp_Plus.png` (`46x46` green `+` badge at bottom-right of the coin icon)
class UnityCoinsWidget extends StatelessWidget {
  static const double hudLeftUnity = 58.0;
  static const double hudTopUnity = 21.0;
  static const double widthUnity = 286.0;
  static const double heightUnity = 108.0;
  static const double coinCenterXUnity = hudLeftUnity + 48.5;
  static const double coinCenterYUnity = hudTopUnity + 52.5;

  final int coins;
  final double scale;
  final bool showPlusBadge;

  const UnityCoinsWidget({
    super.key,
    required this.coins,
    this.scale = 1.0,
    this.showPlusBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget pill = SizedBox(
      width: ux(context, widthUnity),
      height: ux(context, heightUnity),
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: ux(context, 29),
            top: ux(context, 4),
            width: ux(context, 257),
            height: ux(context, 96),
            child: UnityNineSlice(
              sprite: 'WidgetBase.png',
              height: ux(context, 96),
              padding: EdgeInsets.only(
                left: ux(context, 78),
                right: ux(context, 22),
                bottom: ux(context, 4),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$coins',
                  style: TextStyle(
                    fontFamily: 'Baloo2',
                    fontSize: ux(context, 48),
                    fontWeight: FontWeight.w800,
                    fontVariations: const [FontVariation('wght', 800)],
                    color: Colors.white,
                    height: 1.0,
                    shadows: const [
                      Shadow(
                        color: Color(0xAA09042E),
                        offset: Offset(0, 1.5),
                        blurRadius: 2.5,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: ux(context, 2),
            width: ux(context, 97),
            height: ux(context, 101),
            child: Image.asset(
              'assets/images/Icon_Coin.png',
              fit: BoxFit.contain,
            ),
          ),
          if (showPlusBadge)
            Positioned(
              left: ux(context, 58),
              bottom: 0,
              width: ux(context, 46),
              height: ux(context, 46),
              child: Image.asset(
                'assets/images/PowerUp_Plus.png',
                fit: BoxFit.contain,
              ),
            ),
        ],
      ),
    );

    if ((scale - 1.0).abs() > 0.001) {
      pill = Transform.scale(scale: scale, child: pill);
    }
    return IgnorePointer(child: pill);
  }
}


