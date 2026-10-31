import 'package:flutter/material.dart';

import '../../../core/typography/arabic_font_loader.dart';
import '../../../core/typography/arabic_fonts.dart';
import '../domain/card_style.dart';

/// Converts an administrator's [CardStyle] into Flutter text styling.
class ContentStyleResolver {
  const ContentStyleResolver._();

  static TextStyle textStyle(
    CardStyle style, {
    double? fontSize,
    Color? color,
    FontWeight? weight,
    double? height,
  }) {
    final spec = style.fontSpec;
    final resolvedWeight = weight ?? _weightFor(spec, style.fontWeight);
    final resolvedHeight = height ?? style.lineHeight;
    return TextStyle(
      fontFamily: ArabicFontLoader.hasFailed(spec.id) ? null : spec.family,
      fontSize: fontSize ?? style.fontSize,
      fontWeight: spec.variable ? null : resolvedWeight,
      fontVariations: spec.variable
          ? <FontVariation>[FontVariation('wght', _axisWeight(spec, style.fontWeight))]
          : null,
      height: resolvedHeight,
      color: color ?? style.textColorValue,
      decoration: TextDecoration.none,
    );
  }

  static TextStyle titleStyle(CardStyle style, {Color? color}) {
    return textStyle(
      style,
      fontSize: (style.fontSize * 0.62).clamp(18, 32).toDouble(),
      weight: FontWeight.w700,
      height: 1.5,
      color: color,
    );
  }

  static TextStyle metaStyle(CardStyle style, {Color? color}) {
    return textStyle(
      style,
      fontSize: 14,
      weight: FontWeight.w400,
      height: 1.7,
      color: color ?? style.textColorValue.withValues(alpha: 0.72),
    );
  }

  static FontWeight _weightFor(ArabicFontSpec spec, int requested) {
    final value = spec.clampWeight(requested);
    return switch (value) {
      >= 800 => FontWeight.w800,
      >= 700 => FontWeight.w700,
      >= 600 => FontWeight.w600,
      >= 500 => FontWeight.w500,
      >= 400 => FontWeight.w400,
      _ => FontWeight.w300,
    };
  }

  static double _axisWeight(ArabicFontSpec spec, int requested) {
    return spec.clampWeight(requested).toDouble();
  }
}

/// Small helper that avoids repeating RTL text setup in every card.
class ArabicText extends StatelessWidget {
  const ArabicText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.center,
    this.maxLines,
    this.overflow,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}
