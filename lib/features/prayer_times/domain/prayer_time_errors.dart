class PrayerTimesException implements Exception {
  const PrayerTimesException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class PrayerTimesApiException extends PrayerTimesException {
  const PrayerTimesApiException(super.message, {super.cause});
}

class PrayerTimesDataException extends PrayerTimesException {
  const PrayerTimesDataException(super.message, {super.cause});
}

class PrayerTimesCacheException extends PrayerTimesException {
  const PrayerTimesCacheException(super.message, {super.cause});
}

class PrayerTimesUnavailableException extends PrayerTimesException {
  const PrayerTimesUnavailableException({super.cause})
    : super('لا تتوفر مواقيت صلاة لهذا الشهر ولا توجد بيانات محفوظة صالحة.');
}

class PrayerLocationException extends PrayerTimesException {
  const PrayerLocationException(super.message);
}
