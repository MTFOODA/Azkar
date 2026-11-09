class MemorialPage {
  const MemorialPage({
    required this.id,
    required this.ownerUserId,
    required this.slug,
    required this.title,
    this.deceasedGender,
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
  final String? deceasedGender;
  final String? deceasedName;
  final String? dedicationMessage;
  final String? description;
  final bool isPublished;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get displayDeceasedName {
    final name = deceasedName?.trim() ?? '';
    if (name.isEmpty) {
      return deceasedGender == 'female'
          ? 'اسم الفقيدة غير محدد'
          : 'اسم الفقيد غير محدد';
    }
    if (name.startsWith('المرحوم')) return name;
    return switch (deceasedGender) {
      'male' => 'المرحوم $name',
      'female' => 'المرحومة $name',
      _ => name,
    };
  }

  MemorialPage copyWith({
    String? slug,
    String? title,
    String? deceasedGender,
    String? deceasedName,
    String? dedicationMessage,
    String? description,
    bool? isPublished,
  }) => MemorialPage(
    id: id,
    ownerUserId: ownerUserId,
    slug: slug ?? this.slug,
    title: title ?? this.title,
    deceasedGender: deceasedGender ?? this.deceasedGender,
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
    'deceased_gender': deceasedGender,
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
    deceasedGender: _genderOrNull(row['deceased_gender']),
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

  static String? _genderOrNull(Object? value) {
    final gender = value?.toString();
    return gender == 'male' || gender == 'female' ? gender : null;
  }

  static String? _nullIfBlank(String? value) => _textOrNull(value);
}
