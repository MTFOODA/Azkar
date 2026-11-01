import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/app_exception.dart';
import '../../content/data/supabase_content_repository.dart';
import '../domain/memorial_page.dart';
import 'memorial_page_repository.dart';

class SupabaseMemorialPageRepository implements MemorialPageRepository {
  SupabaseMemorialPageRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<MemorialPage>> fetchOwnedPages() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const NotAuthorizedException();
    try {
      final rows = await _client
          .from('memorial_pages')
          .select()
          .eq('owner_user_id', userId)
          .order('updated_at', ascending: false);
      return (rows as List<dynamic>)
          .map((row) => MemorialPage.fromRow(row as Map<String, dynamic>))
          .toList(growable: false);
    } on PostgrestException catch (error) {
      throw translatePostgrestError(error);
    }
  }

  @override
  Future<MemorialPage?> fetchOwnedById(String pageId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const NotAuthorizedException();
    try {
      final row = await _client
          .from('memorial_pages')
          .select()
          .eq('id', pageId)
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
  Future<MemorialPage> create({
    required String slug,
    required String deceasedName,
    required String deceasedGender,
    String? dedicationMessage,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const NotAuthorizedException();
    try {
      final result = await _client.rpc(
        'create_memorial_page',
        params: <String, dynamic>{
          'p_slug': slug,
          'p_deceased_name': deceasedName.trim(),
          'p_deceased_gender': deceasedGender,
          'p_dedication_message': _nullIfBlank(dedicationMessage),
        },
      );
      if (result is! Map<String, dynamic>) {
        throw const AppException('تعذّر إنشاء الصفحة. أعد المحاولة.');
      }
      return MemorialPage.fromRow(result);
    } on PostgrestException catch (error) {
      throw _translatePageWriteError(error);
    }
  }

  @override
  Future<MemorialPage> duplicate({
    required String sourcePageId,
    required String slug,
    required String deceasedName,
    required String deceasedGender,
    String? dedicationMessage,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthorizedException();
    }
    try {
      final row = await _client.rpc(
        'duplicate_memorial_page',
        params: <String, dynamic>{
          'p_source_page_id': sourcePageId,
          'p_slug': slug,
          'p_deceased_name': deceasedName.trim(),
          'p_deceased_gender': deceasedGender,
          'p_dedication_message': _nullIfBlank(dedicationMessage),
        },
      );
      if (row is! Map<String, dynamic>) {
        throw const AppException('تعذّر إنشاء نسخة الصفحة. أعد المحاولة.');
      }
      return MemorialPage.fromRow(row);
    } on PostgrestException catch (error) {
      throw _translatePageWriteError(error);
    }
  }

  @override
  Future<MemorialPage> update(MemorialPage page) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || page.ownerUserId != userId) {
      throw const NotAuthorizedException();
    }
    try {
      final row = await _client
          .from('memorial_pages')
          .update(page.toUpdateRow())
          .eq('id', page.id)
          .eq('owner_user_id', userId)
          .select()
          .single();
      return MemorialPage.fromRow(row);
    } on PostgrestException catch (error) {
      throw _translatePageWriteError(error);
    }
  }

  @override
  Future<void> delete(String pageId) async {
    if (_client.auth.currentUser == null) {
      throw const NotAuthorizedException();
    }
    try {
      await _client.rpc(
        'delete_memorial_page',
        params: <String, dynamic>{'p_page_id': pageId},
      );
    } on PostgrestException catch (error) {
      if (error.code == '42501') {
        throw AppException(
          'ليس لديك صلاحية حذف هذه الصفحة.',
          technical: error.message,
        );
      }
      throw AppException(
        'تعذّر حذف الصفحة. يُرجى المحاولة مرة أخرى.',
        technical: error.message,
      );
    }
  }

  static AppException _translatePageWriteError(PostgrestException error) {
    final message = error.message.toLowerCase();
    if (error.code == '23505' || message.contains('slug')) {
      return AppException(
        'اسم الرابط مستخدم بالفعل، اختر رابطًا آخر.',
        technical: error.message,
      );
    }
    if (error.code == '42501') {
      return AppException(
        'ليس لديك صلاحية تنفيذ هذا الإجراء على الصفحة.',
        technical: error.message,
      );
    }
    if (error.code == '22023' ||
        error.code == '23514' ||
        error.code == 'PGRST116') {
      return translatePostgrestError(error);
    }
    return AppException(
      'تعذّر تنفيذ العملية على الصفحة. يُرجى المحاولة مرة أخرى.',
      technical: error.message,
    );
  }

  static String? _nullIfBlank(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
