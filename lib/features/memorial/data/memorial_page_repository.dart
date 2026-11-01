import '../../../core/utils/app_exception.dart';
import '../domain/memorial_page.dart';

abstract class MemorialPageRepository {
  Future<List<MemorialPage>> fetchOwnedPages();

  Future<MemorialPage?> fetchOwnedById(String pageId);

  Future<MemorialPage?> fetchPublishedBySlug(String slug);

  Future<MemorialPage> create({
    required String slug,
    required String deceasedName,
    required String deceasedGender,
    String? dedicationMessage,
  });

  Future<MemorialPage> duplicate({
    required String sourcePageId,
    required String slug,
    required String deceasedName,
    required String deceasedGender,
    String? dedicationMessage,
  });

  Future<MemorialPage> update(MemorialPage page);

  Future<void> delete(String pageId);
}

class UnconfiguredMemorialPageRepository implements MemorialPageRepository {
  const UnconfiguredMemorialPageRepository();

  AppException get _unavailable =>
      const AppException('تتطلب الصفحات الشخصية ربط التطبيق بمشروع Supabase.');

  @override
  Future<List<MemorialPage>> fetchOwnedPages() async => throw _unavailable;

  @override
  Future<MemorialPage?> fetchOwnedById(String pageId) async =>
      throw _unavailable;

  @override
  Future<MemorialPage?> fetchPublishedBySlug(String slug) async =>
      throw _unavailable;

  @override
  Future<MemorialPage> create({
    required String slug,
    required String deceasedName,
    required String deceasedGender,
    String? dedicationMessage,
  }) async => throw _unavailable;

  @override
  Future<MemorialPage> duplicate({
    required String sourcePageId,
    required String slug,
    required String deceasedName,
    required String deceasedGender,
    String? dedicationMessage,
  }) async => throw _unavailable;

  @override
  Future<MemorialPage> update(MemorialPage page) async => throw _unavailable;

  @override
  Future<void> delete(String pageId) async => throw _unavailable;
}
