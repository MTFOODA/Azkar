import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../mobile_platform/domain/mobile_runtime.dart';
import '../../prayer_times/domain/prayer_time_models.dart';
import '../domain/local_notification.dart';
import 'notification_platform.dart';
import 'notification_schedule_registry.dart';

class LocalNotificationService {
  static const int maxPendingNotificationsPerAccount =
      SembastNotificationScheduleRegistry.maxPendingNotificationsPerAccount;

  factory LocalNotificationService({
    required NotificationPlatform platform,
    required NotificationScheduleRegistry registry,
    required String? Function() currentUserIdProvider,
    MobileRuntime? runtime,
    DateTime Function()? clock,
  }) => LocalNotificationService._(
    platform,
    registry,
    currentUserIdProvider,
    runtime ?? MobileRuntime.current(),
    clock ?? DateTime.now,
  );

  LocalNotificationService._(
    this._platform,
    this._registry,
    this.currentUserIdProvider,
    this._runtime,
    this._clock,
  );

  final NotificationPlatform _platform;
  final NotificationScheduleRegistry _registry;
  final String? Function() currentUserIdProvider;
  final MobileRuntime _runtime;
  final DateTime Function() _clock;
  final StreamController<NotificationActionEvent> _actionController =
      StreamController<NotificationActionEvent>.broadcast();
  final List<NotificationActionEvent> _pendingActions =
      <NotificationActionEvent>[];
  Future<void>? _initialization;
  String? _activeAccountId;

  Stream<NotificationActionEvent> get actions => _actionController.stream;

  bool get isSupported => _runtime.isNativeMobile;

  Future<void> initialize() {
    if (!isSupported) return Future<void>.value();
    return _initialization ??= _initialize().catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      _initialization = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _initialize() async {
    PrayerTimeZones.initialize();
    await _platform.initialize(_receiveResponse);
    final launchResponse = await _platform.getLaunchResponse();
    if (launchResponse != null) {
      _receiveResponse(launchResponse);
    }
  }

  Future<NotificationPermissionState> permissionState() async {
    if (!isSupported) return NotificationPermissionState.unsupported;
    await initialize();
    return _platform.permissionState();
  }

  Future<NotificationPermissionState> requestPermission() async {
    if (!isSupported) return NotificationPermissionState.unsupported;
    await initialize();
    return _platform.requestPermission();
  }

  Future<bool?> exactAlarmPermissionState() async {
    if (!isSupported) return null;
    await initialize();
    final platform = _platform;
    return platform is ExactNotificationAlarmPlatform
        ? (platform as ExactNotificationAlarmPlatform)
              .exactAlarmPermissionState()
        : null;
  }

  Future<void> requestExactAlarmPermission() async {
    if (!isSupported) return;
    await initialize();
    final platform = _platform;
    if (platform is ExactNotificationAlarmPlatform) {
      await (platform as ExactNotificationAlarmPlatform)
          .requestExactAlarmPermission();
    }
  }

  void setActiveAccount(String? accountId) {
    final normalizedId = accountId?.trim();
    _activeAccountId = normalizedId?.isEmpty == true ? null : normalizedId;
    if (_activeAccountId == null) return;
    final fingerprint = accountFingerprint(_activeAccountId!);
    final ready = _pendingActions
        .where((event) => event.accountFingerprint == fingerprint)
        .toList(growable: false);
    _pendingActions.removeWhere(
      (event) => event.accountFingerprint != fingerprint,
    );
    for (final event in ready) {
      if (_isValidEventForAccount(event, _activeAccountId!)) {
        if (_actionController.hasListener) {
          _actionController.add(event);
          _pendingActions.remove(event);
        }
      } else {
        AppLogger.warning(
          'Ignored a notification action with an inconsistent identifier.',
        );
        _pendingActions.remove(event);
      }
    }
  }

  Future<List<NotificationActionEvent>> takePendingActions(
    String accountId,
  ) async {
    _requireActiveAccount(accountId);
    final fingerprint = accountFingerprint(accountId);
    final ready = _pendingActions
        .where(
          (event) =>
              event.accountFingerprint == fingerprint &&
              _isValidEventForAccount(event, accountId),
        )
        .toList(growable: false);
    if (_pendingActions.any(
      (event) =>
          event.accountFingerprint == fingerprint &&
          !_isValidEventForAccount(event, accountId),
    )) {
      AppLogger.warning(
        'Discarded a queued notification action with an inconsistent identifier.',
      );
    }
    _pendingActions.removeWhere(
      (event) => event.accountFingerprint == fingerprint,
    );
    return ready;
  }

  Future<int> schedule(LocalNotificationRequest request) async {
    _requireActiveAccount(request.accountId);
    if (!isSupported) {
      throw const NotificationInfrastructureException(
        'Local notification scheduling is available only on Android and iOS.',
      );
    }
    await initialize();
    final now = _clock().toUtc();
    if (!request.scheduledAt.toUtc().isAfter(now)) {
      throw ArgumentError.value(
        request.scheduledAt,
        'scheduledAt',
        'A notification must be scheduled in the future.',
      );
    }
    if (await _platform.permissionState() !=
        NotificationPermissionState.granted) {
      throw const NotificationInfrastructureException(
        'Notification permission has not been granted.',
      );
    }
    _requireActiveAccount(request.accountId);

    final id = stableNotificationId(request.accountId, request.stableKey);
    final existingKey = await _registry.stableKeyForId(request.accountId, id);
    if (existingKey != null && existingKey != request.stableKey) {
      throw StateError('A stable notification identifier collided.');
    }
    final payload = jsonEncode(<String, Object>{
      'version': 1,
      'account': accountFingerprint(request.accountId),
      'key': request.stableKey,
    });
    await _registry.register(
      accountId: request.accountId,
      stableKey: request.stableKey,
      notificationId: id,
    );
    try {
      await _platform.schedule(
        id: id,
        scheduledAt: request.scheduledAt,
        title: request.title,
        body: request.body,
        payload: payload,
        actions: request.actions,
        hideContentOnLockScreen: request.hideContentOnLockScreen,
      );
    } on Object catch (error, stackTrace) {
      try {
        await _platform.cancel(id);
      } on Object catch (cleanupError, cleanupStackTrace) {
        AppLogger.error(
          'Could not clean up an incomplete local notification.',
          cleanupError,
          cleanupStackTrace,
        );
      }
      try {
        await _registry.remove(
          accountId: request.accountId,
          notificationId: id,
        );
      } on Object catch (cleanupError, cleanupStackTrace) {
        AppLogger.error(
          'Could not remove an incomplete notification registry entry.',
          cleanupError,
          cleanupStackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (_activeUserId != request.accountId) {
      await _platform.cancel(id);
      await _registry.remove(accountId: request.accountId, notificationId: id);
      throw const NotAuthorizedException(
        messageAr: 'تغيّر الحساب قبل اكتمال جدولة التذكير.',
      );
    }
    return id;
  }

  Future<int> scheduleIfAbsent(LocalNotificationRequest request) async {
    _requireActiveAccount(request.accountId);
    final id = stableNotificationId(request.accountId, request.stableKey);
    final existingKey = await _registry.stableKeyForId(request.accountId, id);
    if (existingKey == request.stableKey) return id;
    return schedule(request);
  }

  Future<Map<String, int>> registeredSchedules(String accountId) {
    _requireActiveAccount(accountId);
    return _registry.schedules(accountId);
  }

  /// Reconciles schedules written by the background isolate with this registry.
  /// Foreground takes over ordinary reminders; completion actions stay local.
  Future<void> adoptNativeSchedules(
    String accountId, {
    bool background = false,
  }) async {
    if (!isSupported || _platform is! NotificationScheduleInspectionPlatform) {
      return;
    }
    await initialize();
    final pending = await (_platform as NotificationScheduleInspectionPlatform)
        .pendingNotifications();
    final ids = pending.map((item) => item.id).toSet();
    for (final entry in (await _registry.schedules(accountId)).entries) {
      if (!ids.contains(entry.value)) {
        await _registry.remove(
          accountId: accountId,
          notificationId: entry.value,
        );
      }
    }
    for (final item in pending) {
      final event = _parseResponse(
        NotificationPlatformResponse(
          id: item.id,
          payload: item.payload,
          actionId: null,
        ),
      );
      if (event == null) continue;
      final sameAccount =
          event.accountFingerprint == accountFingerprint(accountId);
      final replace = background
          ? event.stableKey.startsWith('reminder-engine:v1:')
          : event.stableKey.startsWith('reminder-background:v1:');
      if (!sameAccount || replace) {
        await _platform.cancel(item.id);
        if (sameAccount) {
          await _registry.remove(accountId: accountId, notificationId: item.id);
        }
      } else if (item.id == stableNotificationId(accountId, event.stableKey)) {
        await _registry.register(
          accountId: accountId,
          stableKey: event.stableKey,
          notificationId: item.id,
        );
      }
    }
  }

  Future<void> cancelInactiveNativeSchedules(String? activeAccountId) async {
    if (!isSupported || _platform is! NotificationScheduleInspectionPlatform) {
      return;
    }
    await initialize();
    final fingerprint = activeAccountId == null
        ? null
        : accountFingerprint(activeAccountId);
    for (final pending
        in await (_platform as NotificationScheduleInspectionPlatform)
            .pendingNotifications()) {
      final event = _parseResponse(
        NotificationPlatformResponse(
          id: pending.id,
          payload: pending.payload,
          actionId: null,
        ),
      );
      if (event != null && event.accountFingerprint != fingerprint) {
        await _platform.cancel(pending.id);
      }
    }
  }

  Future<void> cancel({
    required String accountId,
    required String stableKey,
  }) async {
    if (accountId.trim().isEmpty || stableKey.trim().isEmpty) {
      throw ArgumentError('An account and stable key are required.');
    }
    if (!isSupported) return;
    await initialize();
    final id = stableNotificationId(accountId, stableKey);
    await _platform.cancel(id);
    await _registry.remove(accountId: accountId, notificationId: id);
  }

  Future<void> cancelAccount(String accountId) async {
    if (accountId.trim().isEmpty) throw ArgumentError.value(accountId);
    if (!isSupported) return;
    await initialize();
    final ids = await _registry.notificationIds(accountId);
    if (_platform is NotificationScheduleInspectionPlatform) {
      for (final pending
          in await (_platform as NotificationScheduleInspectionPlatform)
              .pendingNotifications()) {
        final event = _parseResponse(
          NotificationPlatformResponse(
            id: pending.id,
            payload: pending.payload,
            actionId: null,
          ),
        );
        if (event?.accountFingerprint == accountFingerprint(accountId) &&
            !ids.contains(pending.id)) {
          ids.add(pending.id);
        }
      }
    }
    for (final id in ids) {
      await _platform.cancel(id);
      await _registry.remove(accountId: accountId, notificationId: id);
    }
  }

  Future<void> dispose() => _actionController.close();

  void _receiveResponse(NotificationPlatformResponse response) {
    final event = _parseResponse(response);
    if (event == null) return;
    final activeId = _activeUserId;
    if (activeId != null &&
        accountFingerprint(activeId) != event.accountFingerprint) {
      AppLogger.warning(
        'Ignored a notification action belonging to an inactive account.',
      );
      return;
    }
    if (activeId != null && !_isValidEventForAccount(event, activeId)) {
      AppLogger.warning(
        'Ignored a notification action with an inconsistent identifier.',
      );
      return;
    }
    if (activeId == null) {
      _pendingActions.add(event);
      return;
    }
    _deliverAction(event);
  }

  bool _isValidEventForAccount(
    NotificationActionEvent event,
    String accountId,
  ) =>
      event.accountFingerprint == accountFingerprint(accountId) &&
      event.notificationId == stableNotificationId(accountId, event.stableKey);

  void _deliverAction(NotificationActionEvent event) {
    if (_actionController.hasListener) {
      _actionController.add(event);
    } else {
      _pendingActions.add(event);
    }
  }

  NotificationActionEvent? _parseResponse(
    NotificationPlatformResponse response,
  ) {
    final payload = response.payload;
    final id = response.id;
    if (payload == null || id == null) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['account'] is! String ||
          decoded['key'] is! String ||
          (response.actionId != null &&
              !NotificationActionDefinition.supportedActionIds.contains(
                response.actionId,
              ))) {
        throw const FormatException('Unsupported notification action payload.');
      }
      final accountFingerprint = decoded['account']! as String;
      final stableKey = decoded['key']! as String;
      if (!_isValidFingerprint(accountFingerprint) || stableKey.isEmpty) {
        throw const FormatException('Invalid notification action payload.');
      }
      return NotificationActionEvent(
        notificationId: id,
        accountFingerprint: accountFingerprint,
        stableKey: stableKey,
        actionId: response.actionId,
        receivedAt: _clock().toUtc(),
        wasColdStart: response.wasColdStart,
      );
    } on FormatException catch (error, stackTrace) {
      AppLogger.warning(
        'Discarded a malformed notification action payload.',
        error,
        stackTrace,
      );
      return null;
    }
  }

  String? get _activeUserId =>
      _activeAccountId ?? currentUserIdProvider()?.trim();

  void _requireActiveAccount(String accountId) {
    if (accountId.trim().isEmpty) throw ArgumentError.value(accountId);
    if (_activeUserId != accountId) {
      throw const NotAuthorizedException(
        messageAr: 'يرجى تسجيل الدخول بالحساب المطلوب لجدولة التذكيرات.',
      );
    }
  }

  static int stableNotificationId(String accountId, String stableKey) {
    if (accountId.trim().isEmpty || stableKey.trim().isEmpty) {
      throw ArgumentError('An account and stable key are required.');
    }
    final digest = sha256.convert(utf8.encode('$accountId:$stableKey')).bytes;
    var value = 0;
    for (final byte in digest.take(4)) {
      value = (value << 8) | byte;
    }
    return value & 0x7fffffff;
  }

  static String accountFingerprint(String accountId) =>
      sha256.convert(utf8.encode(accountId)).toString().substring(0, 24);

  static bool _isValidFingerprint(String value) =>
      RegExp(r'^[a-f0-9]{24}$').hasMatch(value);
}
