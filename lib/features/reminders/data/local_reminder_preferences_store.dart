import 'package:sembast/sembast.dart';

import '../../../core/storage/local_database.dart';
import '../../../core/utils/app_exception.dart';
import '../domain/reminder_preferences.dart';

abstract interface class ReminderPreferencesLocalStore {
  Future<LocalReminderPreferencesState?> read(String userId);

  Future<void> saveLocal({
    required String userId,
    required ReminderPreferences preferences,
  });

  Future<void> markSynchronized({
    required String userId,
    required ReminderPreferencesSnapshot snapshot,
  });

  Future<void> resolveConflict({
    required String userId,
    required ReminderPreferences preferences,
    required ReminderPreferencesSnapshot serverSnapshot,
  });
}

class SembastReminderPreferencesStore implements ReminderPreferencesLocalStore {
  SembastReminderPreferencesStore({
    Future<Database> Function()? databaseProvider,
    this.currentUserIdProvider,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final Future<Database> Function() _databaseProvider;
  final String? Function()? currentUserIdProvider;

  StoreRef<String, Map<String, Object?>> get _store =>
      stringMapStoreFactory.store(LocalStores.reminderPreferences);

  String _key(String userId) => 'user:$userId';

  @override
  Future<LocalReminderPreferencesState?> read(String userId) async {
    _validateUserId(userId);
    try {
      final database = await _databaseProvider();
      final row = await _store.record(_key(userId)).get(database);
      if (row == null) return null;
      if (row['user_id'] != userId) {
        throw const FormatException('Reminder settings account key mismatch.');
      }
      final rawPreferences = row['preferences'];
      final rawRevision = row['base_revision'];
      if (rawPreferences is! Map ||
          rawRevision is! int ||
          row['is_dirty'] is! bool) {
        throw const FormatException('Invalid local reminder settings.');
      }
      final rawServer = row['server_snapshot'];
      return LocalReminderPreferencesState(
        preferences: ReminderPreferences.fromJson(
          Map<String, dynamic>.from(rawPreferences),
        ),
        baseRevision: rawRevision,
        isDirty: row['is_dirty'] as bool,
        serverSnapshot: rawServer is Map
            ? _snapshotFromJson(Map<String, dynamic>.from(rawServer))
            : null,
      );
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر قراءة إعدادات التذكير المحفوظة على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<void> saveLocal({
    required String userId,
    required ReminderPreferences preferences,
  }) async {
    _validateUserId(userId);
    try {
      final database = await _databaseProvider();
      await database.transaction((transaction) async {
        final record = _store.record(_key(userId));
        final previous = await record.get(transaction);
        final current = previous == null
            ? null
            : await _stateFromRow(userId, previous);
        await record.put(transaction, <String, Object?>{
          'user_id': userId,
          'preferences': preferences.toJson(),
          'base_revision': current?.baseRevision ?? 0,
          'is_dirty': true,
          'server_snapshot': current?.serverSnapshot == null
              ? null
              : _snapshotToJson(current!.serverSnapshot!),
        });
      });
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر حفظ إعدادات التذكير على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<void> markSynchronized({
    required String userId,
    required ReminderPreferencesSnapshot snapshot,
  }) async {
    _validateUserId(userId);
    try {
      final database = await _databaseProvider();
      await _store.record(_key(userId)).put(database, <String, Object?>{
        'user_id': userId,
        'preferences': snapshot.preferences.toJson(),
        'base_revision': snapshot.revision,
        'is_dirty': false,
        'server_snapshot': _snapshotToJson(snapshot),
      });
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر حفظ حالة مزامنة إعدادات التذكير.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<void> resolveConflict({
    required String userId,
    required ReminderPreferences preferences,
    required ReminderPreferencesSnapshot serverSnapshot,
  }) async {
    _validateUserId(userId);
    try {
      final database = await _databaseProvider();
      await _store.record(_key(userId)).put(database, <String, Object?>{
        'user_id': userId,
        'preferences': preferences.toJson(),
        'base_revision': serverSnapshot.revision,
        'is_dirty': true,
        'server_snapshot': _snapshotToJson(serverSnapshot),
      });
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر حفظ اختيار حل تعارض إعدادات التذكير.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  Future<LocalReminderPreferencesState> _stateFromRow(
    String userId,
    Map<String, Object?> row,
  ) async {
    if (row['user_id'] != userId ||
        row['preferences'] is! Map ||
        row['base_revision'] is! int ||
        row['is_dirty'] is! bool) {
      throw const FormatException('Invalid local reminder settings.');
    }
    final server = row['server_snapshot'];
    return LocalReminderPreferencesState(
      preferences: ReminderPreferences.fromJson(
        Map<String, dynamic>.from(row['preferences']! as Map),
      ),
      baseRevision: row['base_revision']! as int,
      isDirty: row['is_dirty']! as bool,
      serverSnapshot: server is Map
          ? _snapshotFromJson(Map<String, dynamic>.from(server))
          : null,
    );
  }

  Map<String, Object?> _snapshotToJson(ReminderPreferencesSnapshot snapshot) =>
      <String, Object?>{
        'preferences': snapshot.preferences.toJson(),
        'revision': snapshot.revision,
        'updated_at': snapshot.updatedAt.toUtc().toIso8601String(),
      };

  ReminderPreferencesSnapshot _snapshotFromJson(Map<String, dynamic> json) {
    final preferences = json['preferences'];
    final revision = json['revision'];
    final updatedAt = DateTime.tryParse('${json['updated_at'] ?? ''}');
    if (preferences is! Map || revision is! int || updatedAt == null) {
      throw const FormatException('Invalid local server snapshot.');
    }
    return ReminderPreferencesSnapshot(
      preferences: ReminderPreferences.fromJson(
        Map<String, dynamic>.from(preferences),
      ),
      revision: revision,
      updatedAt: updatedAt.toUtc(),
    );
  }

  void _validateUserId(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError.value(userId, 'userId');
    }
    final currentUserIdProvider = this.currentUserIdProvider;
    if (currentUserIdProvider != null && currentUserIdProvider() != userId) {
      throw const NotAuthorizedException(
        messageAr: 'يرجى تسجيل الدخول بالحساب المطلوب للوصول إلى الإعدادات.',
      );
    }
  }
}
