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
import '../../../core/widgets/adaptive_layout.dart';
import '../../../core/widgets/state_views.dart';
import '../../memorial/domain/memorial_page.dart';
import '../../memorial/domain/page_slug.dart';
import '../../memorial/presentation/memorial_gender_segmented_control.dart';
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
      child: PageContent(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final createButton = _createPageButton(context, ref);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (constraints.maxWidth < AppBreakpoints.mobile) ...[
                  const SectionHeader(
                    title: 'صفحاتي وروابطي',
                    subtitle:
                        'أنشئ صفحات تذكارية مستقلة وأدر روابطها من مكان واحد.',
                  ),
                  const SizedBox(height: AppPalette.spaceMd),
                  createButton,
                ] else
                  SectionHeader(
                    title: 'صفحاتي وروابطي',
                    subtitle:
                        'أنشئ صفحات تذكارية مستقلة وأدر روابطها من مكان واحد.',
                    trailing: createButton,
                  ),
                const SizedBox(height: AppPalette.spaceLg),
                pages.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, stackTrace) => ErrorView(
                    error: error,
                    onRetry: () => ref.invalidate(ownedMemorialPagesProvider),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return const EmptyView(
                        title: 'لا توجد صفحات تذكارية بعد',
                        message: 'أنشئ أول صفحة لتبدأ بإضافة المحتوى ومشاركته.',
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AppPalette.spaceSm,
                          ),
                          child: Text(
                            'عدد الصفحات: ${items.length}',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                        AdaptiveCardGrid(
                          spacing: AppPalette.spaceMd,
                          runSpacing: AppPalette.spaceMd,
                          minCardWidth: 340,
                          children: [
                            for (final page in items)
                              _MemorialPageManagementCard(page: page),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _createPageButton(BuildContext context, WidgetRef ref) =>
      FilledButton.icon(
        key: const ValueKey('create-memorial-page'),
        onPressed: () => _createPage(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('إنشاء صفحة جديدة'),
      );

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
    final theme = Theme.of(context);
    final statusColor = page.isPublished
        ? theme.colorScheme.primary
        : theme.colorScheme.secondary;
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

    Widget actionButton({
      required String label,
      required IconData icon,
      required VoidCallback onPressed,
      bool primary = false,
    }) {
      if (primary) {
        return FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
      }
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
    }

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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: StatusBadge(
                label: page.isPublished ? 'منشورة' : 'مسودة',
                color: statusColor,
                icon: page.isPublished
                    ? Icons.public_outlined
                    : Icons.lock_outline,
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
            if (dedication != null && dedication.isNotEmpty) ...[
              const SizedBox(height: AppPalette.spaceSm),
              Text(
                dedication,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppPalette.spaceSm),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                publicUrl,
                maxLines: 2,
                textAlign: TextAlign.left,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (!page.isPublished)
              const Padding(
                padding: EdgeInsets.only(top: AppPalette.spaceSm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('مسودة — الرابط غير متاح للعامة'),
                    SizedBox(height: AppPalette.spaceXs),
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16),
                        SizedBox(width: AppPalette.spaceXs),
                        Expanded(
                          child: Text(
                            'المعاينة خاصة بك؛ لن يتمكن الزوار من فتح الرابط قبل النشر.',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppPalette.spaceMd),
            Wrap(
              spacing: AppPalette.spaceSm,
              runSpacing: AppPalette.spaceXs,
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
            const SizedBox(height: AppPalette.spaceMd),
            Wrap(
              spacing: AppPalette.spaceSm,
              runSpacing: AppPalette.spaceSm,
              children: [
                actionButton(
                  label: 'فتح الصفحة',
                  icon: Icons.open_in_new_outlined,
                  onPressed: () => context.go(openedPath),
                  primary: true,
                ),
                actionButton(
                  label: 'تعديل الصفحة',
                  icon: Icons.edit_outlined,
                  onPressed: () => context.go(basePath),
                ),
                actionButton(
                  label: 'نسخ الرابط',
                  icon: Icons.copy_outlined,
                  onPressed: () => _copyLink(context, publicUrl),
                ),
                actionButton(
                  label: 'مشاركة',
                  icon: Icons.ios_share_outlined,
                  onPressed: () => _sharePage(context, page, publicUrl),
                ),
                actionButton(
                  label: 'نسخ الصفحة',
                  icon: Icons.copy_all_outlined,
                  onPressed: () => _duplicatePage(context, ref),
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
                TextButton.icon(
                  key: ValueKey('delete-memorial-page-${page.id}'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () => _deletePage(context, ref),
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('حذف الصفحة'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePage(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteMemorialPageDialog(
        displayName: page.deceasedName?.trim().isNotEmpty == true
            ? page.deceasedName!.trim()
            : page.title,
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(memorialPageRepositoryProvider).delete(page.id);
      ref.invalidate(ownedMemorialPageProvider(page.id));
      ref.invalidate(pageVisibleSectionCountProvider(page.id));
      ref.invalidate(ownedMemorialPagesProvider);
      if (context.mounted) _showMessage(context, 'تم حذف الصفحة نهائيًا.');
    } catch (error) {
      if (context.mounted) {
        _showMessage(context, friendlyMessage(error), isError: true);
      }
    }
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

class _DeleteMemorialPageDialog extends StatefulWidget {
  const _DeleteMemorialPageDialog({required this.displayName});

  final String displayName;

  @override
  State<_DeleteMemorialPageDialog> createState() =>
      _DeleteMemorialPageDialogState();
}

class _DeleteMemorialPageDialogState extends State<_DeleteMemorialPageDialog> {
  final _confirmation = TextEditingController();

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('هل أنت متأكد من حذف صفحة ${widget.displayName} نهائيًا؟'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيتم حذف الصفحة وجميع محتوياتها المرتبطة بها، ولن تتمكن من استعادتها من داخل التطبيق.',
            ),
            const SizedBox(height: AppPalette.spaceSm),
            const Text('سيتوقف رابط الصفحة العام عن العمل.'),
            const SizedBox(height: AppPalette.spaceMd),
            TextField(
              key: const ValueKey('delete-confirmation-field'),
              controller: _confirmation,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'اكتب "حذف" للتأكيد',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const ValueKey('confirm-delete-memorial-page'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _confirmation.text.trim() == 'حذف'
              ? () => Navigator.of(context).pop(true)
              : null,
          child: const Text('حذف نهائي'),
        ),
      ],
    );
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
                decoration: InputDecoration(
                  labelText: _gender == 'female'
                      ? 'اسم المتوفاة'
                      : 'اسم المتوفى',
                ),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? _gender == 'female'
                          ? 'أدخل اسم المتوفاة.'
                          : 'أدخل اسم المتوفى.'
                    : null,
              ),
              const SizedBox(height: AppPalette.spaceMd),
              FormField<String>(
                initialValue: _gender,
                validator: (value) =>
                    value == null ? 'اختر المرحوم أو المرحومة.' : null,
                builder: (field) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MemorialGenderSegmentedControl(
                      value: field.value,
                      onChanged: (value) {
                        setState(() => _gender = value);
                        field.didChange(value);
                      },
                    ),
                    if (field.errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: AppPalette.spaceXs,
                          left: AppPalette.spaceMd,
                          right: AppPalette.spaceMd,
                        ),
                        child: Text(
                          field.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
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
