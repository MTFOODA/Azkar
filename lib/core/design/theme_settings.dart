import 'package:flutter/material.dart';

import '../typography/arabic_fonts.dart';
import '../utils/hex_color.dart';
import 'app_palette.dart';
import 'card_shape.dart';

/// Global visual configuration, editable by administrators.
///
/// Persisted as a single row in `theme_settings`. All colours are hex strings so
/// they round-trip through Postgres without precision loss.
class ThemeSettings {
  const ThemeSettings({
    this.primaryColor = '#064E3B',
    this.secondaryColor = '#D4AF37',
    this.backgroundColor = '#F8F5EC',
    this.surfaceColor = '#FFFFFF',
    this.defaultCardColor = '#FFFFFF',
    this.defaultTextColor = '#243B35',
    this.defaultFontId = ArabicFonts.defaultFontId,
    this.defaultCardShape = CardShapeId.primary,
    this.updatedAt,
  });

  final String primaryColor;
  final String secondaryColor;
  final String backgroundColor;
  final String surfaceColor;
  final String defaultCardColor;
  final String defaultTextColor;
  final String defaultFontId;
  final CardShapeId defaultCardShape;
  final DateTime? updatedAt;

  static const ThemeSettings defaults = ThemeSettings();

  Color get primary =>
      HexColor.parse(primaryColor, fallback: AppPalette.lightPrimary);

  Color get secondary =>
      HexColor.parse(secondaryColor, fallback: AppPalette.lightSecondary);

  Color get background =>
      HexColor.parse(backgroundColor, fallback: AppPalette.lightBackground);

  Color get surface =>
      HexColor.parse(surfaceColor, fallback: AppPalette.lightSurface);

  Color get card =>
      HexColor.parse(defaultCardColor, fallback: AppPalette.lightSurface);

  Color get text =>
      HexColor.parse(defaultTextColor, fallback: AppPalette.lightText);

  /// Contrast problems an administrator should fix before saving.
  ///
  /// Returns a map of `field -> Arabic explanation`; empty when the palette is
  /// accessible.
  Map<String, String> contrastProblems() {
    final problems = <String, String>{};
    if (!HexColor.meetsContrast(text, card, minimum: 4.5)) {
      problems['textColor'] =
          'تباين النص مع لون البطاقة أقل من الحد المطلوب (4.5:1).';
    }
    if (!HexColor.meetsContrast(card, background, minimum: 1.15)) {
      problems['backgroundColor'] =
          'لون البطاقة قريب جدًا من لون الخلفية، لن تظهر البطاقات بوضوح.';
    }
    if (!HexColor.meetsContrast(primary, background, minimum: 3.0)) {
      problems['primaryColor'] =
          'اللون الأساسي منخفض التباين مع الخلفية (الحد الأدنى 3:1).';
    }
    return problems;
  }

  bool get isAccessible => contrastProblems().isEmpty;

  ThemeSettings copyWith({
    String? primaryColor,
    String? secondaryColor,
    String? backgroundColor,
    String? surfaceColor,
    String? defaultCardColor,
    String? defaultTextColor,
    String? defaultFontId,
    CardShapeId? defaultCardShape,
    DateTime? updatedAt,
  }) {
    return ThemeSettings(
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      defaultCardColor: defaultCardColor ?? this.defaultCardColor,
      defaultTextColor: defaultTextColor ?? this.defaultTextColor,
      defaultFontId: defaultFontId ?? this.defaultFontId,
      defaultCardShape: defaultCardShape ?? this.defaultCardShape,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
    'primary_color': primaryColor,
    'secondary_color': secondaryColor,
    'background_color': backgroundColor,
    'surface_color': surfaceColor,
    'default_card_color': defaultCardColor,
    'default_text_color': defaultTextColor,
    'default_font_family': defaultFontId,
    'default_card_shape': defaultCardShape.id,
  };

  factory ThemeSettings.fromMap(Map<String, dynamic> map) {
    return ThemeSettings(
      primaryColor: _string(map['primary_color'], defaults.primaryColor),
      secondaryColor: _string(map['secondary_color'], defaults.secondaryColor),
      backgroundColor: _string(
        map['background_color'],
        defaults.backgroundColor,
      ),
      surfaceColor: _string(map['surface_color'], defaults.surfaceColor),
      defaultCardColor: _string(
        map['default_card_color'],
        defaults.defaultCardColor,
      ),
      defaultTextColor: _string(
        map['default_text_color'],
        defaults.defaultTextColor,
      ),
      defaultFontId: ArabicFonts.byId(
        _string(map['default_font_family'], defaults.defaultFontId),
      ).id,
      defaultCardShape: CardShapeIdX.fromId(
        map['default_card_shape'] as String?,
      ),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? ''),
    );
  }

  /// Validates an incoming settings payload, returning Arabic field errors.
  Map<String, String> validate() {
    final errors = <String, String>{};
    void checkHex(String key, String value) {
      if (!HexColor.isValid(value)) {
        errors[key] = 'قيمة اللون غير صحيحة، استخدم الصيغة #RRGGBB.';
      }
    }

    checkHex('primaryColor', primaryColor);
    checkHex('secondaryColor', secondaryColor);
    checkHex('backgroundColor', backgroundColor);
    checkHex('surfaceColor', surfaceColor);
    checkHex('defaultCardColor', defaultCardColor);
    checkHex('defaultTextColor', defaultTextColor);
    if (!ArabicFonts.isSupported(defaultFontId)) {
      errors['defaultFontId'] = 'الخط المحدد غير مدعوم.';
    }
    return errors;
  }

  static String _string(Object? value, String fallback) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return fallback;
    return text;
  }
}
