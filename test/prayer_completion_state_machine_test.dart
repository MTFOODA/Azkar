import 'dart:async';
import 'dart:convert';

import 'package:azkar/core/utils/app_exception.dart';
import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:azkar/features/notifications/data/local_notification_service.dart';
import 'package:azkar/features/notifications/data/notification_platform.dart';
import 'package:azkar/features/notifications/data/notification_schedule_registry.dart';
import 'package:azkar/features/notifications/domain/local_notification.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:azkar/features/prayer_tracking/data/local_prayer_completion_reminder_scheduler.dart';
import 'package:azkar/features/prayer_tracking/data/local_prayer_completion_store.dart';
import 'package:azkar/features/prayer_tracking/data/prayer_completion_notification_coordinator.dart';
import 'package:azkar/features/prayer_tracking/domain/prayer_completion_state_machine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  setUpAll(PrayerTimeZones.initialize);

  test(
    'tracks the five prayers independently and schedules at prayer +10m',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final zone = PrayerTimeZones.location('Africa/Cairo');

      for (final (index, prayer) in TrackedPrayer.values.indexed) {
        final prayerTime = timezone.TZDateTime(
          zone,
          2026,
          1,
          3,
          12,
          index * 10,
        );
        final state = await fixture.machine.scheduleOccurrence(
          userId: 'account-a',
          prayer: prayer,
          prayerTime: prayerTime,
        );

        expect(state.identity.prayer, prayer);
        expect(state.status, PrayerCompletionStatus.reminderSent);
        expect(state.scheduledReminderCount, 1);
        expect(
          fixture
              .scheduler
              .schedules[fixture.machine.stableReminderKey(
                state.identity.id,
                1,
              )]
              ?.scheduledAt,
          prayerTime.add(const Duration(minutes: 10)),
        );
      }

      expect(fixture.scheduler.schedules, hasLength(5));
    },
  );

  test(
    'snooze schedules one final reminder at first reminder +20m only',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final state = await fixture.schedule();
      expect(state.scheduledReminderCount, 1);
      expect(state.pendingReminderOrdinal, isNull);
      expect(state.reminderTime(2).isAfter(fixture.clock), isTrue);

      final firstSnooze = await fixture.machine.handleAction(
        userId: 'account-a',
        occurrenceId: state.identity.id,
        action: PrayerCompletionAction.notYetPrayed,
      );
      final duplicateSnooze = await fixture.machine.handleAction(
        userId: 'account-a',
        occurrenceId: state.identity.id,
        action: PrayerCompletionAction.notYetPrayed,
      );

      final finalKey = fixture.machine.stableReminderKey(state.identity.id, 2);
      expect(firstSnooze.state.status, PrayerCompletionStatus.notYetPrayed);
      expect(firstSnooze.state.scheduledReminderCount, 2);
      expect(duplicateSnooze.state.scheduledReminderCount, 2);
      expect(
        fixture.scheduler.schedules[finalKey]?.scheduledAt,
        state.prayerTime.add(const Duration(minutes: 30)),
      );
      expect(fixture.scheduler.schedules, hasLength(2));
    },
  );

  test('ignoring reminders never creates an automatic retry', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final state = await fixture.schedule();

    await fixture.machine.reconcilePendingSchedules('account-a');
    final restored = await fixture.machine.scheduleOccurrence(
      userId: 'account-a',
      prayer: state.identity.prayer,
      prayerTime: state.prayerTime,
    );

    expect(restored.scheduledReminderCount, 1);
    expect(restored.status, PrayerCompletionStatus.reminderSent);
    expect(fixture.scheduler.schedules, hasLength(1));
  });

  test(
    'pending reminder intent survives scheduler failure and app restart',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      fixture.scheduler.failNextSchedule = true;

      await expectLater(fixture.schedule(), throwsStateError);
      final pendingStates = await fixture.store.pendingOccurrences(
        userId: 'account-a',
      );
      expect(pendingStates, hasLength(1));
      expect(pendingStates.single.pendingReminderOrdinal, 1);

      final restarted = fixture.newMachine();
      await restarted.reconcilePendingSchedules('account-a');
      final restored = await fixture.store.readOccurrence(
        userId: 'account-a',
        occurrenceId: pendingStates.single.identity.id,
      );

      expect(restored?.scheduledReminderCount, 1);
      expect(restored?.pendingReminderOrdinal, isNull);
      expect(fixture.scheduler.schedules, hasLength(1));
      await restarted.dispose();
    },
  );

  test(
    'completion cancels both reminders and creates one Tasbeeh event',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final events = <PrayerCompletionTasbeehEvent>[];
      final subscription = fixture.machine.postPrayerTasbeehEvents.listen(
        events.add,
      );
      addTearDown(subscription.cancel);
      final state = await fixture.schedule();
      await fixture.machine.handleAction(
        userId: 'account-a',
        occurrenceId: state.identity.id,
        action: PrayerCompletionAction.notYetPrayed,
      );

      final completed = await fixture.machine.handleAction(
        userId: 'account-a',
        occurrenceId: state.identity.id,
        action: PrayerCompletionAction.prayed,
      );
      await fixture.machine.handleAction(
        userId: 'account-a',
        occurrenceId: state.identity.id,
        action: PrayerCompletionAction.prayed,
      );

      expect(completed.state.status, PrayerCompletionStatus.completed);
      expect(completed.tasbeehEvent, isNotNull);
      expect(events, hasLength(1));
      expect(fixture.scheduler.schedules, isEmpty);
      expect(fixture.scheduler.cancelled, hasLength(2));
    },
  );

  test(
    'manual completion and correction do not duplicate Tasbeeh event',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final events = <PrayerCompletionTasbeehEvent>[];
      final subscription = fixture.machine.postPrayerTasbeehEvents.listen(
        events.add,
      );
      addTearDown(subscription.cancel);
      final prayerTime = timezone.TZDateTime(
        PrayerTimeZones.location('Africa/Cairo'),
        2025,
        12,
        31,
        12,
      );

      final completed = await fixture.machine.setManuallyCompleted(
        userId: 'account-a',
        prayer: TrackedPrayer.asr,
        prayerTime: prayerTime,
        completed: true,
      );
      final corrected = await fixture.machine.setManuallyCompleted(
        userId: 'account-a',
        prayer: TrackedPrayer.asr,
        prayerTime: prayerTime,
        completed: false,
      );
      final completedAgain = await fixture.machine.setManuallyCompleted(
        userId: 'account-a',
        prayer: TrackedPrayer.asr,
        prayerTime: prayerTime,
        completed: true,
      );

      expect(completed.state.status, PrayerCompletionStatus.completed);
      expect(corrected.state.status, PrayerCompletionStatus.notConfirmed);
      expect(completedAgain.state.status, PrayerCompletionStatus.completed);
      expect(events, hasLength(1));
      expect(completedAgain.tasbeehEvent, isNull);
    },
  );

  test(
    'Tasbeeh outbox is durable across restart and retries failed delivery',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final state = await fixture.schedule();
      await fixture.machine.handleAction(
        userId: 'account-a',
        occurrenceId: state.identity.id,
        action: PrayerCompletionAction.prayed,
      );

      final restarted = fixture.newMachine();
      final pending = await fixture.store.pendingTasbeehEvents('account-a');
      expect(pending, hasLength(1));
      expect(pending.single.id, '${state.identity.id}:post-prayer-tasbeeh');

      var failedAttempts = 0;
      await expectLater(
        restarted.deliverPendingTasbeehEvents(
          userId: 'account-a',
          consumer: (_) async {
            failedAttempts++;
            throw StateError('Consumer failed before acknowledgement.');
          },
        ),
        throwsStateError,
      );
      expect(
        await fixture.store.pendingTasbeehEvents('account-a'),
        hasLength(1),
      );

      final handledIds = <String>[];
      await restarted.deliverPendingTasbeehEvents(
        userId: 'account-a',
        consumer: (event) async {
          handledIds.add(event.id);
        },
      );
      await restarted.deliverPendingTasbeehEvents(
        userId: 'account-a',
        consumer: (event) async {
          handledIds.add(event.id);
        },
      );

      expect(failedAttempts, 1);
      expect(handledIds, <String>[pending.single.id]);
      expect(await fixture.store.pendingTasbeehEvents('account-a'), isEmpty);
      await restarted.dispose();
    },
  );

  test(
    'outbox claim expires and recovers after a simulated process crash',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final state = await fixture.schedule();
      await fixture.machine.handleAction(
        userId: 'account-a',
        occurrenceId: state.identity.id,
        action: PrayerCompletionAction.prayed,
      );
      final event = (await fixture.store.pendingTasbeehEvents('account-a'))
          .single;
      final claimed = await fixture.store.claimTasbeehEvent(
        userId: 'account-a',
        eventId: event.id,
        claimId: 'crashed-process',
        now: fixture.clock,
        leaseDuration: const Duration(minutes: 2),
      );
      expect(claimed, isTrue);

      final restarted = fixture.newMachine();
      var handled = false;
      await restarted.deliverPendingTasbeehEvents(
        userId: 'account-a',
        consumer: (_) async {
          handled = true;
        },
      );
      expect(handled, isFalse);

      fixture.clock = fixture.clock.add(const Duration(minutes: 3));
      await restarted.deliverPendingTasbeehEvents(
        userId: 'account-a',
        consumer: (_) async {
          handled = true;
        },
      );
      expect(handled, isTrue);
      expect(await fixture.store.pendingTasbeehEvents('account-a'), isEmpty);
      await restarted.dispose();
    },
  );

  test('concurrent outbox replay claims an event only once', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final state = await fixture.schedule();
    await fixture.machine.handleAction(
      userId: 'account-a',
      occurrenceId: state.identity.id,
      action: PrayerCompletionAction.prayed,
    );
    final restarted = fixture.newMachine();
    final consumerStarted = Completer<void>();
    final finishConsumer = Completer<void>();
    final handled = <String>[];

    final firstDelivery = fixture.machine.deliverPendingTasbeehEvents(
      userId: 'account-a',
      consumer: (event) async {
        handled.add(event.id);
        consumerStarted.complete();
        await finishConsumer.future;
      },
    );
    await consumerStarted.future;
    await restarted.deliverPendingTasbeehEvents(
      userId: 'account-a',
      consumer: (event) async {
        handled.add(event.id);
      },
    );
    finishConsumer.complete();
    await firstDelivery;

    expect(handled, hasLength(1));
    expect(await fixture.store.pendingTasbeehEvents('account-a'), isEmpty);
    await restarted.dispose();
  });

  test('pending outbox events remain isolated from other accounts', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final state = await fixture.schedule();
    await fixture.machine.handleAction(
      userId: 'account-a',
      occurrenceId: state.identity.id,
      action: PrayerCompletionAction.prayed,
    );
    fixture.activeUserId = 'account-b';

    expect(await fixture.store.pendingTasbeehEvents('account-b'), isEmpty);
    var deliveredToOtherAccount = false;
    await fixture.newMachine().deliverPendingTasbeehEvents(
      userId: 'account-b',
      consumer: (_) async {
        deliveredToOtherAccount = true;
      },
    );
    expect(deliveredToOtherAccount, isFalse);
  });

  test(
    'completion state survives restart and duplicate actions stay idempotent',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final state = await fixture.schedule();
      final restarted = fixture.newMachine();
      final events = <PrayerCompletionTasbeehEvent>[];
      final subscription = restarted.postPrayerTasbeehEvents.listen(events.add);
      addTearDown(subscription.cancel);

      final results = await Future.wait(<Future<PrayerCompletionTransition>>[
        restarted.handleAction(
          userId: 'account-a',
          occurrenceId: state.identity.id,
          action: PrayerCompletionAction.prayed,
        ),
        restarted.handleAction(
          userId: 'account-a',
          occurrenceId: state.identity.id,
          action: PrayerCompletionAction.prayed,
        ),
      ]);

      expect(
        results.every(
          (result) => result.state.status == PrayerCompletionStatus.completed,
        ),
        isTrue,
      );
      expect(
        results.where((result) => result.tasbeehEvent != null),
        hasLength(1),
      );
      expect(events, hasLength(1));
      expect(
        (await fixture.store.readOccurrence(
          userId: 'account-a',
          occurrenceId: state.identity.id,
        ))?.status,
        PrayerCompletionStatus.completed,
      );
      await restarted.dispose();
    },
  );

  test('state and completion events are isolated between accounts', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final state = await fixture.schedule();
    fixture.activeUserId = 'account-b';

    await expectLater(
      fixture.machine.handleAction(
        userId: 'account-a',
        occurrenceId: state.identity.id,
        action: PrayerCompletionAction.prayed,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      fixture.store.readOccurrence(
        userId: 'account-b',
        occurrenceId: state.identity.id,
      ),
      throwsA(isA<LocalStorageException>()),
    );
  });

  test('identity uses local date, named zone, and offset across DST', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final eastOfDateLine = timezone.TZDateTime(
      PrayerTimeZones.location('Pacific/Kiritimati'),
      2026,
      1,
      2,
      0,
      5,
    );
    expect(eastOfDateLine.toUtc().day, 1);
    final eastIdentity = PrayerOccurrenceIdentity.forPrayerTime(
      userId: 'account-a',
      prayer: TrackedPrayer.fajr,
      prayerTime: eastOfDateLine,
    );
    expect(eastIdentity.dateKey, '2026-01-02');

    final beforeDst = timezone.TZDateTime(
      PrayerTimeZones.location('America/New_York'),
      2026,
      3,
      8,
      1,
      50,
    );
    final afterDst = timezone.TZDateTime(
      PrayerTimeZones.location('America/New_York'),
      2026,
      3,
      8,
      3,
      10,
    );
    final beforeIdentity = PrayerOccurrenceIdentity.forPrayerTime(
      userId: 'account-a',
      prayer: TrackedPrayer.fajr,
      prayerTime: beforeDst,
    );
    final afterIdentity = PrayerOccurrenceIdentity.forPrayerTime(
      userId: 'account-a',
      prayer: TrackedPrayer.fajr,
      prayerTime: afterDst,
    );

    expect(beforeIdentity.dateKey, afterIdentity.dateKey);
    expect(beforeIdentity.timezoneOffsetMinutes, -300);
    expect(afterIdentity.timezoneOffsetMinutes, -240);
    expect(beforeIdentity.id, isNot(afterIdentity.id));
  });

  test(
    'time adjustment reschedules the pending occurrence without duplicates',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final original = await fixture.schedule();
      final adjustment = original.prayerTime.add(const Duration(minutes: 5));

      final adjusted = await fixture.machine.scheduleOccurrence(
        userId: 'account-a',
        prayer: TrackedPrayer.fajr,
        prayerTime: adjustment,
      );

      final firstKey = fixture.machine.stableReminderKey(
        adjusted.identity.id,
        1,
      );
      expect(adjusted.identity.id, original.identity.id);
      expect(
        fixture.scheduler.schedules[firstKey]?.scheduledAt,
        adjustment.add(const Duration(minutes: 10)),
      );
      expect(fixture.scheduler.schedules, hasLength(1));
    },
  );

  test('time adjustment updates an already scheduled final reminder', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final first = await fixture.schedule();
    final snoozed = await fixture.machine.handleAction(
      userId: 'account-a',
      occurrenceId: first.identity.id,
      action: PrayerCompletionAction.notYetPrayed,
    );
    final adjustment = snoozed.state.prayerTime.add(const Duration(minutes: 5));

    await fixture.machine.scheduleOccurrence(
      userId: 'account-a',
      prayer: TrackedPrayer.fajr,
      prayerTime: adjustment,
    );

    final finalKey = fixture.machine.stableReminderKey(first.identity.id, 2);
    expect(
      fixture.scheduler.schedules[finalKey]?.scheduledAt,
      adjustment.add(const Duration(minutes: 30)),
    );
    expect(fixture.scheduler.schedules, hasLength(2));
  });

  test(
    'time-zone change cancels old context schedule and creates new identity',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final oldTime = timezone.TZDateTime(
        PrayerTimeZones.location('America/New_York'),
        2026,
        1,
        3,
        8,
      );
      final oldState = await fixture.machine.scheduleOccurrence(
        userId: 'account-a',
        prayer: TrackedPrayer.maghrib,
        prayerTime: oldTime,
      );
      final newTime = timezone.TZDateTime(
        PrayerTimeZones.location('America/Toronto'),
        2026,
        1,
        3,
        8,
      );
      final newState = await fixture.machine.scheduleOccurrence(
        userId: 'account-a',
        prayer: TrackedPrayer.maghrib,
        prayerTime: newTime,
      );

      expect(newState.identity.id, isNot(oldState.identity.id));
      expect(
        fixture.scheduler.cancelled,
        containsAll(<String>[
          fixture.machine.stableReminderKey(oldState.identity.id, 1),
          fixture.machine.stableReminderKey(oldState.identity.id, 2),
        ]),
      );
      expect(
        fixture.scheduler.schedules.containsKey(
          fixture.machine.stableReminderKey(newState.identity.id, 1),
        ),
        isTrue,
      );
    },
  );

  test(
    'notification coordinator routes only valid current-account actions',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      final plugin = _FakeNotificationPlatform();
      final notifications = LocalNotificationService(
        platform: plugin,
        registry: _MemoryNotificationRegistry(),
        currentUserIdProvider: () => fixture.activeUserId,
        runtime: const MobileRuntime(
          isWeb: false,
          targetPlatform: TargetPlatform.android,
        ),
        clock: () => fixture.clock,
      )..setActiveAccount('account-a');
      final machine = PrayerCompletionStateMachine(
        store: fixture.store,
        scheduler: LocalPrayerCompletionReminderScheduler(notifications),
        currentUserIdProvider: () => fixture.activeUserId,
        clock: () => fixture.clock,
      );
      final coordinator = PrayerCompletionNotificationCoordinator(
        stateMachine: machine,
        notifications: notifications,
        currentUserIdProvider: () => fixture.activeUserId,
      )..start();
      addTearDown(coordinator.dispose);
      addTearDown(machine.dispose);
      final state = await machine.scheduleOccurrence(
        userId: 'account-a',
        prayer: TrackedPrayer.isha,
        prayerTime: fixture.prayerTime(),
      );
      final stableKey = machine.stableReminderKey(state.identity.id, 1);
      final notificationId = LocalNotificationService.stableNotificationId(
        'account-a',
        stableKey,
      );
      await notifications.initialize();
      plugin.emit(
        NotificationPlatformResponse(
          id: notificationId,
          payload: jsonEncode(<String, Object>{
            'version': 1,
            'account': LocalNotificationService.accountFingerprint('account-a'),
            'key': stableKey,
          }),
          actionId: 'snooze',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(
        (await fixture.store.readOccurrence(
          userId: 'account-a',
          occurrenceId: state.identity.id,
        ))?.status,
        PrayerCompletionStatus.notYetPrayed,
      );
      expect(plugin.scheduled, hasLength(2));
      await notifications.dispose();
    },
  );
}

class _Fixture {
  _Fixture({
    required this.closeDatabase,
    required this.store,
    required this.scheduler,
    required this.clock,
  });

  final Future<void> Function() closeDatabase;
  final LocalPrayerCompletionStore store;
  final _FakeReminderScheduler scheduler;
  DateTime clock;
  String activeUserId = 'account-a';
  late final PrayerCompletionStateMachine machine = newMachine();

  PrayerCompletionStateMachine newMachine() => PrayerCompletionStateMachine(
    store: store,
    scheduler: scheduler,
    currentUserIdProvider: () => activeUserId,
    clock: () => clock,
  );

  timezone.TZDateTime prayerTime() => timezone.TZDateTime(
    PrayerTimeZones.location('Africa/Cairo'),
    2026,
    1,
    3,
    12,
  );

  Future<PrayerCompletionState> schedule() => machine.scheduleOccurrence(
    userId: 'account-a',
    prayer: TrackedPrayer.fajr,
    prayerTime: prayerTime(),
  );

  static Future<_Fixture> create() async {
    final database = await openNewInMemoryDatabase();
    final store = LocalPrayerCompletionStore(
      databaseProvider: () async => database,
    );
    return _Fixture(
      closeDatabase: database.close,
      store: store,
      scheduler: _FakeReminderScheduler(),
      clock: DateTime.utc(2026, 1, 1),
    );
  }

  Future<void> close() async {
    await machine.dispose();
    await closeDatabase();
  }
}

class _FakeReminderScheduler implements PrayerCompletionReminderScheduler {
  final Map<String, _ScheduledReminder> schedules =
      <String, _ScheduledReminder>{};
  final List<String> cancelled = <String>[];
  bool failNextSchedule = false;

  @override
  Future<void> schedule({
    required String userId,
    required String stableKey,
    required TrackedPrayer prayer,
    required int ordinal,
    required timezone.TZDateTime scheduledAt,
  }) async {
    if (failNextSchedule) {
      failNextSchedule = false;
      throw StateError('Test scheduler failure.');
    }
    schedules[stableKey] = _ScheduledReminder(scheduledAt);
  }

  @override
  Future<void> cancel({
    required String userId,
    required String stableKey,
  }) async {
    cancelled.add(stableKey);
    schedules.remove(stableKey);
  }
}

class _ScheduledReminder {
  const _ScheduledReminder(this.scheduledAt);

  final timezone.TZDateTime scheduledAt;
}

class _MemoryNotificationRegistry implements NotificationScheduleRegistry {
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
    records.putIfAbsent(accountId, () => <int, String>{})[notificationId] =
        stableKey;
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
  final Map<int, timezone.TZDateTime> scheduled = <int, timezone.TZDateTime>{};
  void Function(NotificationPlatformResponse response)? _onResponse;

  @override
  Future<void> initialize(
    void Function(NotificationPlatformResponse response) onResponse,
  ) async {
    _onResponse = onResponse;
  }

  @override
  Future<NotificationPermissionState> permissionState() async =>
      NotificationPermissionState.granted;

  @override
  Future<NotificationPermissionState> requestPermission() async =>
      NotificationPermissionState.granted;

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
    scheduled[id] = scheduledAt;
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }

  void emit(NotificationPlatformResponse response) =>
      _onResponse?.call(response);
}
