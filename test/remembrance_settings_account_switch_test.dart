import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/features/content/data/content_repository.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/home_widget/data/remembrance_widget_preferences.dart';
import 'package:azkar/features/home_widget/data/remembrance_widget_service.dart';
import 'package:azkar/features/home_widget/presentation/remembrance_widget_settings_page.dart';
import 'package:azkar/features/memorial/data/memorial_page_repository.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets(
    'the open widget settings screen replaces both content and unsaved filters when accounts change',
    (tester) async {
      final db = await openNewInMemoryDatabase();
      addTearDown(db.close);
      final session = _Session();
      final store = RemembranceWidgetPreferencesStore(
        databaseProvider: () async => db,
        currentUserId: () => session.id,
      );
      final service = RemembranceWidgetService(
        runtime: const MobileRuntime(
          isWeb: true,
          targetPlatform: TargetPlatform.android,
        ),
        currentUserId: () => session.id,
        preferencesStore: store,
        pageRepository: _Content.new,
        memorialRepository: _Pages(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountSessionProvider.overrideWith(() => session),
            remembranceWidgetPreferencesStoreProvider.overrideWithValue(store),
            remembranceWidgetServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(home: RemembranceWidgetSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('fixture-a'), findsOneWidget);
      expect(find.text('fixture-b'), findsNothing);
      final azkar = find.widgetWithText(FilterChip, 'الأذكار');
      await tester.ensureVisible(azkar);
      await tester.tap(azkar);
      await tester.pump();
      expect(tester.widget<FilterChip>(azkar).selected, isFalse);

      session.change('b');
      await tester.pumpAndSettle();
      expect(find.text('fixture-a'), findsNothing);
      expect(find.text('fixture-b'), findsOneWidget);
      expect(tester.widget<FilterChip>(azkar).selected, isTrue);
      final saved = await tester.runAsync(() => store.read('b'));
      expect(saved!.hiddenTypes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Session extends AccountSessionController {
  String id = 'a';
  User user() => User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '',
  );
  @override
  User? build() => user();
  void change(String next) {
    id = next;
    state = user();
  }
}

class _Pages extends Fake implements MemorialPageRepository {
  @override
  Future<List<MemorialPage>> fetchOwnedPages() async => [
    for (final id in ['a', 'b'])
      MemorialPage(
        id: id,
        ownerUserId: id,
        slug: id,
        title: id,
        isPublished: true,
      ),
  ];
}

class _Content extends Fake implements ContentRepository {
  _Content(this.page);
  final String page;
  @override
  Future<List<ContentItem>> fetchPublished(ContentType type) async =>
      type == ContentType.azkar
      ? [
          ContentItem(
            id: 'text-$page',
            type: type,
            title: 'fixture-$page',
            arabicText: 'fixture body $page',
            isPublished: true,
          ),
        ]
      : [];
}
