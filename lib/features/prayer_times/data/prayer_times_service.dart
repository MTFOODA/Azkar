import '../../../core/utils/app_logger.dart';
import '../domain/prayer_time_errors.dart';
import '../domain/prayer_time_models.dart';
import 'prayer_times_provider.dart';

class PrayerTimesService {
  PrayerTimesService({required this.provider, required this.cache});

  final PrayerTimesProvider provider;
  final PrayerCalendarCache cache;

  Future<PrayerCalendar?> readValidatedCachedMonthlyCalendar({
    required PrayerLocation location,
    required PrayerMonth month,
    PrayerCalculationMethod? calculationMethod,
    AsrCalculationMethod asrMethod = AsrCalculationMethod.standard,
  }) async {
    final method =
        calculationMethod ?? PrayerCalculationMethod.forLocation(location);
    final cacheKey = buildPrayerCalendarCacheKey(
      location: location,
      month: month,
      calculationMethod: method,
      asrMethod: asrMethod,
    );
    try {
      final cached = await cache.read(cacheKey);
      if (cached == null) return null;
      _validateCalendar(cached, location, month, method, asrMethod);
      return cached.copyWith(isFromCache: true);
    } on PrayerTimesException catch (error, stackTrace) {
      AppLogger.warning(
        'Prayer-time cache entry was invalid; it will be refreshed.',
        error,
        stackTrace,
      );
      return null;
    }
  }

  /// Fetches the calendar containing [instant] in the selected location's
  /// timezone, including when that local date falls in a different month/year
  /// than UTC.
  Future<PrayerCalendar> fetchCalendarForInstant({
    required PrayerLocation location,
    required DateTime instant,
    PrayerCalculationMethod? calculationMethod,
    AsrCalculationMethod asrMethod = AsrCalculationMethod.standard,
  }) async {
    final utc = instant.toUtc();
    var month = PrayerMonth(utc.year, utc.month);
    var calendar = await fetchMonthlyCalendar(
      location: location,
      month: month,
      calculationMethod: calculationMethod,
      asrMethod: asrMethod,
    );
    final local = PrayerTimeZones.localDateTime(instant, calendar.timezoneId);
    final locationMonth = PrayerMonth(local.year, local.month);
    if (locationMonth.cacheId == month.cacheId) return calendar;
    month = locationMonth;
    calendar = await fetchMonthlyCalendar(
      location: location,
      month: month,
      calculationMethod: calculationMethod,
      asrMethod: asrMethod,
    );
    return calendar;
  }

  Future<PrayerCalendar> fetchMonthlyCalendar({
    required PrayerLocation location,
    required PrayerMonth month,
    PrayerCalculationMethod? calculationMethod,
    AsrCalculationMethod asrMethod = AsrCalculationMethod.standard,
  }) async {
    final method =
        calculationMethod ?? PrayerCalculationMethod.forLocation(location);
    final cacheKey = buildPrayerCalendarCacheKey(
      location: location,
      month: month,
      calculationMethod: method,
      asrMethod: asrMethod,
    );

    PrayerCalendar? cached;
    try {
      cached = await cache.read(cacheKey);
      if (cached != null) {
        _validateCalendar(cached, location, month, method, asrMethod);
      }
    } on PrayerTimesException {
      AppLogger.warning(
        'Prayer-time cache is unavailable or invalid; refreshing from provider.',
      );
      cached = null;
    }

    final PrayerCalendar fresh;
    try {
      fresh = await provider.fetchMonthlyCalendar(
        location: location,
        month: month,
        calculationMethod: method,
        asrMethod: asrMethod,
      );
      _validateCalendar(fresh, location, month, method, asrMethod);
    } on Object catch (error) {
      if (cached != null) {
        AppLogger.warning(
          'Prayer-time provider failed; using the validated local calendar.',
        );
        return cached.copyWith(isFromCache: true);
      }
      throw PrayerTimesUnavailableException(cause: error);
    }

    await cache.write(cacheKey, fresh);
    return fresh;
  }

  static String buildPrayerCalendarCacheKey({
    required PrayerLocation location,
    required PrayerMonth month,
    required PrayerCalculationMethod calculationMethod,
    required AsrCalculationMethod asrMethod,
  }) =>
      '${location.cacheIdentifier}|${month.cacheId}|'
      '${calculationMethod.id}|${asrMethod.id}';

  void _validateCalendar(
    PrayerCalendar calendar,
    PrayerLocation location,
    PrayerMonth month,
    PrayerCalculationMethod calculationMethod,
    AsrCalculationMethod asrMethod,
  ) {
    if (calendar.year != month.year ||
        calendar.month != month.month ||
        calendar.calculationMethod != calculationMethod ||
        calendar.asrMethod != asrMethod ||
        (location.timezoneId != null &&
            calendar.timezoneId != location.timezoneId)) {
      throw const PrayerTimesDataException(
        'تقويم مواقيت الصلاة لا يطابق إعدادات الطلب.',
      );
    }
  }
}
