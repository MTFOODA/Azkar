import 'dart:async';

import '../../../core/utils/app_logger.dart';
import '../domain/prayer_completion_state_machine.dart';

class TasbeehOutboxCoordinator {
  TasbeehOutboxCoordinator({
    required this._stateMachine,
    required this._consumer,
    required this._currentUserIdProvider,
  });

  final PrayerCompletionStateMachine _stateMachine;
  final Future<void> Function(PrayerCompletionTasbeehEvent event) _consumer;
  final String? Function() _currentUserIdProvider;
  StreamSubscription<PrayerCompletionTasbeehEvent>? _subscription;

  void start() {
    _subscription ??= _stateMachine.postPrayerTasbeehEvents.listen((event) {
      if (_currentUserIdProvider()?.trim() != event.userId) return;
      unawaited(reconcilePending(event.userId));
    });
  }

  Future<void> reconcilePending(String userId) async {
    if (_currentUserIdProvider()?.trim() != userId) return;
    try {
      await _stateMachine.deliverPendingTasbeehEvents(
        userId: userId,
        consumer: _consumer,
      );
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Could not deliver a pending post-prayer Tasbeeh event.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
  }
}
