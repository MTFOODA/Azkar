import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/utils/app_logger.dart';
import '../../mobile_platform/domain/mobile_runtime.dart';
import '../../prayer_times/data/prayer_times_service.dart';
import '../../prayer_times/domain/prayer_time_models.dart';
import '../../reminders/data/local_prayer_schedule_location_store.dart';
import '../../reminders/data/local_reminder_preferences_store.dart';
import '../../reminders/domain/reminder_preferences.dart';

/// Publishes only a display calendar to native widgets. No account identifiers,
/// coordinates, tokens, or prayer-completion records cross this channel.
class PrayerHomeWidgetService {
  PrayerHomeWidgetService({
    required this.preferencesStore,
    required this.locationStore,
    required this.prayerTimesService,
    required this.currentUserIdProvider,
    required this.runtime,
    this.channel = const MethodChannel('azkar/home_widget'),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReminderPreferencesLocalStore preferencesStore;
  final LocalPrayerScheduleLocationStore locationStore;
  final PrayerTimesService prayerTimesService;
  final String? Function() currentUserIdProvider;
  final MobileRuntime runtime;
  final MethodChannel channel;
  final DateTime Function() _clock;
  Future<void> _tail = Future<void>.value();

  bool get isSupported => runtime.isNativeMobile;

  Future<void> clear() => _enqueue(() async {
    if (isSupported) await channel.invokeMethod<void>('clearPrayer');
  });

  Future<void> refresh(String userId) => _enqueue(() async {
    if (!isSupported || currentUserIdProvider() != userId) return;
    final preferences =
        (await preferencesStore.read(userId))?.preferences ??
        ReminderPreferences.defaults;
    final location = await locationStore.resolve(
      userId: userId,
      preferences: preferences,
    );
    if (currentUserIdProvider() != userId) return;
    if (location == null) {
      await channel.invokeMethod<void>('clearPrayer');
      return;
    }
    // Clear the previous selection first so an offline location change cannot
    // leave the old city's times visible as if they belonged to the new city.
    final selection =
        '${location.cacheIdentifier}|'
        '${preferences.calculationMethod?.id}|${preferences.asrMethod.id}';
    await channel.invokeMethod<void>('selectLocation', selection);
    final now = _clock();
    final initialMonth = location.timezoneId == null
        ? PrayerMonth(now.toUtc().year, now.toUtc().month)
        : PrayerMonth.forInstant(now, location.timezoneId!);
    Future<PrayerCalendar> calendarFor(PrayerMonth month) async {
      final cached = await prayerTimesService
          .readValidatedCachedMonthlyCalendar(
            location: location,
            month: month,
            calculationMethod: preferences.calculationMethod,
            asrMethod: preferences.asrMethod,
          );
      if (cached != null && cached.days.every((day) => day.hijri != null)) {
        return cached;
      }
      return prayerTimesService.fetchMonthlyCalendar(
        location: location,
        month: month,
        calculationMethod: preferences.calculationMethod,
        asrMethod: preferences.asrMethod,
      );
    }

    var calendar = await calendarFor(initialMonth);
    final localMonth = PrayerMonth.forInstant(now, calendar.timezoneId);
    if (localMonth.cacheId != initialMonth.cacheId) {
      calendar = await calendarFor(localMonth);
    }
    if (currentUserIdProvider() != userId) return;
    final calendars = <PrayerCalendar>[calendar];
    // Keep the following month too, including December -> January. Native
    // widgets can advance dates without starting Flutter or requesting GPS.
    final next = DateTime.utc(calendar.year, calendar.month + 1);
    try {
      calendars.add(await calendarFor(PrayerMonth(next.year, next.month)));
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Next widget calendar is unavailable.',
        error,
        stackTrace,
      );
    }
    if (currentUserIdProvider() != userId) return;
    await channel.invokeMethod<void>(
      'update',
      jsonEncode(buildPayload(location: location, calendars: calendars)),
    );
  });

  Future<bool> requestPin() async =>
      isSupported && (await channel.invokeMethod<bool>('requestPin') ?? false);

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.catchError((Object error, StackTrace stackTrace) {
      AppLogger.warning('Home-screen widget update failed.', error, stackTrace);
    });
    return next;
  }

  static Map<String, Object?> buildPayload({
    required PrayerLocation location,
    required List<PrayerCalendar> calendars,
  }) => <String, Object?>{
    'version': 1,
    'location': location.label,
    'timezone': calendars.first.timezoneId,
    'days': [
      for (final calendar in calendars)
        for (final day in calendar.days)
          <String, Object?>{
            'date': day.localDate.toIso8601String().substring(0, 10),
            if (day.hijri != null) 'hijri': day.hijri!.toJson(),
            'times': {
              for (final prayer in PrayerName.values)
                prayer.id: day.timeFor(prayer).millisecondsSinceEpoch,
            },
          },
    ],
  };
}
