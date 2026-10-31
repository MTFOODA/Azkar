import '../../content/domain/content_type.dart';
import '../domain/homepage_entry.dart';

/// Contract for the dynamic global or page-scoped homepage layout.
abstract class HomepageRepository {
  /// Every layout row (enabled and disabled). Administrator-only.
  Future<List<HomepageEntry>> fetchEntries();

  /// The resolved, ordered cards a visitor sees: enabled entries whose content
  /// is still published. Orphaned entries (content deleted/unpublished) are
  /// skipped, never rendered as a broken card.
  Future<List<HomeCard>> fetchPublishedLayout();

  /// Persists the given order (list index becomes `display_order`).
  Future<void> saveOrder(List<HomepageEntry> entries);

  Future<void> setEnabled(String entryId, bool enabled);

  Future<void> remove(String entryId);

  Future<HomepageEntry> add({
    required ContentType contentType,
    required String contentId,
  });
}
