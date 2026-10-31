import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../content/data/content_repository.dart';
import '../../../content/domain/content_item.dart';
import '../../../content/domain/content_type.dart';

import '../../../home/domain/homepage_entry.dart';

/// Every item (drafts included) for one admin collection.
final adminContentProvider =
    FutureProvider.family<List<ContentItem>, ContentType>((ref, type) async {
      return ref.watch(contentRepositoryProvider).fetchAll(type);
    }, dependencies: [contentRepositoryProvider]);

/// Layout rows plus the content records needed to label them.
class AdminHomepageData {
  const AdminHomepageData({required this.entries, required this.items});

  final List<HomepageEntry> entries;
  final Map<String, ContentItem> items;
}

final adminHomepageProvider = FutureProvider<AdminHomepageData>((ref) async {
  final entries = await ref.watch(homepageRepositoryProvider).fetchEntries();
  final items = <String, ContentItem>{};
  for (final type in ContentType.values) {
    final records = await ref.watch(contentRepositoryProvider).fetchAll(type);
    for (final item in records) {
      items[item.cardKey] = item;
    }
  }
  return AdminHomepageData(entries: entries, items: items);
}, dependencies: [contentRepositoryProvider, homepageRepositoryProvider]);

/// Aggregate dashboard data. No visitor analytics or Tasbeeh counts are
/// collected; these are content counts only.
class AdminDashboardData {
  const AdminDashboardData({required this.counts, required this.recent});

  final Map<ContentType, TypeCounts> counts;
  final List<ContentItem> recent;

  int get published =>
      counts.values.fold(0, (sum, value) => sum + value.published);

  int get drafts => counts.values.fold(0, (sum, value) => sum + value.drafts);
}

final adminDashboardProvider = FutureProvider<AdminDashboardData>((ref) async {
  final repository = ref.watch(contentRepositoryProvider);
  final counts = await repository.counts();
  final recent = <ContentItem>[];
  for (final type in ContentType.values) {
    recent.addAll(await repository.fetchAll(type));
  }
  recent.sort((a, b) {
    final aDate =
        a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate =
        b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  });
  return AdminDashboardData(counts: counts, recent: recent.take(10).toList());
}, dependencies: [contentRepositoryProvider]);
