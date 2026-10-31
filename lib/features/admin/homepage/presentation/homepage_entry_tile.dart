import 'package:flutter/material.dart';

import '../../../../core/design/app_palette.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/domain/content_item.dart';
import '../../../content/domain/content_type.dart';
import '../../../home/domain/homepage_entry.dart';

class HomepageEntryTile extends StatelessWidget {
  const HomepageEntryTile({
    super.key,
    required this.entry,
    required this.item,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggle,
    required this.onRemove,
  });

  final HomepageEntry entry;
  final ContentItem? item;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final title = item == null
        ? 'محتوى غير موجود (${entry.contentId})'
        : (item!.displayTitle.isEmpty
              ? item!.type.labelAr
              : item!.displayTitle);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: AppPalette.spaceSm),
      child: ListTile(
        leading: Icon(entry.contentType.icon),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          item == null
              ? 'يُتجاهل في العرض العام حتى تتم إزالته'
              : '${entry.contentType.pluralLabelAr}${item!.isPublished ? '' : ' • مسودة'}',
        ),
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusBadge(
              label: entry.isEnabled ? 'ظاهر' : 'مخفي',
              color: entry.isEnabled
                  ? AppPalette.success
                  : AppPalette.lightMuted,
            ),
            IconButton(
              tooltip: 'أعلى',
              onPressed: canMoveUp ? onMoveUp : null,
              icon: const Icon(Icons.arrow_upward_outlined),
            ),
            IconButton(
              tooltip: 'أسفل',
              onPressed: canMoveDown ? onMoveDown : null,
              icon: const Icon(Icons.arrow_downward_outlined),
            ),
            IconButton(
              tooltip: entry.isEnabled ? 'إخفاء' : 'إظهار',
              onPressed: onToggle,
              icon: Icon(
                entry.isEnabled
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
            IconButton(
              tooltip: 'إزالة من الرئيسية',
              onPressed: onRemove,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}
