import 'package:azkar/features/content/data/supabase_content_repository.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/core/design/theme_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
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
