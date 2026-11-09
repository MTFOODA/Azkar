import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../../../core/utils/app_logger.dart';
import '../../notifications/data/local_notification_service.dart';
import '../../notifications/domain/local_notification.dart';
import '../../prayer_times/data/prayer_times_service.dart';
import '../../prayer_times/domain/prayer_time_errors.dart';
import '../../prayer_times/domain/prayer_time_models.dart';
import '../../prayer_tracking/domain/prayer_completion_state_machine.dart';
import '../domain/reminder_preferences.dart';
import '../domain/reminder_schedule_engine.dart';
import 'local_prayer_schedule_location_store.dart';
import 'local_reminder_preferences_store.dart';

class LocalReminderSchedulingEngine {
  LocalReminderSchedulingEngine({
    required this.preferencesStore,
    required this.locationStore,
    required this.prayerTimesService,
    required this.notifications,
    required this.prayerCompletionStateMachine,
    required this.currentUserIdProvider,
    this.refreshHomeWidget,
    this.persistBackgroundSnapshot,
    this.backgroundMode = false,
    this.foregroundCompletionUntil,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const int rollingHorizonDays = 3;
  static const int maxEngineSchedules = 30;
  static const int maxPendingNotifications =
      LocalNotificationService.maxPendingNotificationsPerAccount;
  static const Duration maxPrayerCalendarAge = Duration(days: 45);
  String get _keyPrefix =>
      backgroundMode ? 'reminder-background:v1:' : 'reminder-engine:v1:';

  final ReminderPreferencesLocalStore preferencesStore;
  final LocalPrayerScheduleLocationStore locationStore;
  final PrayerTimesService prayerTimesService;
  final LocalNotificationService notifications;
  final PrayerCompletionStateMachine prayerCompletionStateMachine;
  final String? Function() currentUserIdProvider;
  final Future<void> Function(String userId)? refreshHomeWidget;
  final Future<void> Function(
    String,
    ReminderPreferences,
    PrayerLocation?,
    List<PrayerCalendar>,
  )?
  persistBackgroundSnapshot;
  final bool backgroundMode;
  final DateTime? foregroundCompletionUntil;
  final DateTime Function() _clock;
  final Map<String, Future<void>> _inFlight = <String, Future<void>>{};

  Future<ReminderScheduleReport> reconcile(String userId) {
    _validateUser(userId);
    final previous = _inFlight[userId] ?? Future<void>.value();
    final result = previous.then(
      (_) => _reconcile(userId),
      onError: (_, _) => _reconcile(userId),
    );
    final tail = result.then<void>((_) {}, onError: (_, _) {});
    _inFlight[userId] = tail;
    return result.whenComplete(() {
      if (identical(_inFlight[userId], tail)) _inFlight.remove(userId);
    });
  }

  Future<ReminderScheduleReport> _reconcile(String userId) async {
    try {
      await refreshHomeWidget?.call(userId);
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Could not refresh the home widget.',
        error,
        stackTrace,
      );
    }
    if (!notifications.isSupported) {
      return const ReminderScheduleReport(
        scheduledCount: 0,
        cancelledCount: 0,
        skippedForCapacity: 0,
        prayerTimesAvailable: false,
        notificationPermissionGranted: false,
      );
    }
    if (await notifications.permissionState() !=
        NotificationPermissionState.granted) {
      AppLogger.warning(
        'Reminder schedules were left unchanged because notification permission is not granted.',
      );
      return const ReminderScheduleReport(
        scheduledCount: 0,
        cancelledCount: 0,
        skippedForCapacity: 0,
        prayerTimesAvailable: false,
        notificationPermissionGranted: false,
      );
    }
    await notifications.adoptNativeSchedules(
      userId,
      background: backgroundMode,
    );
    await prayerCompletionStateMachine.cancelExpiredSchedules(userId);
    final local = await preferencesStore.read(userId);
    final preferences = local?.preferences ?? ReminderPreferences.defaults;
    final location = await locationStore.resolve(
      userId: userId,
      preferences: preferences,
    );
    final calendars = <String, PrayerCalendar>{};
    var prayerTimesAvailable = false;
    String? resolvedTimezoneId =
        location?.timezoneId ??
        (location == null ? preferences.timezoneId : null);
    if (location != null) {
      try {
        final calendar = await _calendarForCurrentDate(
          location: location,
          preferences: preferences,
        );
        resolvedTimezoneId = calendar.timezoneId;
        if (_isFresh(calendar)) {
          calendars[calendar.prayerMonth.cacheId] = calendar;
          prayerTimesAvailable = true;
          final zone = PrayerTimeZones.location(calendar.timezoneId);
          final localNow = timezone.TZDateTime.from(_clock(), zone);
          for (var offset = 0; offset < rollingHorizonDays; offset++) {
            final dayDate = timezone.TZDateTime(
              zone,
              localNow.year,
              localNow.month,
              localNow.day + offset,
            );
            final month = PrayerMonth(dayDate.year, dayDate.month);
            if (!calendars.containsKey(month.cacheId)) {
              final nextCalendar = await _calendarForMonth(
                location: location,
                month: month,
                preferences: preferences,
              );
              if (!_isFresh(nextCalendar)) {
                prayerTimesAvailable = false;
                calendars.clear();
                break;
              }
              calendars[month.cacheId] = nextCalendar;
            }
          }
        } else {
          AppLogger.warning(
            'Prayer reminders were not scheduled because local prayer times are stale.',
          );
        }
      } on PrayerTimesException catch (error, stackTrace) {
        prayerTimesAvailable = false;
        calendars.clear();
        AppLogger.warning(
          'Prayer reminders were not scheduled because no validated calendar is available.',
          error,
          stackTrace,
        );
      }
    }

    final calendar = calendars.isEmpty ? null : calendars.values.first;
    final timezoneId = calendar?.timezoneId ?? resolvedTimezoneId;
    final candidates = timezoneId == null
        ? <_Candidate>[]
        : _buildCandidates(
            preferences: preferences,
            calendars: prayerTimesAvailable ? calendars : const {},
            timezoneId: timezoneId,
            location: location,
            now: _clock(),
          );

    var existing = await notifications.registeredSchedules(userId);
    if (!preferences.postPrayerTasbeehEnabled) {
      for (final key in existing.keys.where(
        (key) => key.startsWith('post-prayer-tasbeeh:v1:'),
      )) {
        await notifications.cancel(accountId: userId, stableKey: key);
      }
    } else {
      final zoneId = calendar?.timezoneId ?? resolvedTimezoneId;
      if (zoneId != null) {
        final localToday = timezone.TZDateTime.from(
          _clock(),
          PrayerTimeZones.location(zoneId),
        );
        final todayKey = _dateKey(localToday);
        for (final key in existing.keys.where(
          (key) => key.startsWith('post-prayer-tasbeeh:v1:'),
        )) {
          final match = RegExp(r'^post-prayer-tasbeeh:v1:(\d{4}-\d{2}-\d{2}):')
              .firstMatch(key);
          if (match == null || match.group(1)!.compareTo(todayKey) < 0) {
            await notifications.cancel(accountId: userId, stableKey: key);
          }
        }
      }
    }
    existing = await notifications.registeredSchedules(userId);
    var engineExisting = existing.keys
        .where((key) => key.startsWith(_keyPrefix))
        .toSet();
    var externalCount = existing.length - engineExisting.length;
    final existingCompletionCount = existing.keys
        .where((key) => key.startsWith('prayer-completion:v1:'))
        .length;
    final possibleCompletionCount =
        rollingHorizonDays * TrackedPrayer.values.length;
    final completionSlotsToReserve =
        !backgroundMode &&
            preferences.prayerRemindersEnabled &&
            prayerTimesAvailable
        ? (possibleCompletionCount - existingCompletionCount).clamp(
            0,
            possibleCompletionCount,
          )
        : 0;
    final preCompletionEngineLimit =
        (maxPendingNotifications - externalCount - completionSlotsToReserve)
            .clamp(0, maxEngineSchedules)
            .toInt();
    final preCompletionKeys = candidates
        .take(preCompletionEngineLimit)
        .map((candidate) => candidate.key)
        .toSet();
    var cancelledCount = 0;
    for (final staleKey in engineExisting.difference(preCompletionKeys)) {
      await notifications.cancel(accountId: userId, stableKey: staleKey);
      cancelledCount++;
    }

    var completionSkippedForCapacity = 0;
    if (!backgroundMode &&
        preferences.prayerRemindersEnabled &&
        prayerTimesAvailable) {
      completionSkippedForCapacity = await _scheduleCompletionReminders(
        userId: userId,
        preferences: preferences,
        calendars: calendars,
        timezoneId: calendar!.timezoneId,
      );
    } else {
      await prayerCompletionStateMachine.cancelAccountSchedules(userId);
    }

    existing = await notifications.registeredSchedules(userId);
    engineExisting = existing.keys
        .where((key) => key.startsWith(_keyPrefix))
        .toSet();
    externalCount = existing.length - engineExisting.length;
    final remainingGlobalSlots = (maxPendingNotifications - externalCount)
        .clamp(0, maxPendingNotifications)
        .toInt();
    final engineLimit = remainingGlobalSlots < maxEngineSchedules
        ? remainingGlobalSlots
        : maxEngineSchedules;
    final selected = candidates.take(engineLimit).toList(growable: false);
    final selectedKeys = selected.map((candidate) => candidate.key).toSet();
    for (final staleKey in engineExisting.difference(selectedKeys)) {
      await notifications.cancel(accountId: userId, stableKey: staleKey);
      cancelledCount++;
    }

    var scheduledCount = 0;
    for (final candidate in selected) {
      await notifications.schedule(
        LocalNotificationRequest(
          accountId: userId,
          stableKey: candidate.key,
          title: candidate.title,
          body: candidate.body,
          scheduledAt: candidate.scheduledAt,
          hideContentOnLockScreen: preferences.hideNotificationContent,
        ),
      );
      scheduledCount++;
    }
    await persistBackgroundSnapshot?.call(
      userId,
      preferences,
      location,
      calendars.values.toList(),
    );
    return ReminderScheduleReport(
      scheduledCount: scheduledCount,
      cancelledCount: cancelledCount,
      skippedForCapacity:
          candidates.length - selected.length + completionSkippedForCapacity,
      prayerTimesAvailable: prayerTimesAvailable,
      notificationPermissionGranted: true,
    );
  }

  Future<ReminderScheduleReport> saveLocalPreferencesAndReconcile({
    required String userId,
    required ReminderPreferences preferences,
  }) async {
    _validateUser(userId);
    await preferencesStore.saveLocal(userId: userId, preferences: preferences);
    return reconcile(userId);
  }

  Future<ReminderScheduleReport> saveDeviceLocationAndReconcile({
    required String userId,
    required PrayerLocation location,
  }) async {
    _validateUser(userId);
    await locationStore.saveDeviceLocation(userId: userId, location: location);
    return reconcile(userId);
  }

  Future<ReminderScheduleReport> clearDeviceLocationAndReconcile(
    String userId,
  ) async {
    _validateUser(userId);
    await locationStore.clearDeviceLocation(userId);
    return reconcile(userId);
  }

  Future<int> _scheduleCompletionReminders({
    required String userId,
    required ReminderPreferences preferences,
    required Map<String, PrayerCalendar> calendars,
    required String timezoneId,
  }) async {
    final zone = PrayerTimeZones.location(timezoneId);
    final now = timezone.TZDateTime.from(_clock(), zone);
    var skippedForCapacity = 0;
    for (var offset = 0; offset < rollingHorizonDays; offset++) {
      final date = timezone.TZDateTime(
        zone,
        now.year,
        now.month,
        now.day + offset,
      );
      final key = PrayerMonth(date.year, date.month).cacheId;
      final prayerDay = calendars[key]?.dayForInstant(date);
      if (prayerDay == null) continue;
      for (final prayer in TrackedPrayer.values) {
        final prayerTime = prayerDay.timeFor(prayer.prayerTimeName);
        if (prayerTime
            .add(PrayerCompletionState.firstReminderDelay)
            .isAfter(now)) {
          try {
            await prayerCompletionStateMachine.scheduleOccurrence(
              userId: userId,
              prayer: prayer,
              prayerTime: prayerTime,
            );
          } on NotificationScheduleLimitException catch (error, stackTrace) {
            skippedForCapacity++;
            AppLogger.warning(
              'Prayer-completion reminder remains pending because the notification schedule limit was reached.',
              error,
              stackTrace,
            );
          }
        }
      }
    }
    return skippedForCapacity;
  }

  List<_Candidate> _buildCandidates({
    required ReminderPreferences preferences,
    required Map<String, PrayerCalendar> calendars,
    required String timezoneId,
    required PrayerLocation? location,
    required DateTime now,
  }) {
    final zone = PrayerTimeZones.location(timezoneId);
    final localNow = timezone.TZDateTime.from(now, zone);
    final candidates = <_Candidate>[];
    for (var offset = 0; offset < rollingHorizonDays; offset++) {
      final date = timezone.TZDateTime(
        zone,
        localNow.year,
        localNow.month,
        localNow.day + offset,
      );
      final dateKey = _dateKey(date);
      final monthKey = PrayerMonth(date.year, date.month).cacheId;
      final prayerDay = calendars[monthKey]?.dayForInstant(date);
      if (prayerDay != null && location != null) {
        for (final prayer in TrackedPrayer.values) {
          final prayerTime = prayerDay.timeFor(prayer.prayerTimeName);
          final followup = prayerTime.add(
            PrayerCompletionState.firstReminderDelay,
          );
          if (backgroundMode &&
              preferences.prayerRemindersEnabled &&
              followup.isAfter(localNow) &&
              (foregroundCompletionUntil == null ||
                  !prayerTime.isBefore(foregroundCompletionUntil!)) &&
              !ReminderQuietHours.contains(followup, preferences)) {
            candidates.add(
              _Candidate(
                key: _key(
                  'prayer-followup',
                  '${location.cacheIdentifier}|${prayer.id}|$dateKey',
                ),
                title: 'تذكير بالصلاة',
                body: 'هل أتممت صلاة ${_prayerArabic(prayer)}؟',
                scheduledAt: followup,
              ),
            );
          }
          if (preferences.prayerTimeNotificationsEnabled &&
              !ReminderQuietHours.contains(prayerTime, preferences) &&
              prayerTime.isAfter(localNow)) {
            candidates.add(
              _Candidate(
                key: _key(
                  'prayer-time',
                  '${location.cacheIdentifier}|$timezoneId|${prayer.id}|$dateKey',
                ),
                title: 'موعد الصلاة',
                body: 'حان وقت صلاة ${_prayerArabic(prayer)}.',
                scheduledAt: prayerTime,
              ),
            );
          }
        }
      }
      if (preferences.morningAzkarEnabled) {
        _addWallClockCandidate(
          candidates,
          zone: zone,
          date: date,
          time: preferences.morningAzkarTime,
          key: _key('morning-azkar', '$timezoneId|$dateKey'),
          title: 'أذكار الصباح',
          body: 'حان وقت أذكار الصباح.',
          preferences: preferences,
          now: localNow,
        );
      }
      if (preferences.eveningAzkarEnabled) {
        _addWallClockCandidate(
          candidates,
          zone: zone,
          date: date,
          time: preferences.eveningAzkarTime,
          key: _key('evening-azkar', '$timezoneId|$dateKey'),
          title: 'أذكار المساء',
          body: 'حان وقت أذكار المساء.',
          preferences: preferences,
          now: localNow,
        );
      }
      if (preferences.fridayKahfEnabled && date.weekday == DateTime.friday) {
        _addWallClockCandidate(
          candidates,
          zone: zone,
          date: date,
          time: preferences.fridayKahfTime,
          key: _key('friday-kahf', '$timezoneId|$dateKey'),
          title: 'سورة الكهف',
          body: 'تذكير بقراءة سورة الكهف.',
          preferences: preferences,
          now: localNow,
        );
      }
      for (final configuration in preferences.configurations) {
        if (!configuration.enabled ||
            !_isSupportedCustomKind(configuration.kind) ||
            !_matchesRecurrence(configuration, date.weekday)) {
          continue;
        }
        final parameters = configuration.parameters;
        final time = parameters['time'];
        final body = parameters['text'];
        final title = parameters['title'];
        if (time is! String ||
            body is! String ||
            body.trim().isEmpty ||
            (title != null && title is! String)) {
          throw FormatException(
            'Custom reminder "${configuration.id}" has invalid text or time.',
          );
        }
        _addWallClockCandidate(
          candidates,
          zone: zone,
          date: date,
          time: time,
          key: _key('custom', '$timezoneId|${configuration.id}|$dateKey'),
          title: title is String && title.trim().isNotEmpty
              ? title.trim()
              : 'تذكير مخصص',
          body: body.trim(),
          preferences: preferences,
          now: localNow,
        );
      }
    }
    candidates.sort(
      (left, right) => left.scheduledAt.compareTo(right.scheduledAt),
    );
    return candidates;
  }

  void _addWallClockCandidate(
    List<_Candidate> candidates, {
    required timezone.Location zone,
    required timezone.TZDateTime date,
    required String time,
    required String key,
    required String title,
    required String body,
    required ReminderPreferences preferences,
    required timezone.TZDateTime now,
  }) {
    final scheduledAt = ReminderQuietHours.atWallClock(
      zone: zone,
      date: date,
      clockTime: time,
    );
    if (scheduledAt == null) return;
    final adjusted = ReminderQuietHours.defer(scheduledAt, preferences);
    if (adjusted != null && adjusted.isAfter(now)) {
      candidates.add(
        _Candidate(key: key, title: title, body: body, scheduledAt: adjusted),
      );
    }
  }

  bool _matchesRecurrence(ReminderConfiguration configuration, int weekday) {
    final recurrence = configuration.parameters['recurrence'];
    final days = configuration.parameters['days'];
    if (recurrence != null &&
        recurrence != 'daily' &&
        recurrence != 'specific_days') {
      throw FormatException(
        'Custom reminder "${configuration.id}" has an unsupported recurrence.',
      );
    }
    if (recurrence == 'daily') return true;
    if (days == null && recurrence != 'specific_days') return true;
    if (days is! List ||
        days.isEmpty ||
        days.any((day) => day is! int || day < 1 || day > 7)) {
      throw FormatException(
        'Custom reminder "${configuration.id}" needs valid weekdays.',
      );
    }
    return days.contains(weekday);
  }

  bool _isSupportedCustomKind(String kind) => const <String>{
    'custom_remembrance',
    'custom_daily_remembrance',
    'custom_azkar',
    'custom_dua',
    'dua',
  }.contains(kind.trim().toLowerCase());

  bool _isFresh(PrayerCalendar calendar) {
    final age = _clock().toUtc().difference(calendar.fetchedAt.toUtc());
    return !age.isNegative && age <= maxPrayerCalendarAge;
  }

  Future<PrayerCalendar> _calendarForCurrentDate({
    required PrayerLocation location,
    required ReminderPreferences preferences,
  }) async {
    final timezoneId = location.timezoneId;
    if (timezoneId != null) {
      final month = PrayerMonth.forInstant(_clock(), timezoneId);
      return _calendarForMonth(
        location: location,
        month: month,
        preferences: preferences,
      );
    }

    final utc = _clock().toUtc();
    final utcMonth = PrayerMonth(utc.year, utc.month);
    final cached = await prayerTimesService.readValidatedCachedMonthlyCalendar(
      location: location,
      month: utcMonth,
      calculationMethod: preferences.calculationMethod,
      asrMethod: preferences.asrMethod,
    );
    if (cached != null && _isFresh(cached)) return cached;
    return prayerTimesService.fetchCalendarForInstant(
      location: location,
      instant: _clock(),
      calculationMethod: preferences.calculationMethod,
      asrMethod: preferences.asrMethod,
    );
  }

  Future<PrayerCalendar> _calendarForMonth({
    required PrayerLocation location,
    required PrayerMonth month,
    required ReminderPreferences preferences,
  }) async {
    final cached = await prayerTimesService.readValidatedCachedMonthlyCalendar(
      location: location,
      month: month,
      calculationMethod: preferences.calculationMethod,
      asrMethod: preferences.asrMethod,
    );
    if (cached != null && _isFresh(cached)) return cached;
    return prayerTimesService.fetchMonthlyCalendar(
      location: location,
      month: month,
      calculationMethod: preferences.calculationMethod,
      asrMethod: preferences.asrMethod,
    );
  }

  String _key(String kind, String identity) =>
      '$_keyPrefix$kind:${sha256.convert(utf8.encode(identity))}';

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _prayerArabic(TrackedPrayer prayer) => switch (prayer) {
    TrackedPrayer.fajr => 'الفجر',
    TrackedPrayer.dhuhr => 'الظهر',
    TrackedPrayer.asr => 'العصر',
    TrackedPrayer.maghrib => 'المغرب',
    TrackedPrayer.isha => 'العشاء',
  };

  void _validateUser(String userId) {
    if (userId.trim().isEmpty) throw ArgumentError.value(userId, 'userId');
    if (currentUserIdProvider()?.trim() != userId) {
      throw StateError('The active account does not own these reminders.');
    }
  }
}

class _Candidate {
  const _Candidate({
    required this.key,
    required this.title,
    required this.body,
    required this.scheduledAt,
  });

  final String key;
  final String title;
  final String body;
  final timezone.TZDateTime scheduledAt;
}
