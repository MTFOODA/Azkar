import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/design/app_palette.dart';
import '../../../core/design/azkar_brand.dart';
import '../../../core/design/app_theme.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/adaptive_layout.dart';
import '../../../core/widgets/route_back_button.dart';
import '../../../core/widgets/state_views.dart';
import '../../admin/content_management/presentation/admin_content_editor_page.dart';
import '../../admin/content_management/presentation/admin_content_list_page.dart';
import '../../admin/homepage/presentation/admin_homepage_page.dart';
import '../../admin/appearance/presentation/admin_appearance_page.dart';
import '../../content/data/content_repository.dart';
import '../../content/domain/content_type.dart';
import '../../content/widgets/content_card.dart';
import '../../memorial/domain/memorial_page.dart';
import '../../memorial/domain/page_slug.dart';
import '../../memorial/presentation/memorial_section_navigation.dart';
import '../../home/data/bismillah_loader.dart';
import '../../home/domain/homepage_entry.dart';
import '../../sharing/share_widgets.dart';

class OwnerDashboardScope extends ConsumerWidget {
  const OwnerDashboardScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(currentMemorialPageProvider);
    return page.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (error, stackTrace) => Scaffold(
        body: ErrorView(
          error: error,
          onRetry: () => ref.invalidate(currentMemorialPageProvider),
        ),
      ),
      data: (value) {
        if (value == null) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: EmptyView(
                    title: 'لم تُجهّز الصفحة الشخصية بعد',
                    message:
                        'لم يُعثر على صفحة مرتبطة بهذا الحساب. تحقق من '
                        'تطبيق المخطط الأولي ومشغّل '
                        'azkar_provision_owner_page وسياسات RLS. '
                        'لن ينشئ التطبيق صفحة بديلة تلقائيًا.',
                    action: FilledButton.icon(
                      key: const ValueKey('retry-memorial-page'),
                      onPressed: () =>
                          ref.invalidate(currentMemorialPageProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة التحقق'),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return ProviderScope(
          key: ValueKey(value.id),
          overrides: [
            contentRepositoryProvider.overrideWith(
              (scopeRef) =>
                  scopeRef.watch(pageContentRepositoryProvider(value.id)),
            ),
            homepageRepositoryProvider.overrideWith(
              (scopeRef) =>
                  scopeRef.watch(pageHomepageRepositoryProvider(value.id)),
            ),
            themeRepositoryProvider.overrideWith(
              (scopeRef) =>
                  scopeRef.watch(pageThemeRepositoryProvider(value.id)),
            ),
          ],
          child: OwnerDashboardShell(page: value, child: child),
        );
      },
    );
  }
}

class OwnerDashboardShell extends ConsumerWidget {
  const OwnerDashboardShell({
    super.key,
    required this.page,
    required this.child,
  });

  final MemorialPage page;
  final Widget child;

  static const _entries = <({String label, IconData icon, String path})>[
    (label: 'لوحة صفحتي', icon: Icons.dashboard_outlined, path: '/dashboard'),
    (
      label: 'ترتيب الرئيسية',
      icon: Icons.home_outlined,
      path: '/dashboard/homepage',
    ),
    (
      label: 'المظهر والخطوط',
      icon: Icons.palette_outlined,
      path: '/dashboard/appearance',
    ),
    (
      label: 'إعدادات الصفحة',
      icon: Icons.settings_outlined,
      path: '/dashboard/settings',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 1000;
    final location = GoRouterState.of(context).matchedLocation;
    final isRoot = location == '/dashboard';
    final contentDestinations = [
      for (final type in ContentType.values)
        (
          label: type.pluralLabelAr,
          icon: type.icon,
          path: '/dashboard/content/${type.id}',
        ),
    ];
    final destinations = [..._entries, ...contentDestinations];
    final navigation = ListView(
      padding: const EdgeInsets.all(AppPalette.spaceMd),
      children: [
        ListTile(
          title: const Text('لوحة صفحتي'),
          subtitle: Text(
            page.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: const AzkarBrandMark(size: 42),
        ),
        const Divider(),
        for (final entry in destinations)
          ListTile(
            leading: Icon(entry.icon),
            title: Text(entry.label),
            onTap: () =>
                navigateToLocation(context, entry.path, closeDrawer: true),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.open_in_new_outlined),
          title: const Text('معاينة الصفحة العامة'),
          onTap: () => navigateToLocation(
            context,
            AppConfig.memorialPagePath(page.slug),
            closeDrawer: true,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.logout_outlined),
          title: const Text('تسجيل الخروج'),
          onTap: () async {
            if (!await confirmUnsavedChanges(context) || !context.mounted) {
              return;
            }
            await ref.read(accountSessionProvider.notifier).signOut();
            if (context.mounted) context.go('/login');
          },
        ),
      ],
    );
    if (!isWide) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leadingWidth: 0,
          titleSpacing: 0,
          title: LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              width: constraints.maxWidth,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  children: [
                    Builder(
                      builder: (scaffoldContext) => IconButton(
                        key: const ValueKey('owner-shell-menu'),
                        tooltip: 'القائمة',
                        onPressed: () =>
                            Scaffold.of(scaffoldContext).openDrawer(),
                        icon: const Icon(Icons.menu),
                      ),
                    ),
                    const AzkarBrandLockup(markSize: 36),
                    const Spacer(),
                    IconButton(
                      tooltip: 'معاينة الصفحة العامة',
                      onPressed: () => navigateToLocation(
                        context,
                        AppConfig.memorialPagePath(page.slug),
                      ),
                      icon: const Icon(Icons.open_in_new_outlined),
                    ),
                    if (!isRoot) const RouteBackButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
        drawer: Drawer(child: SafeArea(child: navigation)),
        body: SafeArea(child: child),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: 270, child: SafeArea(child: navigation)),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                if (!isRoot)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: RouteBackButton(),
                  ),
                Expanded(child: SafeArea(child: child)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OwnerDashboardHomePage extends ConsumerWidget {
  const OwnerDashboardHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageAsync = ref.watch(currentMemorialPageProvider);
    final counts = ref.watch(_ownerContentCountsProvider);
    return pageAsync.when(
      loading: () => const LoadingView(),
      error: (error, stackTrace) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(currentMemorialPageProvider),
      ),
      data: (page) {
        if (page == null) return const SizedBox.shrink();
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppPalette.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: 'لوحة صفحتي',
                  subtitle: page.isPublished
                      ? 'صفحتك منشورة ومتاحة للزوار.'
                      : 'صفحتك خاصة حتى تنشرها.',
                  trailing: OutlinedButton.icon(
                    onPressed: () =>
                        context.go(AppConfig.memorialPagePath(page.slug)),
                    icon: const Icon(Icons.open_in_new_outlined),
                    label: const Text('معاينة'),
                  ),
                ),
                const SizedBox(height: AppPalette.spaceMd),
                Card(
                  child: ListTile(
                    leading: Icon(
                      page.isPublished
                          ? Icons.public_outlined
                          : Icons.lock_outline,
                    ),
                    title: Text(page.title),
                    subtitle: Text(
                      '${AppConfig.memorialPageLink(page.slug)}\n'
                      '${page.isPublished ? 'منشورة' : 'مسودة — لا تظهر للزوار'}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      tooltip: 'مشاركة الصفحة',
                      onPressed: () => showShareSheet(
                        context,
                        text: page.title,
                        link: AppConfig.memorialPageLink(page.slug),
                      ),
                      icon: const Icon(Icons.ios_share_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: AppPalette.spaceMd),
                counts.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stackTrace) => ErrorView(
                    error: error,
                    onRetry: () => ref.invalidate(_ownerContentCountsProvider),
                  ),
                  data: (result) => Wrap(
                    spacing: AppPalette.spaceMd,
                    runSpacing: AppPalette.spaceMd,
                    children: [
                      for (final type in ContentType.values)
                        ActionChip(
                          avatar: Icon(type.icon),
                          label: Text(
                            '${type.pluralLabelAr} (${result[type]?.total ?? 0})',
                          ),
                          onPressed: () =>
                              context.go('/dashboard/content/${type.id}'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppPalette.spaceLg),
                FilledButton.icon(
                  onPressed: () => context.go('/dashboard/settings'),
                  icon: const Icon(Icons.tune_outlined),
                  label: const Text('إعداد الصفحة والنشر'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

final _ownerContentCountsProvider =
    FutureProvider<Map<ContentType, TypeCounts>>((ref) {
      return ref.watch(contentRepositoryProvider).counts();
    }, dependencies: [contentRepositoryProvider]);

class OwnerPageSettingsPage extends ConsumerStatefulWidget {
  const OwnerPageSettingsPage({super.key});

  @override
  ConsumerState<OwnerPageSettingsPage> createState() =>
      _OwnerPageSettingsPageState();
}

class _OwnerPageSettingsPageState extends ConsumerState<OwnerPageSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _slug = TextEditingController();
  final _title = TextEditingController();
  final _deceased = TextEditingController();
  final _dedication = TextEditingController();
  final _description = TextEditingController();
  String? _loadedId;
  bool _busy = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _slug.dispose();
    _title.dispose();
    _deceased.dispose();
    _dedication.dispose();
    _description.dispose();
    super.dispose();
  }

  void _initialize(MemorialPage page) {
    if (_loadedId == page.id) return;
    _loadedId = page.id;
    _slug.text = page.slug;
    _title.text = page.title;
    _deceased.text = page.deceasedName ?? '';
    _dedication.text = page.dedicationMessage ?? '';
    _description.text = page.description ?? '';
  }

  Future<void> _save(MemorialPage page, {bool? publish}) async {
    if (!_formKey.currentState!.validate()) return;
    if (PageSlug.normalize(_slug.text) != page.slug) {
      final confirmed = await _confirmSlugChange();
      if (!confirmed || !mounted) return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _error = null;
    });
    final updated = page.copyWith(
      slug: PageSlug.normalize(_slug.text),
      title: _title.text.trim(),
      deceasedName: _deceased.text.trim(),
      dedicationMessage: _dedication.text.trim(),
      description: _description.text.trim(),
      isPublished: publish ?? page.isPublished,
    );
    try {
      await ref.read(memorialPageRepositoryProvider).update(updated);
      ref.invalidate(currentMemorialPageProvider);
      if (mounted) setState(() => _message = 'تم حفظ إعدادات الصفحة.');
    } catch (error) {
      if (mounted) setState(() => _error = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmSlugChange() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تغيير الرابط المختصر؟'),
          content: const Text(
            'قد تتوقف الروابط القديمة التي سبق مشاركتها عن العمل. '
            'لن يتم توجيهها تلقائيًا، وسيظل محتوى صفحتك وملكيتها كما هما.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تغيير الرابط'),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(currentMemorialPageProvider);
    return page.when(
      loading: () => const LoadingView(),
      error: (error, stackTrace) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(currentMemorialPageProvider),
      ),
      data: (value) {
        if (value == null) return const SizedBox.shrink();
        _initialize(value);
        final hasUnsavedChanges =
            PageSlug.normalize(_slug.text) != value.slug ||
            _title.text.trim() != value.title ||
            _deceased.text.trim() != (value.deceasedName ?? '') ||
            _dedication.text.trim() != (value.dedicationMessage ?? '') ||
            _description.text.trim() != (value.description ?? '');
        return UnsavedChangesGuard(
          isDirty: hasUnsavedChanges,
          fallbackLocation: '/dashboard',
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(AppPalette.spaceLg),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(
                      title: 'إعدادات الصفحة',
                      subtitle: 'غيّر بيانات صفحتك ورابطها وحالة النشر.',
                    ),
                    const SizedBox(height: AppPalette.spaceMd),
                    TextFormField(
                      controller: _title,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'عنوان الصفحة',
                      ),
                      validator: (text) => (text?.trim().isEmpty ?? true)
                          ? 'أدخل عنوانًا للصفحة.'
                          : null,
                    ),
                    const SizedBox(height: AppPalette.spaceSm),
                    const Text(
                      'ده الاسم اللي هيظهر للزوار أعلى صفحتك، مثال: صدقة جارية على روح والدي.',
                    ),
                    const SizedBox(height: AppPalette.spaceSm),
                    Text(
                      _title.text.trim().isEmpty
                          ? 'معاينة عنوان الصفحة'
                          : _title.text.trim(),
                      textDirection: TextDirection.rtl,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppPalette.spaceMd),
                    TextFormField(
                      controller: _slug,
                      textDirection: TextDirection.ltr,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: 'الرابط المختصر'),
                      validator: (text) => PageSlug.validate(text ?? ''),
                    ),
                    const SizedBox(height: AppPalette.spaceSm),
                    const Text(
                      'ده الاسم المميز لرابط صفحتك اللي هتشاركه مع الناس، مثال: mohamed-ahmed.',
                    ),
                    const SizedBox(height: AppPalette.spaceSm),
                    Text(
                      'يتم التحقق من توفر الرابط عند الحفظ.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppPalette.spaceXs),
                    Text(
                      AppConfig.memorialPagePath(
                        PageSlug.normalize(_slug.text),
                      ),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                    ),
                    const SizedBox(height: AppPalette.spaceMd),
                    TextFormField(
                      controller: _deceased,
                      decoration: const InputDecoration(
                        labelText: 'اسم المتوفى (اختياري)',
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
                      controller: _description,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'وصف الصفحة (اختياري)',
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: AppPalette.spaceMd),
                      Text(_message!, textAlign: TextAlign.center),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppPalette.spaceMd),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppPalette.spaceLg),
                    Wrap(
                      spacing: AppPalette.spaceMd,
                      runSpacing: AppPalette.spaceMd,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : () => _save(value),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('حفظ التغييرات'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _save(value, publish: !value.isPublished),
                          icon: Icon(
                            value.isPublished
                                ? Icons.visibility_off_outlined
                                : Icons.publish_outlined,
                          ),
                          label: Text(
                            value.isPublished ? 'إلغاء النشر' : 'نشر الصفحة',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class OwnerDashboardContentListPage extends StatelessWidget {
  const OwnerDashboardContentListPage({super.key, required this.type});

  final ContentType type;

  @override
  Widget build(BuildContext context) =>
      AdminContentListPage(type: type, basePath: '/dashboard');
}

class OwnerDashboardContentEditorPage extends StatelessWidget {
  const OwnerDashboardContentEditorPage({
    super.key,
    required this.type,
    required this.itemId,
  });

  final ContentType type;
  final String itemId;

  @override
  Widget build(BuildContext context) => AdminContentEditorPage(
    type: type,
    itemId: itemId,
    basePath: '/dashboard',
  );
}

class OwnerDashboardHomepagePage extends StatelessWidget {
  const OwnerDashboardHomepagePage({super.key});

  @override
  Widget build(BuildContext context) =>
      const AdminHomepagePage(isPersonalPage: true);
}

class OwnerDashboardAppearancePage extends StatelessWidget {
  const OwnerDashboardAppearancePage({super.key});

  @override
  Widget build(BuildContext context) =>
      const AdminAppearancePage(isPersonalPageAppearance: true);
}

class PublicMemorialPage extends ConsumerWidget {
  const PublicMemorialPage({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(publicMemorialPageProvider(slug));
    return page.when(
      loading: () => const LoadingView(),
      error: (error, stackTrace) => ErrorView(
        error: error,
        onRetry: () => ref.invalidate(publicMemorialPageProvider(slug)),
      ),
      data: (value) {
        if (value == null) {
          return const EmptyView(
            title: 'الصفحة غير متاحة',
            message: 'قد يكون الرابط غير صحيح أو أن الصفحة غير منشورة.',
            icon: Icons.link_off_outlined,
          );
        }
        final theme = ref.watch(pageThemeSettingsProvider(value.id));
        return theme.when(
          loading: () => const LoadingView(),
          error: (error, stackTrace) => ErrorView(
            error: error,
            onRetry: () => ref.invalidate(pageThemeSettingsProvider(value.id)),
          ),
          data: (settings) => Theme(
            data: settings == null
                ? Theme.of(context)
                : AppTheme.light(settings),
            child: _MemorialPageContent(page: value),
          ),
        );
      },
    );
  }
}

class _MemorialPageContent extends ConsumerStatefulWidget {
  const _MemorialPageContent({required this.page});

  final MemorialPage page;

  @override
  ConsumerState<_MemorialPageContent> createState() =>
      _MemorialPageContentState();
}

class _MemorialPageContentState extends ConsumerState<_MemorialPageContent> {
  final Map<ContentType, GlobalKey> _sectionKeys = {};

  MemorialPage get page => widget.page;

  GlobalKey _keyFor(ContentType type) => _sectionKeys.putIfAbsent(
    type,
    () => MemorialSectionNavigation.register(page.slug, type),
  );

  @override
  void dispose() {
    _unregisterSectionKeys(page.slug);
    super.dispose();
  }

  void _unregisterSectionKeys(String slug) {
    for (final entry in _sectionKeys.entries) {
      MemorialSectionNavigation.unregister(slug, entry.key, entry.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(publicMemorialLayoutProvider(page.id));
    final deceasedName = _publicDeceasedName(page.deceasedName);
    final dedicationMessage = _publicDedicationMessage(page.dedicationMessage);
    return SingleChildScrollView(
      child: PageContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppPalette.spaceLg),
            const AzkarBrandLockup(markSize: 64),
            const SizedBox(height: AppPalette.spaceMd),
            _MemorialIdentityCard(
              key: const ValueKey('first-memorial-card'),
              deceasedName: deceasedName,
              dedicationMessage: dedicationMessage,
            ),
            const SizedBox(height: AppPalette.spaceMd),
            Center(child: ShareMemorialButton(page: page)),
            const SizedBox(height: AppPalette.spaceMd),
            FutureBuilder<String>(
              future: BismillahLoader.load(),
              builder: (context, snapshot) {
                final bismillah = snapshot.data ?? '';
                if (bismillah.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppPalette.spaceMd),
                  child: Text(
                    bismillah,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      height: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                  ),
                );
              },
            ),
            if (page.description != null &&
                page.description!.trim().isNotEmpty) ...[
              const SizedBox(height: AppPalette.spaceMd),
              Text(page.description!, textAlign: TextAlign.center),
            ],
            const SizedBox(height: AppPalette.spaceLg),
            cards.when(
              loading: () => const LoadingView(),
              error: (error, stackTrace) => ErrorView(
                error: error,
                onRetry: () =>
                    ref.invalidate(publicMemorialLayoutProvider(page.id)),
              ),
              data: (items) {
                final sections = _buildMemorialSections(items);
                final visibleTypes = sections
                    .map((section) => section.type)
                    .toList(growable: false);
                _syncSectionKeys(visibleTypes);
                if (sections.isEmpty) {
                  return const EmptyView(
                    title: 'لا يوجد محتوى منشور بعد',
                    message: 'ستظهر هنا البطاقات التي يضيفها مالك الصفحة.',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final itemType in visibleTypes)
                          ActionChip(
                            avatar: Icon(itemType.icon, size: 18),
                            label: Text(itemType.pluralLabelAr),
                            onPressed: () => _scrollToSection(itemType),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppPalette.spaceLg),
                    for (final section in sections)
                      KeyedSubtree(
                        key: ValueKey('memorial-section-${section.type.id}'),
                        child: Padding(
                          key: _keyFor(section.type),
                          padding: const EdgeInsets.only(
                            bottom: AppPalette.spaceXl,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SectionHeader(
                                key: ValueKey(
                                  'memorial-section-heading-${section.type.id}',
                                ),
                                title: section.type.pluralLabelAr,
                                trailing: Icon(section.type.icon),
                              ),
                              const SizedBox(height: AppPalette.spaceMd),
                              AdaptiveCardGrid(
                                children: [
                                  for (final card in section.cards)
                                    homeCardWidget(
                                      card,
                                      key: ValueKey(card.key),
                                      pageId: page.id,
                                      pageSlug: page.slug,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    _MemorialIdentityCard(
                      key: const ValueKey('bottom-memorial-card'),
                      deceasedName: deceasedName,
                      dedicationMessage: dedicationMessage,
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

  void _syncSectionKeys(List<ContentType> visibleTypes) {
    for (final type in _sectionKeys.keys.toList()) {
      if (visibleTypes.contains(type)) continue;
      MemorialSectionNavigation.unregister(
        page.slug,
        type,
        _sectionKeys.remove(type)!,
      );
    }
    for (final type in visibleTypes) {
      _keyFor(type);
    }
  }

  void _scrollToSection(ContentType type) {
    final targetContext = _sectionKeys[type]?.currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: Duration.zero,
      curve: Curves.easeInOut,
      alignment: 0.04,
    );
  }
}

class _MemorialSection {
  const _MemorialSection(this.type, this.cards);

  final ContentType type;
  final List<HomeCard> cards;
}

List<_MemorialSection> _buildMemorialSections(List<HomeCard> cards) {
  final orderedCards =
      cards
          .where((card) => card.entry.isEnabled && card.item.isPublished)
          .toList(growable: false)
          .indexed
          .toList(growable: true)
        ..sort((left, right) {
          final byDisplayOrder = left.$2.entry.displayOrder.compareTo(
            right.$2.entry.displayOrder,
          );
          return byDisplayOrder == 0
              ? left.$1.compareTo(right.$1)
              : byDisplayOrder;
        });
  final cardsByType = <ContentType, List<HomeCard>>{};
  for (final (_, card) in orderedCards) {
    cardsByType.putIfAbsent(card.item.type, () => <HomeCard>[]).add(card);
  }
  return [
    for (final entry in cardsByType.entries)
      _MemorialSection(entry.key, List<HomeCard>.unmodifiable(entry.value)),
  ];
}

class _MemorialIdentityCard extends StatelessWidget {
  const _MemorialIdentityCard({
    super.key,
    required this.deceasedName,
    required this.dedicationMessage,
  });

  final String deceasedName;
  final String dedicationMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppPalette.radiusMd),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppPalette.spaceLg),
        child: Column(
          children: [
            Text(
              deceasedName,
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppPalette.spaceSm),
            Text(
              dedicationMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

String _publicDeceasedName(String? value) {
  final name = value?.trim() ?? '';
  return name.isEmpty ? 'اسم الفقيد/الفقيدة غير محدد' : name;
}

String _publicDedicationMessage(String? value) {
  final message = value?.trim() ?? '';
  return message.isEmpty ? 'رسالة الإهداء لم تُضف بعد.' : message;
}
