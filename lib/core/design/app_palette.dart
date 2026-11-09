import 'package:flutter/material.dart';

/// The curated AZKAR colour palette.
///
/// Light theme values come from the design specification and can be overridden
/// by an administrator through `theme_settings`. The dark theme is a fixed,
/// carefully balanced Islamic night palette so that an administrator cannot
/// accidentally produce an unreadable dark mode.
class AppPalette {
  const AppPalette._();

  // Light theme (administrator editable).
  static const Color lightPrimary = Color(0xFF064E3B);
  static const Color lightSecondary = Color(0xFF9CA3AF);
  static const Color lightBackground = Color(0xFFF3F4F6);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF243B35);
  static const Color lightMuted = Color(0xFF6B7280);
  static const Color lightOutline = Color(0xFFD1D5DB);

  // Dark theme (fixed).
  static const Color darkBackground = Color(0xFF071C17);
  static const Color darkSurface = Color(0xFF102A23);
  static const Color darkPrimary = Color(0xFF9CA3AF);
  static const Color darkSecondary = Color(0xFF68D3A8);
  static const Color darkText = Color(0xFFF3F4F6);
  static const Color darkMuted = Color(0xFF9BA8A2);
  static const Color darkOutline = Color(0xFF1F3B33);

  static const Color error = Color(0xFFB3261E);
  static const Color success = Color(0xFF1B7F5A);
  static const Color warning = Color(0xFF6B7280);

  /// Standard spacing scale (8pt grid).
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double spaceXxl = 48;

  /// Maximum reading width for long Arabic passages.
  static const double maxContentWidth = 1180;
  static const double maxReadingWidth = 760;

  static const double radiusSm = 10;
  static const double radiusMd = 16;
  static const double radiusLg = 24;

  /// Preset swatches offered in the appearance editor.
  static const List<Color> primarySwatches = <Color>[
    Color(0xFF064E3B),
    Color(0xFF0B3D2E),
    Color(0xFF1B4332),
    Color(0xFF123C69),
    Color(0xFF3E2C5A),
    Color(0xFF5B2333),
  ];

  static const List<Color> secondarySwatches = <Color>[
    Color(0xFF9CA3AF),
    Color(0xFF6B7280),
    Color(0xFF9CA3AF),
    Color(0xFFCBD5E1),
    Color(0xFF9CAF88),
    Color(0xFF7FA8C9),
  ];

  static const List<Color> backgroundSwatches = <Color>[
    Color(0xFFF3F4F6),
    Color(0xFFF9FAFB),
    Color(0xFFE5E7EB),
    Color(0xFFEAF0EC),
    Color(0xFFF6F1F4),
    Color(0xFFFFFFFF),
  ];
}
