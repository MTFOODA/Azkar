/// A signed-in administrator.
class AdminSession {
  const AdminSession({
    required this.userId,
    required this.email,
    this.displayName,
    this.role = 'editor',
    this.isDemo = false,
  });

  final String userId;
  final String email;
  final String? displayName;

  /// `owner` can manage other administrators; `editor` can manage content.
  final String role;

  /// True when the session comes from the offline demo backend.
  final bool isDemo;

  bool get isOwner => role == 'owner';

  String get label => (displayName != null && displayName!.trim().isNotEmpty)
      ? displayName!.trim()
      : email;

  String get roleLabelAr => switch (role) {
    'owner' => 'مالك الموقع',
    _ => 'محرر محتوى',
  };
}

/// Authentication contract for the admin dashboard.
///
/// The public website never touches this: visitors are anonymous.
abstract class AdminAuthService {
  AdminSession? get currentSession;

  Stream<AdminSession?> authStateChanges();

  /// Resolves the current Supabase user against the trusted admin profile.
  Future<AdminSession?> currentSessionForSignedInUser();

  Future<void> signOut();

  /// Sends a password-reset email (no-op for the demo backend).
  Future<void> sendPasswordReset(String email);
}
