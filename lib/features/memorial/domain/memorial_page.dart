class MemorialPage {
  const MemorialPage({
    required this.id,
    required this.ownerUserId,
    required this.slug,
    required this.title,
    this.deceasedName,
    this.dedicationMessage,
    this.description,
    this.isPublished = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerUserId;
  final String slug;
  final String title;
  final String? deceasedName;
  final String? dedicationMessage;
  final String? description;
  final bool isPublished;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MemorialPage copyWith({
    String? slug,
    String? title,
    String? deceasedName,
    String? dedicationMessage,
    String? description,
    bool? isPublished,
  }) => MemorialPage(
    id: id,
    ownerUserId: ownerUserId,
    slug: slug ?? this.slug,
    title: title ?? this.title,
    deceasedName: deceasedName ?? this.deceasedName,
    dedicationMessage: dedicationMessage ?? this.dedicationMessage,
    description: description ?? this.description,
    isPublished: isPublished ?? this.isPublished,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  Map<String, dynamic> toUpdateRow() => <String, dynamic>{
    'slug': slug,
    'title': title.trim(),
    'deceased_name': _nullIfBlank(deceasedName),
    'dedication_message': _nullIfBlank(dedicationMessage),
    'description': _nullIfBlank(description),
    'is_published': isPublished,
  };

  factory MemorialPage.fromRow(Map<String, dynamic> row) => MemorialPage(
    id: row['id']?.toString() ?? '',
    ownerUserId: row['owner_user_id']?.toString() ?? '',
    slug: row['slug']?.toString() ?? '',
    title: row['title']?.toString() ?? '',
    deceasedName: _textOrNull(row['deceased_name']),
    dedicationMessage: _textOrNull(row['dedication_message']),
    description: _textOrNull(row['description']),
    isPublished: row['is_published'] == true,
    createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
    updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? ''),
  );

  static String? _textOrNull(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String? _nullIfBlank(String? value) => _textOrNull(value);
}
