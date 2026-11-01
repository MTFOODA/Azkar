import 'package:flutter/material.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/design/card_shape.dart';
import '../../../core/design/theme_settings.dart';
import '../../../core/typography/arabic_fonts.dart';
import '../../../core/utils/hex_color.dart';

/// Hint used when creating a new card.
enum ContentShapeHint { primary, secondary }

/// Per-card appearance configuration, persisted alongside every content row.
///
/// Every value is validated and clamped on read, so a malformed row (or a value
/// written by an outdated client) can never break rendering.
class CardStyle {
  const CardStyle({
    this.fontFamily = ArabicFonts.defaultFontId,
    this.fontSize = 28,
    this.fontWeight = 500,
    this.lineHeight = 2,
    this.textColor = '#243B35',
    this.backgroundColor = '#FFFFFF',
    this.shape = CardShapeId.primary,
    this.textAlignment = TextAlign.center,
    this.gradientEnabled = false,
    this.decorationEnabled = true,
    this.borderEnabled = false,
  });

  final String fontFamily;
  final double fontSize;
  final int fontWeight;
  final double lineHeight;
  final String textColor;
  final String backgroundColor;
  final CardShapeId shape;
  final TextAlign textAlignment;
  final bool gradientEnabled;
  final bool decorationEnabled;
  final bool borderEnabled;

  static const double minFontSize = 14;
  static const double maxFontSize = 72;
  static const double minLineHeight = 1.2;
  static const double maxLineHeight = 3;

  /// Defaults derived from the global theme, so a new card already looks
  /// consistent with the site identity.
  factory CardStyle.fromTheme(ThemeSettings theme, {ContentShapeHint? hint}) {
    return CardStyle(
      fontFamily: theme.defaultFontId,
      textColor: theme.defaultTextColor,
      backgroundColor: theme.defaultCardColor,
      shape: hint == ContentShapeHint.secondary
          ? CardShapeId.secondary
          : theme.defaultCardShape,
    );
  }

  Color get textColorValue =>
      HexColor.parse(textColor, fallback: AppPalette.lightText);

  Color get backgroundColorValue =>
      HexColor.parse(backgroundColor, fallback: AppPalette.lightSurface);

  ArabicFontSpec get fontSpec => ArabicFonts.byId(fontFamily);

  CardStyle copyWith({
    String? fontFamily,
    double? fontSize,
    int? fontWeight,
    double? lineHeight,
    String? textColor,
    String? backgroundColor,
    CardShapeId? shape,
    TextAlign? textAlignment,
    bool? gradientEnabled,
    bool? decorationEnabled,
    bool? borderEnabled,
  }) {
    return CardStyle(
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      lineHeight: lineHeight ?? this.lineHeight,
      textColor: textColor ?? this.textColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      shape: shape ?? this.shape,
      textAlignment: textAlignment ?? this.textAlignment,
      gradientEnabled: gradientEnabled ?? this.gradientEnabled,
      decorationEnabled: decorationEnabled ?? this.decorationEnabled,
      borderEnabled: borderEnabled ?? this.borderEnabled,
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
    'font_family': fontFamily,
    'font_size': fontSize.round(),
    'font_weight': fontWeight,
    'line_height': lineHeight,
    'text_color': textColor,
    'background_color': backgroundColor,
    'card_shape': shape.id,
    'text_alignment': textAlignment.name,
    'gradient_enabled': gradientEnabled,
    'decoration_enabled': decorationEnabled,
    'border_enabled': borderEnabled,
  };

  factory CardStyle.fromRow(Map<String, dynamic> row, ThemeSettings theme) {
    final fallback = CardStyle.fromTheme(theme);
    final readFontSize = _asDouble(row['font_size'], fallback.fontSize);
    final readLineHeight = _asDouble(row['line_height'], fallback.lineHeight);
    final readTextColor = _asString(row['text_color'], fallback.textColor);
    final readBackground = _asString(
      row['background_color'],
      fallback.backgroundColor,
    );
    return CardStyle(
      fontFamily: ArabicFonts.byId(
        _asString(row['font_family'], fallback.fontFamily),
      ).id,
      fontSize: readFontSize.clamp(minFontSize, maxFontSize),
      fontWeight: _asInt(
        row['font_weight'],
        fallback.fontWeight,
      ).clamp(300, 900),
      lineHeight: readLineHeight.clamp(minLineHeight, maxLineHeight),
      textColor: HexColor.isValid(readTextColor)
          ? readTextColor
          : fallback.textColor,
      backgroundColor: HexColor.isValid(readBackground)
          ? readBackground
          : fallback.backgroundColor,
      shape: row['card_shape'] == null
          ? fallback.shape
          : CardShapeIdX.fromId(row['card_shape'] as String?),
      textAlignment: alignmentFromId(row['text_alignment']?.toString()),
      gradientEnabled: _asBool(row['gradient_enabled'], false),
      decorationEnabled: _asBool(row['decoration_enabled'], true),
      borderEnabled: _asBool(row['border_enabled'], false),
    );
  }

  /// Validation used by the admin editor. Returns Arabic field errors.
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (!ArabicFonts.isSupported(fontFamily)) {
      errors['fontFamily'] = 'الخط المحدد غير مدعوم. اختر من الخطوط العشرة.';
    }
    if (fontSize < minFontSize || fontSize > maxFontSize) {
      errors['fontSize'] =
          'حجم الخط يجب أن يكون بين ${minFontSize.round()} و ${maxFontSize.round()}.';
    }
    if (fontWeight < 300 || fontWeight > 900) {
      errors['fontWeight'] = 'وزن الخط يجب أن يكون بين 300 و 900.';
    }
    if (lineHeight < minLineHeight || lineHeight > maxLineHeight) {
      errors['lineHeight'] =
          'ارتفاع السطر يجب أن يكون بين $minLineHeight و $maxLineHeight.';
    }
    if (!HexColor.isValid(textColor)) {
      errors['textColor'] = 'لون النص غير صحيح (#RRGGBB).';
    }
    if (!HexColor.isValid(backgroundColor)) {
      errors['backgroundColor'] = 'لون الخلفية غير صحيح (#RRGGBB).';
    } else if (HexColor.isValid(textColor) &&
        !HexColor.meetsContrast(textColorValue, backgroundColorValue)) {
      errors['textColor'] =
          'تباين النص مع الخلفية أقل من 4.5:1 — قد يصعب قراءته.';
    }
    return errors;
  }

  /// Maps a stored `text_alignment` value (or a [TextAlign] name) to a
  /// [TextAlign]; unknown values fall back to centred text.
  static TextAlign alignmentFromId(String? value) {
    return switch (value) {
      'left' || 'start' || 'TextAlign.start' => TextAlign.start,
      'right' || 'end' || 'TextAlign.end' => TextAlign.end,
      'justify' || 'TextAlign.justify' => TextAlign.justify,
      _ => TextAlign.center,
    };
  }

  static String _asString(Object? value, String fallback) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return fallback;
    return text;
  }

  static double _asDouble(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
  }

  static int _asInt(Object? value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? fallback;
  }

  static bool _asBool(Object? value, bool fallback) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return fallback;
  }
}
