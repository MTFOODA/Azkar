import 'package:sembast/sembast.dart';

import '../../../core/storage/local_database.dart';
import '../../../core/utils/app_exception.dart';
import '../../prayer_times/domain/prayer_time_models.dart';
import '../domain/reminder_preferences.dart';

class LocalPrayerScheduleLocationStore {
  LocalPrayerScheduleLocationStore({
    Future<Database> Function()? databaseProvider,
    this.currentUserIdProvider,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final Future<Database> Function() _databaseProvider;
  final String? Function()? currentUserIdProvider;

  StoreRef<String, Map<String, Object?>> get _store =>
      stringMapStoreFactory.store(LocalStores.preferences);

  Future<PrayerLocation?> resolve({
    required String userId,
    required ReminderPreferences preferences,
  }) async {
    _validateUser(userId);
    if (preferences.manualCity != null && preferences.manualCountry != null) {
      return PrayerLocation.manualCity(
        city: preferences.manualCity!,
        country: preferences.manualCountry!,
        countryCode: preferences.manualCountryCode,
        timezoneId: preferences.timezoneId,
      );
    }
    try {
      final row = await _store
          .record(_key(userId))
          .get(await _databaseProvider());
      if (row == null) return null;
      if (row['user_id'] != userId ||
          row['latitude'] is! num ||
          row['longitude'] is! num) {
        throw const FormatException('Invalid local prayer schedule location.');
      }
      return PrayerLocation.coordinates(
        latitude: (row['latitude']! as num).toDouble(),
        longitude: (row['longitude']! as num).toDouble(),
        countryCode: row['country_code'] as String?,
        timezoneId: row['timezone_id'] as String?,
      );
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر قراءة موقع مواقيت الصلاة المحفوظ على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  Future<void> saveDeviceLocation({
    required String userId,
    required PrayerLocation location,
  }) async {
    _validateUser(userId);
    if (location.kind != PrayerLocationKind.coordinates) {
      throw ArgumentError.value(location, 'location');
    }
    try {
      await _store.record(_key(userId)).put(await _databaseProvider(), {
        'user_id': userId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'country_code': location.countryCode,
        'timezone_id': location.timezoneId,
      });
    } on LocalStorageException {
      rethrow;
    } on Object catch (error) {
      throw LocalStorageException(
        messageAr: 'تعذّر حفظ موقع مواقيت الصلاة على هذا الجهاز.',
        technical: error.toString(),
        cause: error,
      );
    }
  }

  Future<void> clearDeviceLocation(String userId) async {
    _validateUser(userId);
    await _store.record(_key(userId)).delete(await _databaseProvider());
  }

  String _key(String userId) => 'prayer-schedule-location:$userId';

  void _validateUser(String userId) {
    if (userId.trim().isEmpty) throw ArgumentError.value(userId, 'userId');
    final activeUser = currentUserIdProvider?.call();
    if (activeUser != null && activeUser != userId) {
      throw const NotAuthorizedException(
        messageAr: 'لا يمكن استخدام موقع مواقيت صلاة لحساب آخر.',
      );
    }
  }
}
