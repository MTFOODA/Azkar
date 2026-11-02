import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/core/routing/app_router.dart';
import 'package:azkar/features/admin/authentication/domain/admin_auth_service.dart';
import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:azkar/features/onboarding/data/onboarding_completion_store.dart';
import 'package:azkar/features/onboarding/presentation/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'onboarding completion persists in the existing local database',
    () async {
      final database = await openNewInMemoryDatabase();
      addTearDown(database.close);
      final store = OnboardingCompletionStore(
        databaseProvider: () async => database,
      );

      expect(await store.isCompleted(), isFalse);
      await store.markCompleted();
      expect(await store.isCompleted(), isTrue);
    },
  );

  test('first-launch gate only applies to an incomplete native root visit', () {
    const android = MobileRuntime(
      isWeb: false,
      targetPlatform: TargetPlatform.android,
    );
    const web = MobileRuntime(
      isWeb: true,
      targetPlatform: TargetPlatform.android,
    );
    expect(
      shouldShowFirstLaunchOnboarding(
        runtime: android,
        location: '/',
        completed: false,
      ),
      isTrue,
    );
    expect(
      shouldShowFirstLaunchOnboarding(
        runtime: android,
        location: '/m/public-page',
        completed: false,
      ),
      isFalse,
    );
    expect(
      shouldShowFirstLaunchOnboarding(
        runtime: android,
        location: '/',
        completed: true,
      ),
      isFalse,
    );
    expect(
      shouldShowFirstLaunchOnboarding(
        runtime: web,
        location: '/',
        completed: false,
      ),
      isFalse,
    );
  });

  testWidgets('native root route redirects to onboarding on first launch', (
    tester,
  ) async {
    final database = await openNewInMemoryDatabase();
    addTearDown(database.close);
    final store = OnboardingCompletionStore(
      databaseProvider: () async => database,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingCompletionStoreProvider.overrideWithValue(store),
          mobileRuntimeProvider.overrideWithValue(
            const MobileRuntime(
              isWeb: false,
              targetPlatform: TargetPlatform.android,
            ),
          ),
          accountSessionProvider.overrideWith(_AnonymousAccountSession.new),
          adminSessionProvider.overrideWith(_AnonymousAdminSession.new),
        ],
        child: const _RouterApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.text('مرحبًا بك في أذكار'), findsOneWidget);
  });

  testWidgets('onboarding next button advances with Arabic feature titles', (
    tester,
  ) async {
    final database = await openNewInMemoryDatabase();
    addTearDown(database.close);
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingPage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingCompletionStoreProvider.overrideWithValue(
            OnboardingCompletionStore(databaseProvider: () async => database),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();

    expect(find.text('صدقة جارية لمن نحب'), findsOneWidget);
  });

  for (final width in [
    280.0,
    320.0,
    360.0,
    375.0,
    390.0,
    412.0,
    430.0,
    480.0,
    600.0,
    768.0,
    1024.0,
  ]) {
    for (final textScale in [1.0, 1.3]) {
      testWidgets(
        'onboarding final actions fit at ${width.toInt()}px, ${textScale}x text',
        (tester) async {
          const height = 480.0;
          tester.view.physicalSize = Size(width, height);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          final database = await openNewInMemoryDatabase();
          addTearDown(database.close);
          final router = GoRouter(
            initialLocation: '/onboarding',
            routes: [
              GoRoute(
                path: '/onboarding',
                builder: (context, state) => const OnboardingPage(),
              ),
            ],
          );
          addTearDown(router.dispose);

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                onboardingCompletionStoreProvider.overrideWithValue(
                  OnboardingCompletionStore(
                    databaseProvider: () async => database,
                  ),
                ),
              ],
              child: MaterialApp.router(
                routerConfig: router,
                locale: const Locale('ar'),
                supportedLocales: const [Locale('ar'), Locale('en')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (context, child) => Directionality(
                  textDirection: TextDirection.rtl,
                  child: child!,
                ),
              ),
            ),
          );
          await tester.pump();

          for (var index = 0; index < 6; index++) {
            await tester.tap(find.text('التالي'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }

          for (final action in [
            'تسجيل الدخول',
            'إنشاء حساب',
            'استكشاف المحتوى',
          ]) {
            expect(find.text(action), findsOneWidget);
            expect(tester.getRect(find.text(action)).bottom, lessThan(height));
          }
        },
      );
    }
  }
}

class _AnonymousAccountSession extends AccountSessionController {
  @override
  User? build() => null;
}

class _AnonymousAdminSession extends AdminSessionController {
  @override
  AdminSession? build() => null;
}

class _RouterApp extends ConsumerWidget {
  const _RouterApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(routerConfig: ref.watch(routerProvider));
  }
}
