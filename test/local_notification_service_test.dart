import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:azkar/core/storage/local_database.dart';
import 'package:azkar/core/utils/app_exception.dart';
import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:azkar/features/notifications/data/local_notification_service.dart';
import 'package:azkar/features/notifications/data/notification_platform.dart';
import 'package:azkar/features/notifications/data/notification_schedule_registry.dart';
import 'package:azkar/features/notifications/domain/local_notification.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  setUpAll(PrayerTimeZones.initialize);

  test('stable IDs are deterministic and account-scoped', () {
    final id = LocalNotificationService.stableNotificationId(
      'account-a',
      'fajr:2026-11-03',
    );

    expect(
      LocalNotificationService.stableNotificationId(
        'account-a',
        'fajr:2026-11-03',
      ),
      id,
    );
    expect(
      LocalNotificationService.stableNotificationId(
        'account-b',
        'fajr:2026-11-03',
      ),
      isNot(id),
    );
    expect(id, inInclusiveRange(0, 0x7fffffff));
  });

  test('foreground adopts owned actions and replaces background or foreign schedules', () async {
    final platform = _InspectingPlatform();
    final service = _service(platform, _MemoryNotificationRegistry());
    addTearDown(service.dispose);
    service.setActiveAccount('account-a');
    const backgroundKey = 'reminder-background:v1:morning-azkar:test';
    const completionKey = 'prayer-completion:v1:test:reminder:1';
    final backgroundId = LocalNotificationService.stableNotificationId(
      'account-a',
      backgroundKey,
    );
    final foreignId = LocalNotificationService.stableNotificationId(
      'account-b',
      backgroundKey,
    );
    final completionId = LocalNotificationService.stableNotificationId(
      'account-a',
      completionKey,
    );
    platform.pending.addAll([
      PendingNativeNotification(
        backgroundId,
        _payload('account-a', backgroundKey),
      ),
      PendingNativeNotification(
        foreignId,
        _payload('account-b', backgroundKey),
      ),
      PendingNativeNotification(
        completionId,
        _payload('account-a', completionKey),
      ),
    ]);
    await service.adoptNativeSchedules('account-a');
    expect(platform.cancelled, containsAll([backgroundId, foreignId]));
    expect(platform.cancelled, isNot(contains(completionId)));
    expect(await service.registeredSchedules('account-a'), {
      completionKey: completionId,
    });
    await service.cancelInactiveNativeSchedules(null);
    expect(platform.cancelled, contains(completionId));
  });

  test('initialization recovers after a transient plugin failure', () async {
    final platform = _FakeNotificationPlatform()..failInitialization = true;
    final service = _service(platform, _MemoryNotificationRegistry());
    addTearDown(service.dispose);
    await expectLater(service.initialize(), throwsStateError);
    platform.failInitialization = false;
    await service.initialize();
    expect(platform.initializeCalls, 2);
    expect(
      await service.permissionState(),
      NotificationPermissionState.granted,
    );
  });

  test(
    'scheduling is idempotent and uses the supplied IANA time zone',
    () async {
      final platform = _FakeNotificationPlatform();
      final registry = _MemoryNotificationRegistry();
      final service = _service(platform, registry);
      service.setActiveAccount('account-a');

      final scheduledAt = timezone.TZDateTime(
        PrayerTimeZones.location('America/New_York'),
        2026,
        3,
        8,
        3,
        30,
      );
      final request = _request(
        scheduledAt: scheduledAt,
        stableKey: 'fajr:2026-03-08',
      );
      final firstId = await service.schedule(request);
      final secondId = await service.schedule(request);

      expect(firstId, secondId);
      expect(platform.scheduled.keys.toList(), <int>[firstId]);
      expect(
        platform.scheduled[firstId]?.scheduledAt.location.name,
        'America/New_York',
      );
      expect(
        platform.scheduled[firstId]?.scheduledAt.toUtc(),
        scheduledAt.toUtc(),
      );
      await service.dispose();
    },
  );

  test(
    'permission denial prevents scheduling without requesting permission',
    () async {
      final platform = _FakeNotificationPlatform()
        ..permission = NotificationPermissionState.denied;
      final service = _service(platform, _MemoryNotificationRegistry());
      service.setActiveAccount('account-a');

      await expectLater(
        service.schedule(_request()),
        throwsA(isA<NotificationInfrastructureException>()),
      );
      expect(platform.permissionRequests, 0);
      expect(platform.scheduled, isEmpty);
      await service.dispose();
    },
  );

  test('cancellation is limited to the requested account', () async {
    final platform = _FakeNotificationPlatform();
    final registry = _MemoryNotificationRegistry();
    final service = _service(platform, registry);
    service.setActiveAccount('account-a');
    final firstId = await service.schedule(_request(stableKey: 'morning'));
    final secondId = await service.schedule(_request(stableKey: 'evening'));
    service.setActiveAccount('account-b');

    await service.cancelAccount('account-a');

    expect(platform.cancelled.toSet(), <int>{firstId, secondId});
    expect(await registry.notificationIds('account-a'), isEmpty);
    expect(await registry.notificationIds('account-b'), isEmpty);
    await service.dispose();
  });

  test(
    'account changes during scheduling cancel the stale notification',
    () async {
      final platform = _FakeNotificationPlatform()
        ..scheduleBarrier = Completer<void>();
      final registry = _MemoryNotificationRegistry();
      final service = _service(platform, registry);
      service.setActiveAccount('account-a');

      final scheduling = service.schedule(_request());
      await Future<void>.delayed(Duration.zero);
      service.setActiveAccount('account-b');
      platform.scheduleBarrier!.complete();

      await expectLater(scheduling, throwsA(isA<NotAuthorizedException>()));
      expect(platform.cancelled, hasLength(1));
      expect(await registry.notificationIds('account-a'), isEmpty);
      await service.dispose();
    },
  );

  test(
    'web runtime is supported without invoking native notification APIs',
    () async {
      final platform = _FakeNotificationPlatform();
      final service = _service(
        platform,
        _MemoryNotificationRegistry(),
        runtime: const MobileRuntime(
          isWeb: true,
          targetPlatform: TargetPlatform.android,
        ),
      );

      await service.initialize();

      expect(platform.initializeCalls, 0);
      expect(
        await service.permissionState(),
        NotificationPermissionState.unsupported,
      );
      await expectLater(
        service.schedule(_request()),
        throwsA(isA<NotificationInfrastructureException>()),
      );
      expect(platform.scheduled, isEmpty);
      await service.dispose();
    },
  );

  test(
    'cold-start actions are queued and malformed or inactive actions ignored',
    () async {
      const accountId = 'account-a';
      const stableKey = 'fajr:2026-11-03';
      final id = LocalNotificationService.stableNotificationId(
        accountId,
        stableKey,
      );
      final platform = _FakeNotificationPlatform()
        ..launchResponse = NotificationPlatformResponse(
          id: id,
          payload: _payload(accountId, stableKey),
          actionId: 'mark_complete',
          wasColdStart: true,
        );
      final service = _service(platform, _MemoryNotificationRegistry());
      service.setActiveAccount(accountId);
      await service.initialize();

      final pending = await service.takePendingActions(accountId);
      expect(pending, hasLength(1));
      expect(pending.single.wasColdStart, isTrue);
      expect(pending.single.actionId, 'mark_complete');

      final events = <NotificationActionEvent>[];
      final subscription = service.actions.listen(events.add);
      platform.emit(
        const NotificationPlatformResponse(
          id: -1,
          payload: '{malformed',
          actionId: 'mark_complete',
        ),
      );
      platform.emit(
        NotificationPlatformResponse(
          id: LocalNotificationService.stableNotificationId(
            'account-b',
            stableKey,
          ),
          payload: _payload('account-b', stableKey),
          actionId: 'mark_complete',
        ),
      );
      platform.emit(
        NotificationPlatformResponse(
          id: LocalNotificationService.stableNotificationId(
            accountId,
            '$stableKey:other',
          ),
          payload: _payload(accountId, stableKey),
          actionId: 'mark_complete',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
      await subscription.cancel();
      await service.dispose();
    },
  );

  test(
    'Sembast notification registry rejects a mismatched account row',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final store = stringMapStoreFactory.store(
        LocalStores.notificationSchedules,
      );
      await store.record('account:account-a').put(database, <String, Object?>{
        'account_id': 'account-b',
        'notifications': <String, String>{'12': 'fajr'},
      });
      final registry = SembastNotificationScheduleRegistry(
        databaseProvider: () async => database,
      );

      await expectLater(
        registry.notificationIds('account-a'),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test(
    'Sembast registry prevents notification IDs colliding across accounts',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final registry = SembastNotificationScheduleRegistry(
        databaseProvider: () async => database,
      );
      await registry.register(
        accountId: 'account-a',
        stableKey: 'morning',
        notificationId: 7,
      );

      await expectLater(
        registry.register(
          accountId: 'account-b',
          stableKey: 'evening',
          notificationId: 7,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}

LocalNotificationService _service(
  _FakeNotificationPlatform platform,
  NotificationScheduleRegistry registry, {
  MobileRuntime? runtime,
}) {
  var activeUserId = 'account-a';
  return LocalNotificationService(
    platform: platform,
    registry: registry,
    currentUserIdProvider: () => activeUserId,
    runtime: runtime,
    clock: () => DateTime.utc(2026, 1, 1),
  )..setActiveAccount(activeUserId);
}

LocalNotificationRequest _request({
  String stableKey = 'fajr:2026-11-03',
  timezone.TZDateTime? scheduledAt,
}) => LocalNotificationRequest(
  accountId: 'account-a',
  stableKey: stableKey,
  title: 'Prayer reminder',
  body: 'It is time to pray.',
  scheduledAt:
      scheduledAt ??
      timezone.TZDateTime(
        PrayerTimeZones.location('Africa/Cairo'),
        2026,
        11,
        3,
        5,
      ),
);

String _payload(String accountId, String stableKey) =>
    jsonEncode(<String, Object>{
      'version': 1,
      'account': sha256
          .convert(utf8.encode(accountId))
          .toString()
          .substring(0, 24),
      'key': stableKey,
    });

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
  bool failInitialization = false;
  NotificationPermissionState permission = NotificationPermissionState.granted;
  NotificationPlatformResponse? launchResponse;
  Completer<void>? scheduleBarrier;
  int initializeCalls = 0;
  int permissionRequests = 0;
  final Map<int, _ScheduledRequest> scheduled = <int, _ScheduledRequest>{};
  final List<int> cancelled = <int>[];
  void Function(NotificationPlatformResponse response)? _onResponse;

  @override
  Future<void> initialize(
    void Function(NotificationPlatformResponse response) onResponse,
  ) async {
    initializeCalls++;
    if (failInitialization) {
      throw StateError('Temporary initialization failure');
    }
    _onResponse = onResponse;
  }

  @override
  Future<NotificationPermissionState> permissionState() async => permission;

  @override
  Future<NotificationPermissionState> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<NotificationPlatformResponse?> getLaunchResponse() async =>
      launchResponse;

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
    await scheduleBarrier?.future;
    scheduled[id] = _ScheduledRequest(scheduledAt);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  void emit(NotificationPlatformResponse response) =>
      _onResponse?.call(response);
}

class _InspectingPlatform extends _FakeNotificationPlatform
    implements NotificationScheduleInspectionPlatform {
  final pending = <PendingNativeNotification>[];
  @override
  Future<List<PendingNativeNotification>> pendingNotifications() async =>
      pending;
}

class _ScheduledRequest {
  const _ScheduledRequest(this.scheduledAt);

  final timezone.TZDateTime scheduledAt;
}
