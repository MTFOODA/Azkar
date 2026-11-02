import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as timezone;

import '../domain/prayer_time_errors.dart';
import '../domain/prayer_time_models.dart';
import 'prayer_times_provider.dart';

class AlAdhanPrayerTimesProvider implements PrayerTimesProvider {
  AlAdhanPrayerTimesProvider({
    required this.client,
    Uri? baseUri,
    DateTime Function()? clock,
  }) : _baseUri = baseUri ?? Uri.https('api.aladhan.com', ''),
       _clock = clock ?? DateTime.now;

  final http.Client client;
  final Uri _baseUri;
  final DateTime Function() _clock;

  @override
  Future<PrayerCalendar> fetchMonthlyCalendar({
    required PrayerLocation location,
    required PrayerMonth month,
    required PrayerCalculationMethod calculationMethod,
    required AsrCalculationMethod asrMethod,
  }) async {
    final parameters = <String, String>{
      'method': '${calculationMethod.id}',
      'school': '${asrMethod.id}',
      if (location.timezoneId != null) 'timezonestring': location.timezoneId!,
      if (location.kind == PrayerLocationKind.city) ...<String, String>{
        'city': location.city!,
        'country': location.country!,
      },
      if (location.kind == PrayerLocationKind.coordinates) ...<String, String>{
        'latitude': '${location.latitude}',
        'longitude': '${location.longitude}',
      },
    };
    final endpoint = location.kind == PrayerLocationKind.city
        ? 'calendarByCity'
        : 'calendar';
    final uri = _baseUri.replace(
      pathSegments: <String>[
        ..._baseUri.pathSegments.where((segment) => segment.isNotEmpty),
        'v1',
        endpoint,
        '${month.year}',
        '${month.month}',
      ],
      queryParameters: parameters,
    );

    final http.Response response;
    try {
      response = await client.get(uri).timeout(const Duration(seconds: 20));
    } on Object catch (error) {
      throw PrayerTimesApiException(
        'تعذّر الاتصال بخدمة مواقيت الصلاة.',
        cause: error,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PrayerTimesApiException(
        'أعادت خدمة مواقيت الصلاة حالة HTTP ${response.statusCode}.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on Object catch (error) {
      throw PrayerTimesDataException(
        'استجابة خدمة مواقيت الصلاة ليست JSON صالحاً.',
        cause: error,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PrayerTimesDataException(
        'بنية استجابة مواقيت الصلاة غير صالحة.',
      );
    }

    final responseCode = readPrayerJsonInt(decoded['code']);
    if (responseCode != 200) {
      throw PrayerTimesApiException(
        'رفضت خدمة مواقيت الصلاة الطلب برمز $responseCode.',
      );
    }
    final rawData = decoded['data'];
    final rawMeta = decoded['meta'];
    if (rawData is! List ||
        rawMeta is! Map ||
        rawData.any((day) => day is! Map)) {
      throw const PrayerTimesDataException(
        'استجابة خدمة مواقيت الصلاة لا تتضمن التقويم والبيانات الوصفية.',
      );
    }
    final timezoneId = rawMeta['timezone'];
    if (timezoneId is! String || timezoneId.trim().isEmpty) {
      throw const PrayerTimesDataException(
        'لم تحدد خدمة مواقيت الصلاة منطقة زمنية.',
      );
    }
    if (location.timezoneId != null && location.timezoneId != timezoneId) {
      throw const PrayerTimesDataException(
        'المنطقة الزمنية المستلمة لا تطابق المنطقة المختارة.',
      );
    }
    final zone = PrayerTimeZones.location(timezoneId);
    final days =
        rawData
            .map(
              (rawDay) => _parseDay(
                Map<String, dynamic>.from(rawDay as Map),
                month,
                zone,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.localDate.compareTo(right.localDate));

    return PrayerCalendar(
      year: month.year,
      month: month.month,
      timezoneId: timezoneId,
      calculationMethod: calculationMethod,
      asrMethod: asrMethod,
      days: days,
      fetchedAt: _clock().toUtc(),
    );
  }

  PrayerDay _parseDay(
    Map<String, dynamic> rawDay,
    PrayerMonth requestedMonth,
    timezone.Location zone,
  ) {
    final date = rawDay['date'];
    final gregorian = date is Map ? date['gregorian'] : null;
    final timings = rawDay['timings'];
    if (gregorian is! Map || timings is! Map) {
      throw const PrayerTimesDataException(
        'بيانات أحد أيام التقويم غير مكتملة.',
      );
    }
    final year = readPrayerJsonInt(gregorian['year']);
    final day = readPrayerJsonInt(gregorian['day']);
    final rawMonth = gregorian['month'];
    final apiMonth = rawMonth is Map
        ? readPrayerJsonInt(rawMonth['number'])
        : -1;
    final localDate = DateTime.utc(year, apiMonth, day);
    if (year != requestedMonth.year ||
        apiMonth != requestedMonth.month ||
        localDate.year != year ||
        localDate.month != apiMonth ||
        localDate.day != day) {
      throw const PrayerTimesDataException(
        'تاريخ أحد الأيام لا يطابق الشهر المطلوب.',
      );
    }

    final times = <PrayerName, timezone.TZDateTime>{};
    for (final prayer in PrayerName.values) {
      final rawTime =
          timings[prayer.name[0].toUpperCase() + prayer.name.substring(1)];
      if (rawTime is! String) {
        throw PrayerTimesDataException(
          'استجابة اليوم لا تتضمن موعد ${prayer.id}.',
        );
      }
      final (hour, minute) = parsePrayerWallTime(rawTime);
      times[prayer] = timezone.TZDateTime(
        zone,
        year,
        apiMonth,
        day,
        hour,
        minute,
      );
    }
    return PrayerDay(localDate: localDate, times: times);
  }
}
