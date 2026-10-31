import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/app_palette.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/state_views.dart';
import '../../memorial/domain/memorial_page.dart';
import '../../memorial/domain/page_slug.dart';
import '../../sharing/share_widgets.dart';
import '../../sharing/sharing_service.dart';

final pageVisibleSectionCountProvider = FutureProvider.family<int, String>((
  ref,
  pageId,
) async {
  final cards = await ref
      .watch(pageHomepageRepositoryProvider(pageId))
      .fetchPublishedLayout();
  return cards.map((card) => card.item.type).toSet().length;
}, dependencies: [pageHomepageRepositoryProvider]);

class OwnerMemorialPagesPage extends ConsumerWidget {
  const OwnerMemorialPagesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(ownedMemorialPagesProvider);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppPalette.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'صفحاتي وروابطي',
              subtitle: 'أنشئ صفحات تذكارية مستقلة وأدر روابطها من مكان واحد.',
              trailing: FilledButton.icon(
                key: const ValueKey('create-memorial-page'),
                onPressed: () => _createPage(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('إنشاء صفحة جديدة'),
              ),
            ),
            const SizedBox(height: AppPalette.spaceLg),
            pages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => ErrorView(
                error: error,
                onRetry: () => ref.invalidate(ownedMemorialPagesProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyView(
                    title: 'لا توجد صفحات تذكارية بعد',
                    message: 'أنشئ أول صفحة لتبدأ بإضافة المحتوى ومشاركته.',
                    action: FilledButton.icon(
                      onPressed: () => _createPage(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('إنشاء صفحة جديدة'),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final page in items)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppPalette.spaceMd,
                        ),
                        child: _MemorialPageManagementCard(page: page),
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

  Future<void> _createPage(BuildContext context, WidgetRef ref) async {
    final identity = await showDialog<_MemorialPageIdentity>(
      context: context,
      builder: (context) => const _MemorialPageIdentityDialog(),
    );
    if (identity == null) return;
    try {
      final page = await ref
          .read(memorialPageRepositoryProvider)
          .create(
            slug: identity.slug,
            deceasedName: identity.deceasedName,
            deceasedGender: identity.deceasedGender,
            dedicationMessage: identity.dedicationMessage,
          );
      ref.invalidate(ownedMemorialPagesProvider);
      if (context.mounted) {
        context.go('/dashboard/pages/${page.id}');
      }
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, friendlyMessage(error), isError: true);
      }
    }
  }
}

class _MemorialPageManagementCard extends ConsumerWidget {
  const _MemorialPageManagementCard({required this.page});

  final MemorialPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionCount = ref.watch(pageVisibleSectionCountProvider(page.id));
    final publicUrl = AppConfig.memorialPageLink(page.slug);
    final basePath = '/dashboard/pages/${page.id}';
    final openedPath = page.isPublished
        ? AppConfig.memorialPagePath(page.slug)
        : '$basePath/preview';
    final titlePrefix = switch (page.deceasedGender) {
      'male' => 'المرحوم',
      'female' => 'المرحومة',
      _ => 'صفحة تذكارية',
    };
    final deceasedName = page.deceasedName?.trim();
    final dedication = page.dedicationMessage?.trim();

    return Card(
      key: ValueKey('memorial-page-${page.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppPalette.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                page.isPublished ? Icons.public_outlined : Icons.lock_outline,
              ),
              title: Text(
                '$titlePrefix${deceasedName == null || deceasedName.isEmpty ? '' : ' $deceasedName'}',
              ),
              subtitle: Text(
                page.isPublished ? 'منشورة' : 'مسودة — الرابط غير متاح للعامة',
              ),
              trailing: IconButton(
                tooltip: page.isPublished ? 'إلغاء النشر' : 'نشر',
                onPressed: () => _togglePublished(context, ref),
                icon: Icon(
                  page.isPublished
                      ? Icons.visibility_off_outlined
                      : Icons.publish_outlined,
                ),
              ),
            ),
            if (dedication != null && dedication.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppPalette.spaceSm),
                child: Text(
                  dedication,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            SelectableText(
              publicUrl,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
            ),
            if (!page.isPublished)
              const Padding(
                padding: EdgeInsets.only(top: AppPalette.spaceXs),
                child: Text(
                  'المعاينة خاصة بك؛ لن يتمكن الزوار من فتح الرابط قبل النشر.',
                ),
              ),
            const SizedBox(height: AppPalette.spaceSm),
            Wrap(
              spacing: AppPalette.spaceSm,
              runSpacing: AppPalette.spaceSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                sectionCount.when(
                  loading: () => const Chip(
                    avatar: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: Text('جاري حساب الأقسام'),
                  ),
                  error: (error, stackTrace) => ActionChip(
                    avatar: const Icon(Icons.error_outline),
                    label: const Text('تعذر تحميل الأقسام'),
                    onPressed: () => ref.invalidate(
                      pageVisibleSectionCountProvider(page.id),
                    ),
                  ),
                  data: (count) => Chip(
                    avatar: const Icon(Icons.view_agenda_outlined),
                    label: Text('الأقسام الظاهرة: $count'),
                  ),
                ),
                if (page.updatedAt != null)
                  Chip(
                    avatar: const Icon(Icons.update_outlined),
                    label: Text(
                      'آخر تحديث: ${intl.DateFormat('yyyy/MM/dd').format(page.updatedAt!.toLocal())}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppPalette.spaceSm),
            Wrap(
              spacing: AppPalette.spaceSm,
              runSpacing: AppPalette.spaceSm,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.go(openedPath),
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('فتح الصفحة'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go(basePath),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل الصفحة'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyLink(context, publicUrl),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('نسخ الرابط'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _sharePage(context, page, publicUrl),
                  icon: const Icon(Icons.ios_share_outlined),
                  label: const Text('مشاركة'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _duplicatePage(context, ref),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('نسخ الصفحة'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _togglePublished(context, ref),
                  icon: Icon(
                    page.isPublished
                        ? Icons.visibility_off_outlined
                        : Icons.publish_outlined,
                  ),
                  label: Text(page.isPublished ? 'إلغاء النشر' : 'نشر'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyLink(BuildContext context, String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (context.mounted) _showMessage(context, 'تم نسخ الرابط.');
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, 'تعذّر نسخ الرابط.', isError: true);
      }
    }
  }

  Future<void> _togglePublished(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(memorialPageRepositoryProvider)
          .update(page.copyWith(isPublished: !page.isPublished));
      ref.invalidate(ownedMemorialPageProvider(page.id));
      ref.invalidate(ownedMemorialPagesProvider);
      if (context.mounted) {
        _showMessage(
          context,
          page.isPublished ? 'تم إلغاء نشر الصفحة.' : 'تم نشر الصفحة.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, friendlyMessage(error), isError: true);
      }
    }
  }

  Future<void> _duplicatePage(BuildContext context, WidgetRef ref) async {
    final identity = await showDialog<_MemorialPageIdentity>(
      context: context,
      builder: (context) => _MemorialPageIdentityDialog(source: page),
    );
    if (identity == null) return;
    try {
      final copy = await ref
          .read(memorialPageRepositoryProvider)
          .duplicate(
            sourcePageId: page.id,
            slug: identity.slug,
            deceasedName: identity.deceasedName,
            deceasedGender: identity.deceasedGender,
            dedicationMessage: identity.dedicationMessage,
          );
      ref.invalidate(ownedMemorialPagesProvider);
      if (context.mounted) {
        _showMessage(context, 'تم إنشاء نسخة مستقلة.');
        context.go('/dashboard/pages/${copy.id}');
      }
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, friendlyMessage(error), isError: true);
      }
    }
  }
}

class _MemorialPageIdentity {
  const _MemorialPageIdentity({
    required this.slug,
    required this.deceasedName,
    required this.deceasedGender,
    this.dedicationMessage,
  });

  final String slug;
  final String deceasedName;
  final String deceasedGender;
  final String? dedicationMessage;
}

class _MemorialPageIdentityDialog extends StatefulWidget {
  const _MemorialPageIdentityDialog({this.source});

  final MemorialPage? source;

  @override
  State<_MemorialPageIdentityDialog> createState() =>
      _MemorialPageIdentityDialogState();
}

class _MemorialPageIdentityDialogState
    extends State<_MemorialPageIdentityDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _slug;
  late final TextEditingController _name;
  late final TextEditingController _dedication;
  String? _gender;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    final suffix = const Uuid().v4().substring(0, 8);
    final prefix = source == null
        ? 'memorial'
        : source.slug.substring(0, math.min(25, source.slug.length));
    _slug = TextEditingController(text: '$prefix-$suffix');
    _name = TextEditingController();
    _dedication = TextEditingController(text: source?.dedicationMessage ?? '');
  }

  @override
  void dispose() {
    _slug.dispose();
    _name.dispose();
    _dedication.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.source == null ? 'إنشاء صفحة جديدة' : 'نسخ الصفحة'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'اسم المتوفى'),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'أدخل اسم المتوفى.'
                    : null,
              ),
              const SizedBox(height: AppPalette.spaceMd),
              DropdownButtonFormField<String>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'جنس المتوفى'),
                items: const [
                  DropdownMenuItem(value: 'male', child: Text('ذكر — المرحوم')),
                  DropdownMenuItem(
                    value: 'female',
                    child: Text('أنثى — المرحومة'),
                  ),
                ],
                onChanged: (value) => setState(() => _gender = value),
                validator: (value) =>
                    value == null ? 'اختر جنس المتوفى.' : null,
              ),
              const SizedBox(height: AppPalette.spaceMd),
              TextFormField(
                controller: _dedication,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'رسالة الإهداء (اختيارية)',
                ),
              ),
              const SizedBox(height: AppPalette.spaceMd),
              TextFormField(
                controller: _slug,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'الرابط المختصر'),
                validator: (value) => PageSlug.validate(value ?? ''),
              ),
              const SizedBox(height: AppPalette.spaceXs),
              const Text(
                'تُنشأ الصفحة كمسودة مستقلة. يمكنك تعديل بياناتها قبل نشرها.',
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          final gender = _gender;
          if (gender == null) return;
          Navigator.pop(
            context,
            _MemorialPageIdentity(
              slug: PageSlug.normalize(_slug.text),
              deceasedName: _name.text.trim(),
              deceasedGender: gender,
              dedicationMessage: _dedication.text.trim(),
            ),
          );
        },
        child: Text(widget.source == null ? 'إنشاء مسودة' : 'إنشاء نسخة'),
      ),
    ],
  );
}

void _showMessage(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
}

Future<void> _sharePage(
  BuildContext context,
  MemorialPage page,
  String publicUrl,
) async {
  if (!page.isPublished) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الصفحة غير منشورة'),
        content: const Text(
          'الرابط العام غير متاح للزوار. انشر الصفحة أولًا لمشاركتها.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
    return;
  }
  await showShareSheet(
    context,
    text: SharingService.memorialText(page),
    link: publicUrl,
  );
}
