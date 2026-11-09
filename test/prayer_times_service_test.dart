import 'package:azkar/features/prayer_times/data/local_prayer_calendar_cache.dart';
import 'package:azkar/features/prayer_times/data/prayer_times_provider.dart';
import 'package:azkar/features/prayer_times/data/prayer_times_service.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_errors.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  setUpAll(PrayerTimeZones.initialize);

  test('built-in UTC works for test notifications on native runtimes', () {
    final instant = DateTime.utc(2026, 11, 8, 12);
    final utc = PrayerTimeZones.localDateTime(instant, 'UTC');
    expect(utc.toUtc(), instant);
    expect(utc.timeZoneOffset, Duration.zero);
  });

  test(
    'a cache write failure does not discard successful live prayer times',
    () async {
      final month = PrayerMonth(2026, 11);
      final provider = _MutableProvider(
        _calendar(
          month,
          PrayerCalculationMethod.egyptianGeneralAuthority,
          AsrCalculationMethod.standard,
          'Africa/Cairo',
        ),
      );
      final service = PrayerTimesService(
        provider: provider,
        cache: _UnwritableCache(),
      );
      final calendar = await service.fetchMonthlyCalendar(
        location: PrayerLocation.manualCity(city: 'Cairo', country: 'Egypt'),
        month: month,
      );
      expect(calendar.days, hasLength(30));
      expect(calendar.isFromCache, isFalse);
    },
  );

  test('an empty optional time zone is treated as automatic detection', () {
    expect(
      PrayerLocation.manualCity(
        city: 'Cairo',
        country: 'Egypt',
        timezoneId: ' ',
      ).timezoneId,
      isNull,
    );
    expect(
      PrayerLocation.coordinates(
        latitude: 30,
        longitude: 31,
        timezoneId: '',
      ).timezoneId,
      isNull,
    );
  });

  test(
    'uses Egypt method 5 by default and allows another calculation method',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final provider = _MutableProvider(
        _calendar(
          PrayerMonth(2026, 11),
          PrayerCalculationMethod.egyptianGeneralAuthority,
          AsrCalculationMethod.standard,
          'Africa/Cairo',
        ),
      );
      final service = PrayerTimesService(
        provider: provider,
        cache: LocalPrayerCalendarCache(databaseProvider: () async => database),
      );
      final egypt = PrayerLocation.manualCity(
        city: 'Cairo',
        country: 'Egypt',
        countryCode: 'EG',
      );
      final otherLocation = PrayerLocation.manualCity(
        city: 'New York',
        country: 'United States',
        countryCode: 'US',
      );

      await service.fetchMonthlyCalendar(
        location: egypt,
        month: PrayerMonth(2026, 11),
      );
      expect(
        provider.lastCalculationMethod,
        PrayerCalculationMethod.egyptianGeneralAuthority,
      );

      provider.calendar = _calendar(
        PrayerMonth(2026, 11),
        PrayerCalculationMethod.northAmerica,
        AsrCalculationMethod.hanafi,
        'America/New_York',
      );
      await service.fetchMonthlyCalendar(
        location: otherLocation,
        month: PrayerMonth(2026, 11),
        calculationMethod: PrayerCalculationMethod.northAmerica,
        asrMethod: AsrCalculationMethod.hanafi,
      );
      expect(
        provider.lastCalculationMethod,
        PrayerCalculationMethod.northAmerica,
      );
      expect(provider.lastAsrMethod, AsrCalculationMethod.hanafi);
    },
  );

  test('selects Egypt method 5 for coordinates inside Egypt', () {
    final cairo = PrayerLocation.coordinates(
      latitude: 30.0444,
      longitude: 31.2357,
    );
    final newYork = PrayerLocation.coordinates(
      latitude: 40.7128,
      longitude: -74.006,
    );

    expect(
      PrayerCalculationMethod.forLocation(cairo),
      PrayerCalculationMethod.egyptianGeneralAuthority,
    );
    expect(
      PrayerCalculationMethod.forLocation(newYork),
      PrayerCalculationMethod.muslimWorldLeague,
    );
  });

  test(
    'returns a validated saved calendar when the provider is offline',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final location = PrayerLocation.manualCity(
        city: 'Cairo',
        country: 'Egypt',
        countryCode: 'EG',
      );
      final month = PrayerMonth(2026, 11);
      final provider = _MutableProvider(
        _calendar(
          month,
          PrayerCalculationMethod.egyptianGeneralAuthority,
          AsrCalculationMethod.standard,
          'Africa/Cairo',
        ),
      );
      final service = PrayerTimesService(
        provider: provider,
        cache: LocalPrayerCalendarCache(databaseProvider: () async => database),
      );

      final online = await service.fetchMonthlyCalendar(
        location: location,
        month: month,
      );
      expect(online.isFromCache, isFalse);
      provider.error = const PrayerTimesApiException('offline');

      final offline = await service.fetchMonthlyCalendar(
        location: location,
        month: month,
      );
      expect(offline.isFromCache, isTrue);
      expect(offline.days, hasLength(30));
      expect(offline.timezoneId, 'Africa/Cairo');
      expect(offline.days.first.timeFor(PrayerName.fajr).hour, 5);
    },
  );

  test('throws when neither provider nor valid cache has a calendar', () async {
    final database = await openNewInMemoryDatabase();
    addTearDown(database.close);
    final provider = _MutableProvider(null)
      ..error = const PrayerTimesApiException('offline');
    final service = PrayerTimesService(
      provider: provider,
      cache: LocalPrayerCalendarCache(databaseProvider: () async => database),
    );

    await expectLater(
      service.fetchMonthlyCalendar(
        location: PrayerLocation.manualCity(city: 'Cairo', country: 'Egypt'),
        month: PrayerMonth(2026, 11),
      ),
      throwsA(isA<PrayerTimesUnavailableException>()),
    );
  });

  test(
    'converts instants to the selected IANA zone across date boundaries',
    () {
      final instant = DateTime.utc(2026, 4, 1, 1);
      expect(
        PrayerMonth.forInstant(instant, 'America/Los_Angeles').cacheId,
        '2026-03',
      );
      expect(
        PrayerMonth.forInstant(instant, 'Africa/Cairo').cacheId,
        '2026-04',
      );
    },
  );

  test('fetches the location-local month when it differs from UTC', () async {
    final database = await openNewInMemoryDatabase();
    addTearDown(database.close);
    final provider = _MutableProvider(
      null,
      calendarFactory: (month, method, asrMethod) =>
          _calendar(month, method, asrMethod, 'America/Los_Angeles'),
    );
    final service = PrayerTimesService(
      provider: provider,
      cache: LocalPrayerCalendarCache(databaseProvider: () async => database),
    );
    final location = PrayerLocation.coordinates(
      latitude: 34.05,
      longitude: -118.25,
    );

    final calendar = await service.fetchCalendarForInstant(
      location: location,
      instant: DateTime.utc(2026, 4, 1, 1),
    );

    expect(provider.requestedMonths.map((month) => month.cacheId), [
      '2026-04',
      '2026-03',
    ]);
    expect(calendar.prayerMonth.cacheId, '2026-03');
  });

  test(
    'uses the correct offsets before and after a daylight-saving change',
    () {
      final before = PrayerTimeZones.localDateTime(
        DateTime.utc(2026, 3, 8, 6, 30),
        'America/New_York',
      );
      final after = PrayerTimeZones.localDateTime(
        DateTime.utc(2026, 3, 8, 7, 30),
        'America/New_York',
      );

      expect(
        (before.hour, before.timeZoneOffset),
        (1, const Duration(hours: -5)),
      );
      expect(
        (after.hour, after.timeZoneOffset),
        (3, const Duration(hours: -4)),
      );
    },
  );

  test(
    'changes the cache key when location timezone or calculation changes',
    () {
      final location = PrayerLocation.coordinates(
        latitude: 40.7,
        longitude: -74.0,
        timezoneId: 'America/New_York',
      );
      final changedTimezone = PrayerLocation.coordinates(
        latitude: 40.7,
        longitude: -74.0,
        timezoneId: 'America/Toronto',
      );
      String key(PrayerLocation location, PrayerCalculationMethod method) =>
          PrayerTimesService.buildPrayerCalendarCacheKey(
            location: location,
            month: PrayerMonth(2026, 11),
            calculationMethod: method,
            asrMethod: AsrCalculationMethod.standard,
          );

      expect(
        key(location, PrayerCalculationMethod.northAmerica),
        isNot(key(changedTimezone, PrayerCalculationMethod.northAmerica)),
      );
      expect(
        key(location, PrayerCalculationMethod.northAmerica),
        isNot(key(location, PrayerCalculationMethod.muslimWorldLeague)),
      );
    },
  );

  test(
    'round-trips validated calendar wall times through local cache',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final cache = LocalPrayerCalendarCache(
        databaseProvider: () async => database,
      );
      final calendar = _calendar(
        PrayerMonth(2026, 11),
        PrayerCalculationMethod.egyptianGeneralAuthority,
        AsrCalculationMethod.standard,
        'Africa/Cairo',
      );

      await cache.write('cairo-november', calendar);
      final restored = await cache.read('cairo-november');

      expect(restored, isNotNull);
      expect(restored!.timezoneId, 'Africa/Cairo');
      expect(
        restored.days.first.timeFor(PrayerName.fajr).location.name,
        'Africa/Cairo',
      );
      expect(restored.days.first.timeFor(PrayerName.fajr).hour, 5);
      expect(restored.isFromCache, isTrue);
    },
  );
}

class _MutableProvider implements PrayerTimesProvider {
  _MutableProvider(this.calendar, {this.calendarFactory});

  PrayerCalendar? calendar;
  final PrayerCalendar Function(
    PrayerMonth,
    PrayerCalculationMethod,
    AsrCalculationMethod,
  )?
  calendarFactory;
  Object? error;
  PrayerCalculationMethod? lastCalculationMethod;
  AsrCalculationMethod? lastAsrMethod;
  final requestedMonths = <PrayerMonth>[];

  @override
  Future<PrayerCalendar> fetchMonthlyCalendar({
    required PrayerLocation location,
    required PrayerMonth month,
    required PrayerCalculationMethod calculationMethod,
    required AsrCalculationMethod asrMethod,
  }) async {
    requestedMonths.add(month);
    lastCalculationMethod = calculationMethod;
    lastAsrMethod = asrMethod;
    if (error case final Object providerError) throw providerError;
    if (calendarFactory case final factory?) {
      return factory(month, calculationMethod, asrMethod);
    }
    if (calendar case final PrayerCalendar available) return available;
    throw StateError('Test provider has no calendar.');
  }
}

class _UnwritableCache implements PrayerCalendarCache {
  @override
  Future<PrayerCalendar?> read(String cacheKey) async => null;
  @override
  Future<void> write(String cacheKey, PrayerCalendar calendar) async =>
      throw const PrayerTimesCacheException('Storage is full');
}

PrayerCalendar _calendar(
  PrayerMonth month,
  PrayerCalculationMethod method,
  AsrCalculationMethod asrMethod,
  String timezoneId,
) {
  final zone = PrayerTimeZones.location(timezoneId);
  final days = List<PrayerDay>.generate(month.dayCount, (index) {
    final day = index + 1;
    return PrayerDay(
      localDate: DateTime.utc(month.year, month.month, day),
      times: <PrayerName, timezone.TZDateTime>{
        for (final prayer in PrayerName.values)
          prayer: timezone.TZDateTime(
            zone,
            month.year,
            month.month,
            day,
            5 + prayer.index,
            10,
          ),
      },
    );
  });
  return PrayerCalendar(
    year: month.year,
    month: month.month,
    timezoneId: timezoneId,
    calculationMethod: method,
    asrMethod: asrMethod,
    days: days,
    fetchedAt: DateTime.utc(2026, 10, 31),
  );
}
