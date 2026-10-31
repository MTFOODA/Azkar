import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/features/account/presentation/owner_dashboard_pages.dart';
import 'package:azkar/features/admin/authentication/domain/admin_auth_service.dart';
import 'package:azkar/features/admin/dashboard/presentation/admin_shell.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final width in [320.0, 360.0, 393.0, 412.0]) {
    testWidgets('owner dashboard back is leftmost at ${width.toInt()}px', (
      tester,
    ) async {
      await _testCompactHeader(
        tester,
        width: width,
        pageBuilder: () =>
            OwnerDashboardShell(page: _page, child: const SizedBox.shrink()),
        menuKey: const ValueKey('owner-shell-menu'),
      );
    });

    testWidgets('admin dashboard back is leftmost at ${width.toInt()}px', (
      tester,
    ) async {
      await _testCompactHeader(
        tester,
        width: width,
        pageBuilder: () =>
            const AdminShell(location: '/admin/settings', child: SizedBox()),
        menuKey: const ValueKey('admin-shell-menu'),
      );
    });
  }
}

Future<void> _testCompactHeader(
  WidgetTester tester, {
  required double width,
  required Widget Function() pageBuilder,
  required ValueKey<String> menuKey,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (context, state) => pageBuilder()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountSessionProvider.overrideWith(_AnonymousAccountSession.new),
        adminSessionProvider.overrideWith(_AnonymousAdminSession.new),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final header = tester.getRect(find.byType(AppBar));
  final back = tester.getRect(find.byKey(const ValueKey('route-back-button')));
  final menu = tester.getRect(find.byKey(menuKey));
  expect(back.left, lessThanOrEqualTo(header.left + 4));
  expect(menu.right, greaterThanOrEqualTo(header.right - 4));
  expect(tester.takeException(), isNull);
}

const _page = MemorialPage(
  id: 'page-id',
  ownerUserId: 'owner-id',
  slug: 'owner-page',
  title: 'صفحة المالك',
);

class _AnonymousAccountSession extends AccountSessionController {
  @override
  User? build() => null;
}

class _AnonymousAdminSession extends AdminSessionController {
  @override
  AdminSession? build() => null;
}
