import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../../../core/storage/local_database.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/tasbeeh_counter_keys.dart';
import '../domain/tasbeeh_counter_store.dart';

/// [TasbeehCounterStore] backed by the visitor database (IndexedDB on the web,
/// an app-private file on Android/iOS).
class LocalTasbeehCounterStore implements TasbeehCounterStore {
  LocalTasbeehCounterStore({Future<Database> Function()? databaseProvider})
    : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final Future<Database> Function() _databaseProvider;

  StoreRef<String, Map<String, Object?>> get _store =>
      stringMapStoreFactory.store(LocalStores.tasbeehCounters);

  @override
  String get backendLabel =>
      kIsWeb ? 'IndexedDB (تخزين المتصفح)' : 'ملف التطبيق المحلي';

  @override
  Future<BigInt> read(String tasbeehId, {String? pageId}) async {
    final values = await readMany(<String>[tasbeehId], pageId: pageId);
    return values[tasbeehId] ?? BigInt.zero;
  }

  @override
  Future<Map<String, BigInt>> readMany(
    Iterable<String> tasbeehIds, {
    String? pageId,
  }) async {
    final ids = tasbeehIds.toList(growable: false);
    if (ids.isEmpty) return const <String, BigInt>{};
    try {
      final database = await _databaseProvider();
      final keys = ids
          .map((id) => TasbeehCounterKeys.forTasbeeh(id, pageId: pageId))
          .toList(growable: false);
      final snapshots = await _store.records(keys).getSnapshots(database);
      final result = <String, BigInt>{};
      for (final snapshot in snapshots) {
        if (snapshot == null) continue;
        final tasbeehId = TasbeehCounterKeys.tasbeehIdFrom(
          snapshot.key,
          pageId: pageId,
        );
        if (tasbeehId == null) continue;
        final raw = snapshot.value['value'];
        final value = raw is int
            ? BigInt.from(raw)
            : BigInt.tryParse('${raw ?? ''}') ?? BigInt.zero;
        result[tasbeehId] = value.isNegative ? BigInt.zero : value;
      }
      return result;
    } catch (error, stackTrace) {
      AppLogger.error('Tasbeeh counters: read failed', error, stackTrace);
      throw TasbeehStorageException(technical: error.toString());
    }
  }

  @override
  Future<void> write(String tasbeehId, BigInt value, {String? pageId}) async {
    try {
      final database = await _databaseProvider();
      await _store
          .record(TasbeehCounterKeys.forTasbeeh(tasbeehId, pageId: pageId))
          .put(database, <String, Object?>{
            'value': value.isNegative ? '0' : value.toString(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
    } catch (error, stackTrace) {
      AppLogger.error('Tasbeeh counters: write failed', error, stackTrace);
      throw TasbeehStorageException(technical: error.toString());
    }
  }

  @override
  Future<void> delete(String tasbeehId, {String? pageId}) async {
    try {
      final database = await _databaseProvider();
      await _store
          .record(TasbeehCounterKeys.forTasbeeh(tasbeehId, pageId: pageId))
          .delete(database);
    } catch (error, stackTrace) {
      AppLogger.error('Tasbeeh counters: delete failed', error, stackTrace);
      throw TasbeehStorageException(technical: error.toString());
    }
  }
}
