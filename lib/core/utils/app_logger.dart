import 'package:flutter/foundation.dart';

enum AppLogLevel { debug, info, warning, error }

/// Minimal structured logger.
///
/// Rules enforced here:
/// * never log credentials, tokens or the full Supabase key;
/// * keep technical detail out of public-facing UI (screens receive friendly
///   Arabic messages instead);
/// * everything is funnelled through one place so it can later be forwarded to
///   a remote sink (Sentry, Supabase logs, ...) without touching call sites.
class AppLogger {
  AppLogger._();

  /// Debug output is compiled out of release builds unless explicitly enabled
  /// with `--dart-define=AZKAR_VERBOSE_LOGS=true`.
  static const bool _forceVerbose = bool.fromEnvironment('AZKAR_VERBOSE_LOGS');

  static bool get _enabled => kDebugMode || _forceVerbose;

  static const Set<String> _redactedKeys = <String>{
    'anonkey',
    'apikey',
    'authorization',
    'password',
    'refreshtoken',
    'service_role',
    'token',
  };

  static void debug(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(AppLogLevel.debug, message, error, stackTrace);

  static void info(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(AppLogLevel.info, message, error, stackTrace);

  static void warning(
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) => _log(AppLogLevel.warning, message, error, stackTrace);

  static void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(AppLogLevel.error, message, error, stackTrace);

  /// Removes anything that looks like a credential from a diagnostic payload.
  static String redact(String value) {
    var result = value;
    final bearer = RegExp(r'Bearer\s+[A-Za-z0-9\-\._~\+/=]+');
    result = result.replaceAll(bearer, 'Bearer <redacted>');
    final jwt = RegExp(
      r'eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}',
    );
    result = result.replaceAll(jwt, '<redacted-jwt>');
    for (final key in _redactedKeys) {
      result = result.replaceAll(
        RegExp('$key["\']?\\s*[:=]\\s*["\']?[^"\\s,}]+', caseSensitive: false),
        '$key=<redacted>',
      );
    }
    return result;
  }

  static void _log(
    AppLogLevel level,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (!_enabled && level != AppLogLevel.error) return;
    final buffer = StringBuffer('[${level.name.toUpperCase()}] ')
      ..write(redact(message));
    if (error != null) buffer.write(' | error: ${redact(error.toString())}');
    if (stackTrace != null && (kDebugMode || level == AppLogLevel.error)) {
      buffer.write('\n$stackTrace');
    }
    debugPrint(buffer.toString());
  }
}
