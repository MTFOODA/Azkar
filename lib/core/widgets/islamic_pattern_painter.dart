import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A subtle Islamic eight-point-star pattern painted behind content.
class IslamicPatternPainter extends CustomPainter {
  const IslamicPatternPainter({required this.color, this.opacity = 0.08});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final step = size.width < 320 ? 42.0 : 56.0;
    for (var x = -step; x < size.width + step; x += step) {
      for (var y = -step; y < size.height + step; y += step) {
        final row = (y / step).round();
        final center = Offset(x + (row.isEven ? 0 : step / 2), y);
        _drawEightPointStar(canvas, center, step * 0.28, paint);
      }
    }
  }

  void _drawEightPointStar(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    final path = Path();
    for (var i = 0; i < 16; i++) {
      final angle = (i * 22.5 - 90) * math.pi / 180;
      final r = i.isEven ? radius : radius * 0.45;
      final point = center + Offset(r * math.cos(angle), r * math.sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(IslamicPatternPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.opacity != opacity;
}
