import 'package:timezone/timezone.dart' as timezone;

import '../../prayer_times/domain/prayer_time_models.dart';
import 'reminder_preferences.dart';

class ReminderScheduleReport {
  const ReminderScheduleReport({
    required this.scheduledCount,
    required this.cancelledCount,
    required this.skippedForCapacity,
    required this.prayerTimesAvailable,
    required this.notificationPermissionGranted,
  });

  final int scheduledCount;
  final int cancelledCount;
  final int skippedForCapacity;
  final bool prayerTimesAvailable;
  final bool notificationPermissionGranted;
}

class ReminderQuietHours {
  const ReminderQuietHours._();

  static bool contains(
    timezone.TZDateTime time,
    ReminderPreferences preferences,
  ) {
    final startValue = preferences.quietHoursStart;
    final endValue = preferences.quietHoursEnd;
    if (startValue == null || endValue == null) return false;
    final start = _clockParts(startValue);
    final end = _clockParts(endValue);
    final minute = time.hour * 60 + time.minute;
    final startMinute = start.$1 * 60 + start.$2;
    final endMinute = end.$1 * 60 + end.$2;
    if (startMinute == endMinute) return true;
    if (startMinute < endMinute) {
      return minute >= startMinute && minute < endMinute;
    }
    return minute >= startMinute || minute < endMinute;
  }

  static timezone.TZDateTime? defer(
    timezone.TZDateTime time,
    ReminderPreferences preferences,
  ) {
    if (!contains(time, preferences)) return time;
    final startValue = preferences.quietHoursStart!;
    final endValue = preferences.quietHoursEnd!;
    final start = _clockParts(startValue);
    final end = _clockParts(endValue);
    final startMinute = start.$1 * 60 + start.$2;
    final endMinute = end.$1 * 60 + end.$2;
    final wrapsMidnight = startMinute >= endMinute;
    final currentMinute = time.hour * 60 + time.minute;
    final nextDate =
        startMinute == endMinute ||
        (wrapsMidnight && currentMinute >= startMinute);
    final date = nextDate ? time.add(const Duration(days: 1)) : time;
    final deferred = timezone.TZDateTime(
      time.location,
      date.year,
      date.month,
      date.day,
      end.$1,
      end.$2,
    );
    if (deferred.hour != end.$1 || deferred.minute != end.$2) return null;
    return deferred;
  }

  static timezone.TZDateTime? atWallClock({
    required timezone.Location zone,
    required DateTime date,
    required String clockTime,
  }) {
    final parts = parsePrayerWallTime(clockTime);
    final time = timezone.TZDateTime(
      zone,
      date.year,
      date.month,
      date.day,
      parts.$1,
      parts.$2,
    );
    if (time.year != date.year ||
        time.month != date.month ||
        time.day != date.day ||
        time.hour != parts.$1 ||
        time.minute != parts.$2) {
      return null;
    }
    return time;
  }

  static (int, int) _clockParts(String value) {
    final parts = value.split(':');
    return (int.parse(parts[0]), int.parse(parts[1]));
  }
}
