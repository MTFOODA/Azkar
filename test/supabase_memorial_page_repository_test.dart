import 'dart:convert';

import 'package:azkar/features/memorial/data/supabase_memorial_page_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const anonymousKey = 'test-publishable-key';

  test(
    'public lookup queries only published pages by the requested slug',
    () async {
      late http.Request capturedRequest;
      final transport = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode([
            {
              'id': 'page-id',
              'owner_user_id': 'owner-id',
              'slug': 'azkar-a7f29c82',
              'title': 'صفحة تذكارية',
              'deceased_name': 'أحمد محمد',
              'dedication_message': 'نسألكم الدعاء له.',
              'is_published': true,
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      final client = SupabaseClient(
        'https://test-project.supabase.co',
        anonymousKey,
        httpClient: transport,
      );
      addTearDown(() async {
        await client.dispose();
        transport.close();
      });

      final page = await SupabaseMemorialPageRepository(client)
          .fetchPublishedBySlug('azkar-a7f29c82');

      expect(page?.slug, 'azkar-a7f29c82');
      expect(page?.isPublished, isTrue);
      expect(page?.deceasedName, 'أحمد محمد');
      expect(page?.dedicationMessage, 'نسألكم الدعاء له.');
      expect(capturedRequest.url.path, '/rest/v1/memorial_pages');
      expect(capturedRequest.url.queryParameters['slug'], 'eq.azkar-a7f29c82');
      expect(capturedRequest.url.queryParameters['is_published'], 'eq.true');
      expect(capturedRequest.headers['authorization'], 'Bearer $anonymousKey');
    },
  );

  test('unpublished and missing slugs return no public page', () async {
    final transport = MockClient(
      (request) async => http.Response(
        jsonEncode(<Object?>[]),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      ),
    );
    final client = SupabaseClient(
      'https://test-project.supabase.co',
      anonymousKey,
      httpClient: transport,
    );
    addTearDown(() async {
      await client.dispose();
      transport.close();
    });
    final repository = SupabaseMemorialPageRepository(client);

    expect(await repository.fetchPublishedBySlug('draft-page'), isNull);
    expect(await repository.fetchPublishedBySlug('unknown-page'), isNull);
  });
}
