import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../../../core/utils/app_logger.dart';
import '../../home_widget/data/prayer_home_widget_service.dart';
import '../../mobile_platform/domain/mobile_runtime.dart';
import '../../notifications/data/flutter_local_notification_platform.dart';
import '../../notifications/data/local_notification_service.dart';
import '../../notifications/data/notification_platform.dart';
import '../../notifications/data/notification_schedule_registry.dart';
import '../../notifications/domain/local_notification.dart';
import '../../prayer_times/data/aladhan_prayer_times_provider.dart';
import '../../prayer_times/data/local_prayer_calendar_cache.dart';
import '../../prayer_times/data/prayer_times_service.dart';
import '../../prayer_times/domain/prayer_time_models.dart';
import '../../prayer_tracking/data/local_prayer_completion_store.dart';
import '../../prayer_tracking/data/local_prayer_completion_reminder_scheduler.dart';
import '../../prayer_tracking/domain/prayer_completion_state_machine.dart';
import '../domain/reminder_preferences.dart';
import 'local_prayer_schedule_location_store.dart';
import 'local_reminder_preferences_store.dart';
import 'local_reminder_scheduling_engine.dart';

const backgroundReminderTask = 'com.azkar.azkar.refresh-reminders';
const _snapshotKey = 'azkar.reminders.background.v1';
const _foregroundLeaseKey = 'azkar.reminders.foreground-until';
const _backgroundLocationKey = 'azkar.reminders.background-location.v1';
const _widgetChannel = MethodChannel('azkar/home_widget');

@pragma('vm:entry-point')
void backgroundReminderDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      return await runBackgroundReminderRefresh();
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Background reminder refresh failed.',
        error,
        stackTrace,
      );
      return false;
    }
  });
}

class BackgroundReminderService {
  BackgroundReminderService({required this.runtime, this.currentUserId});
  final MobileRuntime runtime;
  final String? Function()? currentUserId;
  final SharedPreferencesAsync _storage = SharedPreferencesAsync();
  Timer? _heartbeat;
  Future<void> _tail = Future.value();
  static Future<void>? _initialization;

  static Future<void> initialize() {
    if (!MobileRuntime.current().isNativeMobile) return Future.value();
    return _initialization ??= Workmanager()
        .initialize(backgroundReminderDispatcher)
        .catchError((Object error, StackTrace trace) {
          _initialization = null;
          Error.throwWithStackTrace(error, trace);
        });
  }

  Future<void> setForeground(bool foreground) async {
    if (!runtime.isNativeMobile) return;
    _heartbeat?.cancel();
    await _writeLease(foreground);
    if (foreground) {
      _heartbeat = Timer.periodic(const Duration(seconds: 45), (_) {
        unawaited(
          _writeLease(true).catchError((Object error) {
            AppLogger.warning('Could not refresh the foreground lease.', error);
          }),
        );
      });
    }
  }

  Future<void> _writeLease(bool active) => _storage.setInt(
    _foregroundLeaseKey,
    active
        ? DateTime.now().add(const Duration(minutes: 2)).millisecondsSinceEpoch
        : 0,
  );

  Future<void> save(
    String userId,
    ReminderPreferences preferences,
    PrayerLocation? location,
    List<PrayerCalendar> calendars,
  ) => _serialize(() async {
    if (!runtime.isNativeMobile) return;
    await initialize();
    if (currentUserId != null && currentUserId!() != userId) return;
    final identity = jsonEncode([
      userId,
      preferences.toJson(),
      location?.cacheIdentifier,
    ]);
    final now = DateTime.now();
    final zone = calendars.isEmpty
        ? null
        : PrayerTimeZones.location(calendars.first.timezoneId);
    final local = zone == null ? now : tz.TZDateTime.from(now, zone);
    final completionUntil = zone == null
        ? now.add(const Duration(days: 3))
        : tz.TZDateTime(zone, local.year, local.month, local.day + 3);
    await _storage.setString(
      _snapshotKey,
      jsonEncode({
        'version': 1,
        'generation': sha256.convert(utf8.encode(identity)).toString(),
        'user': userId,
        'preferences': preferences.toJson(),
        'location': location?.kind == PrayerLocationKind.coordinates
            ? {'latitude': location!.latitude, 'longitude': location.longitude}
            : null,
        'calendars': calendars.map((item) => item.toJson()).toList(),
        'completion_until': completionUntil.toUtc().toIso8601String(),
      }),
    );
    await _widgetChannel.invokeMethod<void>(
      'setBackgroundGeneration',
      sha256.convert(utf8.encode(identity)).toString(),
    );
    await Workmanager().registerPeriodicTask(
      backgroundReminderTask,
      backgroundReminderTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );
  });

  Future<void> clear() => _serialize(() async {
    if (!runtime.isNativeMobile) return;
    await _storage.remove(_snapshotKey);
    await _storage.remove(_backgroundLocationKey);
    await _widgetChannel.invokeMethod<void>('setBackgroundGeneration', null);
    await initialize();
    await Workmanager().cancelByUniqueName(backgroundReminderTask);
  });

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.catchError((Object error) {
      AppLogger.warning('Background reminder configuration failed.', error);
    });
    return result;
  }

  void dispose() => _heartbeat?.cancel();
}

/// Uses an isolated in-memory database. It never concurrently opens the app's
/// Sembast file, initializes Supabase, or stores credentials in worker input.
Future<bool> runBackgroundReminderRefresh() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = SharedPreferencesAsync();
  if ((await storage.getInt(_foregroundLeaseKey) ?? 0) >
      DateTime.now().millisecondsSinceEpoch) {
    return true;
  }
  final raw = await storage.getString(_snapshotKey);
  if (raw == null) return true;
  final snapshot = jsonDecode(raw) as Map<String, dynamic>;
  if (snapshot['version'] != 1) return true;
  final userId = snapshot['user'] as String;
  final preferences = ReminderPreferences.fromJson(
    Map<String, dynamic>.from(snapshot['preferences'] as Map),
  );
  final generation = snapshot['generation'] as String;
  final updatedLocation = await storage.getString(_backgroundLocationKey);
  if (updatedLocation != null) {
    final updated = jsonDecode(updatedLocation) as Map;
    if (updated['generation'] == generation) {
      snapshot['location'] = updated['location'];
      snapshot['calendars'] = updated['calendars'];
    }
  }
  final db = await openNewInMemoryDatabase();
  final client = http.Client();
  final platform = _GuardedBackgroundPlatform(storage, generation);
  final notifications = LocalNotificationService(
    platform: platform,
    registry: SembastNotificationScheduleRegistry(
      databaseProvider: () async => db,
    ),
    currentUserIdProvider: () => userId,
  )..setActiveAccount(userId);
  final stateMachine = PrayerCompletionStateMachine(
    store: LocalPrayerCompletionStore(databaseProvider: () async => db),
    scheduler: LocalPrayerCompletionReminderScheduler(notifications),
    currentUserIdProvider: () => userId,
  );
  try {
    final preferenceStore = SembastReminderPreferencesStore(
      databaseProvider: () async => db,
    );
    await preferenceStore.saveLocal(userId: userId, preferences: preferences);
    final locationStore = LocalPrayerScheduleLocationStore(
      databaseProvider: () async => db,
      allowManualLocation: false,
    );
    final storedLocation = snapshot['location'];
    PrayerLocation? location = storedLocation is Map
        ? PrayerLocation.coordinates(
            latitude: (storedLocation['latitude'] as num).toDouble(),
            longitude: (storedLocation['longitude'] as num).toDouble(),
          )
        : null;
    var moved = false;
    try {
      if (await Geolocator.checkPermission() == LocationPermission.always &&
          await Geolocator.isLocationServiceEnabled()) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 12),
          ),
        );
        if (location == null ||
            Geolocator.distanceBetween(
                  location.latitude!,
                  location.longitude!,
                  position.latitude,
                  position.longitude,
                ) >=
                2000) {
          location = PrayerLocation.coordinates(
            latitude: position.latitude,
            longitude: position.longitude,
          );
          moved = true;
        }
      }
    } on Object catch (error) {
      AppLogger.warning(
        'Background location is unavailable; keeping the last authorized location.',
        error,
      );
    }
    if (location != null) {
      await locationStore.saveDeviceLocation(
        userId: userId,
        location: location,
      );
    }
    final cache = LocalPrayerCalendarCache(databaseProvider: () async => db);
    if (!moved && location != null) {
      for (final rawCalendar in (snapshot['calendars'] as List? ?? [])) {
        final calendar = PrayerCalendar.fromJson(
          Map<String, dynamic>.from(rawCalendar as Map),
        );
        await cache.write(
          PrayerTimesService.buildPrayerCalendarCacheKey(
            location: location,
            month: calendar.prayerMonth,
            calculationMethod: calendar.calculationMethod,
            asrMethod: calendar.asrMethod,
          ),
          calendar,
        );
      }
    }
    await LocalReminderSchedulingEngine(
      preferencesStore: preferenceStore,
      locationStore: locationStore,
      prayerTimesService: PrayerTimesService(
        provider: AlAdhanPrayerTimesProvider(client: client),
        cache: cache,
      ),
      notifications: notifications,
      prayerCompletionStateMachine: stateMachine,
      currentUserIdProvider: () => userId,
      backgroundMode: true,
      persistBackgroundSnapshot:
          (_, settings, resolvedLocation, calendars) async {
            await platform._check();
            if (resolvedLocation == null || calendars.isEmpty) return;
            await storage.setString(
              _backgroundLocationKey,
              jsonEncode({
                'generation': generation,
                'location': {
                  'latitude': resolvedLocation.latitude,
                  'longitude': resolvedLocation.longitude,
                },
                'calendars': calendars.map((item) => item.toJson()).toList(),
              }),
            );
            await platform._check();
            await _widgetChannel.invokeMethod<void>('updateBackground', {
              'generation': generation,
              'calendar': jsonEncode(
                PrayerHomeWidgetService.buildPayload(
                  location: resolvedLocation,
                  calendars: calendars,
                ),
              ),
            });
          },
      foregroundCompletionUntil: DateTime.tryParse(
        '${snapshot['completion_until']}',
      ),
    ).reconcile(userId);
    return true;
  } on _ObsoleteBackgroundTask {
    return true;
  } finally {
    client.close();
    await stateMachine.dispose();
    await notifications.dispose();
    await db.close();
  }
}

class _ObsoleteBackgroundTask implements Exception {}

class _GuardedBackgroundPlatform
    implements NotificationPlatform, NotificationScheduleInspectionPlatform {
  _GuardedBackgroundPlatform(this.storage, this.generation);
  final SharedPreferencesAsync storage;
  final String generation;
  final FlutterLocalNotificationPlatform delegate =
      FlutterLocalNotificationPlatform();
  Future<void> _check() async {
    final raw = await storage.getString(_snapshotKey);
    if (raw == null ||
        (jsonDecode(raw) as Map)['generation'] != generation ||
        (await storage.getInt(_foregroundLeaseKey) ?? 0) >
            DateTime.now().millisecondsSinceEpoch) {
      throw _ObsoleteBackgroundTask();
    }
  }

  @override
  Future<void> initialize(
    void Function(NotificationPlatformResponse) onResponse,
  ) => delegate.initialize(onResponse);
  @override
  Future<NotificationPermissionState> permissionState() async {
    await _check();
    return delegate.permissionState();
  }

  @override
  Future<NotificationPermissionState> requestPermission() => permissionState();
  @override
  Future<NotificationPlatformResponse?> getLaunchResponse() async => null;
  @override
  Future<List<PendingNativeNotification>> pendingNotifications() async {
    await _check();
    return delegate.pendingNotifications();
  }

  @override
  Future<void> cancel(int id) async {
    await _check();
    await delegate.cancel(id);
  }

  @override
  Future<void> schedule({
    required int id,
    required tz.TZDateTime scheduledAt,
    required String title,
    required String body,
    required String payload,
    required List<NotificationActionDefinition> actions,
    required bool hideContentOnLockScreen,
  }) async {
    await _check();
    await delegate.schedule(
      id: id,
      scheduledAt: scheduledAt,
      title: title,
      body: body,
      payload: payload,
      actions: actions,
      hideContentOnLockScreen: hideContentOnLockScreen,
    );
    try {
      await _check();
    } on _ObsoleteBackgroundTask {
      await delegate.cancel(id);
      rethrow;
    }
  }
}
