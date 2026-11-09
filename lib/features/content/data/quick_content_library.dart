import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/content_item.dart';
import '../domain/content_type.dart';
import '../../quran/domain/quran_dataset.dart';

class QuickContentPreset {
  const QuickContentPreset(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get title => data['title'] as String;
  ContentType get type => ContentTypeX.fromId(data['type'] as String)!;
  String get source => data['source'] as String? ?? 'المصحف المعتمد في التطبيق';
  String get searchText => '$title $source ${data['text'] ?? ''}';

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
      description: data['excerpt'] == true
          ? 'مقتطف من الحديث؛ المرجع: ${data['url']}'
          : null,
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
    final items = await load();
    return List.unmodifiable(items.where((item) => item.type == type));
  }

  static List<QuickContentPreset>? _items;
  static Future<List<QuickContentPreset>>? _pending;
  static Future<List<QuickContentPreset>> load() {
    if (_items != null) return Future.value(_items);
    return _pending ??= _load().whenComplete(() => _pending = null);
  }

  static Future<List<QuickContentPreset>> _load() async {
    final json = jsonDecode(
      await rootBundle.loadString('assets/data/quick_content_presets.json'),
    ) as Map;
    return _items = List.unmodifiable(
      (json['items'] as List).map(
        (item) => QuickContentPreset(Map<String, dynamic>.from(item as Map)),
      ),
    );
  }
}
