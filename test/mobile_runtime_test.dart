import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MobileRuntime', () {
    test('web takes precedence over the host target platform', () {
      const runtime = MobileRuntime(
        isWeb: true,
        targetPlatform: TargetPlatform.android,
      );

      expect(runtime.platform, MobileRuntimePlatform.web);
      expect(runtime.isNativeMobile, isFalse);
    });

    test('identifies Android and iOS as native mobile runtimes', () {
      for (final target in [TargetPlatform.android, TargetPlatform.iOS]) {
        final runtime = MobileRuntime(isWeb: false, targetPlatform: target);

        expect(runtime.isNativeMobile, isTrue);
      }
    });

    test('does not classify desktop targets as native mobile', () {
      for (final target in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        final runtime = MobileRuntime(isWeb: false, targetPlatform: target);

        expect(runtime.platform, MobileRuntimePlatform.desktop);
        expect(runtime.isNativeMobile, isFalse);
      }
    });
  });
}
