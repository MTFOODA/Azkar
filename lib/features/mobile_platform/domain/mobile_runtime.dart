import 'package:flutter/foundation.dart';

enum MobileRuntimePlatform { web, android, ios, desktop }

/// Describes the current app runtime without importing mobile-only plugins.
///
/// This identifies the build/runtime target only; it does not imply that a
/// native feature is implemented, permitted, or available on the device.
class MobileRuntime {
  const MobileRuntime({required this.isWeb, required this.targetPlatform});

  factory MobileRuntime.current() =>
      MobileRuntime(isWeb: kIsWeb, targetPlatform: defaultTargetPlatform);

  final bool isWeb;
  final TargetPlatform targetPlatform;

  MobileRuntimePlatform get platform {
    if (isWeb) return MobileRuntimePlatform.web;
    return switch (targetPlatform) {
      TargetPlatform.android => MobileRuntimePlatform.android,
      TargetPlatform.iOS => MobileRuntimePlatform.ios,
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.fuchsia => MobileRuntimePlatform.desktop,
    };
  }

  bool get isNativeMobile =>
      platform == MobileRuntimePlatform.android ||
      platform == MobileRuntimePlatform.ios;
}
