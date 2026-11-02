import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/app_palette.dart';
import '../../../../core/design/azkar_brand.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/widgets/adaptive_layout.dart';
import '../../../../core/widgets/route_back_button.dart';
import '../../../content/domain/content_type.dart';

class AdminDestination {
  const AdminDestination({
    required this.label,
    required this.icon,
    required this.location,
  });

  final String label;
  final IconData icon;
  final String location;
}

const adminDashboardDestination = AdminDestination(
  label: 'لوحة المعلومات',
  icon: Icons.dashboard_outlined,
  location: '/admin/dashboard',
);

final adminContentDestinations = <AdminDestination>[
  for (final type in ContentType.values)
    AdminDestination(
      label: type.pluralLabelAr,
      icon: type.icon,
      location: '/admin/content/${type.id}',
    ),
];

final adminUtilityDestinations = <AdminDestination>[
  const AdminDestination(
    label: 'إدارة الرئيسية',
    icon: Icons.home_outlined,
    location: '/admin/homepage',
  ),
  const AdminDestination(
    label: 'المظهر والخطوط',
    icon: Icons.palette_outlined,
    location: '/admin/appearance',
  ),
  const AdminDestination(
    label: 'الإعدادات',
    icon: Icons.settings_outlined,
    location: '/admin/settings',
  ),
];

List<AdminDestination> get allAdminDestinations => <AdminDestination>[
  adminDashboardDestination,
  ...adminContentDestinations,
  ...adminUtilityDestinations,
];

/// Responsive admin chrome: a navigation rail on desktop and a drawer on small
/// screens. It is only mounted after the route guard has accepted a session.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 1000;
    final isRoot = location == '/admin/dashboard';
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
                        key: const ValueKey('admin-shell-menu'),
                        tooltip: 'القائمة',
                        onPressed: () =>
                            Scaffold.of(scaffoldContext).openDrawer(),
                        icon: const Icon(Icons.menu),
                      ),
                    ),
                    const AzkarBrandLockup(markSize: 36),
                    const Spacer(),
                    _LogoutButton(session: session),
                    if (!isRoot) const RouteBackButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
        drawer: Drawer(
          width: adaptiveDrawerWidth(context),
          child: Material(child: _NavigationList(location: location)),
        ),
        body: SafeArea(child: child),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 250,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: _NavigationList(location: location, session: session),
            ),
          ),
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

class _NavigationList extends ConsumerWidget {
  const _NavigationList({required this.location, this.session});

  final String location;
  final dynamic session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppPalette.spaceMd),
        children: [
          const ListTile(
            title: AzkarBrandLockup(),
            subtitle: Text('إدارة المحتوى والمظهر'),
          ),
          if (session != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                session.email as String,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const Divider(),
          for (final destination in allAdminDestinations)
            ListTile(
              selected: _isSelected(destination),
              leading: Icon(destination.icon),
              title: Text(destination.label),
              onTap: () => _navigate(context, destination),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.public_outlined),
            title: const Text('معاينة الموقع'),
            onTap: () => navigateToLocation(context, '/', closeDrawer: true),
          ),
          if (session != null) _LogoutButton(session: session),
        ],
      ),
    );
  }

  bool _isSelected(AdminDestination destination) {
    if (destination.location == '/admin/dashboard') {
      return location == destination.location || location == '/admin';
    }
    return location.startsWith(destination.location);
  }

  void _navigate(BuildContext context, AdminDestination destination) {
    navigateToLocation(context, destination.location, closeDrawer: true);
  }
}

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton({this.session});

  final dynamic session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (session == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'تسجيل الخروج',
      onPressed: () async {
        if (!await confirmUnsavedChanges(context) || !context.mounted) return;
        await ref.read(adminSessionProvider.notifier).signOut();
        if (context.mounted) context.go('/login');
      },
      icon: const Icon(Icons.logout_outlined),
    );
  }
}

/// Consistent padding for admin pages.
class AdminPageContent extends StatelessWidget {
  const AdminPageContent({
    super.key,
    required this.child,
    this.maxWidth = 1500,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppPalette.spaceLg),
          child: child,
        ),
      ),
    );
  }
}
