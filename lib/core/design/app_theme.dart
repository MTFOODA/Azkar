import 'package:flutter/material.dart';

import '../typography/arabic_font_loader.dart';
import '../typography/arabic_fonts.dart';
import 'app_palette.dart';
import 'theme_settings.dart';

/// Builds the Material 3 [ThemeData] for AZKAR.
///
/// The theme is rebuilt from the latest [ThemeSettings] whenever an
/// administrator saves changes, so the whole application — public site and admin
/// dashboard alike — picks up the new identity without rebuilding the binary.
class AppTheme {
  const AppTheme._();

  static ThemeData light(ThemeSettings settings) => _build(
    settings: settings,
    brightness: Brightness.light,
    primary: settings.primary,
    secondary: settings.secondary,
    background: settings.background,
    surface: settings.surface,
    text: settings.text,
    muted: AppPalette.lightMuted,
    outline: AppPalette.lightOutline,
  );

  static ThemeData dark(ThemeSettings settings) => _build(
    settings: settings,
    brightness: Brightness.dark,
    primary: AppPalette.darkPrimary,
    secondary: AppPalette.darkSecondary,
    background: AppPalette.darkBackground,
    surface: AppPalette.darkSurface,
    text: AppPalette.darkText,
    muted: AppPalette.darkMuted,
    outline: AppPalette.darkOutline,
  );

  /// The font family to use globally, or `null` when the chosen family failed to
  /// register (Flutter then falls back to the platform Arabic font instead of
  /// rendering nothing).
  static String? resolveFontFamily(ThemeSettings settings) {
    final spec = ArabicFonts.byId(settings.defaultFontId);
    return ArabicFontLoader.hasFailed(spec.id) ? null : spec.family;
  }

  static ThemeData _build({
    required ThemeSettings settings,
    required Brightness brightness,
    required Color primary,
    required Color secondary,
    required Color background,
    required Color surface,
    required Color text,
    required Color muted,
    required Color outline,
  }) {
    final fontFamily = resolveFontFamily(settings);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: onColor(primary),
          secondary: secondary,
          onSecondary: onColor(secondary),
          surface: surface,
          onSurface: text,
          onSurfaceVariant: muted,
          outline: outline,
          outlineVariant: outline,
          error: AppPalette.error,
          onError: Colors.white,
        );

    final textTheme = buildTextTheme(fontFamily, text, muted);
    final isLight = brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(color: text.withValues(alpha: 0.85)),
      dividerTheme: DividerThemeData(
        color: outline.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? background : surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onColor(primary),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppPalette.radiusSm),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: primary.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppPalette.radiusSm),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(0, 40),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? surface : surface.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppPalette.radiusSm),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppPalette.radiusSm),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppPalette.radiusSm),
          borderSide: BorderSide(color: secondary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppPalette.radiusSm),
          borderSide: const BorderSide(color: AppPalette.error),
        ),
        labelStyle: textTheme.bodyMedium,
        hintStyle: TextStyle(color: muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? AppPalette.lightText : AppPalette.darkSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: isLight ? Colors.white : AppPalette.darkText,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppPalette.radiusSm),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppPalette.radiusMd),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isLight ? AppPalette.lightText : AppPalette.darkSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: isLight ? Colors.white : AppPalette.darkText,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: secondary,
        linearTrackColor: outline.withValues(alpha: 0.4),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        textColor: text,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppPalette.radiusSm),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: IconThemeData(color: secondary),
        indicatorColor: secondary.withValues(alpha: 0.16),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: text),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: muted),
      ),
    );
  }

  /// Picks black or white text for [background] using WCAG luminance.
  static Color onColor(Color background) =>
      background.computeLuminance() > 0.55 ? AppPalette.lightText : Colors.white;

  /// A single Arabic-first text theme used by both themes.
  static TextTheme buildTextTheme(
    String? fontFamily,
    Color text,
    Color muted,
  ) {
    TextStyle style(
      double size,
      FontWeight weight, {
      double? height,
      Color? color,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color ?? text,
      );
    }

    return TextTheme(
      displayLarge: style(48, FontWeight.w700, height: 1.4),
      displayMedium: style(40, FontWeight.w700, height: 1.4),
      displaySmall: style(32, FontWeight.w700, height: 1.4),
      headlineLarge: style(30, FontWeight.w700, height: 1.5),
      headlineMedium: style(26, FontWeight.w600, height: 1.5),
      headlineSmall: style(23, FontWeight.w600, height: 1.6),
      titleLarge: style(20, FontWeight.w700, height: 1.6),
      titleMedium: style(17, FontWeight.w600, height: 1.7),
      titleSmall: style(15, FontWeight.w600, height: 1.7),
      bodyLarge: style(16, FontWeight.w400, height: 1.9),
      bodyMedium: style(14.5, FontWeight.w400, height: 1.9),
      bodySmall: style(13, FontWeight.w400, height: 1.8, color: muted),
      labelLarge: style(15, FontWeight.w600, height: 1.5),
      labelMedium: style(13.5, FontWeight.w500, height: 1.5),
      labelSmall: style(12, FontWeight.w500, height: 1.5, color: muted),
    );
  }
}
