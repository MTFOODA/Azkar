import 'package:azkar/core/utils/app_exception.dart';
import 'package:azkar/core/design/theme_settings.dart';
import 'package:azkar/features/content/data/content_homepage_lifecycle.dart';
import 'package:azkar/features/content/data/local_content_repository.dart';
import 'package:azkar/features/content/data/content_repository.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/home/data/local_homepage_repository.dart';
import 'package:azkar/features/home/data/homepage_repository.dart';
import 'package:azkar/features/home/domain/homepage_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  test(
    'new published content of every type gets one homepage reference',
    () async {
      final content = _MemoryContentRepository('page-a');
      final homepage = _MemoryHomepageRepository(content);
      final lifecycle = ContentHomepageLifecycle(
        contentRepository: content,
        homepageRepository: homepage,
      );

      final savedItems = <ContentItem>[];
      for (final type in ContentType.values) {
        savedItems.add(
          await lifecycle.saveNew(
            ContentItem(
              id: '',
              type: type,
              title: 'Published',
              isPublished: true,
            ),
          ),
        );
      }

      expect(homepage.entries, hasLength(ContentType.values.length));
      expect(
        homepage.entries.map((entry) => entry.contentId).toSet(),
        savedItems.map((item) => item.id).toSet(),
      );
      expect(
        await homepage.fetchPublishedLayout(),
        hasLength(ContentType.values.length),
      );
    },
  );

  test(
    'drafts stay hidden until published; disabled entries stay hidden',
    () async {
      final content = _MemoryContentRepository('page-a');
      final homepage = _MemoryHomepageRepository(content);
      final lifecycle = ContentHomepageLifecycle(
        contentRepository: content,
        homepageRepository: homepage,
      );

      final draft = await lifecycle.saveNew(
        const ContentItem(id: '', type: ContentType.tasbeeh, title: 'Draft'),
      );
      expect(homepage.entries, hasLength(1));
      expect(await homepage.fetchPublishedLayout(), isEmpty);

      await content.setPublished(ContentType.tasbeeh, draft.id, true);
      expect(await homepage.fetchPublishedLayout(), hasLength(1));

      await homepage.setEnabled(homepage.entries.single.id, false);
      await content.setPublished(ContentType.tasbeeh, draft.id, false);
      await content.setPublished(ContentType.tasbeeh, draft.id, true);
      expect(await homepage.fetchPublishedLayout(), isEmpty);
      expect(homepage.entries.single.isEnabled, isFalse);
    },
  );

  test(
    'existing published content can be added and add is idempotent',
    () async {
      final content = _MemoryContentRepository('page-a');
      final homepage = _MemoryHomepageRepository(content);
      final existing = await content.save(
        const ContentItem(
          id: '',
          type: ContentType.azkar,
          title: 'Existing published content',
          isPublished: true,
        ),
      );
      final first = await homepage.add(
        contentType: existing.type,
        contentId: existing.id,
      );
      final repeated = await homepage.add(
        contentType: existing.type,
        contentId: existing.id,
      );

      expect(repeated.id, first.id);
      expect(homepage.entries, hasLength(1));
      expect(await homepage.fetchPublishedLayout(), hasLength(1));
    },
  );

  test('concurrent local adds create one homepage reference', () async {
    final database = await openNewInMemoryDatabase();
    addTearDown(database.close);
    final content = LocalContentRepository(
      pageId: 'page-a',
      databaseProvider: () async => database,
      themeProvider: () => ThemeSettings.defaults,
    );
    final homepage = LocalHomepageRepository(
      pageId: 'page-a',
      databaseProvider: () async => database,
      contentRepository: content,
    );
    await homepage.fetchEntries();
    final item = await content.save(
      const ContentItem(
        id: '',
        type: ContentType.tasbeeh,
        title: 'Published',
        isPublished: true,
      ),
    );

    final results = await Future.wait([
      homepage.add(contentType: item.type, contentId: item.id),
      homepage.add(contentType: item.type, contentId: item.id),
    ]);

    expect(results.first.id, results.last.id);
    expect(await homepage.fetchEntries(), hasLength(1));
  });

  test(
    'page-specific content and homepage configuration remain independent',
    () async {
      final contentA = _MemoryContentRepository('page-a');
      final contentB = _MemoryContentRepository('page-b');
      final homepageA = _MemoryHomepageRepository(contentA);
      final homepageB = _MemoryHomepageRepository(contentB);
      final lifecycleA = ContentHomepageLifecycle(
        contentRepository: contentA,
        homepageRepository: homepageA,
      );
      final lifecycleB = ContentHomepageLifecycle(
        contentRepository: contentB,
        homepageRepository: homepageB,
      );

      final itemA = await lifecycleA.saveNew(
        const ContentItem(
          id: '',
          type: ContentType.quran,
          title: 'Page A',
          isPublished: true,
        ),
      );
      final itemB = await lifecycleB.saveNew(
        const ContentItem(
          id: '',
          type: ContentType.quran,
          title: 'Page B',
          isPublished: true,
        ),
      );

      expect(itemA.id, isNot(itemB.id));
      expect(homepageA.entries.single.contentId, itemA.id);
      expect(homepageB.entries.single.contentId, itemB.id);
      await expectLater(
        homepageB.add(contentType: itemA.type, contentId: itemA.id),
        throwsA(isA<NotFoundException>()),
      );
      expect(homepageB.entries, hasLength(1));
    },
  );

  test(
    'duplicated content gets an independent hidden record and reference',
    () async {
      final content = _MemoryContentRepository('page-a');
      final homepage = _MemoryHomepageRepository(content);
      final lifecycle = ContentHomepageLifecycle(
        contentRepository: content,
        homepageRepository: homepage,
      );
      final original = await lifecycle.saveNew(
        const ContentItem(
          id: '',
          type: ContentType.tasbeeh,
          title: 'Original',
          isPublished: true,
        ),
      );

      final duplicate = await lifecycle.duplicate(original);

      expect(duplicate.id, isNot(original.id));
      expect(duplicate.isPublished, isFalse);
      expect(homepage.entries, hasLength(2));
      expect(await homepage.fetchPublishedLayout(), hasLength(1));
      expect(
        (await content.fetchById(original.type, original.id))?.title,
        'Original',
      );
    },
  );
}

class _MemoryContentRepository implements ContentRepository {
  _MemoryContentRepository(this.pageId);

  final String pageId;
  final Map<String, ContentItem> _items = {};
  int _nextId = 0;

  @override
  Future<ContentItem> save(ContentItem item) async {
    final id = item.id.isEmpty ? '$pageId-content-${_nextId++}' : item.id;
    final saved = item.copyWith(id: id);
    _items['${item.type.id}:$id'] = saved;
    return saved;
  }

  @override
  Future<ContentItem> duplicate(ContentItem item) {
    return save(item.copyWith(id: '', isPublished: false));
  }

  @override
  Future<ContentItem?> fetchById(ContentType type, String id) async =>
      _items['${type.id}:$id'];

  @override
  Future<List<ContentItem>> fetchPublished(ContentType type) async => _items
      .values
      .where((item) => item.type == type && item.isPublished)
      .toList();

  @override
  Future<void> setPublished(ContentType type, String id, bool published) async {
    final item = await fetchById(type, id);
    if (item == null) throw const NotFoundException();
    _items['${type.id}:$id'] = item.copyWith(isPublished: published);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryHomepageRepository implements HomepageRepository {
  _MemoryHomepageRepository(this._contentRepository);

  final _MemoryContentRepository _contentRepository;
  final List<HomepageEntry> entries = [];
  int _nextId = 0;

  @override
  Future<HomepageEntry> add({
    required ContentType contentType,
    required String contentId,
  }) async {
    for (final entry in entries) {
      if (entry.contentType == contentType && entry.contentId == contentId) {
        return entry;
      }
    }
    if (await _contentRepository.fetchById(contentType, contentId) == null) {
      throw const NotFoundException();
    }
    final nextOrder =
        entries.fold<int>(
          -1,
          (maximum, entry) =>
              entry.displayOrder > maximum ? entry.displayOrder : maximum,
        ) +
        1;
    final entry = HomepageEntry(
      id: 'entry-${_nextId++}',
      contentType: contentType,
      contentId: contentId,
      displayOrder: nextOrder,
    );
    entries.add(entry);
    return entry;
  }

  @override
  Future<List<HomepageEntry>> fetchEntries() async =>
      List<HomepageEntry>.unmodifiable(entries);

  @override
  Future<List<HomeCard>> fetchPublishedLayout() async {
    final cards = <HomeCard>[];
    for (final entry in entries) {
      if (!entry.isEnabled) continue;
      final item = await _contentRepository.fetchById(
        entry.contentType,
        entry.contentId,
      );
      if (item == null || !item.isPublished) continue;
      cards.add(HomeCard(entry: entry, item: item));
    }
    return cards;
  }

  @override
  Future<void> setEnabled(String entryId, bool enabled) async {
    final index = entries.indexWhere((entry) => entry.id == entryId);
    if (index >= 0) {
      entries[index] = entries[index].copyWith(isEnabled: enabled);
    }
  }

  @override
  Future<void> remove(String entryId) async {
    entries.removeWhere((entry) => entry.id == entryId);
  }

  @override
  Future<void> saveOrder(List<HomepageEntry> orderedEntries) async {
    entries
      ..clear()
      ..addAll([
        for (var index = 0; index < orderedEntries.length; index++)
          orderedEntries[index].copyWith(displayOrder: index),
      ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
