/// Base class for errors that carry a **user-facing Arabic message**.
///
/// Technical detail is kept in [technical]/[cause] for logging only; the public
/// website never renders a stack trace or an English database error.
class AppException implements Exception {
  const AppException(this.messageAr, {this._technical, this._cause});

  /// Friendly Arabic message safe to display to a visitor.
  final String messageAr;

  final String? _technical;
  final Object? _cause;

  String? get technical => _technical;
  Object? get cause => _cause;

  @override
  String toString() =>
      'AppException($messageAr'
      '${_technical == null ? '' : ' | $_technical'})';
}

/// Validation failure with per-field Arabic messages.
class ValidationException extends AppException {
  const ValidationException(
    this.fieldErrors, {
    String messageAr = 'يرجى تصحيح الحقول المميزة قبل المتابعة.',
    String? technical,
  }) : super(messageAr, technical: technical);

  /// Field key -> Arabic error message.
  final Map<String, String> fieldErrors;

  bool has(String field) => fieldErrors.containsKey(field);

  String? operator [](String field) => fieldErrors[field];
}

/// The visitor tried to reach an administrative area without a valid session.
class NotAuthorizedException extends AppException {
  const NotAuthorizedException({
    String messageAr = 'هذه الصفحة للمشرفين فقط. يرجى تسجيل الدخول.',
  }) : super(messageAr);
}

/// A record was deleted or is not published.
class NotFoundException extends AppException {
  const NotFoundException({String messageAr = 'لم يتم العثور على هذا المحتوى.'})
    : super(messageAr);
}

/// The device could not reach Supabase.
class NetworkException extends AppException {
  const NetworkException({
    String messageAr =
        'تعذّر الاتصال بالخدمة. تحقّق من اتصال الإنترنت ثم أعد المحاولة.',
    String? technical,
    Object? cause,
  }) : super(messageAr, technical: technical, cause: cause);
}

/// Local browser/app storage failed (for example IndexedDB disabled).
class LocalStorageException extends AppException {
  const LocalStorageException({
    String messageAr =
        'تعذّر الوصول إلى مساحة التخزين المحلية. قد يكون التصفح الخاص مفعّلًا.',
    String? technical,
    Object? cause,
  }) : super(messageAr, technical: technical, cause: cause);
}

/// Maps any thrown object to a friendly Arabic message.
///
/// Anything already carrying an Arabic message is passed through unchanged.
String friendlyMessage(Object? error) {
  if (error is AppException) return error.messageAr;
  if (error == null) return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';

  final text = error.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('clientexception') ||
      text.contains('network') ||
      text.contains('timeout')) {
    return const NetworkException().messageAr;
  }
  if (text.contains('jwt') ||
      text.contains('invalid login credentials') ||
      text.contains('unauthorized') ||
      text.contains('permission denied') ||
      text.contains('row-level security')) {
    return 'بيانات الدخول غير صحيحة أو لا تملك صلاحية لهذا الإجراء.';
  }
  if (text.contains('duplicate key') || text.contains('unique constraint')) {
    return 'هذا العنصر موجود بالفعل.';
  }
  if (text.contains('quotaexceeded') ||
      text.contains('indexeddb') ||
      text.contains('database is closed')) {
    return const LocalStorageException().messageAr;
  }
  return 'حدث خطأ غير متوقع. يرجى المحاولة مرة أخرى.';
}
