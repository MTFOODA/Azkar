import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/design/theme_settings.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/app_exception.dart';
import '../../content/data/supabase_content_repository.dart';
import '../../content/domain/content_item.dart';
import '../../content/domain/content_mappers.dart';
import '../../content/domain/content_type.dart';
import '../domain/homepage_entry.dart';
import 'homepage_repository.dart';

/// Supabase implementation of the dynamic homepage layout.
class SupabaseHomepageRepository implements HomepageRepository {
  SupabaseHomepageRepository({
    required this._client,
    required this._themeProvider,
    this._pageId,
  });

  final SupabaseClient _client;
  final ThemeSettings Function() _themeProvider;
  final String? _pageId;

  @override
  Future<List<HomepageEntry>> fetchEntries() async {
    try {
      var query = _client.from('homepage_cards').select();
      if (_pageId == null) {
        query = query.isFilter('page_id', null);
      } else {
        query = query.eq('page_id', _pageId);
      }
      final rows = await query.order('display_order', ascending: true);
      return (rows as List<dynamic>)
          .map((row) => HomepageEntry.fromRow(row as Map<String, dynamic>))
          .toList(growable: false);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.error('Homepage entries load failed', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<List<HomeCard>> fetchPublishedLayout() async {
    final entries = (await fetchEntries())
        .where((entry) => entry.isEnabled)
        .toList(growable: false);
    if (entries.isEmpty) return const <HomeCard>[];

    // Fetch only the referenced published rows, grouped by type. This avoids
    // downloading entire collections just to render the homepage.
    final itemsByKey = <String, ContentItem>{};
    for (final type in ContentType.values) {
      final ids = entries
          .where((entry) => entry.contentType == type)
          .map((entry) => entry.contentId)
          .toSet()
          .toList(growable: false);
      if (ids.isEmpty) continue;
      try {
        var query = _client
            .from(type.table)
            .select()
            .inFilter('id', ids)
            .eq('is_published', true);
        if (_pageId == null) {
          query = query.isFilter('page_id', null);
        } else {
          query = query.eq('page_id', _pageId);
        }
        final rows = await query;
        for (final raw in rows as List<dynamic>) {
          final item = ContentMapper.fromRow(
            type,
            raw as Map<String, dynamic>,
            theme: _themeProvider(),
          );
          itemsByKey[item.cardKey] = item;
        }
      } on PostgrestException catch (error, stackTrace) {
        AppLogger.error('Homepage content load failed', error, stackTrace);
        throw translatePostgrestError(error);
      }
    }

    final cards = <HomeCard>[];
    for (final entry in entries) {
      final item = itemsByKey['${entry.contentType.id}:${entry.contentId}'];
      if (item == null) continue;
      cards.add(HomeCard(entry: entry, item: item, span: _spanFor(item)));
    }
    return List<HomeCard>.unmodifiable(cards);
  }

  @override
  Future<void> saveOrder(List<HomepageEntry> entries) async {
    try {
      for (var index = 0; index < entries.length; index++) {
        var query = _client
            .from('homepage_cards')
            .update(<String, dynamic>{'display_order': index})
            .eq('id', entries[index].id);
        if (_pageId == null) {
          query = query.isFilter('page_id', null);
        } else {
          query = query.eq('page_id', _pageId);
        }
        await query;
      }
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.error('Homepage order save failed', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<void> setEnabled(String entryId, bool enabled) async {
    try {
      var query = _client
          .from('homepage_cards')
          .update(<String, dynamic>{'is_enabled': enabled})
          .eq('id', entryId);
      if (_pageId == null) {
        query = query.isFilter('page_id', null);
      } else {
        query = query.eq('page_id', _pageId);
      }
      await query;
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.error('Homepage enable toggle failed', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<void> remove(String entryId) async {
    try {
      var query = _client.from('homepage_cards').delete().eq('id', entryId);
      if (_pageId == null) {
        query = query.isFilter('page_id', null);
      } else {
        query = query.eq('page_id', _pageId);
      }
      await query;
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.error('Homepage entry delete failed', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<HomepageEntry> add({
    required ContentType contentType,
    required String contentId,
  }) async {
    final current = await fetchEntries();
    for (final entry in current) {
      if (entry.contentType == contentType && entry.contentId == contentId) {
        return entry;
      }
    }

    try {
      var contentQuery = _client
          .from(contentType.table)
          .select('id')
          .eq('id', contentId);
      if (_pageId == null) {
        contentQuery = contentQuery.isFilter('page_id', null);
      } else {
        contentQuery = contentQuery.eq('page_id', _pageId);
      }
      if (await contentQuery.maybeSingle() == null) {
        throw const NotFoundException();
      }

      final nextOrder =
          current.fold<int>(
            -1,
            (maximum, entry) =>
                entry.displayOrder > maximum ? entry.displayOrder : maximum,
          ) +
          1;
      final row = await _client
          .from('homepage_cards')
          .insert(<String, dynamic>{
            'content_type': contentType.id,
            'content_id': contentId,
            'display_order': nextOrder,
            'is_enabled': true,
            if (_pageId != null) 'page_id': _pageId,
          })
          .select()
          .single();
      return HomepageEntry.fromRow(row);
    } on PostgrestException catch (error, stackTrace) {
      if (error.code == '23505') {
        final refreshed = await fetchEntries();
        for (final entry in refreshed) {
          if (entry.contentType == contentType &&
              entry.contentId == contentId) {
            return entry;
          }
        }
      }
      AppLogger.error('Homepage entry add failed', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  static int _spanFor(ContentItem item) {
    final longReligious =
        (item.type == ContentType.quran || item.type == ContentType.hadith) &&
        item.wordCount > 45;
    return longReligious ? 2 : 1;
  }
}
