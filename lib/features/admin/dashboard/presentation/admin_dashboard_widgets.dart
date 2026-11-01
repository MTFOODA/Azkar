import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/app_palette.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/data/content_repository.dart';
import '../../../content/domain/content_item.dart';
import '../../../content/domain/content_type.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(AppPalette.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                '$value',
                style: theme.textTheme.displaySmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TypeCountCard extends StatelessWidget {
  const TypeCountCard({super.key, required this.type, this.counts});

  final ContentType type;
  final TypeCounts? counts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = counts ?? TypeCounts.empty;
    return Card(
      elevation: 0,
      child: InkWell(
        onTap: () => context.go('/admin/content/${type.id}'),
        borderRadius: BorderRadius.circular(AppPalette.radiusSm),
        child: Padding(
          padding: const EdgeInsets.all(AppPalette.spaceLg),
          child: Row(
            children: [
              Icon(type.icon, color: theme.colorScheme.secondary, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.pluralLabelAr,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '${value.published} منشور • ${value.drafts} مسودة',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecentTile extends StatelessWidget {
  const RecentTile({super.key, required this.item});

  final ContentItem item;

  @override
  Widget build(BuildContext context) {
    final title = item.displayTitle.isEmpty
        ? item.type.labelAr
        : item.displayTitle;
    return ListTile(
      leading: Icon(item.type.icon),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        item.arabicText.isEmpty ? (item.videoUrl ?? '') : item.arabicText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: StatusBadge(
        label: item.isPublished ? 'منشور' : 'مسودة',
        color: item.isPublished ? AppPalette.success : AppPalette.warning,
      ),
      onTap: () => context.go('/admin/content/${item.type.id}/${item.id}/edit'),
    );
  }
}
