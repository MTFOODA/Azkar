import '../../../core/utils/arabic_text_utils.dart';
import '../../../core/utils/youtube_url.dart';
import 'content_item.dart';
import 'content_type.dart';

/// Result of validating a content record before it is saved or published.
class ContentValidationResult {
  const ContentValidationResult(this.fieldErrors, {this.warnings = const []});

  final Map<String, String> fieldErrors;

  /// Non-blocking advisories shown to the administrator.
  final List<String> warnings;

  bool get isValid => fieldErrors.isEmpty;

  bool get hasWarnings => warnings.isNotEmpty;
}

/// Type-aware content rules.
///
/// These mirror the Postgres `CHECK` constraints, so a record that fails here
/// can never reach the database, and a record that bypasses the client is still
/// rejected by the database.
class ContentValidation {
  const ContentValidation._();

  static const int maxArabicLength = 8000;
  static const int maxTitleLength = 200;
  static const int maxDescriptionLength = 2000;
  static const int maxUrlLength = 500;

  /// Validates [item].
  ///
  /// [forPublication] enables the stricter publishing rules:
  /// * Quran text must have been verified against the bundled dataset;
  /// * Hadith cards must carry verifiable source metadata.
  static ContentValidationResult validate(
    ContentItem item, {
    bool forPublication = false,
  }) {
    final errors = <String, String>{};
    final warnings = <String>[];

    if (item.title.trim().length > maxTitleLength) {
      errors['title'] = 'العنوان أطول من $maxTitleLength حرفًا.';
    }
    if (item.arabicText.length > maxArabicLength) {
      errors['arabicText'] = 'النص أطول من $maxArabicLength حرفًا.';
    }
    if ((item.description ?? '').length > maxDescriptionLength) {
      errors['description'] = 'الوصف أطول من $maxDescriptionLength حرفًا.';
    }
    errors.addAll(item.style.validate());
    if (_hasUnsafeMarkup(item.arabicText) ||
        _hasUnsafeMarkup(item.title) ||
        _hasUnsafeMarkup(item.description ?? '') ||
        _hasUnsafeMarkup(item.source ?? '')) {
      errors['arabicText'] =
          'المحتوى يحتوي على وسوم أو أوامر غير مسموحة (HTML/JavaScript).';
    }

    switch (item.type) {
      case ContentType.azkar:
      case ContentType.dua:
        if (item.arabicText.trim().isEmpty) {
          errors['arabicText'] = 'النص العربي مطلوب.';
        }
        break;
      case ContentType.tasbeeh:
        final text = item.arabicText.trim();
        if (text.isEmpty) {
          errors['arabicText'] = 'نص التسبيح مطلوب.';
        } else if (text.length > 200) {
          errors['arabicText'] = 'نص التسبيح يجب أن يكون أقل من 200 حرف.';
        }
        break;
      case ContentType.quran:
        _validateQuran(item, errors, warnings, forPublication: forPublication);
        break;
      case ContentType.hadith:
        _validateHadith(item, errors, warnings, forPublication: forPublication);
        break;
      case ContentType.youtube:
        final url = item.videoUrl?.trim() ?? '';
        if (url.isEmpty) {
          errors['videoUrl'] = 'رابط الفيديو مطلوب.';
        } else if (url.length > maxUrlLength) {
          errors['videoUrl'] = 'الرابط طويل جدًا.';
        } else if (!YoutubeUrl.isValid(url)) {
          errors['videoUrl'] = 'رابط يوتيوب غير صالح. الصيغ المدعومة: youtube.com/watch?v=… أو youtu.be/… أو /shorts/…';
        }
        break;
      case ContentType.dedication:
        if (item.personName == null || item.personName!.trim().isEmpty) {
          errors['personName'] = 'اسم الشخص المُهدى إليه مطلوب.';
        }
        if (item.arabicText.trim().isEmpty &&
            (item.dedicationMessage ?? '').trim().isEmpty) {
          errors['arabicText'] = 'أدخل نص الدعاء أو رسالة الإهداء.';
        }
        break;
    }

    return ContentValidationResult(errors, warnings: warnings);
  }

  /// Rejects HTML/JS payloads. Flutter never interprets markup (so this is not an
  /// XSS vector in the canvas), but the text also flows into web metadata and the
  /// clipboard, where it must stay inert.
  static bool _hasUnsafeMarkup(String? value) {
    if (value == null || value.isEmpty) return false;
    final lower = value.toLowerCase();
    return lower.contains('<script') ||
        lower.contains('javascript:') ||
        lower.contains('<iframe') ||
        lower.contains('onerror=') ||
        lower.contains('<img');
  }

  static int diacriticWarningThreshold(String text) =>
      ArabicTextUtils.diacriticCount(text);

  static void _validateQuran(
    ContentItem item,
    Map<String, String> errors,
    List<String> warnings, {
    required bool forPublication,
  }) {
    if (item.arabicText.trim().isEmpty) {
      errors['arabicText'] = 'نص الآية مطلوب.';
    }
    final surah = item.surahNumber;
    if (surah == null || surah < 1 || surah > 114) {
      errors['surahNumber'] = 'رقم السورة يجب أن يكون بين 1 و 114.';
    }
    if (item.surahName == null || item.surahName!.trim().isEmpty) {
      errors['surahName'] = 'اسم السورة مطلوب.';
    }
    final from = item.ayahFrom;
    final to = item.ayahTo;
    if (from == null || from < 1) {
      errors['ayahFrom'] = 'رقم الآية الابتدائية مطلوب.';
    }
    if (to == null || (from != null && to < from)) {
      errors['ayahTo'] = 'رقم الآية النهائية يجب أن يكون بعد الابتدائية.';
    }
    if (forPublication &&
        (item.validationHash == null || item.validationHash!.isEmpty)) {
      errors['arabicText'] =
          'لا يمكن نشر الآية قبل التحقق منها مقابل النسخة المعتمدة من المصحف.';
    }
    if (item.translation != null && item.translation!.trim().isNotEmpty) {
      warnings.add('تأكد من أن الترجمة من مصدر موثوق ومنسوبة إلى مترجمها.');
    }
  }

  static void _validateHadith(
    ContentItem item,
    Map<String, String> errors,
    List<String> warnings, {
    required bool forPublication,
  }) {
    if (item.arabicText.trim().isEmpty) {
      errors['arabicText'] = 'نص الحديث مطلوب.';
    }
    if (item.source == null || item.source!.trim().isEmpty) {
      errors['source'] = 'اسم الكتاب/المجموعة مطلوب للتحقق من المصدر.';
    }
    final hasNumber =
        item.hadithNumber != null && item.hadithNumber!.trim().isNotEmpty;
    final hasNarrator =
        item.narrator != null && item.narrator!.trim().isNotEmpty;
    if (!hasNumber && !hasNarrator) {
      errors['hadithNumber'] =
          'أدخل رقم الحديث أو الراوي على الأقل لتوثيق المصدر.';
    }
    if (forPublication && item.authenticity == HadithAuthenticity.unverified) {
      warnings.add(
        'الحديث غير مُصنّف. سيظهر للزائر بوسم "قيد المراجعة" ولن يُعرض على أنه صحيح.',
      );
    }
  }
}
