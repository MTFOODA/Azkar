import '../../content/domain/content_item.dart';
import '../../content/domain/content_type.dart';

/// One row of `homepage_cards`: a pointer from the homepage to a content record.
///
/// The homepage is therefore *fully dynamic*: the administrator decides which
/// records appear, in which order, and whether each one is enabled. Nothing about
/// the layout is hard-coded in Flutter.
class HomepageEntry {
  const HomepageEntry({
    required this.id,
    required this.contentType,
    required this.contentId,
    this.displayOrder = 0,
    this.isEnabled = true,
  });

  final String id;
  final ContentType contentType;
  final String contentId;
  final int displayOrder;
  final bool isEnabled;

  HomepageEntry copyWith({
    String? id,
    ContentType? contentType,
    String? contentId,
    int? displayOrder,
    bool? isEnabled,
  }) {
    return HomepageEntry(
      id: id ?? this.id,
      contentType: contentType ?? this.contentType,
      contentId: contentId ?? this.contentId,
      displayOrder: displayOrder ?? this.displayOrder,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
    'content_type': contentType.id,
    'content_id': contentId,
    'display_order': displayOrder,
    'is_enabled': isEnabled,
  };

  factory HomepageEntry.fromRow(Map<String, dynamic> row) => HomepageEntry(
    id: row['id']?.toString() ?? '',
    contentType:
        ContentTypeX.fromId(row['content_type']?.toString()) ??
        ContentType.azkar,
    contentId: row['content_id']?.toString() ?? '',
    displayOrder: (row['display_order'] as num?)?.toInt() ?? 0,
    isEnabled: row['is_enabled'] != false,
  );
}

/// A resolved homepage card: the layout entry plus the content it points to.
class HomeCard {
  const HomeCard({required this.entry, required this.item, this.span = 1});

  final HomepageEntry entry;
  final ContentItem item;

  /// Grid columns the card occupies on wide layouts (long Quran/Hadith passages
  /// can span two columns so they stay readable).
  final int span;

  String get key => '${entry.id}:${item.cardKey}';
}
