import 'dart:convert';

import 'package:azkar/features/home_widget/data/remembrance_widget_service.dart';
import 'package:azkar/features/home_widget/data/remembrance_widget_preferences.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/content/data/content_repository.dart';
import 'package:azkar/features/memorial/data/memorial_page_repository.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('named dedication repeats the memorial heading on every text page', () {
    final text = List.filled(100, 'اللهم اغفر له وارحمه').join(' ');
    final cards = RemembranceWidgetService.contentCards(
      ContentItem(
        id: 'named',
        type: ContentType.dedication,
        personName: 'عبد الله',
        arabicText: text,
      ),
      '/m/test',
    );
    expect(cards.length, greaterThan(1));
    for (final card in cards) {
      expect(
        card['title'],
        startsWith('صدقة جارية على روح المغفور له بإذن الله\n"عبد الله"'),
      );
      expect(card['deceasedName'], 'عبد الله');
      expect(
        card['dedicationHeading'],
        'صدقة جارية على روح المغفور له بإذن الله',
      );
    }
    expect(cards.map((card) => card['text']).join(' '), text);
  });

  test(
    'page dedication uses the deceased name and gender when no own name is set',
    () {
      final card = RemembranceWidgetService.contentCards(
        const ContentItem(
          id: 'page',
          type: ContentType.dedication,
          arabicText: 'اللهم ارحمها',
        ),
        '/m/test',
        deceasedName: 'فاطمة',
        recipient: DedicationRecipient.female,
      ).single;
      expect(
        card['title'],
        'صدقة جارية على روح المغفور لها بإذن الله\n"فاطمة"',
      );
      expect(card['deceasedName'], 'فاطمة');
      expect(card['text'], 'اللهم ارحمها');
    },
  );
  test(
    'selection persists per account and hides every page of a passage',
    () async {
      final db = await openNewInMemoryDatabase();
      addTearDown(db.close);
      var active = 'owner';
      RemembranceWidgetPreferencesStore store() =>
          RemembranceWidgetPreferencesStore(
            databaseProvider: () async => db,
            currentUserId: () => active,
          );
      await store().save(
        'owner',
        const RemembranceWidgetPreferences(
          hiddenIds: {'azkar:long'},
          hiddenTypes: {'dua'},
        ),
      );
      final restored = await store().read('owner');
      final cards = RemembranceWidgetService.contentCards(
        ContentItem(
          id: 'long',
          type: ContentType.azkar,
          arabicText: List.filled(250, 'ذكر').join(' '),
        ),
        '/azkar',
      );
      expect(cards.length, greaterThan(1));
      expect(cards.where(restored.includes), isEmpty);
      expect(restored.includes({'id': 'another', 'kind': 'dua'}), isFalse);
      active = 'other';
      expect((await store().read('other')).hiddenIds, isEmpty);
      await expectLater(store().read('owner'), throwsStateError);
      active = 'owner';
      expect((await store().read('owner')).hiddenIds, {'azkar:long'});
    },
  );

  test(
    'hidden categories stay hidden offline without restoring defaults',
    () async {
      final db = await openNewInMemoryDatabase();
      addTearDown(db.close);
      final settings = RemembranceWidgetPreferencesStore(
        databaseProvider: () async => db,
      );
      final repo = _Content();
      Map? payload;
      const channel = MethodChannel('azkar/home_widget');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'updateRemembrance') {
              payload = jsonDecode(call.arguments as String) as Map;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = RemembranceWidgetService(
        runtime: const MobileRuntime(
          isWeb: false,
          targetPlatform: TargetPlatform.android,
        ),
        currentUserId: () => 'owner',
        globalRepository: repo,
        pageRepository: (_) => repo,
        memorialRepository: _Memorial(),
        preferencesStore: settings,
      );
      await service.refresh('owner');
      final available = await settings.readCatalog('owner');
      expect(available, isNotEmpty);
      expect(payload!['rotationSeconds'], 7);
      await settings.save(
        'owner',
        const RemembranceWidgetPreferences(
          hiddenTypes: {'azkar', 'dua', 'dedication', 'hadith', 'quran'},
        ),
      );
      repo.offline = true;
      expect(await service.loadAvailable('owner'), available);
      await service.refresh('owner');
      expect(payload!['cards'], isEmpty);
      expect(await settings.readCatalog('other'), isEmpty);
    },
  );
  test('long content is paginated without changing the words', () {
    final text = List.filled(100, 'سبحان الله وبحمده').join(' ');
    final cards = RemembranceWidgetService.contentCards(
      ContentItem(
        id: 'dhikr',
        type: ContentType.azkar,
        arabicText: text,
        isPublished: true,
      ),
      '/azkar',
    );
    expect(cards.length, greaterThan(1));
    expect(cards.map((card) => card['text']).join(' '), text);
    expect(
      cards.every((card) => (card['text'] as String).length <= 380),
      isTrue,
    );
  });
  test(
    'widget excludes draft content and unpublished or other-owner memorials',
    () async {
      String? payload;
      const channel = MethodChannel('azkar/home_widget');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'updateRemembrance') {
              payload = call.arguments as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final repo = _Content();
      await RemembranceWidgetService(
        runtime: const MobileRuntime(
          isWeb: false,
          targetPlatform: TargetPlatform.android,
        ),
        currentUserId: () => 'owner',
        globalRepository: repo,
        pageRepository: (_) => repo,
        memorialRepository: _Memorial(),
      ).refresh('owner');
      final cards = jsonDecode(payload!)['cards'] as List;
      expect(cards, isNotEmpty);
      final memorial = cards.singleWhere((card) => card['id'] == 'memorial:a');
      expect(
        memorial['title'],
        'صدقة جارية على روح المغفور له بإذن الله\n"الاسم المنشور"',
      );
      expect(memorial['text'], 'اللهم اغفر له وارحمه');
      final noMessage = cards.singleWhere((card) => card['id'] == 'memorial:d');
      expect(noMessage['deceasedName'], 'فاطمة');
      expect(noMessage['text'], isEmpty);
      expect(noMessage['title'], contains('\n"فاطمة"'));
      expect(payload, contains('الاسم المنشور'));
      expect(payload, isNot(contains('اسم مسودة')));
      expect(payload, isNot(contains('حساب آخر')));
      expect(payload, isNot(contains('محتوى غير منشور')));
    },
  );
}

class _Content extends Fake implements ContentRepository {
  bool offline = false;
  @override
  Future<List<ContentItem>> fetchPublished(ContentType type) async {
    if (offline) throw StateError('offline');
    return type == ContentType.azkar
        ? [
            const ContentItem(
              id: 'visible',
              type: ContentType.azkar,
              arabicText: 'سبحان الله',
              isPublished: true,
            ),
            const ContentItem(
              id: 'draft',
              type: ContentType.azkar,
              arabicText: 'محتوى غير منشور',
            ),
          ]
        : [];
  }
}

class _Memorial extends Fake implements MemorialPageRepository {
  @override
  Future<List<MemorialPage>> fetchOwnedPages() async => const [
    MemorialPage(
      id: 'a',
      ownerUserId: 'owner',
      slug: 'a',
      title: 'A',
      deceasedName: 'الاسم المنشور',
      dedicationMessage: 'اللهم اغفر له وارحمه',
      isPublished: true,
    ),
    MemorialPage(
      id: 'b',
      ownerUserId: 'owner',
      slug: 'b',
      title: 'B',
      deceasedName: 'اسم مسودة',
    ),
    MemorialPage(
      id: 'c',
      ownerUserId: 'other',
      slug: 'c',
      title: 'C',
      deceasedName: 'حساب آخر',
      isPublished: true,
    ),
    MemorialPage(
      id: 'd',
      ownerUserId: 'owner',
      slug: 'd',
      title: 'D',
      deceasedName: 'فاطمة',
      deceasedGender: 'female',
      isPublished: true,
    ),
  ];
}
