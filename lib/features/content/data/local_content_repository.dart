import 'dart:async';

import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/demo_seed.dart';
import '../../../core/design/theme_settings.dart';
import '../../../core/storage/local_database.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/content_item.dart';
import '../domain/content_mappers.dart';
import '../domain/content_type.dart';
import 'content_repository.dart';

/// Offline/demo content repository.
///
/// It is a real CRUD repository (not a mock screen): drafts, publishing,
/// duplication and ordering all work and are persisted in the visitor database.
/// It is used only when Supabase is not configured and by automated tests.
class LocalContentRepository implements ContentRepository {
  LocalContentRepository({
    required this._themeProvider,
    Future<Database> Function()? databaseProvider,
    this._pageId,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final ThemeSettings Function() _themeProvider;
  final Future<Database> Function() _databaseProvider;
  final String? _pageId;
  final Uuid _uuid = const Uuid();

  final Map<ContentType, List<ContentItem>> _cache =
      <ContentType, List<ContentItem>>{};
  final Set<ContentType> _loaded = <ContentType>{};
  final StreamController<List<ContentItem>> _changes =
      StreamController<List<ContentItem>>.broadcast();
  Future<void>? _seedFuture;

  StoreRef<String, Map<String, Object?>> get _store =>
      stringMapStoreFactory.store(LocalStores.demoContent);

  StoreRef<String, Object?> get _preferences =>
      StoreRef<String, Object?>(LocalStores.preferences);

  @override
  Future<List<ContentItem>> fetchPublished(ContentType type) async {
    await _ensureLoaded(type);
    return _ordered(
      _cache[type]!.where((item) => item.isPublished).toList(growable: false),
    );
  }

  @override
  Future<List<ContentItem>> fetchAll(ContentType type) async {
    await _ensureLoaded(type);
    return _ordered(_cache[type]!);
  }

  @override
  Future<ContentItem?> fetchById(ContentType type, String id) async {
    await _ensureLoaded(type);
    for (final item in _cache[type]!) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<ContentItem> save(ContentItem item) async {
    await _ensureLoaded(item.type);
    final now = DateTime.now().toUtc();
    final isNew = item.id.isEmpty || item.id.startsWith('new-');
    final id = isNew ? _uuid.v4() : item.id;
    ContentItem? previous;
    for (final existing in _cache[item.type]!) {
      if (existing.id == id) {
        previous = existing;
        break;
      }
    }
    final saved = item.copyWith(
      id: id,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
    final list = _cache[item.type]!;
    final index = list.indexWhere((existing) => existing.id == id);
    if (index == -1) {
      list.add(saved);
    } else {
      list[index] = saved;
    }
    await _persist(saved);
    _notify();
    return saved;
  }

  @override
  Future<void> delete(ContentType type, String id) async {
    await _ensureLoaded(type);
    _cache[type]!.removeWhere((item) => item.id == id);
    final database = await _databaseProvider();
    await _store.record(_recordKey(type, id)).delete(database);
    _notify();
  }

  @override
  Future<void> setPublished(ContentType type, String id, bool published) async {
    final item = await fetchById(type, id);
    if (item == null) throw const NotFoundException();
    await save(item.copyWith(isPublished: published));
  }

  @override
  Future<void> reorder(ContentType type, List<String> orderedIds) async {
    await _ensureLoaded(type);
    final list = _cache[type]!;
    for (var index = 0; index < orderedIds.length; index++) {
      final id = orderedIds[index];
      final itemIndex = list.indexWhere((item) => item.id == id);
      if (itemIndex == -1) continue;
      final item = list[itemIndex].copyWith(displayOrder: index);
      list[itemIndex] = item;
      await _persist(item);
    }
    _notify();
  }

  @override
  Future<ContentItem> duplicate(ContentItem item) async {
    await _ensureLoaded(item.type);
    return save(
      item.copyWith(
        id: '',
        title: item.title.trim().isEmpty ? item.title : '${item.title} (نسخة)',
        isPublished: false,
        displayOrder: _cache[item.type]!.length,
        createdAt: null,
        updatedAt: null,
        clearValidation: true,
      ),
    );
  }

  @override
  Future<Map<ContentType, TypeCounts>> counts() async {
    final result = <ContentType, TypeCounts>{};
    for (final type in ContentType.values) {
      await _ensureLoaded(type);
      final list = _cache[type]!;
      result[type] = TypeCounts(
        published: list.where((item) => item.isPublished).length,
        drafts: list.where((item) => !item.isPublished).length,
      );
    }
    return result;
  }

  @override
  Stream<List<ContentItem>> watchPublished() async* {
    yield const <ContentItem>[];
    yield* _changes.stream;
  }

  Future<void> _ensureLoaded(ContentType type) async {
    if (_loaded.contains(type)) return;
    await _ensureSeeded();
    final database = await _databaseProvider();
    final records = await _store.find(
      database,
      finder: Finder(
        filter: Filter.and(<Filter>[
          Filter.equals('type', type.id),
          if (_pageId != null) Filter.equals('page_id', _pageId),
          if (_pageId == null) Filter.equals('page_id', null),
        ]),
      ),
    );
    final theme = _themeProvider();
    _cache[type] = records
        .map(
          (record) => ContentMapper.fromRow(
            type,
            Map<String, dynamic>.from(record.value),
            theme: theme,
          ),
        )
        .toList(growable: true);
    _loaded.add(type);
  }

  Future<void> _ensureSeeded() {
    if (_pageId != null) return Future<void>.value();
    return _seedFuture ??= _seedIfNeeded();
  }

  Future<void> _seedIfNeeded() async {
    try {
      final database = await _databaseProvider();
      const markerKey = 'demo_seed_version';
      final existing = await _preferences.record(markerKey).get(database);
      if (existing == 1) return;
      final theme = _themeProvider();
      await database.transaction((transaction) async {
        for (final item in DemoSeed.content()) {
          await _store
              .record(_recordKey(item.type, item.id))
              .put(transaction, _toStoredRow(item));
        }
        await _preferences.record(markerKey).put(transaction, 1);
      });
      AppLogger.info('Demo content seeded locally (${theme.defaultFontId}).');
    } catch (error, stackTrace) {
      _seedFuture = null;
      AppLogger.error('Demo content seed failed', error, stackTrace);
      throw LocalStorageException(technical: 'demo seed: $error', cause: error);
    }
  }

  Future<void> _persist(ContentItem item) async {
    final database = await _databaseProvider();
    await _store
        .record(_recordKey(item.type, item.id))
        .put(database, _toStoredRow(item));
  }

  Map<String, Object?> _toStoredRow(ContentItem item) => <String, Object?>{
    ...item.toRow(includeId: true),
    'type': item.type.id,
    if (_pageId != null) 'page_id': _pageId,
    'created_at': item.createdAt?.toIso8601String(),
    'updated_at': item.updatedAt?.toIso8601String(),
  };

  String _recordKey(ContentType type, String id) =>
      _pageId == null ? '${type.id}/$id' : '$_pageId/${type.id}/$id';

  List<ContentItem> _ordered(Iterable<ContentItem> items) {
    final list = items.toList(growable: false)
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return List<ContentItem>.unmodifiable(list);
  }

  void _notify() => _changes.add(const <ContentItem>[]);

  /// Releases the broadcast controller (useful in tests).
  Future<void> dispose() => _changes.close();
}
