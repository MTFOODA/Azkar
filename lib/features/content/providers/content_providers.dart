import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/typography/arabic_font_loader.dart';
import '../../content/domain/content_item.dart';
import '../../content/domain/content_type.dart';
import '../../home/domain/homepage_entry.dart';

/// The homepage is resolved entirely from the administrator-managed layout.
final homeLayoutProvider = FutureProvider<List<HomeCard>>((ref) async {
  final cards = await ref
      .watch(homepageRepositoryProvider)
      .fetchPublishedLayout();
  // Warm only the fonts actually used by visible cards, after the data arrives.
  await ArabicFontLoader.ensureAll(
    cards.map((card) => card.item.style.fontFamily),
  );
  return cards;
}, dependencies: [homepageRepositoryProvider]);

/// Published records for a collection route (`/azkar`, `/quran`, ...).
final publishedContentProvider =
    FutureProvider.family<List<ContentItem>, ContentType>((ref, type) async {
      final items = await ref
          .watch(contentRepositoryProvider)
          .fetchPublished(type);
      await ArabicFontLoader.ensureAll(
        items.map((item) => item.style.fontFamily),
      );
      return items;
    }, dependencies: [contentRepositoryProvider]);

/// A single shared-card deep link. The record type and id form the family key.
final sharedContentProvider =
    FutureProvider.family<ContentItem?, ({ContentType type, String id})>((
      ref,
      key,
    ) async {
      return ref.watch(contentRepositoryProvider).fetchById(key.type, key.id);
    }, dependencies: [contentRepositoryProvider]);
