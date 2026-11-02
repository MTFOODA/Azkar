import 'package:timezone/timezone.dart' as timezone;

enum NotificationPermissionState { granted, denied, unsupported }

class NotificationActionDefinition {
  NotificationActionDefinition({required this.id, required this.title}) {
    if (!RegExp(r'^[a-z][a-z0-9_]{0,39}$').hasMatch(id) ||
        title.trim().isEmpty ||
        title.trim().length > 40) {
      throw ArgumentError('Invalid notification action.');
    }
    if (!supportedActionIds.contains(id)) {
      throw ArgumentError.value(id, 'id', 'Unsupported notification action.');
    }
  }

  static const supportedActionIds = <String>{'mark_complete', 'snooze'};

  final String id;
  final String title;
}

class LocalNotificationRequest {
  LocalNotificationRequest({
    required this.accountId,
    required this.stableKey,
    required this.title,
    required this.body,
    required this.scheduledAt,
    List<NotificationActionDefinition> actions =
        const <NotificationActionDefinition>[],
    this.hideContentOnLockScreen = false,
  }) : actions = List<NotificationActionDefinition>.unmodifiable(actions) {
    if (accountId.trim().isEmpty ||
        stableKey.trim().isEmpty ||
        stableKey.length > 200) {
      throw ArgumentError('Notification account and stable key are required.');
    }
    if (title.trim().isEmpty || body.trim().isEmpty) {
      throw ArgumentError('Notification title and body are required.');
    }
    if (title.length > 200 || body.length > 1000) {
      throw ArgumentError('Notification text exceeds supported limits.');
    }
    if (this.actions.length > 2 ||
        this.actions.map((action) => action.id).toSet().length !=
            this.actions.length) {
      throw ArgumentError('Notification actions must be unique and limited.');
    }
  }

  final String accountId;
  final String stableKey;
  final String title;
  final String body;
  final timezone.TZDateTime scheduledAt;
  final List<NotificationActionDefinition> actions;
  final bool hideContentOnLockScreen;
}

class NotificationActionEvent {
  const NotificationActionEvent({
    required this.notificationId,
    required this.accountFingerprint,
    required this.stableKey,
    required this.actionId,
    required this.receivedAt,
    required this.wasColdStart,
  });

  final int notificationId;
  final String accountFingerprint;
  final String stableKey;
  final String? actionId;
  final DateTime receivedAt;
  final bool wasColdStart;
}

class NotificationInfrastructureException implements Exception {
  const NotificationInfrastructureException(this.message);

  final String message;

  @override
  String toString() => 'NotificationInfrastructureException: $message';
}

class NotificationScheduleLimitException
    extends NotificationInfrastructureException {
  const NotificationScheduleLimitException()
    : super('The account notification schedule limit was reached.');
}
