import '../domain/content_item.dart';
import '../domain/content_type.dart';

/// Read/write contract for published content within the repository's scope.
///
/// Implementations:
/// * [SupabaseContentRepository] — production (RLS-protected Postgres);
/// * `LocalContentRepository` — the offline demo backend used when no Supabase
///   project is configured, and by the automated tests.
abstract class ContentRepository {
  /// Published items of [type], ordered by `display_order`.
  ///
  /// A page-scoped implementation filters by its immutable page id; a legacy
  /// global implementation is limited by the database's RLS policy.
  Future<List<ContentItem>> fetchPublished(ContentType type);

  /// Every item of [type] including drafts. Requires an administrator session;
  /// RLS rejects it for anonymous callers.
  Future<List<ContentItem>> fetchAll(ContentType type);

  /// A single item by id (published rows only for anonymous callers).
  Future<ContentItem?> fetchById(ContentType type, String id);

  /// Inserts or updates. Returns the persisted record (with the database id).
  Future<ContentItem> save(ContentItem item);

  Future<void> delete(ContentType type, String id);

  Future<void> setPublished(ContentType type, String id, bool published);

  /// Persists the new order of [orderedIds] (index in the list becomes
  /// `display_order`).
  Future<void> reorder(ContentType type, List<String> orderedIds);

  /// Creates a copy of [item] as an unpublished draft.
  Future<ContentItem> duplicate(ContentItem item);

  /// Counts per content type, used by the dashboard overview.
  Future<Map<ContentType, TypeCounts>> counts();

  /// Real-time stream of published content (falls back to a single snapshot on
  /// backends without realtime support).
  Stream<List<ContentItem>> watchPublished();
}

/// Published/draft counts for one content type.
class TypeCounts {
  const TypeCounts({required this.published, required this.drafts});

  final int published;
  final int drafts;

  int get total => published + drafts;

  static const TypeCounts empty = TypeCounts(published: 0, drafts: 0);
}
