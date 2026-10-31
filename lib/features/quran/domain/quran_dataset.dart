import '../../../core/utils/arabic_text_utils.dart';
import '../../../core/utils/stable_hash.dart';

/// Metadata of one surah, loaded from `assets/data/quran_index.json`.
class QuranSurahMeta {
  const QuranSurahMeta({
    required this.number,
    required this.name,
    required this.englishName,
    required this.ayahCount,
  });

  final int number;
  final String name;
  final String englishName;
  final int ayahCount;

  factory QuranSurahMeta.fromJson(Map<String, dynamic> json) => QuranSurahMeta(
    number: (json['number'] as num).toInt(),
    name: (json['name'] as String?) ?? '',
    englishName: (json['englishName'] as String?) ?? '',
    ayahCount: (json['ayahCount'] as num?)?.toInt() ?? 0,
  );

  String get labelAr => '$number. $name';
}

/// Outcome of validating admin-entered Quranic text against the verified
/// dataset.
class QuranValidationResult {
  const QuranValidationResult({
    required this.isValid,
    required this.messageAr,
    this.expectedText,
    this.submittedText,
    this.fingerprint,
    this.datasetVersion,
    this.differingWordIndex,
  });

  final bool isValid;
  final String messageAr;

  /// The exact text from the verified dataset for the requested range.
  final String? expectedText;
  final String? submittedText;
  final String? fingerprint;
  final String? datasetVersion;

  /// Index of the first word that differs (1-based), when available.
  final int? differingWordIndex;

  bool get hasExpectedText => (expectedText ?? '').isNotEmpty;
}

/// The complete Tanzil Uthmani text plus range validation helpers.
///
/// This class never generates or "fixes" Quranic text. It only answers the
/// question "does the text the administrator is about to publish match the
/// verified dataset for the selected surah/ayah range?".
class QuranDataset {
  QuranDataset({
    required this.datasetName,
    required this.edition,
    required this.provider,
    required this.version,
    required this.retrievedAt,
    required this.surahs,
    required this._ayahs,
  });

  final String datasetName;
  final String edition;
  final String provider;

  /// `edition@retrievedAt`, stored on every validated Quran row so the exact
  /// dataset provenance travels with the content.
  final String version;

  final String retrievedAt;
  final List<QuranSurahMeta> surahs;
  final Map<int, List<String>> _ayahs;

  static const String assetPath = 'assets/data/quran_uthmani.json';
  static const String indexPath = 'assets/data/quran_index.json';

  int get ayahCount =>
      _ayahs.values.fold(0, (sum, ayahs) => sum + ayahs.length);

  /// The verified text of a single ayah, or `null` when out of range.
  String? ayahText(int surahNumber, int ayahNumber) {
    final ayahs = _ayahs[surahNumber];
    if (ayahs == null) return null;
    if (ayahNumber < 1 || ayahNumber > ayahs.length) return null;
    return ayahs[ayahNumber - 1];
  }

  /// The verified text of an inclusive ayah range, joined by a single space.
  String? rangeText(int surahNumber, int from, int to) {
    final ayahs = _ayahs[surahNumber];
    if (ayahs == null) return null;
    final start = from < 1 ? 1 : from;
    if (start > ayahs.length) return null;
    final end = to < start ? start : to;
    final effectiveEnd = end > ayahs.length ? ayahs.length : end;
    return ayahs.sublist(start - 1, effectiveEnd).join(' ');
  }

  QuranSurahMeta? surah(int number) {
    for (final meta in surahs) {
      if (meta.number == number) return meta;
    }
    return null;
  }

  /// Validates [text] against the dataset for the requested range.
  QuranValidationResult validateRange({
    required int surahNumber,
    required int from,
    required int to,
    required String text,
  }) {
    final meta = surah(surahNumber);
    if (meta == null) {
      return const QuranValidationResult(
        isValid: false,
        messageAr: 'رقم السورة غير صحيح (1 - 114).',
      );
    }
    if (from < 1 || from > meta.ayahCount) {
      return QuranValidationResult(
        isValid: false,
        messageAr:
            'رقم الآية الابتدائية خارج نطاق سورة ${meta.name} (${meta.ayahCount} آية).',
      );
    }
    if (to < from || to > meta.ayahCount) {
      return QuranValidationResult(
        isValid: false,
        messageAr:
            'رقم الآية النهائية يجب أن يكون بين $from و ${meta.ayahCount}.',
      );
    }

    final expected = rangeText(surahNumber, from, to) ?? '';
    final submitted = ArabicTextUtils.collapseWhitespace(text);
    if (ArabicTextUtils.comparisonKey(submitted).isEmpty) {
      return QuranValidationResult(
        isValid: false,
        messageAr: 'نص الآية مطلوب.',
        expectedText: expected,
        datasetVersion: version,
      );
    }

    final submittedKey = ArabicTextUtils.comparisonKey(submitted);
    final expectedKey = ArabicTextUtils.comparisonKey(expected);
    final fingerprint = StableHash.fingerprint(expectedKey);

    if (submittedKey == expectedKey) {
      return QuranValidationResult(
        isValid: true,
        messageAr: 'تم التحقق: النص مطابق للنسخة المعتمدة من المصحف.',
        expectedText: expected,
        submittedText: submitted,
        fingerprint: fingerprint,
        datasetVersion: version,
      );
    }

    final differingWord = _firstDifferingWord(expected, submitted);
    return QuranValidationResult(
      isValid: false,
      messageAr: differingWord == null
          ? 'النص لا يطابق النسخة المعتمدة من المصحف.'
          : 'النص لا يطابق النسخة المعتمدة (اختلاف عند الكلمة رقم $differingWord).',
      expectedText: expected,
      submittedText: submitted,
      datasetVersion: version,
      differingWordIndex: differingWord,
    );
  }

  static int? _firstDifferingWord(String expected, String submitted) {
    final a = expected
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final b = submitted
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    final shortest = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shortest; i++) {
      if (ArabicTextUtils.comparisonKey(a[i]) !=
          ArabicTextUtils.comparisonKey(b[i])) {
        return i + 1;
      }
    }
    if (a.length != b.length) return shortest + 1;
    return null;
  }

  /// Parses the bundled dataset JSON.
  factory QuranDataset.fromJson(Map<String, dynamic> json) {
    final rawSurahs = json['surahs'];
    if (rawSurahs is! List<dynamic> || rawSurahs.length != 114) {
      throw const FormatException('Expected exactly 114 Quran surahs');
    }
    if (json['surahCount'] != 114 || json['ayahCount'] != 6236) {
      throw const FormatException('Quran dataset metadata counts do not match');
    }

    final meta = <QuranSurahMeta>[];
    final ayahs = <int, List<String>>{};
    var totalAyahs = 0;
    for (var surahIndex = 0; surahIndex < rawSurahs.length; surahIndex++) {
      final entry = rawSurahs[surahIndex];
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid Quran surah record');
      }
      final map = entry;
      final surahMeta = QuranSurahMeta.fromJson(map);
      if (surahMeta.number != surahIndex + 1 ||
          surahMeta.name.isEmpty ||
          surahMeta.englishName.isEmpty) {
        throw FormatException('Invalid metadata for surah ${surahIndex + 1}');
      }

      final rawAyahs = map['ayahs'];
      if (rawAyahs is! List<dynamic> ||
          rawAyahs.length != surahMeta.ayahCount) {
        throw FormatException(
          'Invalid ayah count for surah ${surahMeta.number}',
        );
      }
      final textList = <String>[];
      for (var ayahIndex = 0; ayahIndex < rawAyahs.length; ayahIndex++) {
        final rawAyah = rawAyahs[ayahIndex];
        if (rawAyah is! Map<String, dynamic> ||
            rawAyah['n'] != ayahIndex + 1 ||
            rawAyah['text'] is! String ||
            (rawAyah['text'] as String).trim().isEmpty) {
          throw FormatException(
            'Invalid ayah ${ayahIndex + 1} in surah ${surahMeta.number}',
          );
        }
        textList.add(rawAyah['text'] as String);
      }

      meta.add(surahMeta);
      totalAyahs += textList.length;
      ayahs[surahMeta.number] = List<String>.unmodifiable(textList);
    }
    if (totalAyahs != 6236) {
      throw const FormatException('Expected exactly 6236 Quran ayahs');
    }
    final edition = json['edition']?.toString() ?? 'quran-uthmani';
    final retrievedAt = json['retrievedAt']?.toString() ?? 'unknown';
    return QuranDataset(
      datasetName: json['dataset']?.toString() ?? 'Tanzil Uthmani Quran text',
      edition: edition,
      provider: json['provider']?.toString() ?? 'Al Quran Cloud',
      version: '$edition@$retrievedAt',
      retrievedAt: retrievedAt,
      surahs: List<QuranSurahMeta>.unmodifiable(meta),
      ayahs: ayahs,
    );
  }
}
