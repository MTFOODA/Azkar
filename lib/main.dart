import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/supabase_configuration_error_page.dart';
import 'core/typography/arabic_font_loader.dart';
import 'core/typography/arabic_fonts.dart';
import 'core/utils/app_logger.dart';

/// Registers font copyright notices in Flutter's license page.
void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final font in ArabicFonts.all) {
      yield LicenseEntryWithLineBreaks(<String>[
        'AZKAR Arabic Fonts',
      ], font.license);
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();

  if (AppConfig.shouldBlockForMissingSupabase(
    demoModeExplicitlyEnabled: AppConfig.forceDemoMode,
    hasSupabaseCredentials: AppConfig.hasSupabaseCredentials,
  )) {
    await ArabicFontLoader.ensureDefault();
    _registerFontLicenses();
    runApp(
      SupabaseConfigurationErrorPage(
        missingSettings: AppConfig.missingSupabaseSettings,
      ),
    );
    return;
  }

  if (kReleaseMode &&
      (AppConfig.useDemoBackend || !AppConfig.hasPublicBaseUrl)) {
    throw StateError(
      'Release builds require SUPABASE_URL, SUPABASE_ANON_KEY, and a valid '
      'HTTPS PUBLIC_BASE_URL. Demo Mode is only available in debug/profile builds.',
    );
  }

  if (!AppConfig.useDemoBackend) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
  } else {
    AppLogger.info('AZKAR is running with the offline demo backend.');
  }

  // Only the default family is awaited; other families load lazily when used.
  await ArabicFontLoader.ensureDefault();
  _registerFontLicenses();

  runApp(const ProviderScope(child: AzkarApp()));
}
