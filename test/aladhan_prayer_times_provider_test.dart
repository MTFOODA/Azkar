import 'dart:convert';

import 'package:azkar/features/prayer_times/data/aladhan_prayer_times_provider.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_errors.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUpAll(PrayerTimeZones.initialize);

  test('fetches a validated city calendar with the selected method', () async {
    Uri? requestedUri;
    final provider = AlAdhanPrayerTimesProvider(
      client: MockClient((request) async {
        requestedUri = request.url;
        return http.Response(
          jsonEncode(_calendarResponse(PrayerMonth(2026, 11))),
          200,
        );
      }),
      clock: () => DateTime.utc(2026, 10, 31),
    );

    final location = PrayerLocation.manualCity(
      city: 'Cairo',
      country: 'Egypt',
      countryCode: 'EG',
    );
    final calendar = await provider.fetchMonthlyCalendar(
      location: location,
      month: PrayerMonth(2026, 11),
      calculationMethod: PrayerCalculationMethod.forLocation(location),
      asrMethod: AsrCalculationMethod.standard,
    );

    expect(requestedUri!.path, '/v1/calendarByCity/2026/11');
    expect(requestedUri!.queryParameters['city'], 'Cairo');
    expect(requestedUri!.queryParameters['country'], 'Egypt');
    expect(requestedUri!.queryParameters['method'], '5');
    expect(requestedUri!.queryParameters['school'], '0');
    expect(calendar.days, hasLength(30));
    expect(calendar.timezoneId, 'Africa/Cairo');
    expect(
      calendar.calculationMethod,
      PrayerCalculationMethod.egyptianGeneralAuthority,
    );
    expect(calendar.days.first.timeFor(PrayerName.fajr).hour, 5);
  });

  test('rejects a response with a missing prayer time', () async {
    final provider = AlAdhanPrayerTimesProvider(
      client: MockClient((_) async {
        final response = _calendarResponse(PrayerMonth(2026, 11));
        (response['data'] as List).first['timings'].remove('Isha');
        return http.Response(jsonEncode(response), 200);
      }),
    );

    await expectLater(
      provider.fetchMonthlyCalendar(
        location: PrayerLocation.manualCity(city: 'Cairo', country: 'Egypt'),
        month: PrayerMonth(2026, 11),
        calculationMethod: PrayerCalculationMethod.egyptianGeneralAuthority,
        asrMethod: AsrCalculationMethod.standard,
      ),
      throwsA(isA<PrayerTimesDataException>()),
    );
  });

  test('rejects malformed JSON and unsuccessful API responses', () async {
    final malformedProvider = AlAdhanPrayerTimesProvider(
      client: MockClient((_) async => http.Response('not-json', 200)),
    );
    final failedProvider = AlAdhanPrayerTimesProvider(
      client: MockClient(
        (_) async => http.Response('service unavailable', 503),
      ),
    );
    final request = (
      PrayerLocation.manualCity(city: 'Cairo', country: 'Egypt'),
      PrayerMonth(2026, 11),
    );

    Future<PrayerCalendar> fetch(AlAdhanPrayerTimesProvider provider) =>
        provider.fetchMonthlyCalendar(
          location: request.$1,
          month: request.$2,
          calculationMethod: PrayerCalculationMethod.egyptianGeneralAuthority,
          asrMethod: AsrCalculationMethod.standard,
        );

    await expectLater(
      fetch(malformedProvider),
      throwsA(isA<PrayerTimesDataException>()),
    );
    await expectLater(
      fetch(failedProvider),
      throwsA(isA<PrayerTimesApiException>()),
    );
  });

  test('rejects invalid IANA timezone metadata', () async {
    final response = _calendarResponse(PrayerMonth(2026, 11));
    response['meta']['timezone'] = 'Not/A_Timezone';
    final provider = AlAdhanPrayerTimesProvider(
      client: MockClient((_) async => http.Response(jsonEncode(response), 200)),
    );

    await expectLater(
      provider.fetchMonthlyCalendar(
        location: PrayerLocation.manualCity(city: 'Cairo', country: 'Egypt'),
        month: PrayerMonth(2026, 11),
        calculationMethod: PrayerCalculationMethod.egyptianGeneralAuthority,
        asrMethod: AsrCalculationMethod.standard,
      ),
      throwsA(isA<PrayerTimesDataException>()),
    );
  });
}

Map<String, dynamic> _calendarResponse(PrayerMonth month) => <String, dynamic>{
  'code': 200,
  'status': 'OK',
  'data': List<Map<String, dynamic>>.generate(month.dayCount, (index) {
    final day = index + 1;
    return <String, dynamic>{
      'date': <String, dynamic>{
        'gregorian': <String, dynamic>{
          'day': '$day',
          'month': <String, dynamic>{'number': month.month},
          'year': '${month.year}',
        },
      },
      'timings': <String, String>{
        'Fajr': '05:01 (EET)',
        'Sunrise': '06:20 (EET)',
        'Dhuhr': '11:40 (EET)',
        'Asr': '14:45 (EET)',
        'Maghrib': '17:00 (EET)',
        'Isha': '18:20 (EET)',
      },
    };
  }),
  'meta': <String, dynamic>{'timezone': 'Africa/Cairo'},
};
