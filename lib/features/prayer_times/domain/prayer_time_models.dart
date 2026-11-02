import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import 'prayer_time_errors.dart';

enum PrayerName { fajr, sunrise, dhuhr, asr, maghrib, isha }

extension PrayerNameX on PrayerName {
  String get id => switch (this) {
    PrayerName.fajr => 'fajr',
    PrayerName.sunrise => 'sunrise',
    PrayerName.dhuhr => 'dhuhr',
    PrayerName.asr => 'asr',
    PrayerName.maghrib => 'maghrib',
    PrayerName.isha => 'isha',
  };

  static PrayerName? fromId(String value) {
    for (final prayer in PrayerName.values) {
      if (prayer.id == value) return prayer;
    }
    return null;
  }
}

enum AsrCalculationMethod {
  standard(0, 'Standard'),
  hanafi(1, 'Hanafi');

  const AsrCalculationMethod(this.id, this.label);

  final int id;
  final String label;

  static AsrCalculationMethod fromId(int id) {
    return switch (id) {
      0 => AsrCalculationMethod.standard,
      1 => AsrCalculationMethod.hanafi,
      _ => throw PrayerTimesDataException('طريقة حساب العصر غير مدعومة.'),
    };
  }
}

enum PrayerCalculationMethod {
  jafari(0, 'Shia Ithna-Ashari'),
  karachi(1, 'University of Islamic Sciences, Karachi'),
  northAmerica(2, 'Islamic Society of North America'),
  muslimWorldLeague(3, 'Muslim World League'),
  ummAlQura(4, 'Umm Al-Qura University, Makkah'),
  egyptianGeneralAuthority(5, 'Egyptian General Authority of Survey'),
  tehran(7, 'Institute of Geophysics, University of Tehran'),
  gulf(8, 'Gulf Region'),
  kuwait(9, 'Kuwait'),
  qatar(10, 'Qatar'),
  singapore(11, 'Majlis Ugama Islam Singapura'),
  france(12, 'Union Organization Islamic de France'),
  turkey(13, 'Diyanet İşleri Başkanlığı, Turkey'),
  russia(14, 'Spiritual Administration of Muslims of Russia'),
  moonsightingCommittee(15, 'Moonsighting Committee'),
  dubai(16, 'Dubai'),
  jakim(17, 'Jabatan Kemajuan Islam Malaysia'),
  tunisia(18, 'Tunisia'),
  algeria(19, 'Algeria'),
  indonesia(20, 'Kementerian Agama Republik Indonesia'),
  morocco(21, 'Morocco'),
  portugal(22, 'Portugal'),
  jordan(23, 'Jordan');

  const PrayerCalculationMethod(this.id, this.label);

  final int id;
  final String label;

  static PrayerCalculationMethod forLocation(PrayerLocation location) =>
      location.isEgypt
      ? PrayerCalculationMethod.egyptianGeneralAuthority
      : PrayerCalculationMethod.muslimWorldLeague;

  static PrayerCalculationMethod fromId(int id) {
    for (final method in PrayerCalculationMethod.values) {
      if (method.id == id) return method;
    }
    throw PrayerTimesDataException('طريقة حساب مواقيت الصلاة غير مدعومة.');
  }
}

enum PrayerLocationKind { city, coordinates }

/// A manually selected city or explicitly requested approximate coordinates.
///
/// The city form works without requesting device location. Coordinate cache
/// identifiers are hashed so raw coordinates are not written as Sembast keys.
class PrayerLocation {
  const PrayerLocation._({
    required this.kind,
    required this.label,
    this.city,
    this.country,
    this.countryCode,
    this.latitude,
    this.longitude,
    this.timezoneId,
  });

  factory PrayerLocation.manualCity({
    required String city,
    required String country,
    String? countryCode,
    String? timezoneId,
  }) {
    final trimmedCity = city.trim();
    final trimmedCountry = country.trim();
    if (trimmedCity.isEmpty || trimmedCountry.isEmpty) {
      throw ArgumentError('City and country are required.');
    }
    _validateTimezone(timezoneId);
    return PrayerLocation._(
      kind: PrayerLocationKind.city,
      label: '$trimmedCity, $trimmedCountry',
      city: trimmedCity,
      country: trimmedCountry,
      countryCode: _normalizeCountryCode(countryCode),
      timezoneId: timezoneId?.trim(),
    );
  }

  factory PrayerLocation.coordinates({
    required double latitude,
    required double longitude,
    String? countryCode,
    String? timezoneId,
  }) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(latitude, 'latitude');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(longitude, 'longitude');
    }
    _validateTimezone(timezoneId);
    return PrayerLocation._(
      kind: PrayerLocationKind.coordinates,
      label: 'الموقع الحالي',
      countryCode: _normalizeCountryCode(countryCode),
      latitude: latitude,
      longitude: longitude,
      timezoneId: timezoneId?.trim(),
    );
  }

  final PrayerLocationKind kind;
  final String label;
  final String? city;
  final String? country;
  final String? countryCode;
  final double? latitude;
  final double? longitude;
  final String? timezoneId;

  bool get isEgypt {
    if (countryCode != null) return countryCode == 'EG';
    if (kind == PrayerLocationKind.city) {
      return country?.toLowerCase() == 'egypt' ||
          country?.toLowerCase() == 'eg' ||
          country == 'مصر';
    }
    // Approximate bounds only select the default method; users can override it.
    return latitude! >= 22.0 &&
        latitude! <= 31.7 &&
        longitude! >= 24.7 &&
        longitude! <= 36.9;
  }

  String get cacheIdentifier {
    final locationIdentity = switch (kind) {
      PrayerLocationKind.city =>
        'city:${_locationFingerprint('${city!.toLowerCase()}|${country!.toLowerCase()}')}',
      PrayerLocationKind.coordinates =>
        'coordinates:${_locationFingerprint('${latitude!.toStringAsFixed(5)},${longitude!.toStringAsFixed(5)}')}',
    };
    return '$locationIdentity|${timezoneId ?? 'api-timezone'}';
  }

  static void _validateTimezone(String? timezoneId) {
    if (timezoneId == null || timezoneId.trim().isEmpty) return;
    PrayerTimeZones.location(timezoneId.trim());
  }

  static String? _normalizeCountryCode(String? countryCode) {
    final normalized = countryCode?.trim().toUpperCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class PrayerMonth {
  PrayerMonth(this.year, this.month) {
    if (year < 1 || year > 9999 || month < 1 || month > 12) {
      throw ArgumentError('Prayer month must be a valid Gregorian month.');
    }
  }

  factory PrayerMonth.forInstant(DateTime instant, String timezoneId) {
    final local = PrayerTimeZones.localDateTime(instant, timezoneId);
    return PrayerMonth(local.year, local.month);
  }

  final int year;
  final int month;

  int get dayCount => DateTime.utc(year, month + 1, 0).day;

  String get cacheId => '$year-${month.toString().padLeft(2, '0')}';

  bool containsDate(DateTime date) => date.year == year && date.month == month;
}

class PrayerDay {
  PrayerDay({
    required DateTime localDate,
    required Map<PrayerName, timezone.TZDateTime> times,
  }) : localDate = DateTime.utc(localDate.year, localDate.month, localDate.day),
       times = UnmodifiableMapView<PrayerName, timezone.TZDateTime>(
         Map<PrayerName, timezone.TZDateTime>.of(times),
       ) {
    if (times.length != PrayerName.values.length ||
        PrayerName.values.any((name) => !times.containsKey(name))) {
      throw const PrayerTimesDataException(
        'يجب أن تتضمن بيانات اليوم مواقيت الصلاة الستة.',
      );
    }
    for (final time in times.values) {
      if (time.year != this.localDate.year ||
          time.month != this.localDate.month ||
          time.day != this.localDate.day) {
        throw const PrayerTimesDataException(
          'تاريخ أحد المواقيت لا يطابق تاريخ اليوم المحلي.',
        );
      }
    }
  }

  final DateTime localDate;
  final Map<PrayerName, timezone.TZDateTime> times;

  timezone.TZDateTime timeFor(PrayerName name) => times[name]!;

  Map<String, Object?> toJson() => <String, Object?>{
    'year': localDate.year,
    'month': localDate.month,
    'day': localDate.day,
    'times': <String, String>{
      for (final entry in times.entries)
        entry.key.id: _formatWallTime(entry.value),
    },
  };

  factory PrayerDay.fromJson(Map<String, dynamic> json, String timezoneId) {
    final year = _readInt(json['year']);
    final month = _readInt(json['month']);
    final day = _readInt(json['day']);
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw const PrayerTimesCacheException(
        'تاريخ مخزن مواقيت الصلاة غير صالح.',
      );
    }
    final rawTimes = json['times'];
    if (rawTimes is! Map) {
      throw const PrayerTimesCacheException(
        'بيانات المواقيت المخزنة غير صالحة.',
      );
    }
    final zone = PrayerTimeZones.location(timezoneId);
    final times = <PrayerName, timezone.TZDateTime>{};
    for (final prayer in PrayerName.values) {
      final rawTime = rawTimes[prayer.id];
      if (rawTime is! String) {
        throw const PrayerTimesCacheException(
          'مواقيت الصلاة المخزنة غير مكتملة.',
        );
      }
      final parts = _parseWallTime(rawTime);
      times[prayer] = timezone.TZDateTime(
        zone,
        year,
        month,
        day,
        parts.$1,
        parts.$2,
      );
    }
    try {
      return PrayerDay(localDate: date, times: times);
    } on PrayerTimesDataException catch (error) {
      throw PrayerTimesCacheException(error.message, cause: error);
    }
  }
}

class PrayerCalendar {
  PrayerCalendar({
    required this.year,
    required this.month,
    required this.timezoneId,
    required this.calculationMethod,
    required this.asrMethod,
    required List<PrayerDay> days,
    required this.fetchedAt,
    this.isFromCache = false,
  }) : days = List<PrayerDay>.unmodifiable(days) {
    PrayerTimeZones.location(timezoneId);
    if (month < 1 || month > 12 || year < 1 || year > 9999) {
      throw const PrayerTimesDataException('شهر مواقيت الصلاة غير صالح.');
    }
    if (days.length != DateTime.utc(year, month + 1, 0).day) {
      throw const PrayerTimesDataException(
        'تقويم مواقيت الصلاة لا يحتوي على جميع أيام الشهر.',
      );
    }
    for (var index = 0; index < days.length; index++) {
      final day = days[index].localDate;
      if (day.year != year || day.month != month || day.day != index + 1) {
        throw const PrayerTimesDataException(
          'أيام تقويم مواقيت الصلاة غير مكتملة أو غير مرتبة.',
        );
      }
      for (final time in days[index].times.values) {
        if (time.location.name != timezoneId) {
          throw const PrayerTimesDataException(
            'المنطقة الزمنية لأحد المواقيت لا تطابق التقويم.',
          );
        }
      }
    }
  }

  final int year;
  final int month;
  final String timezoneId;
  final PrayerCalculationMethod calculationMethod;
  final AsrCalculationMethod asrMethod;
  final List<PrayerDay> days;
  final DateTime fetchedAt;
  final bool isFromCache;

  PrayerMonth get prayerMonth => PrayerMonth(year, month);

  PrayerCalendar copyWith({bool? isFromCache}) => PrayerCalendar(
    year: year,
    month: month,
    timezoneId: timezoneId,
    calculationMethod: calculationMethod,
    asrMethod: asrMethod,
    days: days,
    fetchedAt: fetchedAt,
    isFromCache: isFromCache ?? this.isFromCache,
  );

  PrayerDay? dayForInstant(DateTime instant) {
    final local = PrayerTimeZones.localDateTime(instant, timezoneId);
    if (local.year != year || local.month != month) return null;
    return days[local.day - 1];
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'year': year,
    'month': month,
    'timezone_id': timezoneId,
    'calculation_method': calculationMethod.id,
    'asr_method': asrMethod.id,
    'fetched_at': fetchedAt.toUtc().toIso8601String(),
    'days': days.map((day) => day.toJson()).toList(growable: false),
  };

  factory PrayerCalendar.fromJson(Map<String, dynamic> json) {
    try {
      final year = _readInt(json['year']);
      final month = _readInt(json['month']);
      final timezoneId = json['timezone_id'];
      final rawDays = json['days'];
      final fetchedAt = DateTime.tryParse('${json['fetched_at'] ?? ''}');
      if (timezoneId is! String ||
          rawDays is! List ||
          fetchedAt == null ||
          rawDays.any((day) => day is! Map)) {
        throw const PrayerTimesCacheException(
          'تقويم مواقيت الصلاة المخزن غير مكتمل.',
        );
      }
      return PrayerCalendar(
        year: year,
        month: month,
        timezoneId: timezoneId,
        calculationMethod: PrayerCalculationMethod.fromId(
          _readInt(json['calculation_method']),
        ),
        asrMethod: AsrCalculationMethod.fromId(_readInt(json['asr_method'])),
        days: rawDays
            .map(
              (day) => PrayerDay.fromJson(
                Map<String, dynamic>.from(day as Map),
                timezoneId,
              ),
            )
            .toList(growable: false),
        fetchedAt: fetchedAt.toUtc(),
        isFromCache: true,
      );
    } on PrayerTimesCacheException {
      rethrow;
    } on PrayerTimesException catch (error) {
      throw PrayerTimesCacheException(error.message, cause: error);
    } on Object catch (error) {
      throw PrayerTimesCacheException(
        'تعذّر قراءة تقويم مواقيت الصلاة المخزن.',
        cause: error,
      );
    }
  }
}

class PrayerTimeZones {
  PrayerTimeZones._();

  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    timezone_data.initializeTimeZones();
    _initialized = true;
  }

  static timezone.Location location(String timezoneId) {
    initialize();
    try {
      return timezone.getLocation(timezoneId);
    } on Object catch (error) {
      throw PrayerTimesDataException(
        'معرّف المنطقة الزمنية غير صالح: $timezoneId',
        cause: error,
      );
    }
  }

  static timezone.TZDateTime localDateTime(
    DateTime instant,
    String timezoneId,
  ) {
    return timezone.TZDateTime.from(instant, location(timezoneId));
  }
}

String formatPrayerWallTime(timezone.TZDateTime time) => _formatWallTime(time);

int readPrayerJsonInt(Object? value) => _readInt(value);

(int, int) parsePrayerWallTime(String value) => _parseWallTime(value);

String _formatWallTime(timezone.TZDateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _locationFingerprint(String value) =>
    sha256.convert(utf8.encode(value)).toString();

(int, int) _parseWallTime(String value) {
  final match = RegExp(r'^\s*(\d{1,2}):(\d{2})(?:\s|$)').firstMatch(value);
  if (match == null) {
    throw PrayerTimesDataException('تنسيق وقت الصلاة غير صالح: $value');
  }
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    throw PrayerTimesDataException('وقت الصلاة خارج النطاق: $value');
  }
  return (hour, minute);
}

int _readInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  if (value is String) return int.tryParse(value) ?? -1;
  return -1;
}
