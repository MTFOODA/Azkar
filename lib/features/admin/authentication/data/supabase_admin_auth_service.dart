import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/utils/app_exception.dart';
import '../../../../core/utils/app_logger.dart';
import '../domain/admin_auth_service.dart';

/// Resolves administrator authorization for the shared Supabase Auth session.
///
/// The authenticated user must have an **active** row in `admin_profiles`.
///
/// A valid Supabase user without that row cannot enter the platform dashboard.
/// Their Auth session is retained so the separate personal-page dashboard can
/// use the same Supabase account. RLS policies independently re-check
/// `admin_profiles` for every platform-administrator write.
class SupabaseAdminAuthService implements AdminAuthService {
  SupabaseAdminAuthService(this._client);

  final SupabaseClient _client;
  AdminSession? _cached;

  @override
  AdminSession? get currentSession => _cached;

  @override
  Stream<AdminSession?> authStateChanges() async* {
    yield _cached ?? await _restore();
    yield* _client.auth.onAuthStateChange.asyncMap((state) async {
      if (state.session == null) {
        _cached = null;
        return null;
      }
      try {
        final session = await _loadProfile(state.session!.user);
        _cached = session;
        return session;
      } catch (error, stackTrace) {
        AppLogger.warning('Admin profile lookup failed', error, stackTrace);
        _cached = null;
        return null;
      }
    });
  }

  Future<AdminSession?> _restore() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final session = await _loadProfile(user);
      _cached = session;
      return session;
    } catch (error, stackTrace) {
      AppLogger.warning('Admin session restore failed', error, stackTrace);
      return null;
    }
  }

  Future<AdminSession> _loadProfile(User user) async {
    final session = await _lookupProfile(user);
    if (session == null) {
      throw const NotAuthorizedException(
        messageAr: 'هذا الحساب لا يملك صلاحية إدارية على الموقع.',
      );
    }
    return session;
  }

  Future<AdminSession?> _lookupProfile(User user) async {
    final row = await _client
        .from('admin_profiles')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null || row['is_active'] != true) {
      return null;
    }
    return AdminSession(
      userId: user.id,
      email: user.email ?? row['email']?.toString() ?? '',
      displayName: row['display_name']?.toString(),
      role: row['role']?.toString() ?? 'editor',
    );
  }

  @override
  Future<AdminSession?> currentSessionForSignedInUser() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _cached = null;
      return null;
    }
    final session = await _lookupProfile(user);
    _cached = session;
    return session;
  }

  @override
  Future<void> signOut() async {
    _cached = null;
    await _client.auth.signOut();
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: '${AppConfig.siteBaseUrl}/reset-password',
    );
  }
}
