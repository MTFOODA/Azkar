import 'dart:async';

import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:azkar/features/prayer_tracking/data/local_prayer_completion_store.dart';
import 'package:azkar/features/reminders/data/local_reminder_preferences_store.dart';
import 'package:azkar/features/reminders/data/reminder_preferences_remote_store.dart';
import 'package:azkar/features/reminders/data/reminder_preferences_sync_service.dart';
import 'package:azkar/features/reminders/data/supabase_reminder_preferences_store.dart';
import 'package:azkar/features/reminders/domain/reminder_preferences.dart';
import 'package:azkar/core/utils/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('reminder categories are disabled until explicitly enabled', () {
    final preferences = ReminderPreferences.defaults;

    expect(preferences.prayerRemindersEnabled, isFalse);
    expect(preferences.prayerTimeNotificationsEnabled, isFalse);
    expect(preferences.postPrayerTasbeehEnabled, isFalse);
    expect(preferences.morningAzkarEnabled, isFalse);
    expect(preferences.eveningAzkarEnabled, isFalse);
    expect(preferences.fridayKahfEnabled, isFalse);
    expect(preferences.configurations, isEmpty);
  });

  test('remote preference payload excludes device-only location timezone', () {
    final preferences = ReminderPreferences(
      timezoneId: 'America/New_York',
      configurations: <ReminderConfiguration>[
        ReminderConfiguration(
          id: 'friday-kahf',
          kind: 'weekly',
          enabled: true,
          parameters: const <String, Object?>{'weekday': 5},
        ),
      ],
    );

    expect(preferences.toSettingsJson().containsKey('timezone_id'), isFalse);
    expect(
      preferences.hasSameSyncedValues(
        ReminderPreferences(configurations: preferences.configurations),
      ),
      isTrue,
    );
    for (final sensitiveKey in ['coordinates', ' Location ', 'Latitude']) {
      expect(
        () => ReminderConfiguration(
          id: 'gps',
          kind: 'custom',
          enabled: true,
          parameters: <String, Object?>{
            'metadata': <String, Object?>{
              sensitiveKey: <double>[30.0, 31.0],
            },
          },
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => ReminderPreferences(manualCountryCode: 'EG'),
      throwsArgumentError,
    );
  });

  test('nested configuration parameters are copied and immutable', () {
    final nested = <String, Object?>{'label': 'Friday'};
    final input = <String, Object?>{'metadata': nested};
    final configuration = ReminderConfiguration(
      id: 'friday',
      kind: 'weekly',
      enabled: true,
      parameters: input,
    );

    nested['label'] = 'Changed';
    expect((configuration.parameters['metadata']! as Map)['label'], 'Friday');
    expect(
      () => (configuration.parameters['metadata']! as Map)['label'] = 'No',
      throwsUnsupportedError,
    );
  });

  test(
    'local settings are account-scoped and offline edits stay pending',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final local = SembastReminderPreferencesStore(
        databaseProvider: () async => database,
      );
      final remote = _FakeReminderRemoteStore();
      final service = ReminderPreferencesSyncService(
        localStore: local,
        remoteStore: remote,
      );
      final selected = ReminderPreferences(
        manualCity: 'Cairo',
        manualCountry: 'Egypt',
        manualCountryCode: 'EG',
        timezoneId: 'Africa/Cairo',
        calculationMethod: PrayerCalculationMethod.egyptianGeneralAuthority,
      );

      await service.saveLocal(userId: 'account-a', preferences: selected);
      expect(
        (await service.sync('account-a')).status,
        ReminderSyncStatus.synchronized,
      );
      expect(remote.records['account-a']?.preferences.manualCity, 'Cairo');
      expect(await local.read('account-b'), isNull);

      final pending = ReminderPreferences(
        manualCity: 'Alexandria',
        manualCountry: 'Egypt',
        manualCountryCode: 'EG',
        timezoneId: 'Africa/Cairo',
      );
      remote.fetchError = http.ClientException('offline');
      await service.saveLocal(userId: 'account-a', preferences: pending);
      final offline = await service.sync('account-a');

      expect(offline.status, ReminderSyncStatus.offline);
      expect(offline.preferences.manualCity, 'Alexandria');
      final localState = await local.read('account-a');
      expect(localState?.isDirty, isTrue);
      expect(localState?.preferences.manualCity, 'Alexandria');
    },
  );

  test(
    'local stores reject stale account identifiers after account switch',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      var activeUserId = 'account-a';
      final preferences = SembastReminderPreferencesStore(
        databaseProvider: () async => database,
        currentUserIdProvider: () => activeUserId,
      );
      final completions = LocalPrayerCompletionStore(
        databaseProvider: () async => database,
        currentUserIdProvider: () => activeUserId,
      );
      await preferences.saveLocal(
        userId: 'account-a',
        preferences: ReminderPreferences(prayerRemindersEnabled: true),
      );
      activeUserId = 'account-b';

      await expectLater(
        preferences.read('account-a'),
        throwsA(isA<NotAuthorizedException>()),
      );
      await expectLater(
        completions.isCompleted(
          userId: 'account-a',
          localDate: DateTime(2026, 11, 3),
          prayer: PrayerName.fajr,
        ),
        throwsA(isA<NotAuthorizedException>()),
      );
    },
  );

  test('simultaneous sync requests for one account are deduplicated', () async {
    final database = await openNewInMemoryDatabase();
    addTearDown(database.close);
    final local = SembastReminderPreferencesStore(
      databaseProvider: () async => database,
    );
    final remote = _FakeReminderRemoteStore()..fetchBarrier = Completer<void>();
    final service = ReminderPreferencesSyncService(
      localStore: local,
      remoteStore: remote,
    );

    final first = service.sync('account-a');
    final second = service.sync('account-a');
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    remote.fetchBarrier!.complete();
    final results = await Future.wait(<Future<ReminderSyncResult>>[
      first,
      second,
    ]);

    expect(results, hasLength(2));
    expect(remote.fetchCalls, 1);
  });

  test(
    'independent preference edits merge without losing either device',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final local = SembastReminderPreferencesStore(
        databaseProvider: () async => database,
      );
      final remote = _FakeReminderRemoteStore();
      final service = ReminderPreferencesSyncService(
        localStore: local,
        remoteStore: remote,
      );
      await service.saveLocal(
        userId: 'account-a',
        preferences: ReminderPreferences(),
      );
      await service.sync('account-a');
      remote.fetchError = http.ClientException('offline');
      final localEdit = ReminderPreferences(
        prayerRemindersEnabled: true,
        configurations: <ReminderConfiguration>[
          ReminderConfiguration(
            id: 'local-reminder',
            kind: 'custom',
            enabled: true,
            parameters: const <String, Object?>{'time': '10:00'},
          ),
        ],
      );
      await service.saveLocal(userId: 'account-a', preferences: localEdit);
      remote.fetchError = null;
      remote.records['account-a'] = _snapshot(
        ReminderPreferences(
          eveningAzkarEnabled: true,
          configurations: <ReminderConfiguration>[
            ReminderConfiguration(
              id: 'remote-reminder',
              kind: 'custom',
              enabled: true,
              parameters: const <String, Object?>{'time': '20:00'},
            ),
          ],
        ),
        revision: 2,
      );

      final result = await service.sync('account-a');
      expect(result.status, ReminderSyncStatus.synchronized);
      expect(result.preferences.prayerRemindersEnabled, isTrue);
      expect(result.preferences.eveningAzkarEnabled, isTrue);
      expect(
        result.preferences.configurations.map((item) => item.id),
        containsAll(<String>['local-reminder', 'remote-reminder']),
      );
      expect(
        remote.records['account-a']?.preferences.prayerRemindersEnabled,
        isTrue,
      );
      expect(remote.records['account-a']?.revision, 3);
      expect((await local.read('account-a'))?.isDirty, isFalse);
    },
  );

  test(
    'same-field preference conflicts wait for explicit user resolution',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final local = SembastReminderPreferencesStore(
        databaseProvider: () async => database,
      );
      final remote = _FakeReminderRemoteStore();
      final service = ReminderPreferencesSyncService(
        localStore: local,
        remoteStore: remote,
      );
      await service.saveLocal(
        userId: 'account-a',
        preferences: ReminderPreferences(),
      );
      remote.fetchError = http.ClientException('offline');
      await service.saveLocal(
        userId: 'account-a',
        preferences: ReminderPreferences(morningAzkarTime: '08:00'),
      );
      remote.fetchError = null;
      remote.records['account-a'] = _snapshot(
        ReminderPreferences(morningAzkarTime: '09:00'),
        revision: 2,
      );

      final conflict = await service.sync('account-a');
      expect(conflict.status, ReminderSyncStatus.conflict);
      expect(conflict.preferences.morningAzkarTime, '08:00');
      expect(conflict.serverSnapshot?.preferences.morningAzkarTime, '09:00');
      expect((await local.read('account-a'))?.isDirty, isTrue);

      final resolved = await service.resolveConflict(
        userId: 'account-a',
        preferences: conflict.preferences,
        serverSnapshot: conflict.serverSnapshot!,
      );
      expect(resolved.status, ReminderSyncStatus.synchronized);
      expect(
        remote.records['account-a']?.preferences.morningAzkarTime,
        '08:00',
      );
      expect(remote.records['account-a']?.revision, 3);
      expect((await local.read('account-a'))?.isDirty, isFalse);
    },
  );
  test(
    'equivalent server revisions do not conflict on local-only timezone',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final local = SembastReminderPreferencesStore(
        databaseProvider: () async => database,
      );
      final remote = _FakeReminderRemoteStore();
      final service = ReminderPreferencesSyncService(
        localStore: local,
        remoteStore: remote,
      );
      final base = _snapshot(ReminderPreferences(), revision: 1);
      await local.markSynchronized(userId: 'account-a', snapshot: base);
      await service.saveLocal(
        userId: 'account-a',
        preferences: ReminderPreferences(timezoneId: 'America/New_York'),
      );
      remote.records['account-a'] = _snapshot(
        ReminderPreferences(),
        revision: 2,
      );

      final result = await service.sync('account-a');

      expect(result.status, ReminderSyncStatus.synchronized);
      expect(result.preferences.timezoneId, 'America/New_York');
      expect((await local.read('account-a'))?.isDirty, isFalse);
    },
  );

  test(
    'matching reminder additions on two devices merge as one configuration',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final local = SembastReminderPreferencesStore(
        databaseProvider: () async => database,
      );
      final remote = _FakeReminderRemoteStore();
      final service = ReminderPreferencesSyncService(
        localStore: local,
        remoteStore: remote,
      );
      await service.saveLocal(
        userId: 'account-a',
        preferences: ReminderPreferences(),
      );
      remote.fetchError = http.ClientException('offline');
      final sameReminder = ReminderConfiguration(
        id: 'friday-kahf',
        kind: 'weekly',
        enabled: true,
        parameters: const <String, Object?>{'weekday': 5},
      );
      await service.saveLocal(
        userId: 'account-a',
        preferences: ReminderPreferences(
          configurations: <ReminderConfiguration>[sameReminder],
        ),
      );
      remote.fetchError = null;
      remote.records['account-a'] = _snapshot(
        ReminderPreferences(
          configurations: <ReminderConfiguration>[sameReminder],
        ),
        revision: 2,
      );

      final result = await service.sync('account-a');

      expect(result.status, ReminderSyncStatus.synchronized);
      expect(result.preferences.configurations, hasLength(1));
      expect(result.preferences.configurations.single.id, 'friday-kahf');
      expect(remote.records['account-a']?.revision, 2);
    },
  );

  test(
    'prayer completion is local and namespaced per account and date',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final store = LocalPrayerCompletionStore(
        databaseProvider: () async => database,
      );
      final date = DateTime(2026, 11, 3);
      await store.markCompleted(
        userId: 'account-a',
        localDate: date,
        prayer: PrayerName.fajr,
        isCompleted: true,
      );

      expect(
        await store.isCompleted(
          userId: 'account-a',
          localDate: date,
          prayer: PrayerName.fajr,
        ),
        isTrue,
      );
      expect(
        await store.isCompleted(
          userId: 'account-b',
          localDate: date,
          prayer: PrayerName.fajr,
        ),
        isFalse,
      );
      expect(
        await store.isCompleted(
          userId: 'account-a',
          localDate: DateTime(2026, 11, 4),
          prayer: PrayerName.fajr,
        ),
        isFalse,
      );
    },
  );

  test(
    'Supabase adapter rejects a mismatched account before network access',
    () async {
      final transport = MockClient((request) async {
        fail('A mismatched account must not make an HTTP request.');
      });
      final client = SupabaseClient(
        'https://test-project.supabase.co',
        'test-publishable-key',
        httpClient: transport,
      );
      addTearDown(() async {
        await client.dispose();
        transport.close();
      });

      await expectLater(
        SupabaseReminderPreferencesStore(client).fetch('account-a'),
        throwsA(isA<NotAuthorizedException>()),
      );
    },
  );
}

class _FakeReminderRemoteStore implements ReminderPreferencesRemoteStore {
  final Map<String, ReminderPreferencesSnapshot> records =
      <String, ReminderPreferencesSnapshot>{};
  Object? fetchError;
  Completer<void>? fetchBarrier;
  int fetchCalls = 0;

  @override
  Future<ReminderPreferencesSnapshot?> fetch(String userId) async {
    fetchCalls++;
    await fetchBarrier?.future;
    if (fetchError case final error?) throw error;
    return records[userId];
  }

  @override
  Future<ReminderPreferencesSaveResult> save({
    required String userId,
    required ReminderPreferences preferences,
    required int expectedRevision,
  }) async {
    final current = records[userId];
    if ((current?.revision ?? 0) != expectedRevision) {
      return ReminderPreferencesSaveResult.conflict(current);
    }
    final saved = _snapshot(
      _asSyncedPreferences(preferences),
      revision: (current?.revision ?? 0) + 1,
    );
    records[userId] = saved;
    return ReminderPreferencesSaveResult.saved(saved);
  }
}

ReminderPreferencesSnapshot _snapshot(
  ReminderPreferences preferences, {
  required int revision,
}) => ReminderPreferencesSnapshot(
  preferences: preferences,
  revision: revision,
  updatedAt: DateTime.utc(2026, 11, 3, 12),
);

ReminderPreferences _asSyncedPreferences(ReminderPreferences preferences) =>
    ReminderPreferences.fromRemoteRow(<String, dynamic>{
      'manual_city': preferences.manualCity,
      'manual_country': preferences.manualCountry,
      'manual_country_code': preferences.manualCountryCode,
      'timezone_id': preferences.manualCity == null
          ? null
          : preferences.timezoneId,
      'settings': preferences.toSettingsJson(),
      'configurations': preferences.configurationsJson,
    });
