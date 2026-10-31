import '../../../core/utils/app_exception.dart';

/// Persistence contract for visitor-local Tasbeeh counters.
///
/// Implementations must be isolated per browser profile / app installation and
/// must never write to a shared server counter.
abstract class TasbeehCounterStore {
  /// Reads the persisted value for [tasbeehId] (0 when unknown).
  Future<BigInt> read(String tasbeehId, {String? pageId});

  /// Persists [value] for [tasbeehId].
  Future<void> write(String tasbeehId, BigInt value, {String? pageId});

  /// Removes the persisted value for [tasbeehId].
  Future<void> delete(String tasbeehId, {String? pageId});

  /// Bulk read used to hydrate a whole Tasbeeh page in a single round trip.
  Future<Map<String, BigInt>> readMany(
    Iterable<String> tasbeehIds, {
    String? pageId,
  });

  /// Human readable identifier of the backend, shown in the admin settings page
  /// (for example `IndexedDB` or `App file`).
  String get backendLabel;
}

/// Thrown when the visitor's browser refuses access to local storage.
class TasbeehStorageException extends LocalStorageException {
  const TasbeehStorageException({super.technical})
    : super(
        messageAr: 'تعذّر حفظ عدّاد التسبيح في هذا المتصفح. تأكد من عدم استخدام وضع التصفح الخاص.',
      );
}
