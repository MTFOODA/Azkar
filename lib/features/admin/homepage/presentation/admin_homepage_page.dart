import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/design/app_palette.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/utils/app_exception.dart';
import '../../../../core/widgets/route_back_button.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/domain/content_item.dart';
import '../../../content/domain/content_type.dart';
import '../../../content/providers/content_providers.dart';
import '../../../home/domain/homepage_entry.dart';
import '../../content_management/providers/admin_providers.dart';
import '../../dashboard/presentation/admin_shell.dart';
import 'homepage_entry_tile.dart';

/// Keyboard-accessible homepage ordering and visibility manager.
class AdminHomepagePage extends ConsumerStatefulWidget {
  const AdminHomepagePage({super.key, this.isPersonalPage = false});

  final bool isPersonalPage;

  @override
  ConsumerState<AdminHomepagePage> createState() => _AdminHomepagePageState();
}

class _AdminHomepagePageState extends ConsumerState<AdminHomepagePage> {
  List<HomepageEntry>? _entries;
  AdminHomepageData? _source;
  bool _busy = false;

  Future<void> _refresh() async {
    ref.invalidate(adminHomepageProvider);
    ref.invalidate(homeLayoutProvider);
  }

  Future<void> _saveOrder() async {
    final entries = _entries;
    if (entries == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(homepageRepositoryProvider).saveOrder(entries);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ ترتيب الصفحة الرئيسية')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(HomepageEntry entry) async {
    try {
      await ref
          .read(homepageRepositoryProvider)
          .setEnabled(entry.id, !entry.isEnabled);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    }
  }

  Future<void> _remove(HomepageEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إزالة من الرئيسية'),
        content: const Text(
          'لن يُحذف المحتوى نفسه، ستتم إزالته من الصفحة الرئيسية فقط.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(homepageRepositoryProvider).remove(entry.id);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    }
  }

  void _move(int index, int delta) {
    final entries = _entries;
    if (entries == null) return;
    final target = index + delta;
    if (target < 0 || target >= entries.length) return;
    setState(() {
      final item = entries.removeAt(index);
      entries.insert(target, item);
    });
  }

  Future<void> _addContent(AdminHomepageData data) async {
    final existing = _entries ?? data.entries;
    final candidates =
        data.items.values
            .where((item) {
              return item.isPublished &&
                  !existing.any(
                    (entry) =>
                        entry.contentType == item.type &&
                        entry.contentId == item.id,
                  );
            })
            .toList(growable: false)
          ..sort((a, b) => a.type.index.compareTo(b.type.index));
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد محتوى منشور غير مضاف للرئيسية.')),
      );
      return;
    }
    final selected = await showDialog<ContentItem>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إضافة بطاقة للرئيسية'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final item in candidates)
                ListTile(
                  leading: Icon(item.type.icon),
                  title: Text(
                    item.displayTitle.isEmpty
                        ? item.type.labelAr
                        : item.displayTitle,
                  ),
                  subtitle: Text(item.type.pluralLabelAr),
                  onTap: () => Navigator.pop(dialogContext, item),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    try {
      await ref
          .read(homepageRepositoryProvider)
          .add(contentType: selected.type, contentId: selected.id);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(adminHomepageProvider);
    return asyncData.when(
      loading: () => const LoadingView(),
      error: (error, stackTrace) => ErrorView(error: error, onRetry: _refresh),
      data: (data) {
        if (!identical(_source, data)) {
          _source = data;
          _entries = [...data.entries];
        }
        final entries = _entries!;
        final originalOrder = data.entries.map((entry) => entry.id).toList();
        final currentOrder = entries.map((entry) => entry.id).toList();
        return UnsavedChangesGuard(
          isDirty: currentOrder.toString() != originalOrder.toString(),
          fallbackLocation: widget.isPersonalPage
              ? '/dashboard'
              : '/admin/dashboard',
          child: SingleChildScrollView(
            child: AdminPageContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: 'إدارة الصفحة الرئيسية',
                    subtitle: 'تحكم في البطاقات الظاهرة وترتيبها. البطاقات غير المنشورة لا تظهر للزوار.',
                    trailing: FilledButton.icon(
                      onPressed: () => _addContent(data),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة بطاقة'),
                    ),
                  ),
                  const SizedBox(height: AppPalette.spaceLg),
                  Wrap(
                    spacing: AppPalette.spaceMd,
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _saveOrder,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('حفظ الترتيب'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (!widget.isPersonalPage) {
                            navigateToLocation(context, '/');
                            return;
                          }
                          final page = ref.read(selectedMemorialPageProvider);
                          if (page != null) {
                            navigateToLocation(
                              context,
                              AppConfig.memorialPagePath(page.slug),
                            );
                          }
                        },
                        icon: const Icon(Icons.preview_outlined),
                        label: const Text('معاينة الموقع'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppPalette.spaceLg),
                  if (entries.isEmpty)
                    const EmptyView(
                      title: 'الصفحة الرئيسية فارغة',
                      message: 'أضف بطاقة من المحتوى المنشور.',
                    )
                  else
                    for (var index = 0; index < entries.length; index++)
                      HomepageEntryTile(
                        entry: entries[index],
                        item: data
                            .items['${entries[index].contentType.id}:${entries[index].contentId}'],
                        canMoveUp: index > 0,
                        canMoveDown: index < entries.length - 1,
                        onMoveUp: () => _move(index, -1),
                        onMoveDown: () => _move(index, 1),
                        onToggle: () => _toggle(entries[index]),
                        onRemove: () => _remove(entries[index]),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
