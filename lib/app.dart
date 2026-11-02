import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/app_config.dart';
import 'core/design/app_theme.dart';
import 'core/providers/app_providers.dart';
import 'core/routing/app_router.dart';
import 'core/utils/app_logger.dart';
import 'features/notifications/data/local_notification_service.dart';
import 'features/reminders/domain/reminder_preferences.dart';

/// Root application widget. Arabic RTL is the default everywhere, while the
/// router keeps public and administrative navigation independent.
class AzkarApp extends ConsumerStatefulWidget {
  const AzkarApp({super.key});

  @override
  ConsumerState<AzkarApp> createState() => _AzkarAppState();
}

class _AzkarAppState extends ConsumerState<AzkarApp>
    with WidgetsBindingObserver {
  late final ProviderSubscription<User?> _accountSubscription;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final Map<String, Future<void>> _syncInFlight = <String, Future<void>>{};
  final Map<String, DateTime> _lastSyncAt = <String, DateTime>{};
  final Set<String> _syncAgain = <String>{};
  bool? _hasConnectivity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final completionCoordinator = ref.read(
      prayerCompletionNotificationCoordinatorProvider,
    )..start();
    final tasbeehOutboxCoordinator = ref.read(tasbeehOutboxCoordinatorProvider)
      ..start();
    final notificationService = ref.read(localNotificationServiceProvider);
    final account = ref.read(accountSessionProvider);
    notificationService.setActiveAccount(account?.id);
    if (notificationService.isSupported) {
      unawaited(_initializeNotifications(notificationService));
    }
    if (account != null) {
      unawaited(_syncPreferences(account.id, 'login', force: true));
      unawaited(completionCoordinator.reconcilePendingSchedules(account.id));
      unawaited(tasbeehOutboxCoordinator.reconcilePending(account.id));
      unawaited(_reconcileReminderSchedules(account.id, 'startup'));
    }
    _accountSubscription = ref.listenManual<User?>(
      accountSessionProvider,
      (previous, next) => _accountChanged(previous, next),
    );
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _connectivityChanged,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.error(
          'Could not observe connectivity changes for reminder sync.',
          error,
          stackTrace,
        );
      },
    );
    unawaited(_readInitialConnectivity());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final userId = ref.read(accountSessionProvider)?.id;
      if (userId != null) {
        unawaited(_syncPreferences(userId, 'resume'));
        unawaited(
          ref
              .read(prayerCompletionNotificationCoordinatorProvider)
              .reconcilePendingSchedules(userId),
        );
        unawaited(
          ref.read(tasbeehOutboxCoordinatorProvider).reconcilePending(userId),
        );
        unawaited(_reconcileReminderSchedules(userId, 'resume'));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accountSubscription.close();
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }

  Future<void> _initializeNotifications(
    LocalNotificationService service,
  ) async {
    try {
      await service.initialize();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Could not initialize local notifications.',
        error,
        stackTrace,
      );
    }
  }

  void _accountChanged(User? previous, User? next) {
    if (previous?.id == next?.id) return;
    final notificationService = ref.read(localNotificationServiceProvider);
    notificationService.setActiveAccount(next?.id);
    final previousId = previous?.id;
    if (previousId != null) {
      unawaited(
        _cancelPreviousAccountNotifications(notificationService, previousId),
      );
    }
    if (next != null) {
      unawaited(_syncPreferences(next.id, 'login', force: true));
      unawaited(
        ref
            .read(prayerCompletionNotificationCoordinatorProvider)
            .reconcilePendingSchedules(next.id),
      );
      unawaited(
        ref.read(tasbeehOutboxCoordinatorProvider).reconcilePending(next.id),
      );
      unawaited(_reconcileReminderSchedules(next.id, 'login'));
    }
  }

  Future<void> _cancelPreviousAccountNotifications(
    LocalNotificationService service,
    String accountId,
  ) async {
    try {
      await service.cancelAccount(accountId);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Could not cancel notifications for the previous account.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _syncPreferences(
    String userId,
    String trigger, {
    bool force = false,
  }) async {
    if (!mounted || ref.read(accountSessionProvider)?.id != userId) return;
    final existing = _syncInFlight[userId];
    if (existing != null) {
      if (force) _syncAgain.add(userId);
      await existing;
      if (_syncAgain.remove(userId)) {
        await _syncPreferences(userId, trigger, force: true);
      }
      return;
    }
    final now = DateTime.now();
    final lastSyncAt = _lastSyncAt[userId];
    if (!force &&
        lastSyncAt != null &&
        now.difference(lastSyncAt) < const Duration(seconds: 2)) {
      return;
    }
    _lastSyncAt[userId] = now;
    final operation = _performPreferenceSync(userId, trigger);
    _syncInFlight[userId] = operation;
    try {
      await operation;
    } finally {
      if (identical(_syncInFlight[userId], operation)) {
        _syncInFlight.remove(userId);
      }
    }
  }

  Future<void> _performPreferenceSync(String userId, String trigger) async {
    try {
      final result = await ref
          .read(reminderPreferencesSyncServiceProvider)
          .sync(userId);
      if (result.status == ReminderSyncStatus.conflict) {
        AppLogger.warning(
          'Reminder preferences need explicit conflict resolution after $trigger.',
        );
      }
      await _reconcileReminderSchedules(userId, 'preference-sync');
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Reminder preference sync failed after $trigger.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _readInitialConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _hasConnectivity ??= _isConnected(results);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Could not read initial connectivity for reminder sync.',
        error,
        stackTrace,
      );
    }
  }

  void _connectivityChanged(List<ConnectivityResult> results) {
    final connected = _isConnected(results);
    final restored = connected && _hasConnectivity != true;
    _hasConnectivity = connected;
    if (!restored) return;
    final userId = ref.read(accountSessionProvider)?.id;
    if (userId != null) {
      unawaited(_syncPreferences(userId, 'connectivity', force: true));
      unawaited(
        ref
            .read(prayerCompletionNotificationCoordinatorProvider)
            .reconcilePendingSchedules(userId),
      );
      unawaited(
        ref.read(tasbeehOutboxCoordinatorProvider).reconcilePending(userId),
      );
      unawaited(_reconcileReminderSchedules(userId, 'connectivity'));
    }
  }

  Future<void> _reconcileReminderSchedules(
    String userId,
    String trigger,
  ) async {
    if (!mounted || ref.read(accountSessionProvider)?.id != userId) return;
    try {
      final result = await ref
          .read(localReminderSchedulingEngineProvider)
          .reconcile(userId);
      if (result.skippedForCapacity > 0) {
        AppLogger.warning(
          'Reminder schedule capacity was reached after $trigger; '
          '${result.skippedForCapacity} later reminders were deferred.',
        );
      }
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Could not reconcile local reminder schedules after $trigger.',
        error,
        stackTrace,
      );
    }
  }

  bool _isConnected(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(themeSettingsProvider);
    final mode = ref.watch(themeModeProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: AppConfig.siteTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(settings),
      darkTheme: AppTheme.dark(settings),
      themeMode: mode,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
