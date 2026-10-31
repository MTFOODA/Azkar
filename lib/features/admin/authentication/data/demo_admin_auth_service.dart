import 'dart:async';

import '../../../../core/utils/app_exception.dart';
import '../domain/admin_auth_service.dart';

/// Authentication for the offline demo backend.
///
/// This is intentionally only available when no Supabase project is configured
/// (or when `AZKAR_DEMO_MODE=true`). It protects the demo dashboard from casual
/// access, but it is NOT a production authentication mechanism: use Supabase
/// Auth + `admin_profiles` + RLS for a deployed site.
class DemoAdminAuthService implements AdminAuthService {
  DemoAdminAuthService({required this.email, required this.password});

  final String email;
  final String password;

  final StreamController<AdminSession?> _controller =
      StreamController<AdminSession?>.broadcast();
  AdminSession? _session;

  @override
  AdminSession? get currentSession => _session;

  @override
  Stream<AdminSession?> authStateChanges() async* {
    yield _session;
    yield* _controller.stream;
  }

  @override
  Future<AdminSession?> currentSessionForSignedInUser() async => _session;

  Future<AdminSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (this.email.trim().isEmpty || this.password.isEmpty) {
      throw const AppException(
        'بيانات دخول العرض التجريبي غير مهيأة. '
        'عيّن AZKAR_DEMO_ADMIN_EMAIL وAZKAR_DEMO_ADMIN_PASSWORD.',
      );
    }
    // A small delay makes the UI behave like a real sign-in without pretending
    // to contact a remote service.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (email.trim().toLowerCase() != this.email.toLowerCase() ||
        password != this.password) {
      throw const AppException('بيانات الدخول التجريبية غير صحيحة.');
    }
    _session = AdminSession(
      userId: 'demo-admin',
      email: this.email.trim(),
      displayName: 'مشرف تجريبي',
      role: 'owner',
      isDemo: true,
    );
    _controller.add(_session);
    return _session!;
  }

  @override
  Future<void> signOut() async {
    _session = null;
    _controller.add(null);
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    throw const AppException(
      'استعادة كلمة المرور متاحة عند ربط المشروع بـ Supabase.',
    );
  }

  Future<void> dispose() => _controller.close();
}
