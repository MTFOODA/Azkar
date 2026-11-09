import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/app_palette.dart';
import '../../core/design/azkar_brand.dart';
import '../../core/config/app_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/app_logger.dart';
import '../../core/widgets/adaptive_layout.dart';
import '../../core/widgets/route_back_button.dart';
import '../content/domain/content_type.dart';
import '../memorial/presentation/memorial_section_navigation.dart';
import '../notifications/domain/local_notification.dart';
import 'share_widgets.dart';

/// The public website chrome: responsive navigation, theme switch and sharing.
class PublicScaffold extends ConsumerWidget {
  const PublicScaffold({super.key, required this.child, this.title});

  final Widget child;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminSession = ref.watch(adminSessionProvider);
    final account = ref.watch(accountSessionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAuthenticated = adminSession != null || account != null;
    final accountLocation = adminSession != null
        ? '/admin/dashboard'
        : '/dashboard';
    final location = GoRouterState.of(context).matchedLocation;
    final routeState = GoRouterState.of(context);
    final memorialSlug = routeState.pathParameters['slug'];
    final isMemorialPage = location.startsWith('/m/') && memorialSlug != null;
    final isMemorialRoot =
        isMemorialPage && routeState.pathParameters['type'] == null;
    final isHomePage = location == '/';
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 0,
        titleSpacing: 0,
        title: LayoutBuilder(
          builder: (context, constraints) {
            final showBrandName = constraints.maxWidth >= 640;
            return SizedBox(
              width: constraints.maxWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: Row(
                    children: [
                      Builder(
                        builder: (scaffoldContext) => IconButton(
                          key: const ValueKey('public-header-menu'),
                          tooltip: 'القائمة',
                          onPressed: () =>
                              Scaffold.of(scaffoldContext).openDrawer(),
                          icon: const Icon(Icons.menu),
                        ),
                      ),
                      InkWell(
                        key: const ValueKey('public-header-brand'),
                        onTap: () => context.go(
                          isMemorialPage
                              ? AppConfig.memorialPagePath(memorialSlug)
                              : '/',
                        ),
                        child: showBrandName
                            ? const AzkarBrandLockup(markSize: 36)
                            : const AzkarBrandMark(size: 42),
                      ),
                      const Spacer(),
                      IconButton(
                        key: const ValueKey('public-header-theme'),
                        tooltip: isDark ? 'الوضع النهاري' : 'الوضع الليلي',
                        onPressed: () => ref
                            .read(themeModeProvider.notifier)
                            .setMode(isDark ? ThemeMode.light : ThemeMode.dark),
                        icon: Icon(
                          isDark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                        ),
                      ),
                      const ShareWebsiteButton(
                        key: ValueKey('public-header-share'),
                        compact: true,
                      ),
                      if (isHomePage)
                        KeyedSubtree(
                          key: const ValueKey('public-header-account-action'),
                          child: IconButton(
                            tooltip: isAuthenticated
                                ? 'لوحة التحكم'
                                : 'تسجيل الدخول',
                            onPressed: () => context.go(
                              isAuthenticated ? accountLocation : '/login',
                            ),
                            icon: Icon(
                              isAuthenticated
                                  ? Icons.dashboard_outlined
                                  : Icons.login,
                            ),
                          ),
                        )
                      else if (!isMemorialRoot)
                        const RouteBackButton(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      drawer: const PublicNavigationDrawer(),
      body: SafeArea(child: child),
    );
  }
}

class PublicNavigationDrawer extends ConsumerWidget {
  const PublicNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminSession = ref.watch(adminSessionProvider);
    final account = ref.watch(accountSessionProvider);
    final accountLocation = adminSession != null
        ? '/admin/dashboard'
        : '/dashboard';
    final routeState = GoRouterState.of(context);
    final isMemorialPage =
        routeState.matchedLocation.startsWith('/m/') &&
        routeState.pathParameters['slug'] != null;
    final memorialSlug = isMemorialPage
        ? routeState.pathParameters['slug']
        : null;
    final memorialPath = memorialSlug == null
        ? null
        : AppConfig.memorialPagePath(memorialSlug);
    final categories = memorialSlug == null
        ? const <ContentType>[]
        : MemorialSectionNavigation.visibleTypes(memorialSlug);
    final showAccountTools =
        (account != null || adminSession != null) && !isMemorialPage;
    return Drawer(
      width: adaptiveDrawerWidth(context),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppPalette.spaceMd),
          children: [
            ListTile(
              title: const AzkarBrandLockup(markSize: 44),
              subtitle: const Text('صدقة جارية نسأل الله قبولها'),
              onTap: () => _go(context, memorialPath ?? '/'),
            ),
            const Divider(),
            if (showAccountTools) ...[
              ListTile(
                key: const ValueKey('navigation-prayer-times'),
                leading: const Icon(Icons.mosque_outlined),
                title: const Text('مواقيت الصلاة'),
                onTap: () => _go(context, '/worship'),
              ),
              ListTile(
                key: const ValueKey('navigation-home-widgets'),
                leading: const Icon(Icons.widgets_outlined),
                title: const Text('ويدجت الشاشة الرئيسية'),
                onTap: () => _go(context, '/worship/widget'),
              ),
              ListTile(
                key: const ValueKey('navigation-notifications'),
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('الإشعارات'),
                onTap: () => _openNotifications(context, ref),
              ),
            ],
            for (final type in categories)
              ListTile(
                leading: Icon(type.icon),
                title: Text(type.pluralLabelAr),
                onTap: () => _selectCategory(context, type, memorialSlug),
              ),
            if (categories.isNotEmpty || showAccountTools) const Divider(),
            if (showAccountTools) ...[
              ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: const Text('لوحة التحكم'),
                onTap: () => _go(context, accountLocation),
              ),
              ListTile(
                leading: const Icon(Icons.logout_outlined),
                title: const Text('تسجيل الخروج'),
                onTap: () async {
                  if (adminSession != null) {
                    await ref.read(adminSessionProvider.notifier).signOut();
                  } else {
                    await ref.read(accountSessionProvider.notifier).signOut();
                  }
                  if (context.mounted) _go(context, '/');
                },
              ),
            ],
            if (showAccountTools) const Divider(),
            ListTile(
              key: const ValueKey('about-developer'),
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(
                _isEnglish(context) ? 'About Developer' : 'عن المطوّر',
              ),
              onTap: () => _go(context, '/about-developer'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isEnglish(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'en';

  Future<void> _openNotifications(BuildContext context, WidgetRef ref) async {
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Scaffold.maybeOf(context)?.closeDrawer();
    try {
      final permission = await ref
          .read(localNotificationServiceProvider)
          .permissionState();
      if (!context.mounted) return;
      if (permission == NotificationPermissionState.granted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('الإشعارات مفعّلة بالفعل.')),
        );
      } else if (permission == NotificationPermissionState.unsupported) {
        messenger.showSnackBar(
          const SnackBar(content: Text('الإشعارات متاحة من تطبيق الموبايل.')),
        );
      } else if (router.routeInformationProvider.value.uri.path !=
          '/worship/notifications') {
        _go(context, '/worship/notifications');
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Could not open notification settings.',
        error,
        stackTrace,
      );
      if (messenger.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('تعذّر التحقق من الإشعارات. حاول مرة أخرى.'),
          ),
        );
      }
    }
  }

  void _go(BuildContext context, String location) {
    Scaffold.maybeOf(context)?.closeDrawer();
    if (location == '/') {
      context.go(location);
    } else if (GoRouterState.of(context).uri.toString() != location) {
      GoRouter.optionURLReflectsImperativeAPIs = true;
      context.push(location);
    }
  }

  void _selectCategory(
    BuildContext context,
    ContentType type,
    String? memorialSlug,
  ) {
    if (memorialSlug == null) {
      _go(context, type.route);
      return;
    }
    Navigator.of(context).maybePop();
    MemorialSectionNavigation.scrollTo(memorialSlug, type);
  }
}
