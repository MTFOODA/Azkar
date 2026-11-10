import 'package:azkar/features/content/data/supabase_content_repository.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/core/design/theme_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final pageId in [null, 'owner-page']) {
    test('every collection and write stays inside ${pageId ?? 'global'} scope', () async {
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
            request: request,
        );
      });
      final client = SupabaseClient(
        'https://test-project.supabase.co',
        'test-key',
        httpClient: transport,
      );
      addTearDown(client.dispose);
      final repository = SupabaseContentRepository(
        client: client,
        themeProvider: () => ThemeSettings.defaults,
        pageId: pageId,
      );
      for (final type in ContentType.values) {
        await repository.fetchPublished(type);
        await repository.fetchAll(type);
        await repository.delete(type, 'test-id');
        await repository.setPublished(type, 'test-id', false);
        await repository.reorder(type, ['one', 'two']);
      }
      await repository.counts();
      expect(requests, isNotEmpty);
      for (final request in requests) {
        expect(
          request.url.queryParameters['page_id'],
          pageId == null ? 'is.null' : 'eq.$pageId',
          reason:
              '${request.method} ${request.url.path} must never aggregate other pages',
        );
      }
    });
  }

  test('shared published-card links remain explicit and do not widen collection queries', () async {
    final requests = <http.Request>[];
    final transport = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(null),
        200,
        headers: {'content-type': 'application/json'},
          request: request,
      );
    });
    final client = SupabaseClient(
      'https://test-project.supabase.co',
      'test-key',
      httpClient: transport,
    );
    addTearDown(client.dispose);
    final repository = SupabaseContentRepository(
      client: client,
      themeProvider: () => ThemeSettings.defaults,
    );
    expect(
      await repository.fetchSharedPublished(ContentType.dua, 'public-id'),
      isNull,
    );
    expect(requests.single.url.queryParameters['id'], 'eq.public-id');
    expect(requests.single.url.queryParameters['is_published'], 'eq.true');
    expect(requests.single.url.queryParameters.containsKey('page_id'), isFalse);
    requests.clear();
    expect(await repository.fetchById(ContentType.dua, 'public-id'), isNull);
    expect(requests.single.url.queryParameters['page_id'], 'is.null');
  });

  test('PostgREST constraint details are not user-facing', () {
    final exception = translatePostgrestError(
      const PostgrestException(
        message: 'check constraint failed: private_table',
        code: '23514',
        details: 'column private_column rejected value',
      ),
    );

    expect(
      exception.messageAr,
      'بعض البيانات المدخلة غير صالحة. راجعها ثم أعد المحاولة.',
    );
    expect(exception.messageAr, isNot(contains('private_table')));
    expect(exception.messageAr, isNot(contains('private_column')));
    expect(exception.technical, contains('private_table'));
  });

  test(
    'public category query is restricted to page and published items',
    () async {
      late http.Request capturedRequest;
      final transport = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });
      final client = SupabaseClient(
        'https://test-project.supabase.co',
        'test-publishable-key',
        httpClient: transport,
      );
      addTearDown(() async {
        await client.dispose();
        transport.close();
      });
      final repository = SupabaseContentRepository(
        client: client,
        themeProvider: () => ThemeSettings.defaults,
        pageId: 'current-memorial-id',
      );

      expect(await repository.fetchPublished(ContentType.azkar), isEmpty);
      expect(capturedRequest.url.path, '/rest/v1/azkar');
      expect(
        capturedRequest.url.queryParameters['page_id'],
        'eq.current-memorial-id',
      );
      expect(capturedRequest.url.queryParameters['is_published'], 'eq.true');
    },
  );
}
