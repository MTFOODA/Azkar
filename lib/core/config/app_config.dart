import 'dart:convert';

/// Compile-time application configuration.
///
/// All values are injected with `--dart-define` so that no credential is ever
/// committed to the repository. Only *publishable* values belong here: the
/// Supabase anon (publishable) key is safe in a client **only** because every
/// table is protected by Row Level Security. A service-role key must never be
/// passed to Flutter.
///
/// ```bash
/// flutter run -d chrome \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi... \
///   --dart-define=PUBLIC_BASE_URL=https://azkar.example
/// ```
class AppConfig {
  const AppConfig._();

  /// Supabase project URL, e.g. `https://abcdefgh.supabase.co`.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase anon / publishable key (never the service-role key).
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Canonical public URL of the deployed website. Used for share links,
  /// canonical metadata and the generated sitemap.
  static const String publicBaseUrl = String.fromEnvironment('PUBLIC_BASE_URL');

  /// Forces the offline demo backend even when Supabase credentials exist.
  static const bool forceDemoMode = bool.fromEnvironment('AZKAR_DEMO_MODE');

  /// Enables signup only after the deployed provisioning trigger and RLS have
  /// been verified against the intended Supabase project.
  static const bool authSchemaVerified = bool.fromEnvironment(
    'AZKAR_AUTH_SCHEMA_VERIFIED',
  );

  /// Optional local-only demo login credentials; never use these for a
  /// production administrator account.
  static const String demoAdminEmail = String.fromEnvironment(
    'AZKAR_DEMO_ADMIN_EMAIL',
  );
  static const String demoAdminPassword = String.fromEnvironment(
    'AZKAR_DEMO_ADMIN_PASSWORD',
  );

  static bool get hasDemoAdminCredentials =>
      demoAdminEmail.trim().isNotEmpty && demoAdminPassword.isNotEmpty;

  static bool get hasSupabaseUrl {
    final uri = Uri.tryParse(supabaseUrl.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  static bool get hasSupabasePublishableKey =>
      isSupabasePublishableKey(supabaseAnonKey);

  /// Accepts current publishable keys and legacy anon JWTs, but never a
  /// service-role JWT or a Supabase secret key.
  static bool isSupabasePublishableKey(String value) {
    final key = value.trim();
    if (key.startsWith('sb_publishable_') &&
        key.length > 'sb_publishable_'.length) {
      return true;
    }

    final segments = key.split('.');
    if (segments.length != 3) return false;
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
      );
      return claims is Map<String, dynamic> && claims['role'] == 'anon';
    } on FormatException {
      return false;
    }
  }

  /// True when both Supabase values were provided at build time.
  static bool get hasSupabaseCredentials =>
      hasSupabaseUrl && hasSupabasePublishableKey;

  static List<String> get missingSupabaseSettings => missingSupabaseSettingsFor(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );

  static List<String> missingSupabaseSettingsFor({
    required String url,
    required String publishableKey,
  }) {
    final uri = Uri.tryParse(url.trim());
    final hasUrl =
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
    return [
      if (!hasUrl) 'SUPABASE_URL',
      if (!isSupabasePublishableKey(publishableKey))
        'SUPABASE_ANON_KEY (anon/publishable key)',
    ];
  }

  static bool shouldBlockForMissingSupabase({
    required bool demoModeExplicitlyEnabled,
    required bool hasSupabaseCredentials,
  }) => !demoModeExplicitlyEnabled && !hasSupabaseCredentials;

  static bool get hasPublicBaseUrl {
    final uri = Uri.tryParse(publicBaseUrl.trim());
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// The demo backend is used when explicitly requested or when configuration
  /// is absent. `main` blocks the latter for app launches; provider-level
  /// fallback remains useful for isolated widget tests.
  static bool get useDemoBackend => forceDemoMode || !hasSupabaseCredentials;

  static String? registrationUnavailableMessage({
    required bool demoMode,
    required bool schemaVerified,
  }) {
    if (forceDemoMode) {
      return 'وضع العرض المحلي مفعّل. شغّل التطبيق مع '
          '--dart-define=AZKAR_DEMO_MODE=false بعد إعداد Supabase.';
    }
    if (!hasSupabaseUrl || !hasSupabasePublishableKey) {
      final missing = missingSupabaseSettings
          .map(
            (setting) => setting == 'SUPABASE_ANON_KEY (anon/publishable key)'
                ? 'مفتاح SUPABASE_ANON_KEY عام وصالح'
                : setting,
          )
          .toList();
      return 'إعداد Supabase غير مكتمل: ${missing.join(' و ')}. مرّر القيم '
          'إلى Flutter باستخدام --dart-define-from-file=config/dev.json. '
          'يجب أن يكون المفتاح '
          'العام anon/publishable؛ لن يقبل التطبيق مفتاحًا سريًا أو '
          'مفتاح service_role.';
    }
    if (demoMode) {
      return 'يتعذر تفعيل التسجيل ما دام التطبيق يستخدم وضع العرض المحلي.';
    }
    if (!schemaVerified) {
      return 'التسجيل مغلق حتى التحقق من جداول قاعدة البيانات ومشغّل '
          'azkar_provision_owner_page وسياسات RLS، ثم البناء مع '
          '--dart-define=AZKAR_AUTH_SCHEMA_VERIFIED=true.';
    }
    return null;
  }

  /// Omits an email redirect override when no canonical site URL was supplied,
  /// allowing Supabase Auth to use the project's configured Site URL.
  static String? authRedirectUrl(String path) {
    if (!hasPublicBaseUrl) return null;
    return '$siteBaseUrl$path';
  }

  /// Public base URL without a trailing slash.
  static String get siteBaseUrl {
    final trimmed = publicBaseUrl.trim();
    if (trimmed.isEmpty) return 'https://azkar.example';
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  /// Stable, shareable deep link for a single content record.
  static String contentLink({required String type, required String id}) =>
      '$siteBaseUrl/c/$type/$id';

  static String memorialPageLink(String slug) =>
      '$siteBaseUrl/m/${Uri.encodeComponent(slug)}';

  static String memorialPagePath(String slug) =>
      '/m/${Uri.encodeComponent(slug)}';

  static const String siteNameAr = 'أذكار';
  static const String siteNameEn = 'AZKAR';
  static const String siteTitle = 'AZKAR | أذكار';
  static const String siteDescription =
      'منصة إسلامية مجانية للأذكار والأدعية والقرآن والأحاديث، صدقة جارية. '
      'اقرأ، سبّح، وشارك الأجر.';
  static const String socialImagePath = 'icons/Icon-512.png';

  static String socialImageUrl() => '$siteBaseUrl/$socialImagePath';
}
