import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Parsing, formatting and accessibility checks for the hex colour strings that
/// administrators store in the database (`#RRGGBB` or `#AARRGGBB`).
class HexColor {
  HexColor._();

  static final RegExp _pattern = RegExp(
    r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
  );

  /// Whether [value] is a valid hex colour.
  static bool isValid(String? value) =>
      value != null && _pattern.hasMatch(value.trim());

  /// Parses [value], returning [fallback] when it is missing or malformed.
  static Color parse(String? value, {required Color fallback}) {
    if (!isValid(value)) return fallback;
    var hex = value!.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
  }

  /// Formats [color] as `#RRGGBB` (alpha is dropped so the DB value stays
  /// human editable in a plain text field).
  static String format(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// WCAG 2.1 relative luminance contrast ratio (1.0 – 21.0).
  static double contrastRatio(Color foreground, Color background) {
    final l1 = _relativeLuminance(_flatten(foreground, background));
    final l2 = _relativeLuminance(background);
    final lighter = math.max(l1, l2);
    final darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// WCAG AA for normal text is 4.5:1, AA for large text is 3:1.
  static bool meetsContrast(
    Color foreground,
    Color background, {
    double minimum = 4.5,
  }) => contrastRatio(foreground, background) >= minimum;

  /// Suggests a readable text colour for [background] (used as a "fix" action
  /// in the appearance settings).
  static Color readableOn(Color background) {
    final light = Colors.white;
    final dark = const Color(0xFF10241E);
    return contrastRatio(light, background) >= contrastRatio(dark, background)
        ? light
        : dark;
  }

  /// Converts a colour to a CSS `rgb()` value (used by the web meta/theme
  /// integration).
  static String toCss(Color color) => format(color);

  static Color _flatten(Color foreground, Color background) {
    if (foreground.a >= 1.0) return foreground;
    return Color.alphaBlend(foreground, background);
  }

  static double _relativeLuminance(Color color) {
    double channel(double value) {
      return value <= 0.03928
          ? value / 12.92
          : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }
}
