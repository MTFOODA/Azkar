class PageSlug {
  const PageSlug._();

  static const int minLength = 3;
  static const int maxLength = 40;
  static const Set<String> reserved = <String>{
    'admin',
    'api',
    'assets',
    'auth',
    'c',
    'dashboard',
    'dedications',
    'dua',
    'hadith',
    'login',
    'm',
    'register',
    'settings',
    'videos',
    'azkar',
    'quran',
  };

  static String normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static String? validate(String value) {
    final slug = normalize(value);
    if (slug.length < minLength || slug.length > maxLength) {
      return 'يجب أن يتراوح الرابط المختصر بين 3 و40 حرفًا.';
    }
    if (reserved.contains(slug)) {
      return 'هذا الرابط محجوز.';
    }
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(slug)) {
      return 'استخدم الحروف الإنجليزية والأرقام والشرطة فقط.';
    }
    return null;
  }
}
