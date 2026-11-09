import 'package:azkar/core/widgets/route_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'platform back on a direct shared memorial never routes to the account home',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/m/example',
        routes: [
          ShellRoute(
            builder: (context, state, child) => AppBackNavigation(child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: Text('Home')),
              ),
              GoRoute(
                path: '/m/:slug',
                builder: (_, _) => const Scaffold(body: Text('Memorial')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/m/example');
      expect(find.text('Home'), findsNothing);
    },
  );

  test('worship back targets retain the worship navigation context', () {
    expect(routeBackFallback('/worship/location'), '/worship');
    expect(routeBackFallback('/worship/notifications'), '/worship');
    expect(routeBackFallback('/worship'), '/');
  });
  test('owner Back targets retain the selected memorial context', () {
    expect(
      routeBackFallback('/dashboard/pages/page-a/settings'),
      '/dashboard/pages/page-a',
    );
    expect(
      routeBackFallback('/dashboard/pages/page-a/content/quran/item/edit'),
      '/dashboard/pages/page-a/content/quran',
    );
    expect(
      routeBackFallback('/dashboard/pages/page-a/content/quran'),
      '/dashboard/pages/page-a',
    );
    expect(routeBackFallback('/dashboard/pages/page-a'), '/dashboard');
  });

  testWidgets('dirty routes confirm before using the fallback destination', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/edit',
      routes: [
        GoRoute(
          path: '/edit',
          builder: (context, state) => UnsavedChangesGuard(
            isDirty: true,
            fallbackLocation: '/list',
            child: Scaffold(
              appBar: AppBar(
                leading: const RouteBackButton(fallbackLocation: '/list'),
              ),
              body: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('guarded-navigation'),
                  onPressed: () => navigateToLocation(context, '/list'),
                  child: const Text('قائمة المحتوى'),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/list',
          builder: (context, state) =>
              const Scaffold(body: Text('قائمة المحتوى')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('guarded-navigation')));
    await tester.pumpAndSettle();

    expect(
      find.text('لديك تغييرات غير محفوظة. هل تريد تجاهلها؟'),
      findsOneWidget,
    );
    await tester.tap(find.text('متابعة التعديل'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guarded-navigation')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('guarded-navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تجاهل التغييرات'));
    await tester.pumpAndSettle();
    expect(find.text('قائمة المحتوى'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
