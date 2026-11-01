import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/app_palette.dart';
import '../../core/design/azkar_brand.dart';
import '../../core/config/app_config.dart';
import '../../core/providers/app_providers.dart';
import '../../core/widgets/route_back_button.dart';
import '../content/domain/content_type.dart';
import '../memorial/presentation/memorial_section_navigation.dart';
import '../sharing/share_widgets.dart';

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
                      else
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
    return Drawer(
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
            for (final type in categories)
              ListTile(
                leading: Icon(type.icon),
                title: Text(type.pluralLabelAr),
                onTap: () => _selectCategory(context, type, memorialSlug),
              ),
            const Divider(),
            if (adminSession != null || account != null) ...[
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
          ],
        ),
      ),
    );
  }

  void _go(BuildContext context, String location) {
    Navigator.of(context).maybePop();
    context.go(location);
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
