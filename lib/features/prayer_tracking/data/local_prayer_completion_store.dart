import 'package:sembast/sembast.dart';

import '../../../core/storage/local_database.dart';
import '../../../core/utils/app_exception.dart';
import '../../prayer_times/domain/prayer_time_models.dart';
import '../domain/prayer_completion_state_machine.dart';

class LocalPrayerCompletionStore implements PrayerCompletionStateStore {
  LocalPrayerCompletionStore({
    Future<Database> Function()? databaseProvider,
    this.currentUserIdProvider,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final Future<Database> Function() _databaseProvider;
  final String? Function()? currentUserIdProvider;

  StoreRef<String, Map<String, Object?>> get _store =>
      stringMapStoreFactory.store(LocalStores.prayerCompletions);

  StoreRef<String, Map<String, Object?>> get _outbox =>
      stringMapStoreFactory.store(LocalStores.prayerCompletionOutbox);

  @override
  Future<PrayerCompletionState?> readOccurrence({
    required String userId,
    required String occurrenceId,
  }) async {
    _validateUserId(userId);
    if (occurrenceId.trim().isEmpty) {
      throw ArgumentError.value(occurrenceId, 'occurrenceId');
    }
    try {
      final database = await _databaseProvider();
      final row = await _store.record('occurrence:$occurrenceId').get(database);
      if (row == null) return null;
      final state = PrayerCompletionState.fromJson(
        Map<String, dynamic>.from(row),
      );
      if (state.identity.userId != userId ||
          state.identity.id != occurrenceId) {
        throw const FormatException('Prayer occurrence account mismatch.');
      }
      return state;
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر قراءة حالة الصلاة المحفوظة على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<List<PrayerCompletionState>> occurrencesForPrayerDate({
    required String userId,
    required DateTime localDate,
    required TrackedPrayer prayer,
  }) async {
    _validateUserId(userId);
    final dateKey = _dateKey(localDate);
    try {
      final database = await _databaseProvider();
      final rows = await _store.find(
        database,
        finder: Finder(
          filter: Filter.and(<Filter>[
            Filter.equals('user_id', userId),
            Filter.equals('local_date', dateKey),
            Filter.equals('prayer', prayer.id),
          ]),
        ),
      );
      return rows
          .where((row) => row.key.startsWith('occurrence:'))
          .map(
            (row) => _readOccurrenceRow(
              userId: userId,
              occurrenceId: row.key.substring('occurrence:'.length),
              row: row.value,
            ),
          )
          .toList(growable: false);
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر قراءة حالات الصلاة المحفوظة على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<List<PrayerCompletionState>> occurrencesForAccount({
    required String userId,
  }) async {
    _validateUserId(userId);
    try {
      final database = await _databaseProvider();
      final rows = await _store.find(
        database,
        finder: Finder(filter: Filter.equals('user_id', userId)),
      );
      return rows
          .where((row) => row.key.startsWith('occurrence:'))
          .map(
            (row) => _readOccurrenceRow(
              userId: userId,
              occurrenceId: row.key.substring('occurrence:'.length),
              row: row.value,
            ),
          )
          .toList(growable: false);
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر قراءة حالات الصلاة المحفوظة على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<List<PrayerCompletionState>> pendingOccurrences({
    required String userId,
  }) async {
    _validateUserId(userId);
    try {
      final database = await _databaseProvider();
      final rows = await _store.find(
        database,
        finder: Finder(filter: Filter.equals('user_id', userId)),
      );
      return rows
          .where(
            (row) =>
                row.key.startsWith('occurrence:') &&
                row.value['pending_reminder_ordinal'] is int,
          )
          .map(
            (row) => _readOccurrenceRow(
              userId: userId,
              occurrenceId: row.key.substring('occurrence:'.length),
              row: row.value,
            ),
          )
          .toList(growable: false);
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر قراءة التذكيرات المعلّقة على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<List<PrayerCompletionTasbeehEvent>> pendingTasbeehEvents(
    String userId,
  ) async {
    _validateUserId(userId);
    try {
      final database = await _databaseProvider();
      final rows = await _outbox.find(
        database,
        finder: Finder(
          filter: Filter.and(<Filter>[
            Filter.equals('user_id', userId),
            Filter.equals('acknowledged', false),
          ]),
        ),
      );
      return rows
          .map(
            (row) => PrayerCompletionTasbeehEvent.fromJson(
              Map<String, dynamic>.from(row.value),
            ),
          )
          .toList(growable: false);
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر قراءة أحداث التسبيح المعلّقة على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<void> acknowledgeTasbeehEvent({
    required String userId,
    required String eventId,
    required String claimId,
  }) async {
    _validateUserId(userId);
    if (eventId.trim().isEmpty) throw ArgumentError.value(eventId, 'eventId');
    try {
      final database = await _databaseProvider();
      await database.transaction((transaction) async {
        final record = _outbox.record(eventId);
        final row = await record.get(transaction);
        if (row == null) return;
        if (row['user_id'] != userId) {
          throw const FormatException('Tasbeeh outbox account mismatch.');
        }
        if (row['acknowledged'] == true) return;
        if (row['claim_id'] != claimId) {
          throw StateError('Tasbeeh outbox claim is no longer owned.');
        }
        await record.put(transaction, <String, Object?>{
          ...row,
          'acknowledged': true,
          'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
        });
      });
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر تأكيد معالجة حدث التسبيح.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<bool> claimTasbeehEvent({
    required String userId,
    required String eventId,
    required String claimId,
    required DateTime now,
    required Duration leaseDuration,
  }) async {
    _validateUserId(userId);
    if (eventId.trim().isEmpty ||
        claimId.trim().isEmpty ||
        leaseDuration <= Duration.zero) {
      throw ArgumentError('Invalid Tasbeeh outbox claim.');
    }
    try {
      final database = await _databaseProvider();
      return await database.transaction((transaction) async {
        final record = _outbox.record(eventId);
        final row = await record.get(transaction);
        if (row == null) return false;
        if (row['user_id'] != userId ||
            row['id'] != eventId ||
            row['acknowledged'] is! bool) {
          throw const FormatException('Tasbeeh outbox account mismatch.');
        }
        if (row['acknowledged'] == true) return false;
        final leaseUntil = DateTime.tryParse('${row['lease_until'] ?? ''}');
        if (leaseUntil != null && leaseUntil.isAfter(now.toUtc())) return false;
        await record.put(transaction, <String, Object?>{
          ...row,
          'claim_id': claimId,
          'lease_until': now.toUtc().add(leaseDuration).toIso8601String(),
        });
        return true;
      });
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر استلام حدث التسبيح لمعالجته.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<void> releaseTasbeehEvent({
    required String userId,
    required String eventId,
    required String claimId,
  }) async {
    _validateUserId(userId);
    try {
      final database = await _databaseProvider();
      await database.transaction((transaction) async {
        final record = _outbox.record(eventId);
        final row = await record.get(transaction);
        if (row == null || row['user_id'] != userId) return;
        if (row['claim_id'] != claimId || row['acknowledged'] == true) return;
        await record.put(transaction, <String, Object?>{
          ...row,
          'claim_id': null,
          'lease_until': null,
        });
      });
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر إعادة حدث التسبيح إلى قائمة الانتظار.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  @override
  Future<PrayerCompletionTransaction> transact({
    required String userId,
    required PrayerOccurrenceIdentity identity,
    required PrayerCompletionState Function(PrayerCompletionState? current)
    transition,
  }) async {
    _validateUserId(userId);
    if (identity.userId != userId) {
      throw const NotAuthorizedException(
        messageAr: 'لا يمكن تغيير حالة صلاة لحساب آخر.',
      );
    }
    try {
      final database = await _databaseProvider();
      return await database.transaction((transaction) async {
        final record = _store.record('occurrence:${identity.id}');
        final row = await record.get(transaction);
        final previous = row == null
            ? null
            : _readOccurrenceRow(
                userId: userId,
                occurrenceId: identity.id,
                row: row,
              );
        if (previous != null &&
            !previous.identity.hasSameOccurrence(identity)) {
          throw const FormatException('Prayer occurrence identity mismatch.');
        }
        final current = transition(previous);
        if (!current.identity.hasSameOccurrence(identity)) {
          throw const FormatException(
            'Prayer transition changed the occurrence identity.',
          );
        }
        await record.put(transaction, current.toJson());
        if (previous?.tasbeehEventId == null &&
            current.tasbeehEventId != null) {
          final event = PrayerCompletionTasbeehEvent(
            id: current.tasbeehEventId!,
            userId: userId,
            localDate: current.identity.localDate,
            prayer: current.identity.prayer,
            timezoneId: current.identity.timezoneId,
            timezoneOffsetMinutes: current.identity.timezoneOffsetMinutes,
            occurredAt: current.completedAt!,
          );
          await _outbox.record(event.id).put(transaction, <String, Object?>{
            ...event.toJson(),
            'acknowledged': false,
            'claim_id': null,
            'lease_until': null,
          });
        }
        return PrayerCompletionTransaction(
          previous: previous,
          current: current,
        );
      });
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر تحديث حالة الصلاة المحفوظة على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  PrayerCompletionState _readOccurrenceRow({
    required String userId,
    required String occurrenceId,
    required Map<String, Object?> row,
  }) {
    final state = PrayerCompletionState.fromJson(
      Map<String, dynamic>.from(row),
    );
    if (state.identity.userId != userId || state.identity.id != occurrenceId) {
      throw const FormatException('Prayer occurrence account mismatch.');
    }
    return state;
  }

  String _key(String userId, DateTime localDate, PrayerName prayer) =>
      '$userId:${localDate.year.toString().padLeft(4, '0')}-'
      '${localDate.month.toString().padLeft(2, '0')}-'
      '${localDate.day.toString().padLeft(2, '0')}:${prayer.id}';

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> markCompleted({
    required String userId,
    required DateTime localDate,
    required PrayerName prayer,
    required bool isCompleted,
  }) async {
    _validateUserId(userId);
    final date = DateTime.utc(localDate.year, localDate.month, localDate.day);
    try {
      final database = await _databaseProvider();
      final record = _store.record(_key(userId, date, prayer));
      if (!isCompleted) {
        await record.delete(database);
        return;
      }
      await record.put(database, <String, Object?>{
        'user_id': userId,
        'local_date': date.toIso8601String(),
        'prayer': prayer.id,
        'completed': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر حفظ حالة الصلاة على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  Future<bool> isCompleted({
    required String userId,
    required DateTime localDate,
    required PrayerName prayer,
  }) async {
    _validateUserId(userId);
    final date = DateTime.utc(localDate.year, localDate.month, localDate.day);
    try {
      final database = await _databaseProvider();
      final row = await _store.record(_key(userId, date, prayer)).get(database);
      return row?['user_id'] == userId && row?['completed'] == true;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر قراءة حالة الصلاة المحفوظة على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  void _validateUserId(String userId) {
    if (userId.trim().isEmpty) throw ArgumentError.value(userId, 'userId');
    final currentUserIdProvider = this.currentUserIdProvider;
    if (currentUserIdProvider != null && currentUserIdProvider() != userId) {
      throw const NotAuthorizedException(
        messageAr: 'يرجى تسجيل الدخول بالحساب المطلوب للوصول إلى حالة الصلاة.',
      );
    }
  }
}
