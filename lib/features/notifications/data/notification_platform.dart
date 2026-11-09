import 'package:timezone/timezone.dart' as timezone;

import '../domain/local_notification.dart';

abstract interface class ExactNotificationAlarmPlatform {
  /// Null on platforms without a separate exact-alarm permission.
  Future<bool?> exactAlarmPermissionState();
  Future<void> requestExactAlarmPermission();
}

class PendingNativeNotification {
  const PendingNativeNotification(this.id, this.payload);
  final int id;
  final String? payload;
}

abstract interface class NotificationScheduleInspectionPlatform {
  Future<List<PendingNativeNotification>> pendingNotifications();
}

class NotificationPlatformResponse {
  const NotificationPlatformResponse({
    required this.id,
    required this.payload,
    required this.actionId,
    this.wasColdStart = false,
  });

  final int? id;
  final String? payload;
  final String? actionId;
  final bool wasColdStart;
}

abstract interface class NotificationPlatform {
  Future<void> initialize(
    void Function(NotificationPlatformResponse response) onResponse,
  );

  Future<NotificationPermissionState> permissionState();

  Future<NotificationPermissionState> requestPermission();

  Future<NotificationPlatformResponse?> getLaunchResponse();

  Future<void> schedule({
    required int id,
    required timezone.TZDateTime scheduledAt,
    required String title,
    required String body,
    required String payload,
    required List<NotificationActionDefinition> actions,
    required bool hideContentOnLockScreen,
  });

  Future<void> cancel(int id);
}
