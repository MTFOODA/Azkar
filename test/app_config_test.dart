import 'dart:convert';

import 'package:azkar/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts current Supabase publishable keys', () {
    expect(
      AppConfig.isSupabasePublishableKey('sb_publishable_example'),
      isTrue,
    );
  });

  test('accepts legacy anon JWTs and rejects service-role JWTs', () {
    String jwtForRole(String role) {
      final claims = base64Url
          .encode(utf8.encode(jsonEncode({'role': role})))
          .replaceAll('=', '');
      return 'header.$claims.signature';
    }

    expect(AppConfig.isSupabasePublishableKey(jwtForRole('anon')), isTrue);
    expect(
      AppConfig.isSupabasePublishableKey(jwtForRole('service_role')),
      isFalse,
    );
  });

  test('rejects empty and unrecognized credentials', () {
    expect(AppConfig.isSupabasePublishableKey(''), isFalse);
    expect(
      AppConfig.isSupabasePublishableKey('not-a-publishable-key'),
      isFalse,
    );
  });

  test('valid Supabase settings do not require Demo Mode', () {
    expect(
      AppConfig.missingSupabaseSettingsFor(
        url: 'https://project.supabase.co',
        publishableKey: 'sb_publishable_example',
      ),
      isEmpty,
    );
    expect(
      AppConfig.shouldBlockForMissingSupabase(
        demoModeExplicitlyEnabled: false,
        hasSupabaseCredentials: true,
      ),
      isFalse,
    );
  });

  test('missing or invalid settings block an implicit Demo Mode launch', () {
    expect(AppConfig.missingSupabaseSettingsFor(url: '', publishableKey: ''), [
      'SUPABASE_URL',
      'SUPABASE_ANON_KEY (anon/publishable key)',
    ]);
    expect(
      AppConfig.shouldBlockForMissingSupabase(
        demoModeExplicitlyEnabled: false,
        hasSupabaseCredentials: false,
      ),
      isTrue,
    );
  });

  test('explicit Demo Mode remains available without Supabase settings', () {
    expect(
      AppConfig.shouldBlockForMissingSupabase(
        demoModeExplicitlyEnabled: true,
        hasSupabaseCredentials: false,
      ),
      isFalse,
    );
  });

  test('memorial URLs use the public origin and the /m/:slug route', () {
    const slug = 'azkar-a7f29c82';
    final link = Uri.parse(AppConfig.memorialPageLink(slug));

    expect(link.origin, AppConfig.siteBaseUrl);
    expect(link.path, '/m/$slug');
    expect(AppConfig.memorialPagePath(slug), '/m/$slug');
  });

  test('memorial links encode the slug as a single URL path segment', () {
    expect(
      AppConfig.memorialPageLink('owner name/preview'),
      '${AppConfig.siteBaseUrl}/m/owner%20name%2Fpreview',
    );
  });
}
