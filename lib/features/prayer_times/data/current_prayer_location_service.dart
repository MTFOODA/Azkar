import 'package:geolocator/geolocator.dart';

import '../domain/prayer_time_errors.dart';
import '../domain/prayer_time_models.dart';

abstract interface class PrayerLocationConsent {
  /// Must display a clear in-app explanation and return the user's choice.
  Future<bool> confirmCurrentLocationUse();
}

abstract interface class PrayerDeviceLocationGateway {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<Position> getCurrentPosition();
}

class GeolocatorPrayerDeviceLocationGateway
    implements PrayerDeviceLocationGateway {
  const GeolocatorPrayerDeviceLocationGateway();

  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position> getCurrentPosition() => Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
  );
}

/// Requests device location only after an explicit in-app consent decision.
class CurrentPrayerLocationService {
  CurrentPrayerLocationService({
    required this.consent,
    this.gateway = const GeolocatorPrayerDeviceLocationGateway(),
  });

  final PrayerLocationConsent consent;
  final PrayerDeviceLocationGateway gateway;

  Future<PrayerLocation?> requestCurrentLocation() async {
    if (!await consent.confirmCurrentLocationUse()) return null;
    if (!await gateway.isLocationServiceEnabled()) {
      throw const PrayerLocationException(
        'خدمة تحديد الموقع غير مفعّلة. يمكنك اختيار المدينة يدوياً.',
      );
    }

    var permission = await gateway.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await gateway.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      throw const PrayerLocationException(
        'لم يُسمح بالوصول إلى الموقع. يمكنك اختيار المدينة يدوياً.',
      );
    }

    final position = await gateway.getCurrentPosition();
    return PrayerLocation.coordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
