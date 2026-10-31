import 'package:flutter/material.dart';

import '../../../../core/design/app_palette.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/domain/content_item.dart';
import '../../../content/domain/content_type.dart';

/// One row in an admin content collection.
class AdminContentRow extends StatelessWidget {
  const AdminContentRow({
    super.key,
    required this.item,
    required this.busy,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onTogglePublish,
    required this.onDuplicate,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ContentItem item;
  final bool busy;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onTogglePublish;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.displayTitle.isEmpty
        ? item.type.labelAr
        : item.displayTitle;
    final body = item.arabicText.isEmpty
        ? (item.videoUrl ?? item.videoId ?? '')
        : item.arabicText;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: AppPalette.spaceSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.secondary.withValues(
                  alpha: 0.12,
                ),
                child: Icon(item.type.icon, color: theme.colorScheme.secondary),
              ),
              title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: onEdit,
              trailing: Wrap(
                spacing: 4,
                children: [
                  StatusBadge(
                    label: item.isPublished ? 'منشور' : 'مسودة',
                    color: item.isPublished
                        ? AppPalette.success
                        : AppPalette.warning,
                  ),
                  if (item.reviewBadge != null)
                    StatusBadge(
                      label: item.reviewBadge!,
                      color: AppPalette.warning,
                    ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'تحريك لأعلى',
                    onPressed: busy || !canMoveUp ? null : onMoveUp,
                    icon: const Icon(Icons.arrow_upward_outlined),
                  ),
                  IconButton(
                    tooltip: 'تحريك لأسفل',
                    onPressed: busy || !canMoveDown ? null : onMoveDown,
                    icon: const Icon(Icons.arrow_downward_outlined),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('تعديل'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : onTogglePublish,
                    icon: Icon(
                      item.isPublished
                          ? Icons.unpublished_outlined
                          : Icons.publish_outlined,
                      size: 18,
                    ),
                    label: Text(item.isPublished ? 'إلغاء النشر' : 'نشر'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : onDuplicate,
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('تكرار'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    label: Text(
                      'حذف',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
