import 'dart:convert';

import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:azkar/features/notifications/data/local_notification_service.dart';
import 'package:azkar/features/notifications/data/notification_platform.dart';
import 'package:azkar/features/notifications/data/notification_schedule_registry.dart';
import 'package:azkar/features/notifications/domain/local_notification.dart';
import 'package:azkar/features/prayer_times/data/prayer_times_provider.dart';
import 'package:azkar/features/prayer_times/data/prayer_times_service.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:azkar/features/prayer_tracking/data/local_prayer_completion_reminder_scheduler.dart';
import 'package:azkar/features/prayer_tracking/data/local_prayer_completion_store.dart';
import 'package:azkar/features/prayer_tracking/data/tasbeeh_event_notification_consumer.dart';
import 'package:azkar/features/prayer_tracking/domain/prayer_completion_state_machine.dart';
import 'package:azkar/features/reminders/data/local_prayer_schedule_location_store.dart';
import 'package:azkar/features/reminders/data/local_reminder_preferences_store.dart';
import 'package:azkar/features/reminders/data/local_reminder_scheduling_engine.dart';
import 'package:azkar/features/reminders/domain/reminder_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  setUpAll(PrayerTimeZones.initialize);

  test('background maintenance renews reminders without foreground completion storage', () async {
    final fixture = await _Fixture.create(
      backgroundMode: true,
      clock: DateTime.utc(2026, 1, 8, 2),
    );
    addTearDown(fixture.close);
    await fixture.save(
      ReminderPreferences(
        prayerTimeNotificationsEnabled: true,
        prayerRemindersEnabled: true,
        morningAzkarEnabled: true,
      ),
    );
    final report = await fixture.engine.reconcile('account-a');
    final keys = (await fixture.notifications.registeredSchedules('account-a'))
        .keys;
    expect(report.scheduledCount, greaterThan(0));
    expect(
      keys.every((key) => key.startsWith('reminder-background:v1:')),
      isTrue,
    );
    expect(keys.any((key) => key.contains('prayer-followup:')), isTrue);
    expect(fixture.platform.permissionRequests, 0);
    expect(
      fixture.platform.scheduled.values.every(
        (item) => item.scheduledAt.isAfter(fixture.clock),
      ),
      isTrue,
    );
  });

  test(
    'plans daily, Friday, and specific-day reminders over a bounded horizon',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.save(
        ReminderPreferences(
          timezoneId: 'Africa/Cairo',
          prayerRemindersEnabled: true,
          prayerTimeNotificationsEnabled: true,
          morningAzkarEnabled: true,
          morningAzkarTime: '07:00',
          eveningAzkarEnabled: true,
          eveningAzkarTime: '18:00',
          fridayKahfEnabled: true,
          fridayKahfTime: '09:00',
          configurations: <ReminderConfiguration>[
            ReminderConfiguration(
              id: 'friday-dua',
              kind: 'dua',
              enabled: true,
              parameters: <String, Object?>{
                'text': 'دعاء الجمعة',
                'time': '08:00',
                'recurrence': 'specific_days',
                'days': <int>[DateTime.friday],
              },
            ),
          ],
        ),
      );

      final report = await fixture.engine.reconcile('account-a');
      final schedules = await fixture.notifications.registeredSchedules(
        'account-a',
      );

      expect(report.prayerTimesAvailable, isTrue);
      expect(report.skippedForCapacity, 0);
      expect(
        schedules.keys.where((key) => key.startsWith('reminder-engine:v1:')),
        isNotEmpty,
      );
      expect(
        schedules.keys.any(
          (key) => key.startsWith('reminder-engine:v1:friday-kahf:'),
        ),
        isTrue,
      );
      expect(
        schedules.keys.any(
          (key) => key.startsWith('reminder-engine:v1:custom:'),
        ),
        isTrue,
      );
      expect(schedules.length, lessThanOrEqualTo(60));
      expect(
        fixture.provider.requestedMonths.length,
        lessThanOrEqualTo(LocalReminderSchedulingEngine.rollingHorizonDays + 1),
      );
    },
  );

  test(
    'quiet hours defer remembrance reminders to the quiet-hours end',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.save(
        ReminderPreferences(
          timezoneId: 'Africa/Cairo',
          morningAzkarEnabled: true,
          morningAzkarTime: '07:00',
          quietHoursStart: '22:00',
          quietHoursEnd: '08:00',
        ),
      );

      await fixture.engine.reconcile('account-a');
      final morning = fixture.scheduledFor('morning-azkar');

      expect(morning, hasLength(3));
      expect(morning.first.scheduledAt.hour, 8);
      expect(morning.first.scheduledAt.minute, 0);
    },
  );

  test(
    'custom daily recurrence and cancellation follow preference changes',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final configuration = ReminderConfiguration(
        id: 'daily-remember',
        kind: 'custom_remembrance',
        enabled: true,
        parameters: <String, Object?>{
          'text': 'ذكر يومي',
          'time': '09:00',
          'recurrence': 'daily',
        },
      );
      await fixture.save(
        ReminderPreferences(
          timezoneId: 'Africa/Cairo',
          configurations: <ReminderConfiguration>[configuration],
        ),
      );
      await fixture.engine.reconcile('account-a');
      expect(fixture.scheduledFor('custom'), hasLength(3));

      await fixture.engine.saveLocalPreferencesAndReconcile(
        userId: 'account-a',
        preferences: ReminderPreferences(timezoneId: 'Africa/Cairo'),
      );

      expect(fixture.scheduledFor('custom'), isEmpty);
    },
  );

  test(
    'DST gaps are skipped rather than shifted to a fabricated wall time',
    () async {
      final fixture = await _Fixture.create(clock: DateTime.utc(2026, 3, 8, 4));
      addTearDown(fixture.close);
      await fixture.save(
        ReminderPreferences(
          timezoneId: 'America/New_York',
          morningAzkarEnabled: true,
          morningAzkarTime: '02:30',
        ),
        timezoneId: 'America/New_York',
      );

      await fixture.engine.reconcile('account-a');
      final morning = fixture.scheduledFor('morning-azkar');

      expect(morning, hasLength(1));
      expect(morning.single.scheduledAt.day, 9);
      expect(morning.single.scheduledAt.hour, 2);
      expect(morning.single.scheduledAt.minute, 30);
    },
  );

  test('missing prayer calendars never fabricate prayer schedules', () async {
    final fixture = await _Fixture.create(providerFails: true);
    addTearDown(fixture.close);
    await fixture.save(
      ReminderPreferences(
        manualCity: 'Cairo',
        manualCountry: 'Egypt',
        timezoneId: 'Africa/Cairo',
        prayerRemindersEnabled: true,
        prayerTimeNotificationsEnabled: true,
        morningAzkarEnabled: true,
        morningAzkarTime: '07:00',
      ),
    );

    final report = await fixture.engine.reconcile('account-a');
    final keys = (await fixture.notifications.registeredSchedules('account-a'))
        .keys;

    expect(report.prayerTimesAvailable, isFalse);
    expect(keys.where((key) => key.contains('prayer-time')), isEmpty);
    expect(keys.where((key) => key.startsWith('prayer-completion:')), isEmpty);
    expect(
      keys.where((key) => key.startsWith('reminder-engine:v1:morning')),
      isNotEmpty,
    );
  });

  test(
    'stale cached prayer calendars do not produce prayer schedules',
    () async {
      final fixture = await _Fixture.create(
        providerFetchedAt: DateTime.utc(2025, 1, 1),
      );
      addTearDown(fixture.close);
      await fixture.save(
        ReminderPreferences(
          timezoneId: 'Africa/Cairo',
          prayerRemindersEnabled: true,
          prayerTimeNotificationsEnabled: true,
        ),
      );
      final location = PrayerLocation.coordinates(
        latitude: 30.0444,
        longitude: 31.2357,
        countryCode: 'EG',
        timezoneId: 'Africa/Cairo',
      );
      final month = PrayerMonth(2026, 1);
      final calendar = await fixture.provider.fetchMonthlyCalendar(
        location: location,
        month: month,
        calculationMethod: PrayerCalculationMethod.egyptianGeneralAuthority,
        asrMethod: AsrCalculationMethod.standard,
      );
      final cacheKey = PrayerTimesService.buildPrayerCalendarCacheKey(
        location: location,
        month: month,
        calculationMethod: PrayerCalculationMethod.egyptianGeneralAuthority,
        asrMethod: AsrCalculationMethod.standard,
      );
      await fixture.cache.write(cacheKey, calendar);
      fixture.provider.fail = true;

      final report = await fixture.engine.reconcile('account-a');
      final keys = (await fixture.notifications.registeredSchedules(
        'account-a',
      )).keys;

      expect(report.prayerTimesAvailable, isFalse);
      expect(keys.where((key) => key.contains('prayer-time')), isEmpty);
      expect(
        keys.where((key) => key.startsWith('prayer-completion:')),
        isEmpty,
      );
    },
  );

  test(
    'location changes cancel schedules from the previous location',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.save(
        ReminderPreferences(
          timezoneId: 'Africa/Cairo',
          prayerRemindersEnabled: true,
          prayerTimeNotificationsEnabled: true,
        ),
      );
      await fixture.engine.reconcile('account-a');
      final oldPrayerKeys = (await fixture.notifications.registeredSchedules(
        'account-a',
      )).keys.where((key) => key.contains('prayer-time')).toSet();

      await fixture.engine.saveDeviceLocationAndReconcile(
        userId: 'account-a',
        location: PrayerLocation.coordinates(
          latitude: 40.7128,
          longitude: -74.0060,
          countryCode: 'US',
          timezoneId: 'America/New_York',
        ),
      );
      final newSchedules = await fixture.notifications.registeredSchedules(
        'account-a',
      );
      final newPrayerKeys = newSchedules.keys
          .where((key) => key.contains('prayer-time'))
          .toSet();

      expect(oldPrayerKeys, isNotEmpty);
      expect(newPrayerKeys, isNotEmpty);
      expect(newPrayerKeys.intersection(oldPrayerKeys), isEmpty);
      expect(
        newSchedules.keys.where((key) => key.startsWith('prayer-completion:')),
        isNotEmpty,
      );
    },
  );

  test(
    'notification limits remain account-wide and account isolated',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.save(
        ReminderPreferences(
          timezoneId: 'Africa/Cairo',
          morningAzkarEnabled: true,
          morningAzkarTime: '07:00',
          eveningAzkarEnabled: true,
          eveningAzkarTime: '18:00',
        ),
      );
      await fixture.engine.reconcile('account-a');
      final scheduledCount = fixture.platform.scheduled.length;
      fixture.activeUserId = 'account-b';

      expect(
        () => fixture.engine.reconcile('account-a'),
        throwsA(isA<StateError>()),
      );
      expect(scheduledCount, lessThanOrEqualTo(60));
      expect(fixture.platform.scheduled, hasLength(scheduledCount));
    },
  );

  test(
    'stale engine schedules are pruned before completion capacity is used',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await fixture.save(
        ReminderPreferences(
          timezoneId: 'Africa/Cairo',
          prayerRemindersEnabled: true,
          prayerTimeNotificationsEnabled: true,
        ),
      );
      for (var index = 0; index < 60; index++) {
        fixture.seedSchedule('account-a', 'reminder-engine:v1:stale:$index');
      }

      final report = await fixture.engine.reconcile('account-a');
      final schedules = await fixture.notifications.registeredSchedules(
        'account-a',
      );

      expect(report.prayerTimesAvailable, isTrue);
      expect(
        schedules.keys.where((key) => key.startsWith('prayer-completion:v1:')),
        isNotEmpty,
      );
      expect(schedules.length, lessThanOrEqualTo(60));
    },
  );

  test(
    'denied notification permission is not requested automatically',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      fixture.platform.permission = NotificationPermissionState.denied;
      await fixture.save(
        ReminderPreferences(
          timezoneId: 'Africa/Cairo',
          morningAzkarEnabled: true,
          morningAzkarTime: '07:00',
        ),
      );

      final report = await fixture.engine.reconcile('account-a');

      expect(report.notificationPermissionGranted, isFalse);
      expect(fixture.platform.permissionRequests, 0);
      expect(fixture.platform.scheduled, isEmpty);
    },
  );

  test('reconciliation reuses a fresh validated prayer calendar', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.save(
      ReminderPreferences(
        timezoneId: 'Africa/Cairo',
        prayerTimeNotificationsEnabled: true,
      ),
    );

    await fixture.engine.reconcile('account-a');
    final requestCount = fixture.provider.requestCount;
    await fixture.engine.reconcile('account-a');

    expect(requestCount, greaterThan(0));
    expect(fixture.provider.requestCount, requestCount);
  });

  test('Tasbeeh event replay does not duplicate its notification', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.save(
      ReminderPreferences(
        timezoneId: 'Africa/Cairo',
        postPrayerTasbeehEnabled: true,
        postPrayerDelayMinutes: 0,
      ),
    );
    final state = await fixture.machine.scheduleOccurrence(
      userId: 'account-a',
      prayer: TrackedPrayer.fajr,
      prayerTime: fixture.prayerTime(),
    );
    final transition = await fixture.machine.handleAction(
      userId: 'account-a',
      occurrenceId: state.identity.id,
      action: PrayerCompletionAction.prayed,
    );
    final consumer = TasbeehEventNotificationConsumer(
      notifications: fixture.notifications,
      preferencesStore: fixture.preferences,
      currentUserIdProvider: () => fixture.activeUserId,
      clock: () => fixture.clock.add(const Duration(minutes: 5)),
    );

    await expectLater(
      fixture.machine.deliverPendingTasbeehEvents(
        userId: 'account-a',
        consumer: (event) async {
          await consumer.handle(event);
          throw StateError('Simulated termination before outbox ack.');
        },
      ),
      throwsStateError,
    );
    await fixture.machine.deliverPendingTasbeehEvents(
      userId: 'account-a',
      consumer: consumer.handle,
    );

    final tasbeehSchedules = (await fixture.notifications.registeredSchedules(
      'account-a',
    )).keys.where((key) => key.startsWith('post-prayer-tasbeeh:v1:'));
    expect(transition.tasbeehEvent, isNotNull);
    expect(tasbeehSchedules, hasLength(1));
    expect(
      fixture.platform.scheduled.values.where(
        (schedule) => schedule.stableKey.startsWith('post-prayer-tasbeeh:v1:'),
      ),
      hasLength(1),
    );
  });
}

class _Fixture {
  _Fixture({
    required this.database,
    required this.clock,
    required this.provider,
    required this.cache,
    required this.registry,
    required this.preferences,
    required this.notifications,
    required this.platform,
    required this.machine,
    required this.engine,
  });

  final Database database;
  final DateTime clock;
  final _FakePrayerTimesProvider provider;
  final _FakePrayerCache cache;
  final _FakeNotificationRegistry registry;
  final _FakePreferencesStore preferences;
  final LocalNotificationService notifications;
  final _FakeNotificationPlatform platform;
  final PrayerCompletionStateMachine machine;
  final LocalReminderSchedulingEngine engine;
  String activeUserId = 'account-a';

  Future<void> save(
    ReminderPreferences value, {
    String timezoneId = 'Africa/Cairo',
  }) async {
    await preferences.saveLocal(userId: activeUserId, preferences: value);
    await locationStore.saveDeviceLocation(
      userId: activeUserId,
      location: PrayerLocation.coordinates(
        latitude: 30.0444,
        longitude: 31.2357,
        countryCode: 'EG',
        timezoneId: timezoneId,
      ),
    );
  }

  late final LocalPrayerScheduleLocationStore locationStore =
      LocalPrayerScheduleLocationStore(
        databaseProvider: () async => database,
        currentUserIdProvider: () => activeUserId,
      );

  List<_ScheduledNotification> scheduledFor(String category) {
    return platform.scheduled.values
        .where(
          (item) => item.stableKey.startsWith('reminder-engine:v1:$category:'),
        )
        .toList(growable: false);
  }

  void seedSchedule(String accountId, String stableKey) {
    final id = LocalNotificationService.stableNotificationId(
      accountId,
      stableKey,
    );
    registry.records.putIfAbsent(accountId, () => <int, String>{})[id] =
        stableKey;
    platform.scheduled[id] = _ScheduledNotification(
      stableKey: stableKey,
      scheduledAt: timezone.TZDateTime.from(
        clock.add(const Duration(days: 1)),
        PrayerTimeZones.location('Africa/Cairo'),
      ),
      title: 'stale',
      body: 'stale',
    );
  }

  timezone.TZDateTime prayerTime() => timezone.TZDateTime(
    PrayerTimeZones.location('Africa/Cairo'),
    clock.year,
    clock.month,
    clock.day,
    12,
  );

  Future<void> close() async {
    await machine.dispose();
    await notifications.dispose();
    await database.close();
  }

  static Future<_Fixture> create({
    DateTime? clock,
    DateTime? providerFetchedAt,
    bool providerFails = false,
    bool backgroundMode = false,
  }) async {
    final now = clock ?? DateTime.utc(2026, 1, 1, 4);
    final database = await openNewInMemoryDatabase();
    late _Fixture fixture;
    final preferences = _FakePreferencesStore(() => fixture.activeUserId);
    final registry = _FakeNotificationRegistry();
    final platform = _FakeNotificationPlatform();
    final notifications = LocalNotificationService(
      platform: platform,
      registry: registry,
      currentUserIdProvider: () => fixture.activeUserId,
      runtime: const MobileRuntime(
        isWeb: false,
        targetPlatform: TargetPlatform.android,
      ),
      clock: () => now,
    )..setActiveAccount('account-a');
    final completionStore = LocalPrayerCompletionStore(
      databaseProvider: () async => database,
      currentUserIdProvider: () => fixture.activeUserId,
    );
    final machine = PrayerCompletionStateMachine(
      store: completionStore,
      scheduler: LocalPrayerCompletionReminderScheduler(notifications),
      currentUserIdProvider: () => fixture.activeUserId,
      clock: () => now,
    );
    final provider = _FakePrayerTimesProvider(
      now: providerFetchedAt ?? now,
      fail: providerFails,
    );
    final locationStore = LocalPrayerScheduleLocationStore(
      databaseProvider: () async => database,
      currentUserIdProvider: () => fixture.activeUserId,
    );
    final cache = _FakePrayerCache();
    final engine = LocalReminderSchedulingEngine(
      backgroundMode: backgroundMode,
      preferencesStore: preferences,
      locationStore: locationStore,
      prayerTimesService: PrayerTimesService(provider: provider, cache: cache),
      notifications: notifications,
      prayerCompletionStateMachine: machine,
      currentUserIdProvider: () => fixture.activeUserId,
      clock: () => now,
    );
    fixture = _Fixture(
      database: database,
      clock: now,
      provider: provider,
      cache: cache,
      registry: registry,
      preferences: preferences,
      notifications: notifications,
      platform: platform,
      machine: machine,
      engine: engine,
    );
    return fixture;
  }
}

class _FakePreferencesStore implements ReminderPreferencesLocalStore {
  _FakePreferencesStore(this.currentUserIdProvider);

  final String? Function() currentUserIdProvider;
  final Map<String, ReminderPreferences> values =
      <String, ReminderPreferences>{};

  void _validate(String userId) {
    if (currentUserIdProvider() != userId) {
      throw StateError('Preferences are isolated by account.');
    }
  }

  @override
  Future<LocalReminderPreferencesState?> read(String userId) async {
    _validate(userId);
    final value = values[userId];
    return value == null
        ? null
        : LocalReminderPreferencesState(
            preferences: value,
            baseRevision: 0,
            isDirty: true,
          );
  }

  @override
  Future<void> saveLocal({
    required String userId,
    required ReminderPreferences preferences,
  }) async {
    _validate(userId);
    values[userId] = preferences;
  }

  @override
  Future<void> markSynchronized({
    required String userId,
    required ReminderPreferencesSnapshot snapshot,
  }) async {
    _validate(userId);
    values[userId] = snapshot.preferences;
  }

  @override
  Future<void> resolveConflict({
    required String userId,
    required ReminderPreferences preferences,
    required ReminderPreferencesSnapshot serverSnapshot,
  }) async {
    _validate(userId);
    values[userId] = preferences;
  }
}

class _FakePrayerTimesProvider implements PrayerTimesProvider {
  _FakePrayerTimesProvider({required this.now, required this.fail});

  final DateTime now;
  bool fail;
  final Set<String> requestedMonths = <String>{};
  int requestCount = 0;

  @override
  Future<PrayerCalendar> fetchMonthlyCalendar({
    required PrayerLocation location,
    required PrayerMonth month,
    required PrayerCalculationMethod calculationMethod,
    required AsrCalculationMethod asrMethod,
  }) async {
    requestCount++;
    requestedMonths.add(month.cacheId);
    if (fail) throw StateError('Network unavailable.');
    final timezoneId = location.timezoneId ?? 'Africa/Cairo';
    final zone = PrayerTimeZones.location(timezoneId);
    final days = <PrayerDay>[];
    for (var dayNumber = 1; dayNumber <= month.dayCount; dayNumber++) {
      final date = DateTime.utc(month.year, month.month, dayNumber);
      days.add(
        PrayerDay(
          localDate: date,
          times: <PrayerName, timezone.TZDateTime>{
            PrayerName.fajr: timezone.TZDateTime(
              zone,
              month.year,
              month.month,
              dayNumber,
              5,
            ),
            PrayerName.sunrise: timezone.TZDateTime(
              zone,
              month.year,
              month.month,
              dayNumber,
              6,
            ),
            PrayerName.dhuhr: timezone.TZDateTime(
              zone,
              month.year,
              month.month,
              dayNumber,
              12,
            ),
            PrayerName.asr: timezone.TZDateTime(
              zone,
              month.year,
              month.month,
              dayNumber,
              15,
            ),
            PrayerName.maghrib: timezone.TZDateTime(
              zone,
              month.year,
              month.month,
              dayNumber,
              18,
            ),
            PrayerName.isha: timezone.TZDateTime(
              zone,
              month.year,
              month.month,
              dayNumber,
              20,
            ),
          },
        ),
      );
    }
    return PrayerCalendar(
      year: month.year,
      month: month.month,
      timezoneId: timezoneId,
      calculationMethod: calculationMethod,
      asrMethod: asrMethod,
      days: days,
      fetchedAt: now,
    );
  }
}

class _FakePrayerCache implements PrayerCalendarCache {
  final Map<String, PrayerCalendar> calendars = <String, PrayerCalendar>{};

  @override
  Future<PrayerCalendar?> read(String cacheKey) async => calendars[cacheKey];

  @override
  Future<void> write(String cacheKey, PrayerCalendar calendar) async {
    calendars[cacheKey] = calendar;
  }
}

class _FakeNotificationRegistry implements NotificationScheduleRegistry {
  final Map<String, Map<int, String>> records = <String, Map<int, String>>{};

  @override
  Future<Map<String, int>> schedules(String accountId) async => <String, int>{
    for (final entry
        in records[accountId]?.entries ?? const <MapEntry<int, String>>[])
      entry.value: entry.key,
  };

  @override
  Future<String?> stableKeyForId(String accountId, int notificationId) async =>
      records[accountId]?[notificationId];

  @override
  Future<void> register({
    required String accountId,
    required String stableKey,
    required int notificationId,
  }) async {
    final accountSchedules = records.putIfAbsent(
      accountId,
      () => <int, String>{},
    );
    if (!accountSchedules.containsKey(notificationId) &&
        accountSchedules.length >=
            LocalNotificationService.maxPendingNotificationsPerAccount) {
      throw const NotificationScheduleLimitException();
    }
    accountSchedules[notificationId] = stableKey;
  }

  @override
  Future<List<int>> notificationIds(String accountId) async =>
      records[accountId]?.keys.toList() ?? <int>[];

  @override
  Future<void> remove({
    required String accountId,
    required int notificationId,
  }) async {
    records[accountId]?.remove(notificationId);
  }
}

class _FakeNotificationPlatform implements NotificationPlatform {
  final Map<int, _ScheduledNotification> scheduled =
      <int, _ScheduledNotification>{};
  NotificationPermissionState permission = NotificationPermissionState.granted;
  int permissionRequests = 0;
  late void Function(NotificationPlatformResponse) onResponse;

  @override
  Future<void> initialize(
    void Function(NotificationPlatformResponse response) onResponse,
  ) async {
    this.onResponse = onResponse;
  }

  @override
  Future<NotificationPermissionState> permissionState() async => permission;

  @override
  Future<NotificationPermissionState> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<NotificationPlatformResponse?> getLaunchResponse() async => null;

  @override
  Future<void> schedule({
    required int id,
    required timezone.TZDateTime scheduledAt,
    required String title,
    required String body,
    required String payload,
    required List<NotificationActionDefinition> actions,
    required bool hideContentOnLockScreen,
  }) async {
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    scheduled[id] = _ScheduledNotification(
      stableKey: decoded['key'] as String,
      scheduledAt: scheduledAt,
      title: title,
      body: body,
    );
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }
}

class _ScheduledNotification {
  const _ScheduledNotification({
    required this.stableKey,
    required this.scheduledAt,
    required this.title,
    required this.body,
  });

  final String stableKey;
  final timezone.TZDateTime scheduledAt;
  final String title;
  final String body;
}
