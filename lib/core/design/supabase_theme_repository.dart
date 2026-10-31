import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/content/data/supabase_content_repository.dart';
import '../../core/utils/app_logger.dart';
import 'theme_repository.dart';
import 'theme_settings.dart';

/// Supabase implementation of [ThemeRepository].
///
/// The legacy/global row uses `id = 'global'`. Page instances use their
/// immutable `page_id`; database RLS controls both public reads and writes.
class SupabaseThemeRepository implements ThemeRepository {
  SupabaseThemeRepository(this._client, {this._pageId});

  final SupabaseClient _client;
  final String? _pageId;

  @override
  Future<ThemeSettings?> load() async {
    try {
      var query = _client.from('theme_settings').select();
      query = _pageId == null
          ? query.eq('id', 'global')
          : query.eq('page_id', _pageId);
      final row = await query.maybeSingle();
      if (row == null) return null;
      return ThemeSettings.fromMap(row);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.warning('Theme settings load failed', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<ThemeSettings> save(ThemeSettings settings) async {
    try {
      final row = await _client
          .from('theme_settings')
          .upsert(<String, dynamic>{
            if (_pageId == null) 'id': 'global',
            if (_pageId != null) 'page_id': _pageId,
            ...settings.toMap(),
          }, onConflict: _pageId == null ? 'id' : 'page_id')
          .select()
          .single();
      return ThemeSettings.fromMap(row);
    } on PostgrestException catch (error, stackTrace) {
      AppLogger.warning('Theme settings save failed', error, stackTrace);
      throw translatePostgrestError(error);
    }
  }
}
