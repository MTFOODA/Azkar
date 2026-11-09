import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/account_access_pages.dart';
import '../../features/account/presentation/owner_memorial_pages_page.dart';
import '../../features/account/presentation/owner_dashboard_pages.dart';
import '../../features/admin/appearance/presentation/admin_appearance_page.dart';
import '../../features/admin/content_management/presentation/admin_content_editor_page.dart';
import '../../features/admin/content_management/presentation/admin_content_list_page.dart';
import '../../features/admin/dashboard/presentation/admin_dashboard_page.dart';
import '../../features/admin/dashboard/presentation/admin_shell.dart';
import '../../features/admin/homepage/presentation/admin_homepage_page.dart';
import '../../features/admin/settings/presentation/admin_settings_page.dart';
import '../../features/content/domain/content_type.dart';
import '../../features/content/presentation/content_collection_page.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/onboarding/data/onboarding_completion_store.dart';
import '../../features/onboarding/presentation/onboarding_page.dart';
import '../../features/sharing/public_scaffold.dart';
import '../../features/sharing/about_developer_page.dart';
import '../../features/sharing/shared_content_page.dart';
import '../../features/worship/presentation/prayer_dashboard_page.dart';
import '../../features/home_widget/presentation/remembrance_widget_settings_page.dart';
import '../../features/worship/presentation/prayer_location_settings_page.dart';
import '../../features/worship/presentation/personal_tasbeeh_page.dart';
import '../../features/worship/presentation/reminder_settings_page.dart';
import '../providers/app_providers.dart';
import '../widgets/route_back_button.dart';

/// Central route table. Both dashboard areas require their verified session.
final routerProvider = Provider<GoRouter>((ref) {
  GoRouter.optionURLReflectsImperativeAPIs = true;
  final refresh = _RouterRefreshNotifier();
  ref.onDispose(refresh.dispose);
  ref.listen(adminSessionProvider, (_, _) => refresh.ping());
  ref.listen(accountSessionProvider, (_, _) => refresh.ping());

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) async {
      final session = ref.read(adminSessionProvider);
      final account = ref.read(accountSessionProvider);
      final location = state.matchedLocation;
      final isWorshipArea =
          location == '/worship' || location.startsWith('/worship/');
      final isAdminArea =
          location == '/admin' || location.startsWith('/admin/');
      final isAdminLoginAlias = location == '/admin/login';
      final isOwnerArea =
          location == '/dashboard' || location.startsWith('/dashboard/');
      final isAccountEntry = location == '/login' || location == '/register';
      final runtime = ref.read(mobileRuntimeProvider);
      if (location == '/' &&
          runtime.isNativeMobile &&
          shouldShowFirstLaunchOnboarding(
            runtime: runtime,
            location: location,
            completed: await ref
                .read(onboardingCompletionStoreProvider)
                .isCompleted(),
          )) {
        return '/onboarding';
      }
      if (isWorshipArea && account == null) {
        final destination = Uri.encodeComponent(state.uri.toString());
        return '/login?redirect=$destination';
      }
      if (isAdminLoginAlias) {
        return session != null ? '/admin/dashboard' : '/login';
      }
      if (isAdminArea && session == null) {
        return account != null ? '/dashboard' : '/login';
      }
      if (isOwnerArea && session != null) return '/admin/dashboard';
      if (isOwnerArea && account == null) return '/login';
      if (isAccountEntry && session != null) return '/admin/dashboard';
      if (isAccountEntry && account != null) return '/dashboard';
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppBackNavigation(child: child),
        routes: [
          ShellRoute(
            builder: (context, state, child) => PublicScaffold(child: child),
            routes: [
              GoRoute(path: '/', builder: (context, state) => const HomePage()),
              GoRoute(
                path: '/about-developer',
                builder: (context, state) => const AboutDeveloperPage(),
              ),
              for (final type in ContentType.values)
                GoRoute(
                  path: type.route,
                  builder: (context, state) =>
                      ContentCollectionPage(type: type),
                ),
              GoRoute(
                path: '/c/:type/:id',
                builder: (context, state) {
                  final type = ContentTypeX.fromId(
                    state.pathParameters['type'],
                  );
                  if (type == null) return const RouteNotFoundPage();
                  return SharedContentPage(
                    type: type,
                    id: state.pathParameters['id'] ?? '',
                  );
                },
              ),
              GoRoute(
                path: '/m/:slug',
                builder: (context, state) => PublicMemorialPage(
                  slug: state.pathParameters['slug'] ?? '',
                ),
              ),
              GoRoute(
                path: '/m/:slug/:type',
                builder: (context, state) {
                  if (ContentTypeX.fromId(state.pathParameters['type']) ==
                      null) {
                    return const RouteNotFoundPage();
                  }
                  return PublicMemorialPage(
                    slug: state.pathParameters['slug'] ?? '',
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => AccountLoginPage(
              redirectPath: state.uri.queryParameters['redirect'],
            ),
          ),
          GoRoute(
            path: '/register',
            builder: (context, state) => const AccountRegistrationPage(),
          ),
          GoRoute(
            path: '/forgot-password',
            redirect: (context, state) => '/reset-password',
          ),
          GoRoute(
            path: '/reset-password',
            builder: (context, state) => const PasswordResetPage(),
          ),
          GoRoute(path: '/admin/login', redirect: (context, state) => '/login'),
          GoRoute(
            path: '/onboarding',
            builder: (context, state) => const OnboardingPage(),
          ),
          GoRoute(
            path: '/worship',
            builder: (context, state) => const PrayerDashboardPage(),
          ),
          GoRoute(
            path: '/worship/reminders',
            builder: (context, state) => const ReminderSettingsPage(),
          ),
          GoRoute(
            path: '/worship/widget',
            builder: (context, state) => const RemembranceWidgetSettingsPage(),
          ),
          GoRoute(
            path: '/worship/widget/content',
            redirect: (context, state) => '/worship/widget',
          ),
          GoRoute(
            path: '/worship/location',
            builder: (context, state) => const PrayerLocationSettingsPage(),
          ),
          GoRoute(
            path: '/worship/notifications',
            builder: (context, state) => const NotificationPermissionPage(),
          ),
          GoRoute(
            path: '/worship/tasbeeh',
            builder: (context, state) => const PersonalTasbeehPage(),
          ),
          GoRoute(
            path: '/admin',
            redirect: (context, state) => '/admin/dashboard',
          ),
          GoRoute(
            path: '/admin/content',
            redirect: (context, state) => '/admin/content/azkar',
          ),
          GoRoute(
            path: '/admin/tasbeeh',
            redirect: (context, state) => '/admin/content/tasbeeh',
          ),
          GoRoute(
            path: '/admin/videos',
            redirect: (context, state) => '/admin/content/youtube',
          ),
          GoRoute(
            path: '/admin/dedications',
            redirect: (context, state) => '/admin/content/dedication',
          ),
          ShellRoute(
            builder: (context, state, child) =>
                AdminShell(location: state.matchedLocation, child: child),
            routes: [
              GoRoute(
                path: '/admin/dashboard',
                builder: (context, state) => const AdminDashboardPage(),
              ),
              GoRoute(
                path: '/admin/homepage',
                builder: (context, state) => const AdminHomepagePage(),
              ),
              GoRoute(
                path: '/admin/appearance',
                builder: (context, state) => const AdminAppearancePage(),
              ),
              GoRoute(
                path: '/admin/settings',
                builder: (context, state) => const AdminSettingsPage(),
              ),
              GoRoute(
                path: '/admin/content/:type',
                builder: (context, state) {
                  final type = ContentTypeX.fromId(
                    state.pathParameters['type'],
                  );
                  if (type == null) return const RouteNotFoundPage();
                  return AdminContentListPage(type: type);
                },
              ),
              GoRoute(
                path: '/admin/content/:type/new',
                builder: (context, state) {
                  final type = ContentTypeX.fromId(
                    state.pathParameters['type'],
                  );
                  if (type == null) return const RouteNotFoundPage();
                  return AdminContentEditorPage(type: type, itemId: 'new');
                },
              ),
              GoRoute(
                path: '/admin/content/:type/:id/edit',
                builder: (context, state) {
                  final type = ContentTypeX.fromId(
                    state.pathParameters['type'],
                  );
                  if (type == null) return const RouteNotFoundPage();
                  return AdminContentEditorPage(
                    type: type,
                    itemId: state.pathParameters['id'],
                  );
                },
              ),
            ],
          ),
          ShellRoute(
            builder: (context, state, child) => OwnerDashboardScope(
              pageId: state.pathParameters['pageId'],
              child: child,
            ),
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) =>
                    const PublicScaffold(child: OwnerMemorialPagesPage()),
              ),
              GoRoute(
                path: '/dashboard/settings',
                redirect: (context, state) => '/dashboard',
              ),
              GoRoute(
                path: '/dashboard/homepage',
                redirect: (context, state) => '/dashboard',
              ),
              GoRoute(
                path: '/dashboard/appearance',
                redirect: (context, state) => '/dashboard',
              ),
              GoRoute(
                path: '/dashboard/content/:type',
                redirect: (context, state) => '/dashboard',
              ),
              GoRoute(
                path: '/dashboard/content/:type/new',
                redirect: (context, state) => '/dashboard',
              ),
              GoRoute(
                path: '/dashboard/content/:type/:id/edit',
                redirect: (context, state) => '/dashboard',
              ),
              GoRoute(
                path: '/dashboard/pages/:pageId',
                builder: (context, state) => const OwnerDashboardHomePage(),
              ),
              GoRoute(
                path: '/dashboard/pages/:pageId/settings',
                builder: (context, state) => const OwnerPageSettingsPage(),
              ),
              GoRoute(
                path: '/dashboard/pages/:pageId/homepage',
                builder: (context, state) => const OwnerDashboardHomepagePage(),
              ),
              GoRoute(
                path: '/dashboard/pages/:pageId/appearance',
                builder: (context, state) =>
                    const OwnerDashboardAppearancePage(),
              ),
              GoRoute(
                path: '/dashboard/pages/:pageId/content/:type',
                builder: (context, state) {
                  final type = ContentTypeX.fromId(
                    state.pathParameters['type'],
                  );
                  if (type == null) return const RouteNotFoundPage();
                  return OwnerDashboardContentListPage(
                    type: type,
                    pageId: state.pathParameters['pageId'] ?? '',
                  );
                },
              ),
              GoRoute(
                path: '/dashboard/pages/:pageId/content/:type/new',
                builder: (context, state) {
                  final type = ContentTypeX.fromId(
                    state.pathParameters['type'],
                  );
                  if (type == null) return const RouteNotFoundPage();
                  return OwnerDashboardContentEditorPage(
                    type: type,
                    itemId: 'new',
                    pageId: state.pathParameters['pageId'] ?? '',
                  );
                },
              ),
              GoRoute(
                path: '/dashboard/pages/:pageId/content/:type/:id/edit',
                builder: (context, state) {
                  final type = ContentTypeX.fromId(
                    state.pathParameters['type'],
                  );
                  if (type == null) return const RouteNotFoundPage();
                  return OwnerDashboardContentEditorPage(
                    type: type,
                    itemId: state.pathParameters['id'] ?? '',
                    pageId: state.pathParameters['pageId'] ?? '',
                  );
                },
              ),
              GoRoute(
                path: '/dashboard/pages/:pageId/preview',
                builder: (context, state) => OwnerMemorialPreviewPage(
                  pageId: state.pathParameters['pageId'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        const PublicScaffold(child: RouteNotFoundPage()),
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

class RouteNotFoundPage extends StatelessWidget {
  const RouteNotFoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined, size: 52),
            const SizedBox(height: 16),
            const Text('الصفحة غير موجودة', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go('/'),
              child: const Text('العودة للرئيسية'),
            ),
          ],
        ),
      ),
    );
  }
}
