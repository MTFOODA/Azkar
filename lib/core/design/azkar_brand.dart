import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_palette.dart';

class AzkarBrandMark extends StatelessWidget {
  const AzkarBrandMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'AZKAR | أذكار',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _AzkarBrandPainter(
              foreground: isDark
                  ? AppPalette.darkText
                  : AppPalette.lightPrimary,
              accent: AppPalette.lightSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class AzkarBrandLockup extends StatelessWidget {
  const AzkarBrandLockup({super.key, this.markSize = 42});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? AppPalette.darkText : AppPalette.lightPrimary;

    return Semantics(
      label: 'AZKAR | أذكار',
      image: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            AzkarBrandMark(size: markSize),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AZKAR',
                  textDirection: TextDirection.ltr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    height: 1.05,
                  ),
                ),
                Text(
                  'أذكار',
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AzkarBrandPainter extends CustomPainter {
  const _AzkarBrandPainter({required this.foreground, required this.accent});

  final Color foreground;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);

    final archPaint = Paint()
      ..color = foreground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final arch = Path()
      ..moveTo(22, 86)
      ..lineTo(22, 45)
      ..cubicTo(22, 25.7, 34.5, 13, 50, 13)
      ..cubicTo(65.5, 13, 78, 25.7, 78, 45)
      ..lineTo(78, 86);
    canvas.drawPath(arch, archPaint);

    final goldLine = Paint()
      ..color = accent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(30, 86), const Offset(70, 86), goldLine);
    canvas.drawLine(
      const Offset(39, 78),
      const Offset(61, 78),
      Paint()
        ..color = foreground
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    final crescent = Path()
      ..moveTo(44.7, 35.6)
      ..cubicTo(37.2, 37.4, 31.9, 44.1, 31.9, 52)
      ..cubicTo(31.9, 61.2, 39.4, 68.7, 48.6, 68.7)
      ..cubicTo(52.2, 68.7, 55.5, 67.6, 58.2, 65.6)
      ..cubicTo(49.1, 65.4, 41.8, 57.9, 41.8, 48.8)
      ..cubicTo(41.8, 43.5, 44.3, 38.7, 48.2, 35.6)
      ..cubicTo(47.1, 35.4, 45.9, 35.4, 44.7, 35.6)
      ..close();
    canvas.drawPath(crescent, Paint()..color = accent);
    canvas.drawCircle(const Offset(50, 8), 3, Paint()..color = accent);

    final star = Path();
    for (var index = 0; index < 16; index++) {
      final angle = -math.pi / 2 + index * math.pi / 8;
      final radius = index.isEven ? 10.3 : 4.7;
      final point = Offset(
        66 + math.cos(angle) * radius,
        45 + math.sin(angle) * radius,
      );
      if (index == 0) {
        star.moveTo(point.dx, point.dy);
      } else {
        star.lineTo(point.dx, point.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = accent);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AzkarBrandPainter oldDelegate) =>
      foreground != oldDelegate.foreground || accent != oldDelegate.accent;
}
