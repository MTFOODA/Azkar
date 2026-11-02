import 'package:timezone/timezone.dart' as timezone;

import '../../notifications/data/local_notification_service.dart';
import '../../notifications/domain/local_notification.dart';
import '../domain/prayer_completion_state_machine.dart';

class LocalPrayerCompletionReminderScheduler
    implements PrayerCompletionReminderScheduler {
  const LocalPrayerCompletionReminderScheduler(this._notifications);

  final LocalNotificationService _notifications;

  @override
  Future<void> schedule({
    required String userId,
    required String stableKey,
    required TrackedPrayer prayer,
    required int ordinal,
    required timezone.TZDateTime scheduledAt,
  }) async {
    final title = ordinal == 1 ? 'تذكير بالصلاة' : 'تذكير أخير بالصلاة';
    await _notifications.schedule(
      LocalNotificationRequest(
        accountId: userId,
        stableKey: stableKey,
        title: title,
        body: 'هل صليت ${_prayerName(prayer)}؟',
        scheduledAt: scheduledAt,
        actions: <NotificationActionDefinition>[
          NotificationActionDefinition(id: 'mark_complete', title: 'صليت'),
          NotificationActionDefinition(id: 'snooze', title: 'لسه مصليتش'),
        ],
        hideContentOnLockScreen: true,
      ),
    );
  }

  @override
  Future<void> cancel({required String userId, required String stableKey}) =>
      _notifications.cancel(accountId: userId, stableKey: stableKey);

  String _prayerName(TrackedPrayer prayer) => switch (prayer) {
    TrackedPrayer.fajr => 'الفجر',
    TrackedPrayer.dhuhr => 'الظهر',
    TrackedPrayer.asr => 'العصر',
    TrackedPrayer.maghrib => 'المغرب',
    TrackedPrayer.isha => 'العشاء',
  };
}
