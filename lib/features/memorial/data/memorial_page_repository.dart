import '../../../core/utils/app_exception.dart';
import '../domain/memorial_page.dart';

abstract class MemorialPageRepository {
  Future<MemorialPage?> fetchMine();

  Future<MemorialPage?> fetchPublishedBySlug(String slug);

  Future<MemorialPage> update(MemorialPage page);
}

class UnconfiguredMemorialPageRepository implements MemorialPageRepository {
  const UnconfiguredMemorialPageRepository();

  AppException get _unavailable =>
      const AppException('تتطلب الصفحات الشخصية ربط التطبيق بمشروع Supabase.');

  @override
  Future<MemorialPage?> fetchMine() async => throw _unavailable;

  @override
  Future<MemorialPage?> fetchPublishedBySlug(String slug) async =>
      throw _unavailable;

  @override
  Future<MemorialPage> update(MemorialPage page) async => throw _unavailable;
}
