import 'package:sembast/sembast.dart';

import '../../../core/storage/local_database.dart';
import '../domain/local_notification.dart';

abstract interface class NotificationScheduleRegistry {
  Future<Map<String, int>> schedules(String accountId);

  Future<String?> stableKeyForId(String accountId, int notificationId);

  Future<void> register({
    required String accountId,
    required String stableKey,
    required int notificationId,
  });

  Future<List<int>> notificationIds(String accountId);

  Future<void> remove({required String accountId, required int notificationId});
}

class SembastNotificationScheduleRegistry
    implements NotificationScheduleRegistry {
  static const int maxPendingNotificationsPerAccount = 60;

  SembastNotificationScheduleRegistry({
    Future<Database> Function()? databaseProvider,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final Future<Database> Function() _databaseProvider;

  StoreRef<String, Map<String, Object?>> get _store =>
      stringMapStoreFactory.store(LocalStores.notificationSchedules);

  @override
  Future<Map<String, int>> schedules(String accountId) async {
    _validateAccount(accountId);
    final row = await _record(accountId).get(await _databaseProvider());
    return _readIds(
      accountId,
      row,
    ).map((id, stableKey) => MapEntry(stableKey! as String, int.parse(id)));
  }

  @override
  Future<String?> stableKeyForId(String accountId, int notificationId) async {
    final row = await _record(accountId).get(await _databaseProvider());
    final values = _readIds(accountId, row);
    final key = values['$notificationId'];
    return key is String ? key : null;
  }

  @override
  Future<void> register({
    required String accountId,
    required String stableKey,
    required int notificationId,
  }) async {
    _validateAccount(accountId);
    final database = await _databaseProvider();
    await database.transaction((transaction) async {
      final record = _record(accountId);
      final row = await record.get(transaction);
      final ids = _readIds(accountId, row);
      for (final candidate in await _store.find(transaction)) {
        if (candidate.key == 'account:$accountId') continue;
        final owner = candidate.value['account_id'];
        if (owner is! String || candidate.key != 'account:$owner') {
          throw const FormatException(
            'Invalid notification schedule registry ownership.',
          );
        }
        final ownerIds = _readIds(owner, candidate.value);
        if (owner != accountId && ownerIds.containsKey('$notificationId')) {
          throw StateError(
            'A notification identifier is already registered to another account.',
          );
        }
      }
      final existing = ids['$notificationId'];
      if (existing != null && existing != stableKey) {
        throw StateError('A stable notification identifier collided.');
      }
      final duplicateId = ids.entries.cast<MapEntry<String, Object?>>().where(
        (entry) => entry.value == stableKey && entry.key != '$notificationId',
      );
      if (duplicateId.isNotEmpty) {
        throw StateError('A stable notification key resolved inconsistently.');
      }
      if (existing == null && ids.length >= maxPendingNotificationsPerAccount) {
        throw const NotificationScheduleLimitException();
      }
      ids['$notificationId'] = stableKey;
      await record.put(transaction, <String, Object?>{
        'account_id': accountId,
        'notifications': ids,
      });
    });
  }

  @override
  Future<List<int>> notificationIds(String accountId) async {
    _validateAccount(accountId);
    final row = await _record(accountId).get(await _databaseProvider());
    return _readIds(accountId, row).keys.map(int.parse).toList(growable: false);
  }

  @override
  Future<void> remove({
    required String accountId,
    required int notificationId,
  }) async {
    _validateAccount(accountId);
    final database = await _databaseProvider();
    await database.transaction((transaction) async {
      final record = _record(accountId);
      final row = await record.get(transaction);
      final ids = _readIds(accountId, row)..remove('$notificationId');
      if (ids.isEmpty) {
        await record.delete(transaction);
      } else {
        await record.put(transaction, <String, Object?>{
          'account_id': accountId,
          'notifications': ids,
        });
      }
    });
  }

  RecordRef<String, Map<String, Object?>> _record(String accountId) {
    _validateAccount(accountId);
    return _store.record('account:$accountId');
  }

  Map<String, Object?> _readIds(String accountId, Map<String, Object?>? row) {
    if (row == null) return <String, Object?>{};
    if (row['account_id'] != accountId || row['notifications'] is! Map) {
      throw const FormatException('Invalid notification schedule registry.');
    }
    final notifications = Map<String, Object?>.from(
      row['notifications']! as Map,
    );
    for (final entry in notifications.entries) {
      final id = int.tryParse(entry.key);
      if (id == null ||
          id < 0 ||
          id > 0x7fffffff ||
          entry.value is! String ||
          (entry.value! as String).trim().isEmpty) {
        throw const FormatException('Invalid notification schedule registry.');
      }
    }
    return notifications;
  }

  void _validateAccount(String accountId) {
    if (accountId.trim().isEmpty) {
      throw ArgumentError.value(accountId, 'accountId');
    }
  }
}
