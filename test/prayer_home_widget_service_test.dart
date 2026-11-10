import 'dart:async';
import 'dart:convert';

import 'package:azkar/features/home_widget/data/prayer_home_widget_service.dart';
import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:azkar/features/prayer_times/data/local_prayer_calendar_cache.dart';
import 'package:azkar/features/prayer_times/data/prayer_times_provider.dart';
import 'package:azkar/features/prayer_times/data/prayer_times_service.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:azkar/features/reminders/data/local_prayer_schedule_location_store.dart';
import 'package:azkar/features/reminders/data/local_reminder_preferences_store.dart';
import 'package:azkar/features/reminders/domain/reminder_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('azkar/home_widget');
  const mobile = MobileRuntime(
    isWeb: false,
    targetPlatform: TargetPlatform.android,
  );

  test(
    'publishes both months across year end without private account data',
    () async {
      final db = await openNewInMemoryDatabase();
      addTearDown(db.close);
      final store = SembastReminderPreferencesStore(
        databaseProvider: () async => db,
      );
      final locationStore = LocalPrayerScheduleLocationStore(
        databaseProvider: () async => db,
      );
      await locationStore.saveDeviceLocation(
        userId: 'private-user',
        location: PrayerLocation.coordinates(
          latitude: 30.0444,
          longitude: 31.2357,
          timezoneId: 'Africa/Cairo',
        ),
      );
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final provider = _CalendarProvider();
      final service = PrayerHomeWidgetService(
        preferencesStore: store,
        locationStore: locationStore,
        prayerTimesService: PrayerTimesService(
          provider: provider,
          cache: LocalPrayerCalendarCache(databaseProvider: () async => db),
        ),
        currentUserIdProvider: () => 'private-user',
        runtime: mobile,
        clock: () => DateTime.utc(2026, 12, 31, 12),
      );
      await service.refresh('private-user');
      final json = calls.last.arguments as String;
      final payload = jsonDecode(json) as Map;
      expect(payload['timezone'], 'Africa/Cairo');
      expect(payload['location'], 'الموقع الحالي');
      expect((payload['days'] as List).first['date'], '2026-12-01');
      expect((payload['days'] as List).first['hijri'], {
        'day': 1,
        'month': 5,
        'year': 1448,
      });
      expect((payload['days'] as List).last['date'], '2027-01-31');
      expect(provider.requests, ['2026-12', '2027-01']);
      expect(json, isNot(contains('private-user')));
      expect(json, isNot(contains('latitude')));
      expect(json, isNot(contains('30.0444')));
      // Repeated refreshes use the validated calendars already saved locally.
      await service.refresh('private-user');
      expect(provider.requests, hasLength(2));
    },
  );

  test(
    'a sign-out during fetch cannot republish the old account calendar',
    () async {
      final db = await openNewInMemoryDatabase();
      addTearDown(db.close);
      final store = SembastReminderPreferencesStore(
        databaseProvider: () async => db,
      );
      await store.saveLocal(
        userId: 'user-a',
        preferences: ReminderPreferences(
          manualCity: 'Cairo',
          manualCountry: 'Egypt',
        ),
      );
      String? activeUser = 'user-a';
      final provider = _CalendarProvider()..barrier = Completer<void>();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = PrayerHomeWidgetService(
        preferencesStore: store,
        locationStore: LocalPrayerScheduleLocationStore(
          databaseProvider: () async => db,
        ),
        prayerTimesService: PrayerTimesService(
          provider: provider,
          cache: LocalPrayerCalendarCache(databaseProvider: () async => db),
        ),
        currentUserIdProvider: () => activeUser,
        runtime: mobile,
        clock: () => DateTime.utc(2026, 11, 8),
      );
      final pending = service.refresh('user-a');
      await provider.started.future;
      activeUser = null;
      final clearing = service.clear();
      provider.barrier!.complete();
      await pending;
      await clearing;
      expect(calls.where((call) => call.method == 'update'), isEmpty);
      expect(calls.last.method, 'clearPrayer');
      expect(provider.requests, hasLength(1));
    },
  );

  test('offline location change invalidates the old native selection before failing', () async {
    final db = await openNewInMemoryDatabase();
    addTearDown(db.close);
    final store = SembastReminderPreferencesStore(
      databaseProvider: () async => db,
    );
    await store.saveLocal(
      userId: 'user-a',
      preferences: ReminderPreferences(
        manualCity: 'Alexandria',
        manualCountry: 'Egypt',
      ),
    );
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final provider = _CalendarProvider()..offline = true;
    final service = PrayerHomeWidgetService(
      preferencesStore: store,
      locationStore: LocalPrayerScheduleLocationStore(
        databaseProvider: () async => db,
      ),
      prayerTimesService: PrayerTimesService(
        provider: provider,
        cache: LocalPrayerCalendarCache(databaseProvider: () async => db),
      ),
      currentUserIdProvider: () => 'user-a',
      runtime: mobile,
      clock: () => DateTime.utc(2026, 11, 8),
    );
    await expectLater(service.refresh('user-a'), throwsException);
    expect(calls.map((call) => call.method), ['selectLocation']);
    await service.clear();
    expect(calls.last.method, 'clearPrayer');
  });

  test('web never invokes the native widget channel', () async {
    final db = await openNewInMemoryDatabase();
    addTearDown(db.close);
    final service = PrayerHomeWidgetService(
      preferencesStore: SembastReminderPreferencesStore(
        databaseProvider: () async => db,
      ),
      locationStore: LocalPrayerScheduleLocationStore(
        databaseProvider: () async => db,
      ),
      prayerTimesService: PrayerTimesService(
        provider: _CalendarProvider(),
        cache: LocalPrayerCalendarCache(databaseProvider: () async => db),
      ),
      currentUserIdProvider: () => 'user-a',
      runtime: const MobileRuntime(
        isWeb: true,
        targetPlatform: TargetPlatform.android,
      ),
    );
    await service.refresh('user-a');
    await service.clear();
    expect(await service.requestPin(), isFalse);
  });
}

class _CalendarProvider implements PrayerTimesProvider {
  final requests = <String>[];
  final started = Completer<void>();
  Completer<void>? barrier;
  bool offline = false;

  @override
  Future<PrayerCalendar> fetchMonthlyCalendar({
    required PrayerLocation location,
    required PrayerMonth month,
    required PrayerCalculationMethod calculationMethod,
    required AsrCalculationMethod asrMethod,
  }) async {
    requests.add(month.cacheId);
    if (!started.isCompleted) started.complete();
    await barrier?.future;
    if (offline) throw StateError('offline');
    return PrayerCalendar(
      year: month.year,
      month: month.month,
      timezoneId: 'Africa/Cairo',
      calculationMethod: calculationMethod,
      asrMethod: asrMethod,
      fetchedAt: DateTime.utc(month.year, month.month),
      days: List.generate(
        month.dayCount,
        (index) => PrayerDay(
          localDate: DateTime.utc(month.year, month.month, index + 1),
          hijri: PrayerHijriDate(day: index % 30 + 1, month: 5, year: 1448),
          times: {
            for (final prayer in PrayerName.values)
              prayer: tz.TZDateTime(
                PrayerTimeZones.location('Africa/Cairo'),
                month.year,
                month.month,
                index + 1,
                5 + prayer.index * 2,
              ),
          },
        ),
      ),
    );
  }
}
