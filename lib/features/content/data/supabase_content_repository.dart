import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/design/theme_settings.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/content_item.dart';
import '../domain/content_mappers.dart';
import '../domain/content_type.dart';
import 'content_repository.dart';

/// Production content repository backed by Supabase/Postgres.
///
/// Security model: this class never decides who may write. Every statement runs
/// with the signed-in user's JWT and the database RLS policies decide the
/// outcome, so a compromised client cannot publish content.
class SupabaseContentRepository implements ContentRepository {
  SupabaseContentRepository({
    required this._client,
    required this._themeProvider,
    this._pageId,
  });

  final SupabaseClient _client;
  final ThemeSettings Function() _themeProvider;
  final String? _pageId;

  ThemeSettings get _theme => _themeProvider();

  /// An explicit public card link may resolve a published record from any page.
  /// Collection/admin queries remain scoped; parent-page visibility is enforced
  /// by RLS just as it is for the public memorial link.
  Future<ContentItem?> fetchSharedPublished(ContentType type, String id) async {
    try {
      final row = await _client
          .from(type.table)
          .select()
          .eq('id', id)
          .eq('is_published', true)
          .maybeSingle();
      return row == null
          ? null
          : ContentMapper.fromRow(type, row, theme: _theme);
    } on PostgrestException catch (error) {
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<List<ContentItem>> fetchPublished(ContentType type) async {
    final rows = await _select(type, publishedOnly: true);
    return _mapRows(type, rows);
  }

  @override
  Future<List<ContentItem>> fetchAll(ContentType type) async {
    final rows = await _select(type, publishedOnly: false);
    return _mapRows(type, rows);
  }

  @override
  Future<ContentItem?> fetchById(ContentType type, String id) async {
    try {
      var query = _client.from(type.table).select().eq('id', id);
      query = _pageId == null
          ? query.isFilter('page_id', null)
          : query.eq('page_id', _pageId);
      final row = await query.maybeSingle();
      if (row == null) return null;
      return ContentMapper.fromRow(type, row, theme: _theme);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.error('fetchById failed for ${type.table}', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<ContentItem> save(ContentItem item) async {
    try {
      final isExisting = item.id.isNotEmpty && !item.id.startsWith('new-');
      if (isExisting) {
        var query = _client
            .from(item.type.table)
            .update(item.toRow())
            .eq('id', item.id);
        query = _pageId == null
            ? query.isFilter('page_id', null)
            : query.eq('page_id', _pageId);
        final updated = await query.select().single();
        return ContentMapper.fromRow(item.type, updated, theme: _theme);
      }
      final inserted = await _client
          .from(item.type.table)
          .insert(<String, dynamic>{
            ...item.toRow(),
            if (_pageId != null) 'page_id': _pageId,
          })
          .select()
          .single();
      return ContentMapper.fromRow(item.type, inserted, theme: _theme);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.error('save failed for ${item.type.table}', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<void> delete(ContentType type, String id) async {
    try {
      var query = _client.from(type.table).delete().eq('id', id);
      query = _pageId == null
          ? query.isFilter('page_id', null)
          : query.eq('page_id', _pageId);
      await query;
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.error('delete failed for ${type.table}', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<void> setPublished(ContentType type, String id, bool published) async {
    try {
      var query = _client
          .from(type.table)
          .update(<String, dynamic>{'is_published': published})
          .eq('id', id);
      query = _pageId == null
          ? query.isFilter('page_id', null)
          : query.eq('page_id', _pageId);
      await query;
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.error(
        'setPublished failed for ${type.table}',
        error,
        stackTrace,
      );
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<void> reorder(ContentType type, List<String> orderedIds) async {
    try {
      for (var index = 0; index < orderedIds.length; index++) {
        var query = _client
            .from(type.table)
            .update(<String, dynamic>{'display_order': index})
            .eq('id', orderedIds[index]);
        query = _pageId == null
            ? query.isFilter('page_id', null)
            : query.eq('page_id', _pageId);
        await query;
      }
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.error('reorder failed for ${type.table}', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<ContentItem> duplicate(ContentItem item) {
    final copy = item.copyWith(
      id: '',
      title: item.title.trim().isEmpty ? item.title : '${item.title} (نسخة)',
      isPublished: false,
      displayOrder: item.displayOrder + 1,
      createdAt: null,
      updatedAt: null,
      clearValidation: true,
    );
    return save(copy);
  }

  @override
  Future<Map<ContentType, TypeCounts>> counts() async {
    final result = <ContentType, TypeCounts>{};
    for (final type in ContentType.values) {
      try {
        var query = _client.from(type.table).select('is_published');
        query = _pageId == null
            ? query.isFilter('page_id', null)
            : query.eq('page_id', _pageId);
        final rows = await query;
        var published = 0;
        var drafts = 0;
        for (final row in rows as List<dynamic>) {
          final map = row as Map<String, dynamic>;
          if (map['is_published'] == true) {
            published++;
          } else {
            drafts++;
          }
        }
        result[type] = TypeCounts(published: published, drafts: drafts);
      } on PostgrestException catch (error, stackTrace) {
        AppLogger.error(
          'Content counts failed for ${type.table}',
          error,
          stackTrace,
        );
        throw translatePostgrestError(error);
      }
    }
    return result;
  }

  @override
  Stream<List<ContentItem>> watchPublished() {
    // A single lightweight realtime signal. Pages re-query when it fires, which
    // avoids keeping seven table subscriptions open per visitor.
    try {
      var stream = _client
          .from(ContentType.azkar.table)
          .stream(primaryKey: <String>['id']);
      if (_pageId != null) stream = stream.eq('page_id', _pageId);
      return stream.map((_) => const <ContentItem>[]);
    } catch (error, stackTrace) {
      AppLogger.warning('Realtime stream unavailable', error, stackTrace);
      return const Stream<List<ContentItem>>.empty();
    }
  }

  Future<List<Map<String, dynamic>>> _select(
    ContentType type, {
    required bool publishedOnly,
  }) async {
    try {
      var query = _client.from(type.table).select();
      query = _pageId == null
          ? query.isFilter('page_id', null)
          : query.eq('page_id', _pageId);
      if (publishedOnly) {
        query = query.eq('is_published', true);
      }
      final rows = await query.order('display_order', ascending: true);
      return (rows as List<dynamic>)
          .map((row) => row as Map<String, dynamic>)
          .toList(growable: false);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.error('select failed for ${type.table}', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  List<ContentItem> _mapRows(
    ContentType type,
    List<Map<String, dynamic>> rows,
  ) {
    final theme = _theme;
    return List<ContentItem>.unmodifiable(
      rows.map((row) => ContentMapper.fromRow(type, row, theme: theme)),
    );
  }
}

/// Maps a Postgres error to a friendly Arabic [AppException].
AppException translatePostgrestError(PostgrestException error) {
  final message = error.message.toLowerCase();
  if (message.contains('row-level security') ||
      message.contains('permission denied') ||
      error.code == '42501') {
    return const NotAuthorizedException();
  }
  if (error.code == 'PGRST116') return const NotFoundException();
  if (message.contains('duplicate key') || error.code == '23505') {
    return const AppException('هذا العنصر موجود بالفعل.');
  }
  if (message.contains('check constraint') || error.code == '23514') {
    return AppException(
      'بعض البيانات المدخلة غير صالحة. راجعها ثم أعد المحاولة.',
      technical: error.message,
    );
  }
  return AppException(
    'تعذّر إتمام العملية حاليًا. يُرجى المحاولة لاحقًا.',
    technical: error.message,
  );
}
