import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../../../features/mobile_platform/domain/mobile_runtime.dart';
import '../domain/local_notification.dart';
import 'notification_platform.dart';

class FlutterLocalNotificationPlatform
    implements
        NotificationPlatform,
        ExactNotificationAlarmPlatform,
        NotificationScheduleInspectionPlatform {
  FlutterLocalNotificationPlatform({
    FlutterLocalNotificationsPlugin? plugin,
    MobileRuntime? runtime,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _runtime = runtime ?? MobileRuntime.current();

  static const channelId = 'azkar_reminders';
  static const channelName = 'AZKAR reminders';
  static const channelDescription = 'Scheduled AZKAR reminders';
  static const categoryId = 'azkar_reminder_v1';

  final FlutterLocalNotificationsPlugin _plugin;
  final MobileRuntime _runtime;

  @override
  Future<List<PendingNativeNotification>> pendingNotifications() async =>
      (await _plugin.pendingNotificationRequests())
          .map((item) => PendingNativeNotification(item.id, item.payload))
          .toList();

  @override
  Future<bool?> exactAlarmPermissionState() async {
    if (_runtime.platform != MobileRuntimePlatform.android) return null;
    return _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.canScheduleExactNotifications();
  }

  @override
  Future<void> requestExactAlarmPermission() async {
    if (_runtime.platform != MobileRuntimePlatform.android) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  @override
  Future<void> initialize(
    void Function(NotificationPlatformResponse response) onResponse,
  ) async {
    if (!_runtime.isNativeMobile) return;
    final settings = InitializationSettings(
      android: const AndroidInitializationSettings('ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        defaultPresentAlert: true,
        defaultPresentBanner: true,
        defaultPresentList: true,
        defaultPresentSound: true,
        defaultPresentBadge: false,
        notificationCategories: <DarwinNotificationCategory>[
          DarwinNotificationCategory(
            categoryId,
            actions: <DarwinNotificationAction>[
              DarwinNotificationAction.plain(
                'mark_complete',
                'صليت',
                options: <DarwinNotificationActionOption>{
                  DarwinNotificationActionOption.foreground,
                },
              ),
              DarwinNotificationAction.plain(
                'snooze',
                'لسه مصليتش',
                options: <DarwinNotificationActionOption>{
                  DarwinNotificationActionOption.foreground,
                },
              ),
            ],
          ),
        ],
      ),
    );
    final initialized = await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        onResponse(
          NotificationPlatformResponse(
            id: response.id,
            payload: response.payload,
            actionId: response.actionId?.isEmpty == true
                ? null
                : response.actionId,
          ),
        );
      },
    );
    if (initialized != true) {
      throw const NotificationInfrastructureException(
        'The notification plugin did not initialize on this device.',
      );
    }

    if (_runtime.platform == MobileRuntimePlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: Importance.high,
        ),
      );
    }
  }

  @override
  Future<NotificationPermissionState> permissionState() async {
    if (!_runtime.isNativeMobile) {
      return NotificationPermissionState.unsupported;
    }
    if (_runtime.platform == MobileRuntimePlatform.android) {
      final enabled = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      return enabled == true
          ? NotificationPermissionState.granted
          : NotificationPermissionState.denied;
    }
    final permissions = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    return permissions == null
        ? NotificationPermissionState.denied
        : permissions.isEnabled || permissions.isProvisionalEnabled
        ? NotificationPermissionState.granted
        : NotificationPermissionState.denied;
  }

  @override
  Future<NotificationPermissionState> requestPermission() async {
    if (!_runtime.isNativeMobile) {
      return NotificationPermissionState.unsupported;
    }
    final bool? granted;
    if (_runtime.platform == MobileRuntimePlatform.android) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true, badge: false);
    }
    if (granted == true) return NotificationPermissionState.granted;
    if (granted == false) return NotificationPermissionState.denied;
    return permissionState();
  }

  @override
  Future<NotificationPlatformResponse?> getLaunchResponse() async {
    if (!_runtime.isNativeMobile) return null;
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp != true) return null;
    final response = launchDetails?.notificationResponse;
    if (response == null) return null;
    return NotificationPlatformResponse(
      id: response.id,
      payload: response.payload,
      actionId: response.actionId?.isEmpty == true ? null : response.actionId,
      wasColdStart: true,
    );
  }

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
    if (!_runtime.isNativeMobile) {
      throw const NotificationInfrastructureException(
        'Local notification scheduling is available only on Android and iOS.',
      );
    }
    final visibleTitle = hideContentOnLockScreen ? 'AZKAR | أذكار' : title;
    final visibleBody = hideContentOnLockScreen ? 'لديك تذكير من أذكار.' : body;
    await _plugin.zonedSchedule(
      id: id,
      title: visibleTitle,
      body: visibleBody,
      scheduledDate: scheduledAt,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          visibility: hideContentOnLockScreen
              ? NotificationVisibility.private
              : NotificationVisibility.public,
          actions: actions
              .map(
                (action) => AndroidNotificationAction(
                  action.id,
                  action.title,
                  showsUserInterface: true,
                  cancelNotification: false,
                ),
              )
              .toList(growable: false),
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: actions.isEmpty ? null : categoryId,
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
          presentBadge: false,
        ),
      ),
      androidScheduleMode: await exactAlarmPermissionState() == true
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(int id) async {
    if (!_runtime.isNativeMobile) return;
    await _plugin.cancel(id: id);
  }
}
