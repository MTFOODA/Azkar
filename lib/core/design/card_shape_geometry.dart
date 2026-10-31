import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'card_shape.dart';

/// Computes the asymmetric outline of a card.
///
/// The geometry is *adaptive*: when a card becomes very tall, very narrow or
/// very small — exactly the cases where extreme radii would eat into the content
/// box or look broken — the radii are smoothly blended towards a calm rounded
/// rectangle. Text is never clipped, because the shape only drives the painted
/// background while the content is laid out in a separate padded layer (see
/// `AsymmetricCard`).
class CardShapeGeometry {
  const CardShapeGeometry._();

  /// Blend factor `0` = full artistic geometry, `1` = plain rounded rectangle.
  static double fallbackBlend(Size size) {
    if (size.width <= 0 || size.height <= 0) return 1;
    var blend = 0.0;
    // Very tall content (long Arabic paragraphs, long Quran ranges).
    final aspect = size.height / size.width;
    if (aspect > 2.0) {
      blend = math.max(blend, ((aspect - 2.0) / 1.5).clamp(0.0, 1.0));
    }
    // Very narrow cards (small phones, single-column admin previews).
    if (size.width < 260) {
      blend = math.max(blend, ((260 - size.width) / 160).clamp(0.0, 1.0));
    }
    return blend.clamp(0.0, 1.0);
  }

  /// The four corner radii as `(rx / width, ry / height)` fractions, ordered
  /// top-left, top-right, bottom-right, bottom-left.
  static List<({double rx, double ry})> corners(CardShapeId shape) {
    switch (shape) {
      case CardShapeId.primary:
        return const [
          (rx: 0.50, ry: 0.10),
          (rx: 0.10, ry: 0.50),
          (rx: 0.50, ry: 0.10),
          (rx: 0.10, ry: 0.50),
        ];
      case CardShapeId.secondary:
        return const [
          (rx: 0.10, ry: 0.50),
          (rx: 0.50, ry: 0.10),
          (rx: 0.10, ry: 0.50),
          (rx: 0.50, ry: 0.10),
        ];
      case CardShapeId.rounded:
        return const [
          (rx: 0.06, ry: 0.10),
          (rx: 0.06, ry: 0.10),
          (rx: 0.06, ry: 0.10),
          (rx: 0.06, ry: 0.10),
        ];
      case CardShapeId.rectangle:
        return const [
          (rx: 0.02, ry: 0.03),
          (rx: 0.02, ry: 0.03),
          (rx: 0.02, ry: 0.03),
          (rx: 0.02, ry: 0.03),
        ];
    }
  }

  /// Builds the outline for a card of [size].
  static Path buildPath(CardShapeId shape, Size size) {
    final path = Path();
    if (size.width <= 0 || size.height <= 0) return path;

    final blend = fallbackBlend(size);
    final base = corners(shape);
    final safe = corners(
      shape == CardShapeId.rectangle
          ? CardShapeId.rectangle
          : CardShapeId.rounded,
    );
    final radii = <({double rx, double ry})>[
      for (var i = 0; i < 4; i++)
        (
          rx: _lerp(base[i].rx, safe[i].rx, blend),
          ry: _lerp(base[i].ry, safe[i].ry, blend),
        ),
    ];

    final w = size.width;
    final h = size.height;
    final rx = [
      for (final r in radii) (r.rx * w).clamp(0.0, w / 2),
    ];
    final ry = [
      for (final r in radii) (r.ry * h).clamp(0.0, h / 2),
    ];

    final tl = Radius.elliptical(rx[0], ry[0]);
    final tr = Radius.elliptical(rx[1], ry[1]);
    final br = Radius.elliptical(rx[2], ry[2]);
    final bl = Radius.elliptical(rx[3], ry[3]);

    path.moveTo(tl.x, 0);
    path.lineTo(w - tr.x, 0);
    path.arcToPoint(Offset(w, tr.y), radius: tr, clockwise: true);
    path.lineTo(w, h - br.y);
    path.arcToPoint(Offset(w - br.x, h), radius: br, clockwise: true);
    path.lineTo(bl.x, h);
    path.arcToPoint(Offset(0, h - bl.y), radius: bl, clockwise: true);
    path.lineTo(0, tl.y);
    path.arcToPoint(Offset(tl.x, 0), radius: tl, clockwise: true);
    path.close();

    return path;
  }

  /// The inset a content box needs so text never touches the curved edges.
  static EdgeInsets contentInsets(CardShapeId shape, Size size) {
    final blend = fallbackBlend(size);
    final horizontal = switch (shape) {
      CardShapeId.primary || CardShapeId.secondary =>
        size.width * (0.09 * (1 - blend) + 0.05 * blend),
      _ => size.width * 0.05,
    };
    final vertical = switch (shape) {
      CardShapeId.primary || CardShapeId.secondary =>
        size.height * (0.09 * (1 - blend) + 0.05 * blend),
      _ => size.height * 0.05,
    };
    return EdgeInsets.symmetric(
      horizontal: math.max(20, math.min(horizontal, 72)),
      vertical: math.max(20, math.min(vertical, 72)),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// Clips a child to the asymmetric card outline.
class AsymmetricCardClipper extends CustomClipper<Path> {
  const AsymmetricCardClipper(this.shape);

  final CardShapeId shape;

  @override
  Path getClip(Size size) => CardShapeGeometry.buildPath(shape, size);

  @override
  bool shouldReclip(AsymmetricCardClipper oldClipper) =>
      oldClipper.shape != shape;
}
