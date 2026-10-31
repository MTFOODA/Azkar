import 'package:flutter/material.dart';

import '../../content/domain/content_type.dart';

class MemorialSectionNavigation {
  MemorialSectionNavigation._();

  static final Map<String, Map<ContentType, GlobalKey>> _sections = {};

  static GlobalKey register(String slug, ContentType type) {
    return _sections
        .putIfAbsent(slug, () => {})
        .putIfAbsent(
          type,
          () => GlobalKey(debugLabel: 'public-memorial-${type.id}'),
        );
  }

  static void unregister(String slug, ContentType type, GlobalKey key) {
    final sections = _sections[slug];
    if (sections?[type] != key) return;
    sections!.remove(type);
    if (sections.isEmpty) _sections.remove(slug);
  }

  static List<ContentType> visibleTypes(String slug) =>
      List<ContentType>.unmodifiable(_sections[slug]?.keys ?? const []);

  static Future<void> scrollTo(String slug, ContentType type) async {
    final targetContext = _sections[slug]?[type]?.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      alignment: 0.04,
    );
  }
}
