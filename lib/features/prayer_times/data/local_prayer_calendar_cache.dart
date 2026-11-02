import 'package:sembast/sembast.dart';

import '../../../core/storage/local_database.dart';
import '../domain/prayer_time_errors.dart';
import '../domain/prayer_time_models.dart';
import 'prayer_times_provider.dart';

class LocalPrayerCalendarCache implements PrayerCalendarCache {
  LocalPrayerCalendarCache({Future<Database> Function()? databaseProvider})
    : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final Future<Database> Function() _databaseProvider;

  StoreRef<String, Map<String, Object?>> get _store =>
      stringMapStoreFactory.store(LocalStores.prayerCalendars);

  @override
  Future<PrayerCalendar?> read(String cacheKey) async {
    try {
      final database = await _databaseProvider();
      final row = await _store.record(cacheKey).get(database);
      if (row == null) return null;
      final rawCalendar = row['calendar'];
      if (rawCalendar is! Map) {
        throw const PrayerTimesCacheException(
          'تقويم مواقيت الصلاة المخزن غير صالح.',
        );
      }
      return PrayerCalendar.fromJson(Map<String, dynamic>.from(rawCalendar));
    } on PrayerTimesCacheException {
      rethrow;
    } on Object catch (error) {
      throw PrayerTimesCacheException(
        'تعذّر قراءة تقويم مواقيت الصلاة المخزن.',
        cause: error,
      );
    }
  }

  @override
  Future<void> write(String cacheKey, PrayerCalendar calendar) async {
    try {
      final database = await _databaseProvider();
      await _store.record(cacheKey).put(database, <String, Object?>{
        'calendar': calendar.toJson(),
      });
    } on Object catch (error) {
      throw PrayerTimesCacheException(
        'تعذّر حفظ تقويم مواقيت الصلاة محلياً.',
        cause: error,
      );
    }
  }
}
