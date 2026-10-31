import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/app_exception.dart';
import '../../content/data/supabase_content_repository.dart';
import '../domain/memorial_page.dart';
import 'memorial_page_repository.dart';

class SupabaseMemorialPageRepository implements MemorialPageRepository {
  SupabaseMemorialPageRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MemorialPage?> fetchMine() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const NotAuthorizedException();
    try {
      final row = await _client
          .from('memorial_pages')
          .select()
          .eq('owner_user_id', userId)
          .maybeSingle();
      return row == null ? null : MemorialPage.fromRow(row);
    } on PostgrestException catch (error) {
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<MemorialPage?> fetchPublishedBySlug(String slug) async {
    try {
      final row = await _client
          .from('memorial_pages')
          .select()
          .eq('slug', slug)
          .eq('is_published', true)
          .maybeSingle();
      return row == null ? null : MemorialPage.fromRow(row);
    } on PostgrestException catch (error) {
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<MemorialPage> update(MemorialPage page) async {
    try {
      final row = await _client
          .from('memorial_pages')
          .update(page.toUpdateRow())
          .eq('id', page.id)
          .select()
          .single();
      return MemorialPage.fromRow(row);
    } on PostgrestException catch (error) {
      if (error.code == '23505' ||
          error.message.toLowerCase().contains('slug')) {
        throw AppException(
          'هذا الرابط مستخدم بالفعل. اختر رابطًا آخر.',
          technical: error.message,
        );
      }
      throw translatePostgrestError(error);
    }
  }
}
