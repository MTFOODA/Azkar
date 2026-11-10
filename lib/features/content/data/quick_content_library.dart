import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../../../core/utils/arabic_text_utils.dart';
import '../domain/content_item.dart';
import '../domain/content_type.dart';
import '../../quran/domain/quran_dataset.dart';

class QuickContentPreset {
  QuickContentPreset(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get title => data['title'] as String;
  ContentType get type => ContentTypeX.fromId(data['type'] as String)!;
  String get source => data['source'] as String? ?? 'المصحف المعتمد في التطبيق';
  late final List<String> categories = List.unmodifiable(
    (data['categories'] as List? ?? const ['مختارات أساسية'])
        .whereType<String>(),
  );
  String get searchText =>
      '$title $source ${data['text'] ?? ''} ${data['narrator'] ?? ''} ${categories.join(' ')}';
  late final String normalizedSearchText = ArabicTextUtils.comparisonKey(
    searchText,
  );

  ContentItem createDraft({QuranDataset? dataset}) {
    final surah = data['surah'] as int?;
    final from = data['from'] as int?;
    final to = data['to'] as int?;
    final text = type == ContentType.quran
        ? dataset!.rangeText(surah!, from!, to!)!
        : data['text'] as String;
    final validation = type == ContentType.quran
        ? dataset!.validateRange(
            surahNumber: surah!,
            from: from!,
            to: to!,
            text: text,
          )
        : null;
    if (validation != null && !validation.isValid) {
      throw StateError('Invalid Quran preset: $id');
    }
    return ContentItem(
      id: '',
      type: type,
      title: title,
      arabicText: text,
      source: type == ContentType.quran
          ? 'القرآن الكريم — ${dataset!.surah(surah!)!.name}'
          : source,
      description:
          data['description'] as String? ??
          (data['excerpt'] == true
              ? 'مقتطف من الحديث؛ المرجع: ${data['url']}'
              : null),
      narrator: data['narrator'] as String?,
      hadithNumber: data['number'] as String?,
      authenticity: HadithAuthenticityX.fromId(data['authenticity'] as String?),
      surahNumber: surah,
      surahName: surah == null ? null : dataset!.surah(surah)!.name,
      ayahFrom: from,
      ayahTo: to,
      validationHash: validation?.fingerprint,
      datasetVersion: validation?.datasetVersion,
    );
  }
}

class QuickContentLibrary {
  static const supportedTypes = {
    ContentType.azkar,
    ContentType.tasbeeh,
    ContentType.dua,
    ContentType.hadith,
    ContentType.quran,
  };

  static bool supports(ContentType type) => supportedTypes.contains(type);

  static Future<List<QuickContentPreset>> forType(ContentType type) async {
    if (!supports(type)) return const [];
    return _byType[type] ??= _loadType(type)
        .catchError((Object error, StackTrace stack) {
          _byType.remove(type);
          Error.throwWithStackTrace(error, stack);
        });
  }

  static final _byType = <ContentType, Future<List<QuickContentPreset>>>{};
  static Future<List<QuickContentPreset>>? _base;

  static Future<List<QuickContentPreset>> load() async => List.unmodifiable(
    (await Future.wait(supportedTypes.map(forType))).expand((items) => items),
  );

  static Future<List<QuickContentPreset>> _read(String path) async {
    final source = await rootBundle.loadString(path);
    // Parse and build the search index away from the Android UI thread.
    return compute(_parseQuickPresets, source);
  }

  static Future<List<QuickContentPreset>> _loadType(ContentType type) async {
    final base = await (_base ??= _read(
      'assets/data/quick_content_presets.json',
    ));
    final extra = switch (type) {
      ContentType.azkar || ContentType.dua || ContentType.hadith => await _read(
        'assets/data/quick_content_library/${type.id}.json',
      ),
      _ => const <QuickContentPreset>[],
    };
    return List.unmodifiable([
      ...base.where((preset) => preset.type == type),
      ...extra.where((preset) => preset.type == type),
    ]);
  }
}

List<QuickContentPreset> _parseQuickPresets(String source) {
  final document = jsonDecode(source) as Map;
  return (document['items'] as List)
      .map((item) {
        final preset = QuickContentPreset(
          Map<String, dynamic>.from(item as Map),
        );
        if (preset.normalizedSearchText.isEmpty) {
          throw const FormatException(
            'A quick-content preset has no searchable text.',
          );
        }
        return preset;
      })
      .toList(growable: false);
}
