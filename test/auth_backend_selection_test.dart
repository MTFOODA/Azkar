import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/features/account/data/supabase_account_auth_service.dart';
import 'package:azkar/features/admin/authentication/data/supabase_admin_auth_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('configured Supabase client backs account and admin authentication', () {
    final client = SupabaseClient(
      'https://project.supabase.co',
      'sb_publishable_test',
    );
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        isDemoBackendProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.dispose);

    expect(container.read(isDemoBackendProvider), isFalse);
    expect(
      container.read(accountAuthServiceProvider),
      isA<SupabaseAccountAuthService>(),
    );
    expect(
      container.read(adminAuthServiceProvider),
      isA<SupabaseAdminAuthService>(),
    );
  });
}
