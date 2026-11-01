import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/local_database.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/app_exception.dart';
import '../../content/data/content_repository.dart';
import '../../content/domain/content_item.dart';
import '../../content/domain/content_type.dart';
import '../domain/homepage_entry.dart';
import 'homepage_repository.dart';

/// Offline/demo homepage repository.
///
/// Layout entries are stored locally, while the referenced content remains in
/// [ContentRepository]. This mirrors the production separation between
/// `homepage_cards` and the content tables.
class LocalHomepageRepository implements HomepageRepository {
  LocalHomepageRepository({
    required this._contentRepository,
    Future<Database> Function()? databaseProvider,
    this._pageId,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final ContentRepository _contentRepository;
  final Future<Database> Function() _databaseProvider;
  final String? _pageId;
  final Uuid _uuid = const Uuid();

  String get _entryKey =>
      _pageId == null ? 'homepage_entries' : 'homepage_entries_$_pageId';
  StoreRef<String, Object?> get _preferences =>
      StoreRef<String, Object?>(LocalStores.preferences);

  List<HomepageEntry>? _cache;
  final Map<String, Future<HomepageEntry>> _pendingAdds = {};

  @override
  Future<List<HomepageEntry>> fetchEntries() async {
    if (_cache != null) return List<HomepageEntry>.unmodifiable(_cache!);
    final database = await _databaseProvider();
    final raw = await _preferences.record(_entryKey).get(database);
    if (raw is List<dynamic>) {
      _cache = raw
          .whereType<Map<dynamic, dynamic>>()
          .map((row) => HomepageEntry.fromRow(Map<String, dynamic>.from(row)))
          .toList(growable: true);
    } else {
      _cache = await _createInitialLayout();
      await _persist();
    }
    return List<HomepageEntry>.unmodifiable(_cache!);
  }

  @override
  Future<List<HomeCard>> fetchPublishedLayout() async {
    final entries = (await fetchEntries())
        .where((entry) => entry.isEnabled)
        .toList(growable: false);
    final items = <String, ContentItem>{};
    for (final type in ContentType.values) {
      if (!entries.any((entry) => entry.contentType == type)) continue;
      final published = await _contentRepository.fetchPublished(type);
      for (final item in published) {
        items[item.cardKey] = item;
      }
    }
    final cards = <HomeCard>[];
    for (final entry in entries) {
      final item = items['${entry.contentType.id}:${entry.contentId}'];
      if (item == null) continue;
      cards.add(HomeCard(entry: entry, item: item, span: _spanFor(item)));
    }
    return List<HomeCard>.unmodifiable(cards);
  }

  @override
  Future<void> saveOrder(List<HomepageEntry> entries) async {
    await fetchEntries();
    _cache = <HomepageEntry>[
      for (var index = 0; index < entries.length; index++)
        entries[index].copyWith(displayOrder: index),
    ];
    await _persist();
  }

  @override
  Future<void> setEnabled(String entryId, bool enabled) async {
    final entries = await fetchEntries();
    _cache = entries
        .map(
          (entry) =>
              entry.id == entryId ? entry.copyWith(isEnabled: enabled) : entry,
        )
        .toList(growable: true);
    await _persist();
  }

  @override
  Future<void> remove(String entryId) async {
    final entries = await fetchEntries();
    _cache = entries
        .where((entry) => entry.id != entryId)
        .toList(growable: true);
    await _persist();
  }

  @override
  Future<HomepageEntry> add({
    required ContentType contentType,
    required String contentId,
  }) async {
    final key = '${contentType.id}:$contentId';
    final pending = _pendingAdds[key];
    if (pending != null) return pending;

    final operation = _add(contentType: contentType, contentId: contentId);
    _pendingAdds[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_pendingAdds[key], operation)) _pendingAdds.remove(key);
    }
  }

  Future<HomepageEntry> _add({
    required ContentType contentType,
    required String contentId,
  }) async {
    final entries = await fetchEntries();
    for (final entry in entries) {
      if (entry.contentType == contentType && entry.contentId == contentId) {
        return entry;
      }
    }
    if (await _contentRepository.fetchById(contentType, contentId) == null) {
      throw const NotFoundException();
    }
    for (final entry in await fetchEntries()) {
      if (entry.contentType == contentType && entry.contentId == contentId) {
        return entry;
      }
    }
    final nextOrder =
        entries.fold<int>(
          -1,
          (maximum, entry) =>
              entry.displayOrder > maximum ? entry.displayOrder : maximum,
        ) +
        1;
    final created = HomepageEntry(
      id: _uuid.v4(),
      contentType: contentType,
      contentId: contentId,
      displayOrder: nextOrder,
    );
    _cache = <HomepageEntry>[...entries, created];
    await _persist();
    return created;
  }

  Future<List<HomepageEntry>> _createInitialLayout() async => <HomepageEntry>[];

  Future<void> _persist() async {
    try {
      final database = await _databaseProvider();
      final rows = _cache!
          .map(
            (entry) => <String, Object?>{
              'id': entry.id,
              ...entry.toRow(),
              if (_pageId != null) 'page_id': _pageId,
            },
          )
          .toList(growable: false);
      await _preferences.record(_entryKey).put(database, rows);
    } catch (error, stackTrace) {
      AppLogger.error('Local homepage save failed', error, stackTrace);
      rethrow;
    }
  }

  static int _spanFor(ContentItem item) {
    final longReligious =
        (item.type == ContentType.quran || item.type == ContentType.hadith) &&
        item.wordCount > 45;
    return longReligious ? 2 : 1;
  }
}
