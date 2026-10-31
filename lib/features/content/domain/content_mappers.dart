import '../../../core/design/theme_settings.dart';
import 'card_style.dart';
import 'content_item.dart';
import 'content_type.dart';

/// Conversion between [ContentItem] and its Postgres row.
///
/// The row is the UNION of the shared columns plus the type-specific columns of
/// the relevant table; only the fields that belong to [ContentItem.type] are
/// emitted, so a row never contains a column the table does not have.
extension ContentItemRowMapping on ContentItem {
  /// Serialises the item for `insert`/`update`.
  ///
  /// [includeId] must be `false` for inserts (the database owns the UUID) and
  /// `true` for updates performed by id.
  Map<String, dynamic> toRow({bool includeId = false}) {
    final row = <String, dynamic>{
      if (includeId) 'id': id,
      'title': title.trim(),
      'arabic_text': arabicText,
      'description': _nullIfBlank(description),
      'source': _nullIfBlank(source),
      'display_order': displayOrder,
      'is_published': isPublished,
      ...style.toRow(),
    };

    switch (type) {
      case ContentType.quran:
        row.addAll(<String, dynamic>{
          'translation': _nullIfBlank(translation),
          'surah_number': surahNumber,
          'surah_name': _nullIfBlank(surahName),
          'ayah_from': ayahFrom,
          'ayah_to': ayahTo,
          'validation_hash': validationHash,
          'dataset_version': datasetVersion,
        });
        break;
      case ContentType.hadith:
        row.addAll(<String, dynamic>{
          'narrator': _nullIfBlank(narrator),
          'hadith_number': _nullIfBlank(hadithNumber),
          'authenticity': authenticity.id,
          'explanation': _nullIfBlank(explanation),
        });
        break;
      case ContentType.youtube:
        row.addAll(<String, dynamic>{
          'video_url': _nullIfBlank(videoUrl),
          'video_id': _nullIfBlank(videoId),
        });
        break;
      case ContentType.dedication:
        row.addAll(<String, dynamic>{
          'person_name': _nullIfBlank(personName),
          'message': _nullIfBlank(dedicationMessage),
          'dua_text': arabicText,
          'recipient': recipient.id,
        });
        break;
      case ContentType.azkar:
      case ContentType.dua:
      case ContentType.tasbeeh:
        break;
    }

    return row;
  }

  static String? _nullIfBlank(String? value) {
    final text = value?.trim();
    return (text == null || text.isEmpty) ? null : text;
  }
}

/// Builds [ContentItem]s from Postgres rows.
class ContentMapper {
  const ContentMapper._();

  static ContentItem fromRow(
    ContentType type,
    Map<String, dynamic> row, {
    required ThemeSettings theme,
  }) {
    final style = CardStyle.fromRow(row, theme);
    final isDedication = type == ContentType.dedication;
    return ContentItem(
      id: row['id']?.toString() ?? '',
      type: type,
      arabicText: _text(
        isDedication ? row['dua_text'] : row['arabic_text'],
      ),
      title: _text(row['title']),
      description: _textOrNull(row['description']),
      source: _textOrNull(row['source']),
      translation: _textOrNull(row['translation']),
      narrator: _textOrNull(row['narrator']),
      hadithNumber: _textOrNull(row['hadith_number']),
      authenticity: HadithAuthenticityX.fromId(
        row['authenticity']?.toString(),
      ),
      explanation: _textOrNull(row['explanation']),
      surahNumber: _intOrNull(row['surah_number']),
      surahName: _textOrNull(row['surah_name']),
      ayahFrom: _intOrNull(row['ayah_from']),
      ayahTo: _intOrNull(row['ayah_to']),
      validationHash: _textOrNull(row['validation_hash']),
      datasetVersion: _textOrNull(row['dataset_version']),
      videoUrl: _textOrNull(row['video_url']),
      videoId: _textOrNull(row['video_id']),
      personName: _textOrNull(row['person_name']),
      dedicationMessage: _textOrNull(
        row['message'] ?? row['dedication_message'],
      ),
      recipient: DedicationRecipientX.fromId(row['recipient']?.toString()),
      style: style,
      displayOrder: _intOrNull(row['display_order']) ?? 0,
      isPublished: row['is_published'] == true,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
    );
  }

  static String _text(Object? value) => value?.toString() ?? '';

  static String? _textOrNull(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _intOrNull(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
