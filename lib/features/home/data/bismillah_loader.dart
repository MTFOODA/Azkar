import 'package:flutter/services.dart';

import '../../../core/utils/app_logger.dart';

/// Loads the small Bismillah asset derived from the verified Quran dataset.
///
/// The homepage never hard-codes a Quranic string in Dart source; the text is
/// extracted from the same Tanzil Uthmani dataset used by the admin validator.
class BismillahLoader {
  const BismillahLoader._();

  static Future<String>? _future;

  static Future<String> load() {
    return _future ??= _read();
  }

  static Future<String> _read() async {
    try {
      final text = await rootBundle.loadString('assets/data/bismillah.txt');
      return text.trim();
    } catch (error, stackTrace) {
      AppLogger.warning('Bismillah asset unavailable', error, stackTrace);
      return '';
    }
  }
}
