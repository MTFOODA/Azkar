import 'package:sembast/sembast.dart';

import 'local_database_stub.dart'
    if (dart.library.io) 'local_database_io.dart'
    if (dart.library.js_interop) 'local_database_web.dart';

/// The single, per-visitor database used for locally persisted state.
///
/// * **Flutter Web** — [databaseFactoryWeb] stores the database in IndexedDB,
///   which survives page reloads and browser restarts (subject to the browser's
///   storage retention policy and to the visitor not using private mode).
/// * **Android / iOS** — [databaseFactoryIo] writes an app-private file inside
///   the application support directory.
///
/// Nothing in this database is shared with other visitors: it is *visitor-local*
/// state only. Server-side Tasbeeh counters deliberately do not exist.
class LocalDatabase {
  LocalDatabase._();

  static const String databaseName = 'azkar_visitor.db';

  static Future<Database>? _instance;

  /// Opens (once) the visitor database.
  static Future<Database> instance() =>
      _instance ??= openLocalDatabase(databaseName);

  /// Overrides the database for tests.
  static void overrideForTesting(Database? database) {
    _instance = database == null ? null : Future<Database>.value(database);
  }

  static Future<void> close() async {
    final pending = _instance;
    _instance = null;
    if (pending == null) return;
    final database = await pending;
    await database.close();
  }
}

/// Store names used inside the visitor database.
class LocalStores {
  const LocalStores._();

  /// Tasbeeh counter records, keyed by `azkar_tasbeeh_<tasbeehId>`.
  static const String tasbeehCounters = 'tasbeeh_counters';

  /// Visitor preferences (theme mode, etc.).
  static const String preferences = 'preferences';

  /// Cached published content for the demo/offline backend.
  static const String demoContent = 'demo_content';

  /// Validated monthly prayer-time calendars, keyed by location and settings.
  static const String prayerCalendars = 'prayer_calendars';

  /// Account-namespaced reminder settings and pending synchronization state.
  static const String reminderPreferences = 'reminder_preferences';

  /// Device-local prayer completions; never synchronized to Supabase.
  static const String prayerCompletions = 'prayer_completions';

  /// Durable, account-scoped post-prayer Tasbeeh events in the same database.
  static const String prayerCompletionOutbox = 'prayer_completion_outbox';

  /// Account-scoped notification identifiers for cancellation on account change.
  static const String notificationSchedules = 'notification_schedules';
}
