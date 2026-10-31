import 'dart:convert';

import 'package:azkar/core/design/theme_settings.dart';
import 'package:azkar/core/utils/app_exception.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/home/data/supabase_homepage_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('add validates page ownership, appends after current order, and deduplicates', () async {
    final entries = <Map<String, dynamic>>[
      _entry(
        id: 'entry-existing',
        pageId: 'page-a',
        contentType: 'azkar',
        contentId: 'old-content',
        order: 4,
        enabled: false,
      ),
    ];
    final contentQueries = <Uri>[];
    final inserts = <Map<String, dynamic>>[];
    final transport = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/homepage_cards')) {
        return _json(entries, request: request);
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/tasbeeh_cards')) {
        contentQueries.add(request.url);
        return _json([
          {'id': 'new-content'},
        ], request: request);
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/homepage_cards')) {
        final body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        inserts.add(body);
        final created = _entry(
          id: 'entry-created',
          pageId: body['page_id'] as String,
          contentType: body['content_type'] as String,
          contentId: body['content_id'] as String,
          order: body['display_order'] as int,
          enabled: body['is_enabled'] as bool,
        );
        entries.add(created);
        return _json(created, request: request, status: 201);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    final client = _client(transport);
    addTearDown(() async {
      await client.dispose();
      transport.close();
    });
    final repository = SupabaseHomepageRepository(
      client: client,
      themeProvider: () => ThemeSettings.defaults,
      pageId: 'page-a',
    );

    final created = await repository.add(
      contentType: ContentType.tasbeeh,
      contentId: 'new-content',
    );
    final repeated = await repository.add(
      contentType: ContentType.tasbeeh,
      contentId: 'new-content',
    );

    expect(created.id, 'entry-created');
    expect(repeated.id, 'entry-created');
    expect(inserts, hasLength(1));
    expect(inserts.single['display_order'], 5);
    expect(inserts.single['is_enabled'], isTrue);
    expect(inserts.single['page_id'], 'page-a');
    expect(contentQueries.single.queryParameters['page_id'], 'eq.page-a');
  });

  test('cross-page content cannot be added to another page homepage', () async {
    final requests = <http.Request>[];
    final transport = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/homepage_cards')) {
        return _json([], request: request);
      }
      if (request.url.path.endsWith('/tasbeeh_cards')) {
        return _json([], request: request);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    final client = _client(transport);
    addTearDown(() async {
      await client.dispose();
      transport.close();
    });
    final repository = SupabaseHomepageRepository(
      client: client,
      themeProvider: () => ThemeSettings.defaults,
      pageId: 'page-b',
    );

    await expectLater(
      repository.add(
        contentType: ContentType.tasbeeh,
        contentId: 'content-from-page-a',
      ),
      throwsA(isA<NotFoundException>()),
    );
    expect(
      requests.any(
        (request) =>
            request.method == 'POST' &&
            request.url.path.endsWith('/homepage_cards'),
      ),
      isFalse,
    );
  });
}

SupabaseClient _client(http.Client transport) => SupabaseClient(
  'https://test-project.supabase.co',
  'test-publishable-key',
  httpClient: transport,
);

http.Response _json(
  Object body, {
  required http.Request request,
  int status = 200,
}) {
  final range = body is List && body.isNotEmpty
      ? '0-${body.length - 1}/${body.length}'
      : '*/0';
  return http.Response(
    jsonEncode(body),
    status,
    request: request,
    headers: {'content-type': 'application/json', 'content-range': range},
  );
}

Map<String, dynamic> _entry({
  required String id,
  required String pageId,
  required String contentType,
  required String contentId,
  required int order,
  required bool enabled,
}) => {
  'id': id,
  'page_id': pageId,
  'content_type': contentType,
  'content_id': contentId,
  'display_order': order,
  'is_enabled': enabled,
};
