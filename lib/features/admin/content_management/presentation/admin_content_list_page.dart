import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/app_palette.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/utils/app_exception.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../content/data/content_homepage_lifecycle.dart';
import '../../../content/domain/content_item.dart';
import '../../../content/domain/content_type.dart';
import '../../../content/domain/content_validation.dart';
import '../providers/admin_providers.dart';
import '../../dashboard/presentation/admin_shell.dart';
import 'admin_content_row.dart';

/// Reusable administrator collection table for all content types.
class AdminContentListPage extends ConsumerStatefulWidget {
  const AdminContentListPage({
    super.key,
    required this.type,
    this.basePath = '/admin',
  });

  final ContentType type;
  final String basePath;

  @override
  ConsumerState<AdminContentListPage> createState() =>
      _AdminContentListPageState();
}

class _AdminContentListPageState extends ConsumerState<AdminContentListPage> {
  String _query = '';
  bool _busy = false;

  Future<void> _refresh() async {
    invalidateContentViews(ref);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } catch (error) {
      if (error is ContentHomepageLinkException) {
        invalidateContentViews(ref);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePublish(ContentItem item) async {
    final publishing = !item.isPublished;
    if (publishing) {
      final validation = ContentValidation.validate(item, forPublication: true);
      if (!validation.isValid) {
        final message = validation.fieldErrors.values.first;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      if (item.type == ContentType.quran) {
        final result = await ref
            .read(quranDatasetRepositoryProvider)
            .validate(
              surahNumber: item.surahNumber ?? 0,
              from: item.ayahFrom ?? 0,
              to: item.ayahTo ?? item.ayahFrom ?? 0,
              text: item.arabicText,
            );
        if (!result.isValid) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(result.messageAr)));
          }
          return;
        }
      }
    }
    await _run(
      () => ref
          .read(contentRepositoryProvider)
          .setPublished(item.type, item.id, publishing),
    );
  }

  Future<void> _delete(ContentItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف المحتوى'),
        content: Text(
          'سيتم حذف هذا العنصر نهائيًا. هل أنت متأكد؟\n\n${item.displayTitle}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => ref.read(contentRepositoryProvider).delete(item.type, item.id),
    );
  }

  Future<void> _move(List<ContentItem> items, int index, int delta) async {
    final target = index + delta;
    if (target < 0 || target >= items.length) return;
    final reordered = [...items];
    final item = reordered.removeAt(index);
    reordered.insert(target, item);
    await _run(
      () => ref
          .read(contentRepositoryProvider)
          .reorder(widget.type, reordered.map((item) => item.id).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncItems = ref.watch(adminContentProvider(widget.type));
    return SingleChildScrollView(
      child: AdminPageContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'إدارة ${widget.type.pluralLabelAr}',
              subtitle: 'إنشاء وتعديل ونشر وترتيب المحتوى دون تعديل الكود.',
              trailing: FilledButton.icon(
                onPressed: () => context.go(
                  '${widget.basePath}/content/${widget.type.id}/new',
                ),
                icon: const Icon(Icons.add),
                label: const Text('إضافة'),
              ),
            ),
            const SizedBox(height: AppPalette.spaceMd),
            TextField(
              decoration: const InputDecoration(
                labelText: 'بحث في المحتوى',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: AppPalette.spaceLg),
            asyncItems.when(
              loading: () => const LoadingView(),
              error: (error, stackTrace) =>
                  ErrorView(error: error, onRetry: _refresh),
              data: (items) {
                final filtered = items
                    .where((item) {
                      if (_query.isEmpty) return true;
                      final haystack =
                          '${item.title} ${item.arabicText} ${item.source ?? ''} ${item.personName ?? ''}';
                      return haystack.contains(_query);
                    })
                    .toList(growable: false);
                if (filtered.isEmpty) {
                  return EmptyView(
                    title: _query.isEmpty
                        ? 'لا توجد سجلات بعد'
                        : 'لا توجد نتائج للبحث',
                    message: 'أضف أول ${widget.type.labelAr} من زر الإضافة.',
                    icon: widget.type.icon,
                  );
                }
                return Column(
                  children: [
                    for (var index = 0; index < filtered.length; index++)
                      AdminContentRow(
                        item: filtered[index],
                        busy: _busy,
                        canMoveUp: _query.isEmpty && index > 0,
                        canMoveDown:
                            _query.isEmpty && index < filtered.length - 1,
                        onEdit: () => context.go(
                          '${widget.basePath}/content/${widget.type.id}/${filtered[index].id}/edit',
                        ),
                        onTogglePublish: () => _togglePublish(filtered[index]),
                        onDuplicate: () => _run(() async {
                          await ref
                              .read(contentHomepageLifecycleProvider)
                              .duplicate(filtered[index]);
                        }),
                        onDelete: () => _delete(filtered[index]),
                        onMoveUp: () => _move(filtered, index, -1),
                        onMoveDown: () => _move(filtered, index, 1),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
