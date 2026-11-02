import 'package:azkar/features/prayer_times/data/current_prayer_location_service.dart';
import 'package:azkar/features/prayer_times/domain/prayer_time_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  test(
    'does not inspect or request device location without user consent',
    () async {
      final gateway = _FakeLocationGateway();
      final service = CurrentPrayerLocationService(
        consent: _FakeConsent(false),
        gateway: gateway,
      );

      expect(await service.requestCurrentLocation(), isNull);
      expect(gateway.calls, isEmpty);
    },
  );

  test(
    'requests approximate location only after consent and OS permission',
    () async {
      final gateway = _FakeLocationGateway();
      final service = CurrentPrayerLocationService(
        consent: _FakeConsent(true),
        gateway: gateway,
      );

      final location = await service.requestCurrentLocation();

      expect(gateway.calls, ['service', 'check', 'request', 'position']);
      expect(location!.kind, PrayerLocationKind.coordinates);
      expect(location.latitude, 30.0444);
      expect(location.longitude, 31.2357);
      expect(location.timezoneId, isNull);
    },
  );
}

class _FakeConsent implements PrayerLocationConsent {
  const _FakeConsent(this.allowed);

  final bool allowed;

  @override
  Future<bool> confirmCurrentLocationUse() async => allowed;
}

class _FakeLocationGateway implements PrayerDeviceLocationGateway {
  final calls = <String>[];
  LocationPermission permission = LocationPermission.denied;

  @override
  Future<bool> isLocationServiceEnabled() async {
    calls.add('service');
    return true;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    calls.add('check');
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    calls.add('request');
    permission = LocationPermission.whileInUse;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition() async {
    calls.add('position');
    return Position(
      longitude: 31.2357,
      latitude: 30.0444,
      timestamp: DateTime.utc(2026, 11),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );
  }
}
