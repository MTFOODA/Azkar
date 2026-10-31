/// Builds the storage keys used for visitor-local Tasbeeh counters.
///
/// The key is derived from the **immutable Tasbeeh id**, never from its text:
/// an administrator can freely edit the wording of "سبحان الله" without resetting
/// the visitor's count, and brand-new cards always start at zero because they get
/// a brand-new id.
class TasbeehCounterKeys {
  const TasbeehCounterKeys._();

  static const String prefix = 'azkar_tasbeeh_';

  /// `azkar_tasbeeh_<tasbeehId>` for global cards, or
  /// `azkar_tasbeeh_<pageId>_<tasbeehId>` for page-scoped cards.
  static String forTasbeeh(String tasbeehId, {String? pageId}) {
    final id = tasbeehId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(
        tasbeehId,
        'tasbeehId',
        'Tasbeeh id must not be empty',
      );
    }
    final page = pageId?.trim();
    return page == null || page.isEmpty ? '$prefix$id' : '$prefix${page}_$id';
  }

  /// Extracts the Tasbeeh id from a storage key (diagnostics/tests).
  static String? tasbeehIdFrom(String key, {String? pageId}) {
    final page = pageId?.trim();
    if (page == null || page.isEmpty) {
      return key.startsWith(prefix) ? key.substring(prefix.length) : null;
    }
    final pagePrefix = '$prefix${page}_';
    return key.startsWith(pagePrefix) ? key.substring(pagePrefix.length) : null;
  }
}
