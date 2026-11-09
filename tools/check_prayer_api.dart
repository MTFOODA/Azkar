import 'dart:io';

import 'package:azkar/features/prayer_times/data/aladhan_prayer_times_provider.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:http/http.dart' as http;

/// Optional live smoke test; normal tests use the recorded provider fixture.
Future<void> main() async {
  final client = http.Client();
  try {
    final provider = AlAdhanPrayerTimesProvider(client: client);
    final location = PrayerLocation.manualCity(city: 'Cairo', country: 'Egypt');
    final month = PrayerMonth.forInstant(DateTime.now(), 'Africa/Cairo');
    final calendar = await provider.fetchMonthlyCalendar(
      location: location,
      month: month,
      calculationMethod: PrayerCalculationMethod.egyptianGeneralAuthority,
      asrMethod: AsrCalculationMethod.standard,
    );
    final today = calendar.dayForInstant(DateTime.now())!;
    stdout.writeln(
      'AlAdhan OK: ${calendar.days.length} days, ${calendar.timezoneId}, method ${calendar.calculationMethod.id}',
    );
    for (final prayer in PrayerName.values) {
      stdout.writeln(
        '${prayer.id}: ${formatPrayerWallTime(today.timeFor(prayer))}',
      );
    }
  } finally {
    client.close();
  }
}
