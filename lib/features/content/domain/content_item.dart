import '../../../core/utils/arabic_text_utils.dart';
import 'card_style.dart';
import 'content_type.dart';

/// Authenticity classification of a Hadith card.
///
/// `unverified` is a first-class, visible state: an administrator must never be
/// forced to invent a grading. Unverified cards are flagged in the dashboard and
/// carry a "يُراجَع" badge on the public site instead of an authenticity claim.
enum HadithAuthenticity { sahih, hasan, daif, unverified }

extension HadithAuthenticityX on HadithAuthenticity {
  String get id => name;

  String get labelAr => switch (this) {
    HadithAuthenticity.sahih => 'صحيح',
    HadithAuthenticity.hasan => 'حسن',
    HadithAuthenticity.daif => 'ضعيف',
    HadithAuthenticity.unverified => 'يُراجَع (غير مُصنّف)',
  };

  bool get isVerified =>
      this == HadithAuthenticity.sahih || this == HadithAuthenticity.hasan;

  static HadithAuthenticity fromId(String? value) {
    return switch (value) {
      'sahih' => HadithAuthenticity.sahih,
      'hasan' => HadithAuthenticity.hasan,
      'daif' => HadithAuthenticity.daif,
      _ => HadithAuthenticity.unverified,
    };
  }
}

/// Grammatical gender used to phrase a dedication.
enum DedicationRecipient { male, female, multiple }

extension DedicationRecipientX on DedicationRecipient {
  String get id => name;

  String get labelAr => switch (this) {
    DedicationRecipient.male => 'مفرد مذكر',
    DedicationRecipient.female => 'مفرد مؤنث',
    DedicationRecipient.multiple => 'أكثر من شخص',
  };

  /// Default opening line for the dedication card. The administrator can
  /// override the wordings through the free-text fields.
  String get defaultPrefix => switch (this) {
    DedicationRecipient.male => 'صدقة جارية على روح',
    DedicationRecipient.female => 'صدقة جارية على روح',
    DedicationRecipient.multiple => 'صدقة جارية على أرواح',
  };

  String get defaultHonorific => switch (this) {
    DedicationRecipient.male => 'المرحوم',
    DedicationRecipient.female => 'المرحومة',
    DedicationRecipient.multiple => 'المرحومين',
  };

  static DedicationRecipient fromId(String? value) {
    return switch (value) {
      'female' => DedicationRecipient.female,
      'multiple' => DedicationRecipient.multiple,
      _ => DedicationRecipient.male,
    };
  }
}

/// The single content record used by the editor, the renderer and the homepage.
///
/// Each [ContentType] maps to its own Postgres table, but the union of the
/// columns is small enough that one strongly typed record is clearer (and far
/// less repetitive) than seven nearly identical classes. Type-specific rules —
/// which fields are required, which validations run — live in
/// `content_validation.dart`.
class ContentItem {
  const ContentItem({
    required this.id,
    required this.type,
    this.arabicText = '',
    this.title = '',
    this.description,
    this.source,
    this.translation,
    this.narrator,
    this.hadithNumber,
    this.authenticity = HadithAuthenticity.unverified,
    this.explanation,
    this.surahNumber,
    this.surahName,
    this.ayahFrom,
    this.ayahTo,
    this.validationHash,
    this.datasetVersion,
    this.videoUrl,
    this.videoId,
    this.personName,
    this.dedicationMessage,
    this.recipient = DedicationRecipient.male,
    this.style = const CardStyle(),
    this.displayOrder = 0,
    this.isPublished = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final ContentType type;

  /// The main Arabic text. For Quran cards it is the verified verse text, for
  /// dedications it is the dua.
  final String arabicText;

  final String title;
  final String? description;
  final String? source;

  /// Optional trusted translation (Quran cards).
  final String? translation;

  // Hadith metadata.
  final String? narrator;
  final String? hadithNumber;
  final HadithAuthenticity authenticity;
  final String? explanation;

  // Quran metadata.
  final int? surahNumber;
  final String? surahName;
  final int? ayahFrom;
  final int? ayahTo;

  /// Fingerprint of the text that was validated against the verified dataset.
  final String? validationHash;
  final String? datasetVersion;

  // YouTube metadata.
  final String? videoUrl;
  final String? videoId;

  // Dedication metadata.
  final String? personName;
  final String? dedicationMessage;
  final DedicationRecipient recipient;

  final CardStyle style;
  final int displayOrder;
  final bool isPublished;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Text shown as the card heading (may be empty).
  String get displayTitle {
    if (title.trim().isNotEmpty) return title.trim();
    if (type == ContentType.quran && surahName != null) return surahName!;
    if (type == ContentType.dedication && personName != null) {
      return '${recipient.defaultHonorific} / ${personName!}';
    }
    if (type == ContentType.youtube) return 'فيديو';
    return '';
  }

  /// Human readable reference line (surah/verse, hadith source, dedication).
  String get referenceLine {
    switch (type) {
      case ContentType.quran:
        final surah = surahName?.trim() ?? '';
        if (surah.isEmpty) return '';
        final from = ayahFrom;
        final to = ayahTo;
        if (from == null) return surah;
        final range = to == null || to == from
            ? ArabicTextUtils.toArabicDigits(from)
            : '${ArabicTextUtils.toArabicDigits(from)}-${ArabicTextUtils.toArabicDigits(to)}';
        return '$surah — الآية $range';
      case ContentType.hadith:
        final parts = <String>[];
        if (narrator != null && narrator!.trim().isNotEmpty) {
          parts.add('الراوي: ${narrator!.trim()}');
        }
        if (source != null && source!.trim().isNotEmpty) {
          parts.add(source!.trim());
        }
        if (hadithNumber != null && hadithNumber!.trim().isNotEmpty) {
          parts.add('رقم ${hadithNumber!.trim()}');
        }
        if (authenticity != HadithAuthenticity.unverified) {
          parts.add(authenticity.labelAr);
        }
        return parts.join(' • ');
      case ContentType.dedication:
        return dedicationMessage?.trim() ?? '';
      default:
        return source?.trim() ?? '';
    }
  }

  /// Badge text for unverified religious content.
  String? get reviewBadge =>
      type == ContentType.hadith && !authenticity.isVerified
      ? 'قيد المراجعة'
      : null;

  /// Full text placed on the clipboard / share sheet.
  String get shareText {
    final lines = <String>[];
    final heading = displayTitle;
    if (heading.isNotEmpty) lines.add(heading);
    final body = type == ContentType.youtube
        ? (videoUrl ?? '')
        : arabicText.trim();
    if (body.isNotEmpty) lines.add(body);
    final reference = referenceLine;
    if (reference.isNotEmpty) lines.add(reference);
    return lines.join('\n');
  }

  bool get hasArabicText => arabicText.trim().isNotEmpty;

  int get wordCount => ArabicTextUtils.wordCount(arabicText);

  /// Stable key used by lists so cards keep their identity across reorders.
  String get cardKey => '${type.id}:$id';

  ContentItem copyWith({
    String? id,
    ContentType? type,
    String? arabicText,
    String? title,
    String? description,
    String? source,
    String? translation,
    String? narrator,
    String? hadithNumber,
    HadithAuthenticity? authenticity,
    String? explanation,
    int? surahNumber,
    String? surahName,
    int? ayahFrom,
    int? ayahTo,
    String? validationHash,
    String? datasetVersion,
    String? videoUrl,
    String? videoId,
    String? personName,
    String? dedicationMessage,
    DedicationRecipient? recipient,
    CardStyle? style,
    int? displayOrder,
    bool? isPublished,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearValidation = false,
  }) {
    return ContentItem(
      id: id ?? this.id,
      type: type ?? this.type,
      arabicText: arabicText ?? this.arabicText,
      title: title ?? this.title,
      description: description ?? this.description,
      source: source ?? this.source,
      translation: translation ?? this.translation,
      narrator: narrator ?? this.narrator,
      hadithNumber: hadithNumber ?? this.hadithNumber,
      authenticity: authenticity ?? this.authenticity,
      explanation: explanation ?? this.explanation,
      surahNumber: surahNumber ?? this.surahNumber,
      surahName: surahName ?? this.surahName,
      ayahFrom: ayahFrom ?? this.ayahFrom,
      ayahTo: ayahTo ?? this.ayahTo,
      validationHash: clearValidation
          ? null
          : (validationHash ?? this.validationHash),
      datasetVersion: clearValidation
          ? null
          : (datasetVersion ?? this.datasetVersion),
      videoUrl: videoUrl ?? this.videoUrl,
      videoId: videoId ?? this.videoId,
      personName: personName ?? this.personName,
      dedicationMessage: dedicationMessage ?? this.dedicationMessage,
      recipient: recipient ?? this.recipient,
      style: style ?? this.style,
      displayOrder: displayOrder ?? this.displayOrder,
      isPublished: isPublished ?? this.isPublished,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
