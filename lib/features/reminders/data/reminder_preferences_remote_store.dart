import '../domain/reminder_preferences.dart';

class ReminderPreferencesSaveResult {
  const ReminderPreferencesSaveResult.saved(this.snapshot) : isConflict = false;

  const ReminderPreferencesSaveResult.conflict(this.snapshot)
    : isConflict = true;

  final bool isConflict;
  final ReminderPreferencesSnapshot? snapshot;
}

abstract interface class ReminderPreferencesRemoteStore {
  Future<ReminderPreferencesSnapshot?> fetch(String userId);

  Future<ReminderPreferencesSaveResult> save({
    required String userId,
    required ReminderPreferences preferences,
    required int expectedRevision,
  });
}
