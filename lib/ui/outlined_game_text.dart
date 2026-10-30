import 'package:flutter/material.dart';

/// Renders cartoon 3D outlined text matching Unity TextMeshPro SDF multi-stroke labels.
class OutlinedGameText extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;
  final double shadowOffsetY;
  final TextAlign textAlign;
  final double letterSpacing;

  const OutlinedGameText(
    this.text, {
    super.key,
    required this.fontSize,
    this.fillColor = Colors.white,
    this.strokeColor = const Color(0xFF1A2E7A),
    this.strokeWidth = 4.5,
    this.shadowOffsetY = 2.2,
    this.textAlign = TextAlign.center,
    this.letterSpacing = 0.3,
  });

  @override
  Widget build(BuildContext context) {
    const variations = [FontVariation('wght', 800)];

    final strokeStyle = TextStyle(
      fontFamily: 'Baloo2',
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      fontVariations: variations,
      letterSpacing: letterSpacing,
      height: 1.05,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = strokeColor,
    );

    final fillStyle = TextStyle(
      fontFamily: 'Baloo2',
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      fontVariations: variations,
      letterSpacing: letterSpacing,
      height: 1.05,
      color: fillColor,
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        if (shadowOffsetY > 0)
          Transform.translate(
            offset: Offset(0, shadowOffsetY),
            child: Text(
              text,
              textAlign: textAlign,
              style: strokeStyle,
            ),
          ),
        Text(
          text,
          textAlign: textAlign,
          style: strokeStyle,
        ),
        Text(
          text,
          textAlign: textAlign,
          style: fillStyle,
        ),
      ],
    );
  }
}

enum GlossyButtonTheme { green, blue, red }

/// Glossy 3D beveled button matching `Button_CTA.png` / `Button_Blue.png` / `Button_Red.png`
/// without 9-slice corner stretching artifacts at arbitrary aspect ratios.
class GlossyGameButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final GlossyButtonTheme theme;
  final double width;
  final double height;
  final double borderRadius;

  const GlossyGameButton({
    super.key,
    required this.child,
    required this.onTap,
    this.theme = GlossyButtonTheme.green,
    this.width = 232,
    this.height = 66,
    this.borderRadius = 20,
  });

  @override
  State<GlossyGameButton> createState() => _GlossyGameButtonState();
}

class _GlossyGameButtonState extends State<GlossyGameButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    final (Color rimTop, Color faceTop, Color faceBottom, Color lipColor, Color borderDark) =
        !enabled
            ? (
                const Color(0xFF9BA5B8),
                const Color(0xFF7D879B),
                const Color(0xFF636D80),
                const Color(0xFF474F60),
                const Color(0xFF282E3A),
              )
            : switch (widget.theme) {
                GlossyButtonTheme.green => (
                    const Color(0xFF8FF92B),
                    const Color(0xFF53E015),
                    const Color(0xFF2EB809),
                    const Color(0xFF0E7D03),
                    const Color(0xFF053D01),
                  ),
                GlossyButtonTheme.blue => (
                    const Color(0xFF6CD6FF),
                    const Color(0xFF29A9FF),
                    const Color(0xFF0E7AE6),
                    const Color(0xFF084BA8),
                    const Color(0xFF04255E),
                  ),
                GlossyButtonTheme.red => (
                    const Color(0xFFFF8599),
                    const Color(0xFFFF4361),
                    const Color(0xFFE01B3C),
                    const Color(0xFF9C0B23),
                    const Color(0xFF4D0310),
                  ),
              };

    final pressOffset = _pressed && enabled ? 3.5 : 0.0;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: widget.width,
        height: widget.height,
        transform: Matrix4.translationValues(0, pressOffset, 0),
        decoration: BoxDecoration(
          color: lipColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: borderDark, width: 2.6),
          boxShadow: [
            if (!_pressed)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        padding: EdgeInsets.only(
          left: 5,
          right: 5,
          top: 4,
          bottom: _pressed ? 4 : 8,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius - 5),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [faceTop, faceBottom],
            ),
            border: Border(
              top: BorderSide(color: rimTop, width: 3.0),
            ),
          ),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
