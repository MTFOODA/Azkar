import 'package:azkar/core/widgets/route_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
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
