import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/app_exception.dart';
import '../domain/reminder_preferences.dart';
import 'reminder_preferences_remote_store.dart';

class SupabaseReminderPreferencesStore
    implements ReminderPreferencesRemoteStore {
  SupabaseReminderPreferencesStore(this._client);

  final SupabaseClient _client;

  static const _columns =
      'user_id,revision,manual_city,manual_country,manual_country_code,'
      'timezone_id,settings,updated_at';

  @override
  Future<ReminderPreferencesSnapshot?> fetch(String userId) async {
    _requireCurrentAccount(userId);
    final row = await _client
        .from('user_reminder_preferences')
        .select(_columns)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    _requireCurrentAccount(userId);
    final configurations = await _client
        .from('user_reminder_configurations')
        .select('id,kind,enabled,memorial_page_id,parameters')
        .eq('user_id', userId)
        .order('id');
    _requireCurrentAccount(userId);
    return _snapshotFromRow(<String, dynamic>{
      ...row,
      'configurations': configurations,
    });
  }

  @override
  Future<ReminderPreferencesSaveResult> save({
    required String userId,
    required ReminderPreferences preferences,
    required int expectedRevision,
  }) async {
    _requireCurrentAccount(userId);
    final result = await _client.rpc(
      'save_user_reminder_preferences',
      params: <String, dynamic>{
        'p_user_id': userId,
        'p_expected_revision': expectedRevision,
        'p_manual_city': preferences.manualCity?.trim(),
        'p_manual_country': preferences.manualCountry?.trim(),
        'p_manual_country_code': preferences.manualCountryCode
            ?.trim()
            .toUpperCase(),
        'p_timezone_id': preferences.manualCity == null
            ? null
            : preferences.timezoneId,
        'p_settings': preferences.toSettingsJson(),
        'p_configurations': preferences.configurationsJson,
      },
    );
    _requireCurrentAccount(userId);
    if (result is! Map) {
      throw const FormatException(
        'Invalid reminder preferences save response.',
      );
    }
    final response = Map<String, dynamic>.from(result);
    final status = response['status'];
    if (status == 'conflict') {
      final current = response['current'];
      return ReminderPreferencesSaveResult.conflict(
        current is Map
            ? _snapshotFromRow(Map<String, dynamic>.from(current))
            : null,
      );
    }
    if (status != 'saved' || response['record'] is! Map) {
      throw const FormatException('Invalid reminder preferences save status.');
    }
    return ReminderPreferencesSaveResult.saved(
      _snapshotFromRow(Map<String, dynamic>.from(response['record'] as Map)),
    );
  }

  ReminderPreferencesSnapshot _snapshotFromRow(Map<String, dynamic> row) {
    if (row['user_id'] != _client.auth.currentUser?.id) {
      throw const NotAuthorizedException(
        messageAr: 'لا يمكن الوصول إلى إعدادات حساب آخر.',
      );
    }
    final revision = row['revision'];
    final updatedAt = DateTime.tryParse('${row['updated_at'] ?? ''}');
    if (revision is! int || updatedAt == null) {
      throw const FormatException('Invalid remote reminder preferences row.');
    }
    return ReminderPreferencesSnapshot(
      preferences: ReminderPreferences.fromRemoteRow(row),
      revision: revision,
      updatedAt: updatedAt.toUtc(),
    );
  }

  void _requireCurrentAccount(String userId) {
    if (userId.trim().isEmpty || _client.auth.currentUser?.id != userId) {
      throw const NotAuthorizedException(
        messageAr: 'يرجى تسجيل الدخول بالحساب المطلوب لمزامنة الإعدادات.',
      );
    }
  }
}
