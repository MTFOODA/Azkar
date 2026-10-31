import 'package:flutter/material.dart';

/// The seven dynamic content kinds the administrator can publish.
///
/// Every kind is stored in its own Postgres table (see the proposed
/// `supabase/migrations/20261030_multi_tenant_foundation.sql`) but shares the same editor, the same
/// card renderer and the same homepage ordering mechanism.
enum ContentType { azkar, quran, hadith, dua, tasbeeh, youtube, dedication }

extension ContentTypeX on ContentType {
  String get id => switch (this) {
    ContentType.azkar => 'azkar',
    ContentType.quran => 'quran',
    ContentType.hadith => 'hadith',
    ContentType.dua => 'dua',
    ContentType.tasbeeh => 'tasbeeh',
    ContentType.youtube => 'youtube',
    ContentType.dedication => 'dedication',
  };

  /// Physical Postgres table.
  String get table => switch (this) {
    ContentType.azkar => 'azkar',
    ContentType.quran => 'quran_verses',
    ContentType.hadith => 'hadith',
    ContentType.dua => 'duas',
    ContentType.tasbeeh => 'tasbeeh_cards',
    ContentType.youtube => 'youtube_videos',
    ContentType.dedication => 'dedications',
  };

  String get labelAr => switch (this) {
    ContentType.azkar => 'ذكر',
    ContentType.quran => 'آية قرآنية',
    ContentType.hadith => 'حديث',
    ContentType.dua => 'دعاء',
    ContentType.tasbeeh => 'تسبيح',
    ContentType.youtube => 'فيديو',
    ContentType.dedication => 'إهداء',
  };

  String get pluralLabelAr => switch (this) {
    ContentType.azkar => 'الأذكار',
    ContentType.quran => 'الآيات القرآنية',
    ContentType.hadith => 'الأحاديث',
    ContentType.dua => 'الأدعية',
    ContentType.tasbeeh => 'التسبيح',
    ContentType.youtube => 'الفيديوهات',
    ContentType.dedication => 'الإهداءات',
  };

  /// Public route of the collection page.
  String get route => switch (this) {
    ContentType.azkar => '/azkar',
    ContentType.quran => '/quran',
    ContentType.hadith => '/hadith',
    ContentType.dua => '/dua',
    ContentType.tasbeeh => '/tasbeeh',
    ContentType.youtube => '/videos',
    ContentType.dedication => '/dedications',
  };

  IconData get icon => switch (this) {
    ContentType.azkar => Icons.auto_awesome_outlined,
    ContentType.quran => Icons.menu_book_outlined,
    ContentType.hadith => Icons.format_quote_outlined,
    ContentType.dua => Icons.volunteer_activism_outlined,
    ContentType.tasbeeh => Icons.countertops_outlined,
    ContentType.youtube => Icons.ondemand_video_outlined,
    ContentType.dedication => Icons.favorite_outline,
  };

  /// Textual kinds get the copy/share action bar.
  bool get isTextual => switch (this) {
    ContentType.azkar || ContentType.quran || ContentType.dua => true,
    ContentType.hadith => true,
    _ => false,
  };

  /// Kinds whose content must pass religious-content validation before it can
  /// be published.
  bool get requiresReligiousValidation =>
      this == ContentType.quran || this == ContentType.hadith;

  /// The card shape used when the administrator did not choose one.
  bool get prefersSecondaryShape => this == ContentType.dedication;

  static ContentType? fromId(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final type in ContentType.values) {
      if (type.id == normalized || type.table == normalized) return type;
    }
    return null;
  }

  static List<ContentType> get all => ContentType.values;
}
