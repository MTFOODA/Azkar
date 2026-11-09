import 'package:geolocator/geolocator.dart';

import '../../reminders/data/local_prayer_schedule_location_store.dart';
import '../../reminders/domain/reminder_preferences.dart';
import '../domain/prayer_time_models.dart';

/// Refreshes only an already-authorized location; never prompts on startup.
class AutomaticPrayerLocationService {
  const AutomaticPrayerLocationService(this.store, this.currentUserId);
  final LocalPrayerScheduleLocationStore store;
  final String? Function() currentUserId;

  Future<bool> refresh(String userId) async {
    if (currentUserId() != userId ||
        !await Geolocator.isLocationServiceEnabled()) {
      return false;
    }
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return false;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return savePosition(userId, position);
  }

  Future<bool> savePosition(String userId, Position position) async {
    if (currentUserId() != userId) return false;
    final previous = await store.resolve(
      userId: userId,
      preferences: ReminderPreferences.defaults,
    );
    if (previous?.kind == PrayerLocationKind.coordinates &&
        Geolocator.distanceBetween(
              previous!.latitude!,
              previous.longitude!,
              position.latitude,
              position.longitude,
            ) <
            2000) {
      return false;
    }
    await store.saveDeviceLocation(
      userId: userId,
      location: PrayerLocation.coordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      ),
    );
    return currentUserId() == userId;
  }
}
