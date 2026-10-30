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

  /// Exact 9-slice borders extracted from Unity `extracted_assets/_Manifests/sprites.json`.
  static const Map<String, UnitySliceSpec> slices = {
    'Background_Popup.png': UnitySliceSpec(158, 207, 156, 163),
    'Panel_Popup.png': UnitySliceSpec(120, 120, 120, 120),
    'Panel_PlayOn.png': UnitySliceSpec(61, 67, 59, 48),
    'Box_Text.png': UnitySliceSpec(62, 69, 65, 51),
    'Banner.png': UnitySliceSpec(50, 57, 50, 37),
    'Label_Level.png': UnitySliceSpec(90, 0, 90, 0),
    'WidgetBase.png': UnitySliceSpec(111, 0, 107, 0),
    'Button_CTA.png': UnitySliceSpec(72, 70, 72, 56),
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

  const _UnityNineSlicePainter({
    required this.image,
    required this.spec,
    required this.canvasScale,
    this.tint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null || size.width <= 0.5 || size.height <= 0.5) return;

    final iw = img.width.toDouble();
    final ih = img.height.toDouble();

    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (tint != null) {
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

  /// `Baloo2_ExtraBold_Popup_Title.json` + `Gradient_Popup_Title_Light.png`
  static const popupTitle = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFD7E7FF),
    strokeColor: Color(0xFF043C92),
    strokeRatio: 0.165,
    outerStrokeColor: Color(0xFF012C78),
    outerStrokeRatio: 0.21,
    underlayColor: Color(0xCC001038),
    underlayYRatio: 0.075,
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

  /// `Baloo2_ExtraBold_CTA_Green_Text.json` (`Next Level`, `Play On`, `Continue`, `Buy`, `Try Again`)
  static const ctaGreen = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFF3FFE8),
    strokeColor: Color(0xFF027C05),
    strokeRatio: 0.175,
    underlayColor: Color(0xFF026104),
    underlayYRatio: 0.085,
  );

  /// `Baloo2_ExtraBold_CTA_Blue_Text.json` (`25` coin reward, `Watch`, `Get`)
  static const ctaBlue = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFEDF5FF),
    strokeColor: Color(0xFF295FB9),
    strokeRatio: 0.185,
    underlayColor: Color(0xFF174191),
    underlayYRatio: 0.085,
  );

  /// `Baloo2_ExtraBold_CTA_Red_Text.json` (`Restart` red CTA)
  static const ctaRed = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFEEF1),
    strokeColor: Color(0xFF83001E),
    strokeRatio: 0.175,
    underlayColor: Color(0xFF5C0013),
    underlayYRatio: 0.075,
  );

  /// `Baloo2_ExtraBold_CTA_Gray_Text.json` (Disabled CTA buttons)
  static const ctaGray = UnityTextMaterial(
    faceTop: Color(0xFFF2F5F8),
    faceBottom: Color(0xFFDCE2E8),
    strokeColor: Color(0xFF354953),
    strokeRatio: 0.17,
    underlayColor: Color(0xFF26353D),
    underlayYRatio: 0.075,
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
  static const bannerBrown = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFEAB5),
    strokeColor: Color(0xFF761400),
    strokeRatio: 0.16,
    underlayColor: Color(0xFF540D00),
    underlayYRatio: 0.08,
    letterSpacing: 0.6,
  );

  /// `Baloo2_ExtraBold_Level_Complete.json` (`Level complete!` Stage-1 Win wave text)
  static const levelCompleteWave = UnityTextMaterial(
    faceTop: Color(0xFFFFF35C),
    faceBottom: Color(0xFFFFD000),
    strokeColor: Color(0xFFDD6237),
    strokeRatio: 0.16,
    outerStrokeColor: Color(0xFF9F1B00),
    outerStrokeRatio: 0.21,
    underlayColor: Color(0xD9000000),
    underlayYRatio: 0.10,
  );

  /// `Baloo2_ExtraBold_Label.json` (`Level 19` inside `Label_Level.png`)
  static const blueLabel = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFEAF3FF),
    strokeColor: Color(0xFF0436C4),
    strokeRatio: 0.19,
    underlayColor: Color(0x88011C6E),
    underlayYRatio: 0.055,
  );

  /// `Baloo2_ExtraBold_Label_Pink.json` (Power-up magenta count badge `3`)
  static const pinkBadge = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFFFFF),
    strokeColor: Color(0xFFBF12BA),
    strokeRatio: 0.18,
    underlayColor: Color(0xAA00096A),
    underlayYRatio: 0.08,
  );

  /// `Baloo2_ExtraBold_Navigation_Bar_Label_Brown.json` (`-1` on `Icon_BrokenLife.png`)
  static const brownCounter = UnityTextMaterial(
    faceTop: Color(0xFFFFFFFF),
    faceBottom: Color(0xFFFFEFEA),
    strokeColor: Color(0xFF610000),
    strokeRatio: 0.18,
    underlayColor: Color(0xFF470009),
    underlayYRatio: 0.085,
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
}

/// Multi-layer SDF Text widget replicating Unity's TextMeshPro SDF shaders (multi-outline,
/// drop underlay, and top-to-bottom face gradient).
class UnitySdfText extends StatelessWidget {
  final String text;
  final double unityFontSize;
  final UnityTextMaterial material;
  final TextAlign textAlign;
  final int? maxLines;

  const UnitySdfText(
    this.text, {
    super.key,
    required this.unityFontSize,
    this.material = UnityTextMaterial.popupTitle,
    this.textAlign = TextAlign.center,
    this.maxLines,
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
          letterSpacing: material.letterSpacing,
          height: 1.08,
          foreground: foreground,
          color: color,
        );

    final innerSw = (fs * material.strokeRatio).clamp(1.2, 22.0);
    final outerSw = material.outerStrokeColor != null
        ? (fs * material.outerStrokeRatio).clamp(innerSw + 0.8, 28.0)
        : innerSw;
    final dropY = fs * material.underlayYRatio;

    Widget faceText = Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      style: baseStyle(color: Colors.white),
    );

    if (material.faceTop != material.faceBottom) {
      faceText = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [material.faceTop, material.faceBottom],
        ).createShader(bounds),
        child: faceText,
      );
    } else if (material.faceTop != Colors.white) {
      faceText = Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        style: baseStyle(color: material.faceTop),
      );
    }

    return Stack(
      alignment: Alignment.center,
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

enum UnityButtonSkin { green, blue, red }

/// Authentic Unity 9-Slice CTA Button (`Button_CTA.png`, `Button_Blue.png`, `Button_Red.png`,
/// `Button_CTA_Disabled.png`) with `Button_Down` / `Button_Up` spring scale squish and
/// optional `Inset_Button_CTA.png` coin price box or `Icon_Ad.png` badge.
class UnityCtaButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final UnityButtonSkin skin;
  final double unityWidth;
  final double unityHeight;
  final double unityFontSize;
  final int? coinPrice;
  final bool showAdBadge;
  final Widget? trailingBadge;

  const UnityCtaButton({
    super.key,
    required this.label,
    required this.onTap,
    this.skin = UnityButtonSkin.green,
    this.unityWidth = 560,
    this.unityHeight = 158,
    this.unityFontSize = 84,
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
    final sprite = !enabled
        ? 'Button_CTA_Disabled.png'
        : switch (widget.skin) {
            UnityButtonSkin.green => 'Button_CTA.png',
            UnityButtonSkin.blue => 'Button_Blue.png',
            UnityButtonSkin.red => 'Button_Red.png',
          };

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
          sprite: sprite,
          width: w,
          height: h,
          padding: EdgeInsets.only(
            left: ux(context, 34),
            right: ux(context, 30),
            bottom: ux(context, 12),
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

/// Exact replica of Unity's shared `PopupView.prefab` (`Background_Popup.png` bright sky-blue
/// 3D outer frame + `Header` title + overlapping top-right `Button_Close.png` + `Panel_Popup.png`
/// crisp icy-white inner card + `Footer` CTA buttons).
class UnityPopupCard extends StatelessWidget {
  final String title;
  final double titleUnitySize;
  final VoidCallback? onClose;
  final Widget panelChild;
  final Widget footerChild;
  final double unityWidth;
  final EdgeInsets? panelPadding;

  const UnityPopupCard({
    super.key,
    required this.title,
    this.titleUnitySize = 104,
    this.onClose,
    required this.panelChild,
    required this.footerChild,
    this.unityWidth = 910,
    this.panelPadding,
  });

  @override
  Widget build(BuildContext context) {
    final cardW = ux(context, unityWidth);
    final closeSize = ux(context, 136);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.78, end: 1.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: child,
      ),
      child: SizedBox(
        width: cardW,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // 1. Sky-Blue 3D Outer Shell (`Background_Popup.png`)
            UnityNineSlice(
              sprite: 'Background_Popup.png',
              width: cardW,
              padding: EdgeInsets.fromLTRB(
                ux(context, 52),
                ux(context, 38),
                ux(context, 52),
                ux(context, 62),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Title
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: ux(context, 54)),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: UnitySdfText(
                        title,
                        unityFontSize: titleUnitySize,
                        material: UnityTextMaterial.popupTitle,
                      ),
                    ),
                  ),
                  SizedBox(height: ux(context, 28)),

                  // 2. Crisp Icy-White Inner Card (`Panel_Popup.png`)
                  UnityNineSlice(
                    sprite: 'Panel_Popup.png',
                    width: double.infinity,
                    padding: panelPadding ??
                        EdgeInsets.fromLTRB(
                          ux(context, 44),
                          ux(context, 46),
                          ux(context, 44),
                          ux(context, 46),
                        ),
                    child: panelChild,
                  ),

                  SizedBox(height: ux(context, 34)),

                  // 3. Footer Buttons
                  footerChild,
                ],
              ),
            ),

            // 4. Overlapping Top-Right 3D Royal-Blue Close Button (`Button_Close.png`)
            if (onClose != null)
              Positioned(
                top: -ux(context, 24),
                right: -ux(context, 18),
                child: UnitySpriteButton(
                  onTap: onClose,
                  child: Image.asset(
                    'assets/images/Button_Close.png',
                    width: closeSize,
                    height: closeSize,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
