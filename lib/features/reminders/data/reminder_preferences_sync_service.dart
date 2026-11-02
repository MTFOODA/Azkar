import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/reminder_preferences.dart';
import 'local_reminder_preferences_store.dart';
import 'reminder_preferences_remote_store.dart';

class ReminderPreferencesSyncService {
  ReminderPreferencesSyncService({
    required this.localStore,
    required this.remoteStore,
    this.currentUserIdProvider,
  });

  final ReminderPreferencesLocalStore localStore;
  final ReminderPreferencesRemoteStore remoteStore;
  final String? Function()? currentUserIdProvider;
  Future<void> _operationTail = Future<void>.value();
  final Map<String, Future<ReminderSyncResult>> _syncInFlight =
      <String, Future<ReminderSyncResult>>{};
  static final Object _mergeConflict = Object();
  static final Object _missingValue = Object();

  Future<ReminderSyncResult> sync(String userId) {
    final existing = _syncInFlight[userId];
    if (existing != null) return existing;
    final future = _serialize(() => _sync(userId));
    _syncInFlight[userId] = future;
    future.then(
      (_) {
        _syncInFlight.remove(userId);
      },
      onError: (Object error, StackTrace stackTrace) {
        _syncInFlight.remove(userId);
      },
    );
    return future;
  }

  Future<ReminderSyncResult> _sync(String userId) async {
    _validateUserId(userId);
    var local = await localStore.read(userId);
    final ReminderPreferencesSnapshot? remote;
    try {
      remote = await remoteStore.fetch(userId);
      _validateUserId(userId);
    } on Object catch (error, stackTrace) {
      if (!_isNetworkFailure(error)) rethrow;
      AppLogger.warning(
        'Reminder preferences are offline; local changes remain pending.',
        error,
        stackTrace,
      );
      final preferences = local?.preferences ?? ReminderPreferences.defaults;
      return ReminderSyncResult(
        status: ReminderSyncStatus.offline,
        preferences: preferences,
      );
    }

    if (local == null || !local.isDirty) {
      if (remote != null) {
        final preferences = _preserveLocalOnlyValues(
          remote.preferences,
          local?.preferences,
        );
        final snapshot = _snapshotWithPreferences(remote, preferences);
        await localStore.markSynchronized(userId: userId, snapshot: snapshot);
        return ReminderSyncResult(
          status: ReminderSyncStatus.synchronized,
          preferences: preferences,
          serverSnapshot: snapshot,
        );
      }
      if (local != null && local.baseRevision > 0) {
        return ReminderSyncResult(
          status: ReminderSyncStatus.conflict,
          preferences: local.preferences,
          serverSnapshot: local.serverSnapshot,
        );
      }
      final defaults = ReminderPreferences.defaults;
      final initial = ReminderPreferencesSnapshot(
        preferences: defaults,
        revision: 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      await localStore.markSynchronized(userId: userId, snapshot: initial);
      return ReminderSyncResult(
        status: ReminderSyncStatus.synchronized,
        preferences: defaults,
        serverSnapshot: initial,
      );
    }

    if (remote != null && remote.revision != local.baseRevision) {
      if (remote.preferences.hasSameSyncedValues(local.preferences)) {
        final preferences = _preserveLocalOnlyValues(
          remote.preferences,
          local.preferences,
        );
        final snapshot = _snapshotWithPreferences(remote, preferences);
        await localStore.markSynchronized(userId: userId, snapshot: snapshot);
        return ReminderSyncResult(
          status: ReminderSyncStatus.synchronized,
          preferences: preferences,
          serverSnapshot: snapshot,
        );
      }
      final base = _basePreferences(local);
      if (base != null) {
        final merged = _mergeIndependentChanges(
          base: base,
          local: local.preferences,
          remote: remote.preferences,
        );
        if (merged != null) {
          await localStore.resolveConflict(
            userId: userId,
            preferences: merged,
            serverSnapshot: remote,
          );
          return _sync(userId);
        }
      }
      return ReminderSyncResult(
        status: ReminderSyncStatus.conflict,
        preferences: local.preferences,
        serverSnapshot: remote,
      );
    }
    if (remote == null && local.baseRevision != 0) {
      return ReminderSyncResult(
        status: ReminderSyncStatus.conflict,
        preferences: local.preferences,
      );
    }

    final ReminderPreferencesSaveResult saveResult;
    try {
      saveResult = await remoteStore.save(
        userId: userId,
        preferences: local.preferences,
        expectedRevision: local.baseRevision,
      );
      _validateUserId(userId);
    } on Object catch (error, stackTrace) {
      if (!_isNetworkFailure(error)) rethrow;
      AppLogger.warning(
        'Reminder preferences could not sync; local changes remain pending.',
        error,
        stackTrace,
      );
      return ReminderSyncResult(
        status: ReminderSyncStatus.offline,
        preferences: local.preferences,
      );
    }

    if (saveResult.isConflict) {
      final current = saveResult.snapshot;
      if (current != null &&
          current.preferences.hasSameSyncedValues(local.preferences)) {
        final preferences = _preserveLocalOnlyValues(
          current.preferences,
          local.preferences,
        );
        final snapshot = _snapshotWithPreferences(current, preferences);
        await localStore.markSynchronized(userId: userId, snapshot: snapshot);
        return ReminderSyncResult(
          status: ReminderSyncStatus.synchronized,
          preferences: preferences,
          serverSnapshot: snapshot,
        );
      }
      if (current != null) {
        final base = _basePreferences(local);
        if (base != null) {
          final merged = _mergeIndependentChanges(
            base: base,
            local: local.preferences,
            remote: current.preferences,
          );
          if (merged != null) {
            await localStore.resolveConflict(
              userId: userId,
              preferences: merged,
              serverSnapshot: current,
            );
            return _sync(userId);
          }
        }
      }
      return ReminderSyncResult(
        status: ReminderSyncStatus.conflict,
        preferences: local.preferences,
        serverSnapshot: current,
      );
    }

    final saved = saveResult.snapshot;
    if (saved == null) {
      throw StateError('A successful reminder save returned no snapshot.');
    }
    await localStore.markSynchronized(userId: userId, snapshot: saved);
    return ReminderSyncResult(
      status: ReminderSyncStatus.synchronized,
      preferences: saved.preferences,
      serverSnapshot: saved,
    );
  }

  Future<ReminderSyncResult> saveLocal({
    required String userId,
    required ReminderPreferences preferences,
  }) => _serialize(() async {
    _validateUserId(userId);
    await localStore.saveLocal(userId: userId, preferences: preferences);
    return _sync(userId);
  });

  Future<ReminderSyncResult> resolveConflict({
    required String userId,
    required ReminderPreferences preferences,
    required ReminderPreferencesSnapshot serverSnapshot,
  }) => _serialize(() async {
    _validateUserId(userId);
    await localStore.resolveConflict(
      userId: userId,
      preferences: preferences,
      serverSnapshot: serverSnapshot,
    );
    return _sync(userId);
  });

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  bool _isNetworkFailure(Object error) =>
      error is TimeoutException ||
      error is http.ClientException ||
      error is AuthRetryableFetchException;

  ReminderPreferences? _basePreferences(LocalReminderPreferencesState local) {
    final snapshot = local.serverSnapshot;
    if (snapshot != null && snapshot.revision == local.baseRevision) {
      return snapshot.preferences;
    }
    return local.baseRevision == 0 ? ReminderPreferences.defaults : null;
  }

  ReminderPreferences _preserveLocalOnlyValues(
    ReminderPreferences remote,
    ReminderPreferences? local,
  ) {
    if (remote.manualCity != null || local?.manualCity != null) return remote;
    return ReminderPreferences.fromJson(<String, dynamic>{
      ...remote.toJson(),
      'timezone_id': local?.timezoneId,
    });
  }

  ReminderPreferencesSnapshot _snapshotWithPreferences(
    ReminderPreferencesSnapshot snapshot,
    ReminderPreferences preferences,
  ) => ReminderPreferencesSnapshot(
    preferences: preferences,
    revision: snapshot.revision,
    updatedAt: snapshot.updatedAt,
  );

  ReminderPreferences? _mergeIndependentChanges({
    required ReminderPreferences base,
    required ReminderPreferences local,
    required ReminderPreferences remote,
  }) {
    final merged = local.toJson();
    final baseLocation = _locationValues(base);
    final localLocation = _locationValues(local);
    final remoteLocation = _locationValues(remote);
    final location = _mergeValue(baseLocation, localLocation, remoteLocation);
    if (identical(location, _mergeConflict)) return null;
    final mergedLocation = location! as Map<String, Object?>;
    merged['manual_city'] = mergedLocation['manual_city'];
    merged['manual_country'] = mergedLocation['manual_country'];
    merged['manual_country_code'] = mergedLocation['manual_country_code'];
    merged['timezone_id'] = mergedLocation['manual_city'] == null
        ? local.timezoneId
        : mergedLocation['timezone_id'];

    final baseSettings = base.toSettingsJson();
    final localSettings = local.toSettingsJson();
    final remoteSettings = remote.toSettingsJson();
    for (final key in localSettings.keys) {
      final value = _mergeValue(
        baseSettings[key],
        localSettings[key],
        remoteSettings[key],
      );
      if (identical(value, _mergeConflict)) return null;
      merged[key] = value;
    }

    final configurations = _mergeConfigurations(
      base.configurationsJson,
      local.configurationsJson,
      remote.configurationsJson,
    );
    if (configurations == null) return null;
    merged['configurations'] = configurations;
    return ReminderPreferences.fromJson(Map<String, dynamic>.from(merged));
  }

  Map<String, Object?> _locationValues(
    ReminderPreferences preferences,
  ) => <String, Object?>{
    'manual_city': preferences.manualCity,
    'manual_country': preferences.manualCountry,
    'manual_country_code': preferences.manualCountryCode,
    if (preferences.manualCity != null) 'timezone_id': preferences.timezoneId,
  };

  List<Map<String, Object?>>? _mergeConfigurations(
    List<Map<String, Object?>> base,
    List<Map<String, Object?>> local,
    List<Map<String, Object?>> remote,
  ) {
    final baseById = _configurationsById(base);
    final localById = _configurationsById(local);
    final remoteById = _configurationsById(remote);
    final ids = <String>{
      ...baseById.keys,
      ...localById.keys,
      ...remoteById.keys,
    }.toList()..sort();
    final merged = <Map<String, Object?>>[];
    for (final id in ids) {
      final value = _mergeValue(
        baseById[id] ?? _missingValue,
        localById[id] ?? _missingValue,
        remoteById[id] ?? _missingValue,
      );
      if (identical(value, _mergeConflict)) return null;
      if (!identical(value, _missingValue)) {
        merged.add(Map<String, Object?>.from(value! as Map));
      }
    }
    return merged;
  }

  Map<String, Map<String, Object?>> _configurationsById(
    List<Map<String, Object?>> configurations,
  ) => <String, Map<String, Object?>>{
    for (final configuration in configurations)
      configuration['id']! as String: configuration,
  };

  Object? _mergeValue(Object? base, Object? local, Object? remote) {
    if (identical(local, base)) return remote;
    if (identical(remote, base) || identical(local, remote)) return local;
    if (_sameValue(local, base)) return remote;
    if (_sameValue(remote, base) || _sameValue(local, remote)) return local;
    return _mergeConflict;
  }

  bool _sameValue(Object? left, Object? right) =>
      identical(left, _missingValue) || identical(right, _missingValue)
      ? identical(left, right)
      : _canonicalJson(left) == _canonicalJson(right);

  String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList(growable: false);
    return value;
  }

  void _validateUserId(String userId) {
    if (userId.trim().isEmpty) throw ArgumentError.value(userId, 'userId');
    final currentUserIdProvider = this.currentUserIdProvider;
    if (currentUserIdProvider != null && currentUserIdProvider() != userId) {
      throw const NotAuthorizedException(
        messageAr: 'يرجى تسجيل الدخول بالحساب المطلوب لمزامنة الإعدادات.',
      );
    }
  }
}
