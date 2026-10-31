import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/account_auth_service.dart';

class SupabaseAccountAuthService implements AccountAuthService {
  SupabaseAccountAuthService(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      final normalizedName = displayName.trim();
      const pageTitlePrefix = 'صفحة الأذكار الخاصة بـ ';
      final availableNameLength = 160 - pageTitlePrefix.runes.length;
      final pageTitle =
          '$pageTitlePrefix${String.fromCharCodes(normalizedName.runes.take(availableNameLength))}';
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: AppConfig.authRedirectUrl('/dashboard'),
        data: <String, dynamic>{
          'display_name': normalizedName,
          'page_title': pageTitle,
        },
      );
      return response.session != null;
    } on AuthRetryableFetchException catch (error, stackTrace) {
      AppLogger.warning(
        'Account registration network failure',
        error,
        stackTrace,
      );
      throw NetworkException(technical: error.message, cause: error);
    } on AuthException catch (error, stackTrace) {
      AppLogger.warning('Account registration failed', error, stackTrace);
      throw AppException(_translateAuthError(error), technical: error.message);
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthRetryableFetchException catch (error, stackTrace) {
      AppLogger.warning('Account sign-in network failure', error, stackTrace);
      throw NetworkException(technical: error.message, cause: error);
    } on AuthException catch (error, stackTrace) {
      AppLogger.warning('Account sign-in failed', error, stackTrace);
      throw AppException(_translateAuthError(error), technical: error.message);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: AppConfig.authRedirectUrl('/reset-password'),
      );
    } on AuthRetryableFetchException catch (error, stackTrace) {
      AppLogger.warning(
        'Account password reset network failure',
        error,
        stackTrace,
      );
      throw NetworkException(technical: error.message, cause: error);
    } on AuthException catch (error, stackTrace) {
      AppLogger.warning('Account password reset failed', error, stackTrace);
      throw AppException(_translateAuthError(error), technical: error.message);
    }
  }

  @override
  Future<void> updatePassword(String password) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthRetryableFetchException catch (error, stackTrace) {
      AppLogger.warning(
        'Account password update network failure',
        error,
        stackTrace,
      );
      throw NetworkException(technical: error.message, cause: error);
    } on AuthException catch (error, stackTrace) {
      AppLogger.warning('Account password update failed', error, stackTrace);
      throw AppException(_translateAuthError(error), technical: error.message);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  String _translateAuthError(AuthException error) {
    final message = error.message.toLowerCase();
    if (message.contains('already registered') ||
        message.contains('already been registered') ||
        message.contains('user already exists')) {
      return 'تعذّر إنشاء الحساب. إذا كان لديك حساب، جرّب تسجيل الدخول '
          'أو استعادة كلمة المرور.';
    }
    if (message.contains('slug') ||
        message.contains('memorial_pages_slug') ||
        message.contains('duplicate key') ||
        message.contains('unique constraint')) {
      return 'هذا الرابط غير صالح أو مستخدم بالفعل. اختر رابطًا آخر.';
    }
    if (message.contains('invalid login credentials')) {
      return 'بيانات الدخول غير صحيحة.';
    }
    if (message.contains('email not confirmed')) {
      return 'يرجى تأكيد البريد الإلكتروني قبل تسجيل الدخول.';
    }
    if (message.contains('password should be') ||
        message.contains('password must')) {
      return 'كلمة المرور لا تستوفي متطلبات الأمان.';
    }
    if (message.contains('invalid email') ||
        message.contains('email address is invalid')) {
      return 'أدخل بريدًا إلكترونيًا صحيحًا.';
    }
    if (message.contains('rate limit') || error.statusCode == '429') {
      return 'محاولات كثيرة جدًا. انتظر قليلًا ثم أعد المحاولة.';
    }
    if (message.contains('network') ||
        message.contains('socket') ||
        message.contains('fetch') ||
        message.contains('connection')) {
      return const NetworkException().messageAr;
    }
    return 'تعذّر إتمام العملية. تحقق من البيانات ثم أعد المحاولة.';
  }
}
