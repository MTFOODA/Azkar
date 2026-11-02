import 'package:timezone/timezone.dart' as timezone;

import '../../notifications/data/local_notification_service.dart';
import '../../notifications/domain/local_notification.dart';
import '../../prayer_times/domain/prayer_time_models.dart';
import '../../reminders/data/local_reminder_preferences_store.dart';
import '../../reminders/domain/reminder_preferences.dart';
import '../../reminders/domain/reminder_schedule_engine.dart';
import '../domain/prayer_completion_state_machine.dart';

class TasbeehEventNotificationConsumer {
  TasbeehEventNotificationConsumer({
    required this.notifications,
    required this.preferencesStore,
    required this.currentUserIdProvider,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LocalNotificationService notifications;
  final ReminderPreferencesLocalStore preferencesStore;
  final String? Function() currentUserIdProvider;
  final DateTime Function() _clock;

  Future<void> handle(PrayerCompletionTasbeehEvent event) async {
    if (currentUserIdProvider()?.trim() != event.userId) {
      throw StateError('The active account cannot consume this Tasbeeh event.');
    }
    final preferences =
        (await preferencesStore.read(event.userId))?.preferences ??
        ReminderPreferences.defaults;
    if (!preferences.postPrayerTasbeehEnabled) return;

    final zone = PrayerTimeZones.location(event.timezoneId);
    final now = timezone.TZDateTime.from(_clock(), zone);
    final eventDate = event.localDate;
    if (now.year != eventDate.year ||
        now.month != eventDate.month ||
        now.day != eventDate.day) {
      return;
    }
    final intended = timezone.TZDateTime.from(
      event.occurredAt,
      zone,
    ).add(Duration(minutes: preferences.postPrayerDelayMinutes));
    final candidate = intended.isAfter(now)
        ? intended
        : now.add(const Duration(minutes: 1));
    final scheduledAt = ReminderQuietHours.defer(candidate, preferences);
    if (scheduledAt == null) return;
    await notifications.scheduleIfAbsent(
      LocalNotificationRequest(
        accountId: event.userId,
        stableKey:
            'post-prayer-tasbeeh:v1:${event.localDate.year.toString().padLeft(4, '0')}-'
            '${event.localDate.month.toString().padLeft(2, '0')}-'
            '${event.localDate.day.toString().padLeft(2, '0')}:${event.id}',
        title: 'تسبيح ما بعد الصلاة',
        body: 'حان وقت أذكار ما بعد الصلاة.',
        scheduledAt: scheduledAt,
        hideContentOnLockScreen: preferences.hideNotificationContent,
      ),
    );
  }
}
