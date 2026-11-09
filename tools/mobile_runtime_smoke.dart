// Development-only entry point for native plugin/background acceptance tests.
// Build with: flutter build apk --debug -t tools/mobile_runtime_smoke.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:azkar/features/notifications/data/flutter_local_notification_platform.dart';
import 'package:azkar/features/prayer_times/data/aladhan_prayer_times_provider.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:azkar/features/reminders/data/background_reminder_service.dart';
import 'package:azkar/features/reminders/domain/reminder_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('AZKAR native smoke test'))),
    ),
  );
  await BackgroundReminderService.initialize();
  final client = http.Client();
  try {
    final location = PrayerLocation.coordinates(
      latitude: 30.0444,
      longitude: 31.2357,
    );
    final month = PrayerMonth.forInstant(DateTime.now(), 'Africa/Cairo');
    final calendar = await AlAdhanPrayerTimesProvider(client: client)
        .fetchMonthlyCalendar(
          location: location,
          month: month,
          calculationMethod: PrayerCalculationMethod.egyptianGeneralAuthority,
          asrMethod: AsrCalculationMethod.standard,
        );
    const channel = MethodChannel('azkar/home_widget');
    await channel.invokeMethod<void>(
      'updateRemembrance',
      jsonEncode({
        'version': 1,
        'cards': [
          {
            'id': 'smoke-1',
            'title': 'ذكر',
            'text': 'سبحان الله وبحمده',
            'route': '/azkar',
          },
          {
            'id': 'smoke-2',
            'title': 'دعاء',
            'text': 'اللهم اغفر لموتانا وموتى المسلمين',
            'route': '/dua',
          },
        ],
      }),
    );
    final service = BackgroundReminderService(
      runtime: MobileRuntime.current(),
      currentUserId: () => 'native-smoke-user',
    );
    await service.setForeground(false);
    await service.save(
      'native-smoke-user',
      ReminderPreferences(
        prayerTimeNotificationsEnabled: true,
        morningAzkarEnabled: true,
        calculationMethod: PrayerCalculationMethod.egyptianGeneralAuthority,
      ),
      location,
      [calendar],
    );
    final platform = FlutterLocalNotificationPlatform();
    await platform.initialize((_) {});
    await platform.schedule(
      id: 9000,
      scheduledAt: PrayerTimeZones.localDateTime(
        DateTime.now().add(const Duration(seconds: 15)),
        'UTC',
      ),
      title: 'AZKAR native notification smoke',
      body: 'Native notification delivery verified',
      payload: 'native-smoke',
      actions: [],
      hideContentOnLockScreen: false,
    );
    debugPrint('AZKAR_SMOKE: native bridge and background task registered.');
  } catch (error, trace) {
    debugPrint('AZKAR_SMOKE_FAILED: $error\n$trace');
  } finally {
    client.close();
  }
}
