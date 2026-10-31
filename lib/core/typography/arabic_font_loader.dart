import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import 'arabic_fonts.dart';

/// Registers the bundled Arabic font families on demand.
///
/// Only the family that is actually needed is ever downloaded: the ten
/// families live in the asset bundle but are registered lazily through
/// [FontLoader]. A visitor therefore never pays for nine unused font files,
/// while essential Arabic content still renders without any network access to
/// a font CDN.
class ArabicFontLoader {
  ArabicFontLoader._();

  static final Map<String, Future<bool>> _inFlight = <String, Future<bool>>{};
  static final Set<String> _loaded = <String>{};

  /// Families that failed to register; they fall back to Amiri / the platform
  /// Arabic font instead of throwing in the widget tree.
  static final Set<String> _failed = <String>{};

  static bool isLoaded(String fontId) => _loaded.contains(fontId);

  static bool hasFailed(String fontId) => _failed.contains(fontId);

  /// Registers [fontId]. Safe to call repeatedly and concurrently: the
  /// underlying load happens at most once per family.
  static Future<bool> ensure(String fontId) {
    final spec = ArabicFonts.byId(fontId);
    if (_loaded.contains(spec.id)) return Future<bool>.value(true);
    return _inFlight.putIfAbsent(spec.id, () => _load(spec));
  }

  /// Registers every family in [fontIds] (used to warm up a page after the
  /// first frame, so cards never flash a fallback font for long).
  static Future<void> ensureAll(Iterable<String> fontIds) async {
    final unique = fontIds.map((id) => ArabicFonts.byId(id).id).toSet();
    await Future.wait(unique.map(ensure));
  }

  /// Registers the default family. Awaited during bootstrap so the first frame
  /// already uses proper Arabic typography.
  static Future<void> ensureDefault() => ensure(ArabicFonts.defaultFontId);

  static Future<bool> _load(ArabicFontSpec spec) async {
    try {
      final loader = FontLoader(spec.family);
      for (final asset in spec.assets) {
        loader.addFont(rootBundle.load(asset.path));
      }
      await loader.load();
      _loaded.add(spec.id);
      AppLogger.debug('Arabic font registered: ${spec.family}');
      return true;
    } catch (error, stackTrace) {
      _failed.add(spec.id);
      AppLogger.warning(
        'Failed to register Arabic font ${spec.family}',
        error,
        stackTrace,
      );
      return false;
    } finally {
      _inFlight.remove(spec.id);
    }
  }

  /// Test/utility hook to forget cached state.
  @visibleForTesting
  static void resetForTesting() {
    _inFlight.clear();
    _loaded.clear();
    _failed.clear();
  }
}
