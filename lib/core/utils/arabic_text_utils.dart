/// Utilities for Arabic text handling.
///
/// The golden rule: **never modify the content the administrator typed.**
/// Helpers here either *read* the text (detection, formatting) or produce a
/// throw-away comparison key used for validation. The stored and rendered
/// string always keeps every diacritic and Quranic symbol exactly as entered.
class ArabicTextUtils {
  ArabicTextUtils._();

  /// Arabic diacritics, Quranic annotation signs and tatweel.
  static final RegExp _diacritics = RegExp(
    '[\\u0610-\\u061A\\u064B-\\u065F\\u0670\\u06D6-\\u06ED\\u0640\\uFEFF]',
  );

  static final RegExp _arabicLetters = RegExp('[\\u0600-\\u06FF\\u0750-\\u077F]');
  static final RegExp _whitespaceRun = RegExp(r'\s+');
  static final RegExp _arabicIndicDigits = RegExp('[\\u0660-\\u0669]');

  /// True when [text] contains at least one Arabic character.
  static bool containsArabic(String text) => _arabicLetters.hasMatch(text);

  /// True when the ratio of Arabic letters is at least [threshold].
  static bool isMostlyArabic(String text, {double threshold = 0.5}) {
    final nonSpace = text.replaceAll(_whitespaceRun, '');
    if (nonSpace.isEmpty) return false;
    final runes = nonSpace.runes.toList(growable: false);
    final arabic = runes
        .where((rune) => _arabicLetters.hasMatch(String.fromCharCode(rune)))
        .length;
    return arabic / runes.length >= threshold;
  }

  /// Removes diacritics only. Used for display options and search — never for
  /// persisting content.
  static String stripDiacritics(String text) =>
      text.replaceAll(_diacritics, '');

  /// Counts the diacritic marks in [text] (used by the admin Quran validator to
  /// warn when a verse was pasted without its vowel marks).
  static int diacriticCount(String text) =>
      _diacritics.allMatches(text).length;

  /// Collapses every whitespace run (including non-breaking spaces) into a
  /// single space and trims the ends.
  static String collapseWhitespace(String text) =>
      text.replaceAll(_whitespaceRun, ' ').trim();

  /// Normalises Arabic-Indic digits in [text] to ASCII digits.
  static String normalizeDigits(String text) => text.replaceAllMapped(
    _arabicIndicDigits,
    (match) => (match.group(0)!.codeUnitAt(0) - 0x0660).toString(),
  );

  /// Produces a comparison key that ignores differences which carry no meaning
  /// for verse identity: diacritics, tatweel, whitespace variants and the
  /// interchangeable alef/ya/ta-marbuta glyph forms.
  ///
  /// This is the key used by the Quran validator. It is deliberately one-way:
  /// the ORIGINAL text is what gets stored and rendered.
  static String comparisonKey(String text) {
    var value = stripDiacritics(text);
    value = value
        .replaceAll(RegExp('[\\u0622\\u0623\\u0625\\u0627\\u0671]'), '\u0627')
        .replaceAll(RegExp('[\\u0649\\u064A]'), '\u064A')
        .replaceAll('\u0629', '\u0647')
        .replaceAll(RegExp('[\\u0624]'), '\u0648')
        .replaceAll(RegExp('[\\u0626]'), '\u064A');
    value = collapseWhitespace(value);
    value = normalizeDigits(value);
    // Quranic pause marks / small high signs are not letters; drop anything
    // that is not a letter, a digit or a space.
    value = value.replaceAll(RegExp(r'[^\u0621-\u064A\u0660-\u06690-9 ]'), '');
    return value;
  }

  /// True when two strings share the same comparison key.
  static bool matches(String a, String b) =>
      comparisonKey(a) == comparisonKey(b);

  /// Converts Western digits in [value] to Arabic-Indic digits for display.
  static String toArabicDigits(Object value) {
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const indic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var result = value.toString();
    for (var i = 0; i < western.length; i++) {
      result = result.replaceAll(western[i], indic[i]);
    }
    return result;
  }

  /// Formats a Tasbeeh counter value with thousands separators.
  static String formatCounter(int value) {
    final negative = value < 0;
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return negative ? '-$buffer' : buffer.toString();
  }

  /// Number of words in [text] (Arabic-aware, diacritics insensitive).
  static int wordCount(String text) {
    final normalized = collapseWhitespace(stripDiacritics(text));
    if (normalized.isEmpty) return 0;
    return normalized.split(' ').length;
  }

  /// Shortens [text] to [maxLength] characters on a word boundary, keeping
  /// diacritics intact.
  static String preview(String text, {int maxLength = 120}) {
    final collapsed = collapseWhitespace(text);
    if (collapsed.length <= maxLength) return collapsed;
    final cut = collapsed.substring(0, maxLength);
    final lastSpace = cut.lastIndexOf(' ');
    final safe = lastSpace > maxLength ~/ 2 ? cut.substring(0, lastSpace) : cut;
    return '$safe…';
  }
}
