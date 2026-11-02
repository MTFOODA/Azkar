import 'dart:async';

import '../../../core/utils/app_logger.dart';
import '../../notifications/data/local_notification_service.dart';
import '../../notifications/domain/local_notification.dart';
import '../domain/prayer_completion_state_machine.dart';

class PrayerCompletionNotificationCoordinator {
  factory PrayerCompletionNotificationCoordinator({
    required PrayerCompletionStateMachine stateMachine,
    required LocalNotificationService notifications,
    required String? Function() currentUserIdProvider,
  }) => PrayerCompletionNotificationCoordinator._(
    stateMachine,
    notifications,
    currentUserIdProvider,
  );

  PrayerCompletionNotificationCoordinator._(
    this._stateMachine,
    this._notifications,
    this._currentUserIdProvider,
  );

  final PrayerCompletionStateMachine _stateMachine;
  final LocalNotificationService _notifications;
  final String? Function() _currentUserIdProvider;
  StreamSubscription<NotificationActionEvent>? _subscription;

  void start() {
    _subscription ??= _notifications.actions.listen(
      _handleAction,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'Prayer-completion notification action stream failed.',
          error,
          stackTrace,
        );
      },
    );
  }

  Future<void> reconcilePendingSchedules(String userId) async {
    try {
      await _stateMachine.reconcilePendingSchedules(userId);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Could not reconcile pending prayer-completion reminders.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _handleAction(NotificationActionEvent event) async {
    final userId = _currentUserIdProvider()?.trim();
    if (userId == null ||
        userId.isEmpty ||
        event.accountFingerprint !=
            LocalNotificationService.accountFingerprint(userId)) {
      AppLogger.warning(
        'Ignored a prayer-completion action for an inactive account.',
      );
      return;
    }
    if (event.actionId == null) return;
    final action = switch (event.actionId) {
      'mark_complete' => PrayerCompletionAction.prayed,
      'snooze' => PrayerCompletionAction.notYetPrayed,
      _ => null,
    };
    final match = RegExp(
      r'^prayer-completion:v1:([a-f0-9]{64}):reminder:([12])$',
    ).firstMatch(event.stableKey);
    if (action == null ||
        match == null ||
        event.notificationId !=
            LocalNotificationService.stableNotificationId(
              userId,
              event.stableKey,
            )) {
      AppLogger.warning('Ignored an invalid prayer-completion action.');
      return;
    }
    try {
      await _stateMachine.handleAction(
        userId: userId,
        occurrenceId: match.group(1)!,
        action: action,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Could not apply a prayer-completion notification action.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
  }
}
