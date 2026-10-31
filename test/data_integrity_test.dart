import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/home/data/bismillah_loader.dart';
import 'package:azkar/features/quran/domain/quran_dataset.dart';
import 'package:azkar/features/quran/data/quran_dataset_repository.dart';
import 'package:azkar/features/tasbeeh/data/local_tasbeeh_counter_store.dart';
import 'package:azkar/features/tasbeeh/domain/tasbeeh_counter_keys.dart';
import 'package:azkar/features/content/data/local_content_repository.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/core/design/theme_settings.dart';
import 'package:azkar/features/memorial/domain/page_slug.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all seven content types have unique identifiers and tables', () {
    expect(ContentType.values, hasLength(7));
    expect(ContentType.values.map((type) => type.id).toSet(), hasLength(7));
    expect(ContentType.values.map((type) => type.table).toSet(), hasLength(7));
    expect(ContentTypeX.fromId('quran_verses'), ContentType.quran);
    expect(ContentType.dua.table, 'duas');
  });

  test('bundled Quran data and surah index are intact and usable', () async {
    final repository = QuranDatasetRepository();
    final index = await repository.surahIndex();
    final dataset = await repository.dataset();

    expect(index, hasLength(114));
    expect(index.first.name, startsWith('س'));
    expect(dataset.surahs, hasLength(114));
    expect(dataset.ayahCount, 6236);
    expect(await BismillahLoader.load(), dataset.ayahText(1, 1));

    final firstAyah = dataset.rangeText(1, 1, 1)!;
    expect(
      (await repository.validate(
        surahNumber: 1,
        from: 1,
        to: 1,
        text: firstAyah,
      )).isValid,
      isTrue,
    );
    expect(
      (await repository.validate(
        surahNumber: 1,
        from: 1,
        to: 1,
        text: 'not Quranic text',
      )).isValid,
      isFalse,
    );
  });

  test('Quran parser rejects incomplete datasets', () {
    expect(() => QuranDataset.fromJson(const {}), throwsFormatException);
  });

  test('local Tasbeeh counters persist independently by card id', () async {
    final database = await openNewInMemoryDatabase();
    addTearDown(database.close);
    final store = LocalTasbeehCounterStore(
      databaseProvider: () async => database,
    );

    final largeCount = BigInt.parse('900719925474099312345');
    await store.write('first-card', largeCount);
    await store.write('second-card', BigInt.from(4));
    await stringMapStoreFactory
        .store('tasbeeh_counters')
        .record('azkar_tasbeeh_legacy-card')
        .put(database, {'value': 9});

    expect(
      await store.readMany(['first-card', 'second-card', 'missing-card']),
      {'first-card': largeCount, 'second-card': BigInt.from(4)},
    );
    expect(await store.read('legacy-card'), BigInt.from(9));

    await store.delete('first-card');
    expect(await store.read('first-card'), BigInt.zero);
    expect(await store.read('second-card'), BigInt.from(4));
  });

  test('page-scoped Tasbeeh counters isolate identical card ids', () async {
    final database = await openNewInMemoryDatabase();
    addTearDown(database.close);
    final store = LocalTasbeehCounterStore(
      databaseProvider: () async => database,
    );

    await store.write('same-card', BigInt.from(7), pageId: 'page-one');
    await store.write('same-card', BigInt.from(12), pageId: 'page-two');

    expect(await store.read('same-card', pageId: 'page-one'), BigInt.from(7));
    expect(await store.read('same-card', pageId: 'page-two'), BigInt.from(12));
    expect(
      TasbeehCounterKeys.forTasbeeh('same-card', pageId: 'page-one'),
      'azkar_tasbeeh_page-one_same-card',
    );
  });

  test(
    'local content repositories isolate pages and keep global rows separate',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      LocalContentRepository repository(String pageId) =>
          LocalContentRepository(
            pageId: pageId,
            databaseProvider: () async => database,
            themeProvider: () => ThemeSettings.defaults,
          );

      await repository('page-one').save(
        const ContentItem(
          id: '',
          type: ContentType.azkar,
          title: 'صفحة أولى',
          arabicText: 'ذكر',
        ),
      );
      await repository('page-two').save(
        const ContentItem(
          id: '',
          type: ContentType.azkar,
          title: 'صفحة ثانية',
          arabicText: 'ذكر آخر',
        ),
      );

      expect(
        (await repository('page-one').fetchAll(ContentType.azkar))
            .map((item) => item.title),
        ['صفحة أولى'],
      );
      expect(
        (await repository('page-two').fetchAll(ContentType.azkar))
            .map((item) => item.title),
        ['صفحة ثانية'],
      );
      final global = LocalContentRepository(
        databaseProvider: () async => database,
        themeProvider: () => ThemeSettings.defaults,
      );
      expect(
        (await global.fetchAll(ContentType.azkar))
            .any((item) => item.title == 'عينة — ذكر'),
        isTrue,
      );
      expect(
        (await repository('page-one').fetchAll(ContentType.azkar))
            .map((item) => item.title),
        ['صفحة أولى'],
      );
    },
  );

  test('page slugs normalize, validate, and reject reserved routes', () {
    expect(PageSlug.normalize('  My__Memorial Page  '), 'my-memorial-page');
    expect(PageSlug.validate('valid-memorial'), isNull);
    expect(PageSlug.validate('dashboard'), isNotNull);
    expect(PageSlug.validate('bad/slugs'), isNotNull);
    expect(PageSlug.validate('ab'), isNotNull);
  });
}
