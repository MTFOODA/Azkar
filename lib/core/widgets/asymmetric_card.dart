import 'package:flutter/material.dart';

import '../design/card_shape.dart';
import '../design/card_shape_geometry.dart';
import 'islamic_pattern_painter.dart';

/// Paints an [AsymmetricCard] background without clipping its content.
class CardSurfacePainter extends CustomPainter {
  const CardSurfacePainter({
    required this.shape,
    required this.backgroundColor,
    required this.shadowColor,
    required this.borderColor,
    required this.showBorder,
    required this.gradient,
    required this.decorationColor,
    required this.showDecoration,
    required this.elevation,
  });

  final CardShapeId shape;
  final Color backgroundColor;
  final Color shadowColor;
  final Color borderColor;
  final bool showBorder;
  final Gradient? gradient;
  final Color decorationColor;
  final bool showDecoration;
  final double elevation;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final path = CardShapeGeometry.buildPath(shape, size);
    if (elevation > 0) canvas.drawShadow(path, shadowColor, elevation, true);
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;
    if (gradient != null) {
      paint.shader = gradient!.createShader(rect);
    } else {
      paint.color = backgroundColor;
    }
    canvas.drawPath(path, paint);

    if (showDecoration) {
      canvas.save();
      canvas.clipPath(path);
      IslamicPatternPainter(color: decorationColor).paint(canvas, size);
      canvas.restore();
    }
    if (showBorder) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = borderColor,
      );
    }
  }

  @override
  bool shouldRepaint(CardSurfacePainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.shadowColor != shadowColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.showBorder != showBorder ||
        oldDelegate.gradient != gradient ||
        oldDelegate.decorationColor != decorationColor ||
        oldDelegate.showDecoration != showDecoration ||
        oldDelegate.elevation != elevation;
  }
}

/// The signature AZKAR card surface.
///
/// The artistic outline is painted behind a normal padded child. Text and
/// buttons are therefore never clipped by the extreme corner radii, and long
/// Arabic content can grow vertically without becoming unreadable.
class AsymmetricCard extends StatefulWidget {
  const AsymmetricCard({
    super.key,
    required this.child,
    this.shape = CardShapeId.primary,
    this.backgroundColor = Colors.white,
    this.gradient,
    this.decorationColor,
    this.showDecoration = false,
    this.borderColor,
    this.showBorder = false,
    this.elevation = 8,
    this.onTap,
    this.semanticLabel,
    this.margin,
    this.padding,
    this.hoverScale = 1.008,
  });

  final Widget child;
  final CardShapeId shape;
  final Color backgroundColor;
  final Gradient? gradient;
  final Color? decorationColor;
  final bool showDecoration;
  final Color? borderColor;
  final bool showBorder;
  final double elevation;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double hoverScale;

  @override
  State<AsymmetricCard> createState() => _AsymmetricCardState();
}

class _AsymmetricCardState extends State<AsymmetricCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final scale = reducedMotion
        ? 1.0
        : _pressed
        ? 0.995
        : _hovered
        ? widget.hoverScale
        : 1.0;
    final theme = Theme.of(context);

    Widget card = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 400.0;
        final padding =
            widget.padding ??
            CardShapeGeometry.contentInsets(widget.shape, Size(width, 400));
        return CustomPaint(
          painter: CardSurfacePainter(
            shape: widget.shape,
            backgroundColor: widget.backgroundColor,
            shadowColor: theme.shadowColor.withValues(alpha: 0.18),
            borderColor: widget.borderColor ?? theme.colorScheme.outline,
            showBorder: widget.showBorder,
            gradient: widget.gradient,
            decorationColor:
                widget.decorationColor ?? theme.colorScheme.secondary,
            showDecoration: widget.showDecoration,
            elevation: widget.elevation,
          ),
          child: Padding(padding: padding, child: widget.child),
        );
      },
    );

    if (widget.onTap != null) {
      card = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          borderRadius: BorderRadius.circular(20),
          child: card,
        ),
      );
    }

    card = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: scale,
        duration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: card,
      ),
    );

    if (widget.semanticLabel != null) {
      card = Semantics(
        label: widget.semanticLabel,
        button: widget.onTap != null,
        child: card,
      );
    }
    if (widget.margin != null) {
      card = Padding(padding: widget.margin!, child: card);
    }
    return card;
  }
}
