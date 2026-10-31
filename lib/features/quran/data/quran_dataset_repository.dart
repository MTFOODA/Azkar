import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/quran_dataset.dart';

/// Loads the bundled, verified Quranic dataset.
///
/// The full text (1.4 MB of UTF-8) is only parsed when an administrator opens
/// the Quran editor — the public website never downloads it just to display a
/// published verse, because the verse text is already stored in the row. The
/// surah index (114 entries, ~11 kB) is separate and cheap.
class QuranDatasetRepository {
  QuranDatasetRepository({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  Future<List<QuranSurahMeta>>? _indexFuture;
  Future<QuranDataset>? _datasetFuture;
  QuranDataset? _cachedDataset;

  bool get isDatasetLoaded => _cachedDataset != null;

  /// The cached dataset, when it has already been loaded (synchronous access for
  /// rebuilds inside the editor).
  QuranDataset? get cachedDataset => _cachedDataset;

  Future<List<QuranSurahMeta>> surahIndex() {
    return _indexFuture ??= _loadIndex();
  }

  Future<QuranDataset> dataset() {
    return _datasetFuture ??= _loadDataset();
  }

  Future<List<QuranSurahMeta>> _loadIndex() async {
    try {
      final raw = await _bundle.loadString(QuranDataset.indexPath);
      final decoded = jsonDecode(raw) as List<dynamic>;
      final index = decoded
          .map(
            (entry) => QuranSurahMeta.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false);
      if (index.length != 114 ||
          index.asMap().entries.any(
            (entry) => entry.value.number != entry.key + 1,
          ) ||
          index.any((surah) => surah.name.isEmpty || surah.ayahCount < 1) ||
          index.fold<int>(0, (total, surah) => total + surah.ayahCount) !=
              6236) {
        throw const FormatException('Invalid Quran surah index structure');
      }
      return List<QuranSurahMeta>.unmodifiable(index);
    } catch (error, stackTrace) {
      _indexFuture = null;
      AppLogger.error(
        'Failed to load the Quran surah index',
        error,
        stackTrace,
      );
      throw const AppException(
        'تعذّر تحميل فهرس السور. تأكد من تضمين ملفات البيانات.',
        technical: 'quran_index.json load failure',
      );
    }
  }

  Future<QuranDataset> _loadDataset() async {
    try {
      final raw = await _bundle.loadString(QuranDataset.assetPath);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final dataset = QuranDataset.fromJson(decoded);
      _cachedDataset = dataset;
      AppLogger.info(
        'Verified Quran dataset loaded: ${dataset.surahs.length} surahs, '
        '${dataset.ayahCount} ayahs (${dataset.version})',
      );
      return dataset;
    } catch (error, stackTrace) {
      _datasetFuture = null;
      AppLogger.error(
        'Failed to load the verified Quran dataset',
        error,
        stackTrace,
      );
      throw const AppException(
        'تعذّر تحميل النسخة المعتمدة من المصحف، لذلك لا يمكن التحقق من الآيات.',
        technical: 'quran_uthmani.json load failure',
      );
    }
  }

  /// Convenience: validates a range using the loaded dataset.
  Future<QuranValidationResult> validate({
    required int surahNumber,
    required int from,
    required int to,
    required String text,
  }) async {
    final loadedDataset = await dataset();
    return loadedDataset.validateRange(
      surahNumber: surahNumber,
      from: from,
      to: to,
      text: text,
    );
  }
}
