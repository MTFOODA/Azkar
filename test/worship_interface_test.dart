import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/features/notifications/data/local_notification_service.dart';
import 'package:azkar/features/notifications/data/notification_platform.dart';
import 'package:azkar/features/notifications/data/notification_schedule_registry.dart';
import 'package:azkar/features/notifications/domain/local_notification.dart';
import 'package:azkar/features/worship/presentation/reminder_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  testWidgets('notification permission is requested only after user action', (
    tester,
  ) async {
    final database = await openNewInMemoryDatabase();
    addTearDown(database.close);
    final platform = _PermissionPlatform();
    final notifications = LocalNotificationService(
      platform: platform,
      registry: SembastNotificationScheduleRegistry(
        databaseProvider: () async => database,
      ),
      currentUserIdProvider: () => 'test-user',
    );
    addTearDown(notifications.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localNotificationServiceProvider.overrideWithValue(notifications),
        ],
        child: const MaterialApp(home: NotificationPermissionPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(platform.permissionRequests, 0);
    expect(
      find.text('لن نطلب الإذن تلقائياً عند تشغيل التطبيق.'),
      findsOneWidget,
    );
    expect(find.text('السماح بالإشعارات'), findsOneWidget);

    await tester.tap(find.text('السماح بالإشعارات'));
    await tester.pumpAndSettle();

    expect(platform.permissionRequests, 1);
    expect(find.text('الإذن مفعّل'), findsOneWidget);
  });
}

class _PermissionPlatform implements NotificationPlatform {
  NotificationPermissionState permission = NotificationPermissionState.denied;
  int permissionRequests = 0;
  void Function(NotificationPlatformResponse response)? onResponse;

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
    permission = NotificationPermissionState.granted;
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
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}
