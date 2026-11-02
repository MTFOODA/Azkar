import '../domain/prayer_time_models.dart';

/// Replaceable source of validated prayer-time calendars.
abstract interface class PrayerTimesProvider {
  Future<PrayerCalendar> fetchMonthlyCalendar({
    required PrayerLocation location,
    required PrayerMonth month,
    required PrayerCalculationMethod calculationMethod,
    required AsrCalculationMethod asrMethod,
  });
}

/// Local cache contract; implementations must store only validated calendars.
abstract interface class PrayerCalendarCache {
  Future<PrayerCalendar?> read(String cacheKey);

  Future<void> write(String cacheKey, PrayerCalendar calendar);
}
