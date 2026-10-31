import 'dart:convert';

import 'package:azkar/core/utils/app_exception.dart';
import 'package:azkar/features/account/data/supabase_account_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('signup leaves slug generation to the provisioning trigger', () async {
    late Map<String, dynamic> payload;
    final transport = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/auth/v1/signup');
      payload = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'id': 'test-user',
          'aud': 'authenticated',
          'role': 'authenticated',
          'email': 'owner@example.test',
          'user_metadata': payload['data'],
          'app_metadata': <String, Object?>{},
          'created_at': '2026-10-30T00:00:00.000Z',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = SupabaseClient(
      'https://test-project.supabase.co',
      'test-publishable-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    addTearDown(() async {
      await client.dispose();
      transport.close();
    });

    final hasSession = await SupabaseAccountAuthService(client).register(
      displayName: '  Test Owner ',
      email: ' owner@example.test ',
      password: 'secure-pass-123',
    );

    expect(hasSession, isFalse);
    expect(payload['data'], {
      'display_name': 'Test Owner',
      'page_title': 'صفحة الأذكار الخاصة بـ Test Owner',
    });
    expect((payload['data'] as Map<String, dynamic>).keys.toSet(), {
      'display_name',
      'page_title',
    });
    expect(payload['email'], 'owner@example.test');
  });

  test(
    'duplicate-account response does not reveal account existence',
    () async {
      final transport = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'user_already_exists',
            'msg': 'User already registered',
          }),
          422,
          headers: {'content-type': 'application/json'},
        ),
      );
      final client = SupabaseClient(
        'https://test-project.supabase.co',
        'test-publishable-key',
        httpClient: transport,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      );
      addTearDown(() async {
        await client.dispose();
        transport.close();
      });

      await expectLater(
        SupabaseAccountAuthService(client).register(
          displayName: 'Test Owner',
          email: 'owner@example.test',
          password: 'secure-pass-123',
        ),
        throwsA(
          isA<AppException>().having(
            (error) => error.messageAr,
            'messageAr',
            contains('إذا كان لديك حساب'),
          ),
        ),
      );
    },
  );

  test('network failure is reported as an Arabic connectivity error', () async {
    final transport = MockClient(
      (request) async => throw http.ClientException('offline', request.url),
    );
    final client = SupabaseClient(
      'https://test-project.supabase.co',
      'test-publishable-key',
      httpClient: transport,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );
    addTearDown(() async {
      await client.dispose();
      transport.close();
    });

    await expectLater(
      SupabaseAccountAuthService(client)
          .signIn(email: 'owner@example.test', password: 'secure-pass-123'),
      throwsA(
        isA<AppException>().having(
          (error) => error.messageAr,
          'messageAr',
          contains('اتصال الإنترنت'),
        ),
      ),
    );
  });
}
