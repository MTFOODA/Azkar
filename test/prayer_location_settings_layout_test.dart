import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:azkar/features/reminders/data/local_prayer_schedule_location_store.dart';
import 'package:azkar/features/reminders/data/local_reminder_preferences_store.dart';
import 'package:azkar/features/reminders/domain/reminder_preferences.dart';
import 'package:azkar/features/worship/presentation/prayer_location_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const widths = <double>[320, 360, 375, 390, 430, 768, 1200];
  const locales = <Locale>[Locale('ar'), Locale('en')];

  for (final locale in locales) {
    final direction = locale.languageCode == 'ar'
        ? TextDirection.rtl
        : TextDirection.ltr;
    for (final width in widths) {
      testWidgets(
        'prayer settings fit at ${width}px (${locale.languageCode})',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final preferencesStore = _PreferencesStore(
            ReminderPreferences.defaults.copyWith(
              manualCity: 'القاهرة',
              manualCountry: 'مصر',
              calculationMethod: PrayerCalculationMethod.indonesia,
            ),
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                accountSessionProvider.overrideWith(_Session.new),
                reminderPreferencesLocalStoreProvider.overrideWithValue(
                  preferencesStore,
                ),
                localPrayerScheduleLocationStoreProvider.overrideWithValue(
                  _LocationStore(),
                ),
              ],
              child: MaterialApp(
                locale: locale,
                builder: (context, child) =>
                    Directionality(textDirection: direction, child: child!),
                home: const PrayerLocationSettingsPage(),
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            ProviderScope.containerOf(
              tester.element(find.byType(PrayerLocationSettingsPage)),
            ).read(accountSessionProvider)?.id,
            'layout-user',
          );
          expect(find.textContaining('تعذّر قراءة الإعدادات:'), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          final methodDropdown = find.byType(
            DropdownButtonFormField<PrayerCalculationMethod>,
          );
          await tester.scrollUntilVisible(
            methodDropdown,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(methodDropdown, findsOneWidget);
          expect(find.textContaining('20 — Kementerian'), findsOneWidget);
          final box = tester.getRect(methodDropdown);
          expect(box.left, greaterThanOrEqualTo(0));
          expect(box.right, lessThanOrEqualTo(width));

          if (width != 320 || locale.languageCode != 'ar') return;

          await tester.tap(methodDropdown, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          expect(
            find.byType(DropdownMenuItem<PrayerCalculationMethod>),
            findsAtLeastNWidgets(1),
          );
          await tester.tapAt(const Offset(10, 10));
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          expect(methodDropdown, findsOneWidget);
          expect(find.textContaining('20 — Kementerian'), findsOneWidget);

          final asr = find.byType(
            DropdownButtonFormField<AsrCalculationMethod>,
          );
          await tester.scrollUntilVisible(
            asr,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(asr);
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          expect(find.text('Hanafi'), findsOneWidget);
          await tester.tapAt(const Offset(10, 10));
          await tester.pump(const Duration(milliseconds: 500));
          expect(tester.takeException(), isNull);
          expect(find.text('Standard'), findsOneWidget);
        },
      );
    }
  }
}

class _PreferencesStore implements ReminderPreferencesLocalStore {
  _PreferencesStore(this.preferences);

  ReminderPreferences preferences;

  @override
  Future<LocalReminderPreferencesState?> read(String userId) async =>
      LocalReminderPreferencesState(
        preferences: preferences,
        baseRevision: 0,
        isDirty: false,
      );

  @override
  Future<void> saveLocal({
    required String userId,
    required ReminderPreferences preferences,
  }) async {
    this.preferences = preferences;
  }

  @override
  Future<void> markSynchronized({
    required String userId,
    required ReminderPreferencesSnapshot snapshot,
  }) async {
    preferences = snapshot.preferences;
  }

  @override
  Future<void> resolveConflict({
    required String userId,
    required ReminderPreferences preferences,
    required ReminderPreferencesSnapshot serverSnapshot,
  }) async {
    this.preferences = preferences;
  }
}

class _LocationStore implements LocalPrayerScheduleLocationStore {
  @override
  bool get allowManualLocation => false;
  @override
  String? Function()? get currentUserIdProvider => null;

  @override
  Future<PrayerLocation?> resolve({
    required String userId,
    required ReminderPreferences preferences,
  }) async =>
      preferences.manualCity == null || preferences.manualCountry == null
      ? null
      : PrayerLocation.manualCity(
          city: preferences.manualCity!,
          country: preferences.manualCountry!,
          countryCode: preferences.manualCountryCode,
          timezoneId: preferences.timezoneId,
        );

  @override
  Future<void> saveDeviceLocation({
    required String userId,
    required PrayerLocation location,
  }) async {}

  @override
  Future<void> clearDeviceLocation(String userId) async {}
}

class _Session extends AccountSessionController {
  @override
  User? build() => User(
    id: 'layout-user',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    email: 'layout@example.test',
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}
