import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/core/design/azkar_brand.dart';
import 'package:azkar/features/admin/authentication/domain/admin_auth_service.dart';
import 'package:azkar/features/sharing/about_developer_page.dart';
import 'package:azkar/features/sharing/public_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final width in [320.0, 360.0, 393.0, 412.0, 600.0, 768.0, 1024.0]) {
    testWidgets(
      'public header fits and orders controls at ${width.toInt()}px',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        final router = _createRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(_createApp(router));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        final header = tester.getRect(find.byType(AppBar));
        final loginAction = find.byKey(
          const ValueKey('public-header-account-action'),
        );
        final menuAction = find.byKey(const ValueKey('public-header-menu'));
        final shareAction = find.byKey(const ValueKey('public-header-share'));
        final brand = find.byKey(const ValueKey('public-header-brand'));
        expect(loginAction, findsOneWidget);
        expect(menuAction, findsOneWidget);
        expect(shareAction, findsOneWidget);
        expect(brand, findsOneWidget);
        expect(find.byIcon(Icons.login), findsOneWidget);
        expect(find.byIcon(Icons.menu), findsOneWidget);
        expect(find.byIcon(Icons.share_outlined), findsOneWidget);
        expect(find.byType(AzkarBrandMark), findsOneWidget);
        expect(find.text('تسجيل الدخول'), findsNothing);

        final loginRect = tester.getRect(loginAction);
        final menuRect = tester.getRect(menuAction);
        final shareRect = tester.getRect(shareAction);
        final brandRect = tester.getRect(brand);
        expect(loginRect.left, lessThanOrEqualTo(header.left + 12));
        expect(menuRect.right, greaterThanOrEqualTo(header.right - 12));
        expect(loginRect.right, lessThanOrEqualTo(shareRect.left));
        expect(shareRect.right, lessThanOrEqualTo(brandRect.left));
        expect(brandRect.right, lessThanOrEqualTo(menuRect.left));
        expect(find.byTooltip('الوضع الليلي'), findsOneWidget);
      },
    );
  }

  for (final width in [320.0, 360.0, 393.0, 412.0, 600.0, 768.0, 1024.0]) {
    testWidgets(
      'internal header replaces account action with leftmost back at ${width.toInt()}px',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);

        final router = _createRouter(initialLocation: '/azkar');
        addTearDown(router.dispose);
        await tester.pumpWidget(_createApp(router));
        await tester.pump();

        expect(find.byKey(const ValueKey('route-back-button')), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(
          find.byKey(const ValueKey('public-header-account-action')),
          findsNothing,
        );
        expect(find.byIcon(Icons.login), findsNothing);
        expect(find.byIcon(Icons.dashboard_outlined), findsNothing);
        expect(
          find.byKey(const ValueKey('public-header-share')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('public-header-theme')),
          findsOneWidget,
        );

        final header = tester.getRect(find.byType(AppBar));
        final back = tester.getRect(
          find.byKey(const ValueKey('route-back-button')),
        );
        final share = tester.getRect(
          find.byKey(const ValueKey('public-header-share')),
        );
        final theme = tester.getRect(
          find.byKey(const ValueKey('public-header-theme')),
        );
        final menu = tester.getRect(
          find.byKey(const ValueKey('public-header-menu')),
        );
        expect(back.left, lessThanOrEqualTo(header.left + 12));
        expect(back.right, lessThanOrEqualTo(share.left));
        expect(share.right, lessThanOrEqualTo(theme.left));
        expect(menu.right, greaterThanOrEqualTo(header.right - 12));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('authenticated homepage shows only the dashboard action', (
    tester,
  ) async {
    final router = _createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_createApp(router, authenticated: true));
    await tester.pump();

    expect(find.byTooltip('لوحة التحكم'), findsOneWidget);
    expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
    expect(find.byIcon(Icons.login), findsNothing);
    expect(find.byKey(const ValueKey('route-back-button')), findsNothing);
  });

  testWidgets('back pops the previous route instead of routing home', (
    tester,
  ) async {
    final router = _createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_createApp(router));
    await tester.pumpAndSettle();
    router.push('/azkar');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('route-back-button')));
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.byIcon(Icons.login), findsOneWidget);
  });

  testWidgets('a direct memorial detail route has a safe parent back target', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final router = _createRouter(initialLocation: '/m/example/azkar');
    addTearDown(router.dispose);
    await tester.pumpWidget(_createApp(router));
    await tester.pump();

    expect(find.byKey(const ValueKey('route-back-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('route-back-button')));
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/m/example');
    expect(tester.takeException(), isNull);
  });

  testWidgets('share, drawer, and login controls remain interactive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final router = _createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_createApp(router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('public-header-share')));
    await tester.pumpAndSettle();
    expect(find.text('شارك الأجر مع من تحب'), findsOneWidget);
    Navigator.of(tester.element(find.text('شارك الأجر مع من تحب'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('القائمة'));
    await tester.pumpAndSettle();
    expect(find.text('الأذكار'), findsNothing);
    expect(tester.getRect(find.byType(Drawer)).width, lessThanOrEqualTo(360));
    Navigator.of(tester.element(find.byType(Drawer))).pop();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('public-header-account-action')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('login-route')), findsOneWidget);
  });

  for (final width in [280.0, 320.0, 360.0]) {
    testWidgets(
      'public drawer fits and footer navigates at ${width.toInt()}px',
      (tester) async {
        tester.view.physicalSize = Size(width, 360);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final router = _createRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(_createApp(router));
        await tester.pump();

        await tester.tap(find.byTooltip('القائمة'));
        await tester.pumpAndSettle();
        final drawer = tester.getRect(find.byType(Drawer));
        expect(drawer.width, lessThanOrEqualTo(width * 0.88 + 1));
        expect(drawer.left, greaterThanOrEqualTo(-1));
        expect(drawer.right, lessThanOrEqualTo(width + 1));
        expect(tester.takeException(), isNull);

        final about = find.byKey(const ValueKey('about-developer'));
        await tester.scrollUntilVisible(
          about,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(about);
        await tester.pump();
        await tester.tap(about);
        await tester.pumpAndSettle();

        expect(
          router.routeInformationProvider.value.uri.path,
          '/about-developer',
        );
        expect(find.byType(AboutDeveloperPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('missing APK URL reports unavailable without opening a link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    final router = _createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_createApp(router));
    await tester.pump();
    await tester.tap(find.byTooltip('القائمة'));
    await tester.pumpAndSettle();
    final download = find.byKey(const ValueKey('android-apk-download'));
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pumpAndSettle();

    expect(
      find.text('رابط تحميل نسخة أندرويد غير متاح حالياً.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'about page shows supplied profiles and supports back navigation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 540);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final router = _createRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(_createApp(router));
      await tester.pump();
      router.push('/about-developer');
      await tester.pumpAndSettle();

      expect(find.text('Mohamed Fooda'), findsOneWidget);
      expect(find.text('Flutter Developer'), findsOneWidget);
      expect(find.text('LinkedIn'), findsOneWidget);
      expect(find.text('GitHub'), findsOneWidget);
      expect(
        AboutDeveloperPage.linkedInUrl,
        'https://www.linkedin.com/in/mohamed-fooda-08b00132a',
      );
      expect(AboutDeveloperPage.githubUrl, 'https://github.com/MTFOODA');
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('route-back-button')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
    },
  );

  testWidgets('about page renders English copy in left-to-right direction', (
    tester,
  ) async {
    final router = _createRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(_createApp(router, locale: const Locale('en')));
    await tester.pump();
    router.push('/about-developer');
    await tester.pumpAndSettle();

    expect(find.text('About the Developer'), findsOneWidget);
    expect(find.textContaining('AZKAR was developed'), findsOneWidget);
    final pageDirection = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.text('About the Developer'),
            matching: find.byType(Directionality),
          )
          .first,
    );
    expect(pageDirection.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('ar'), const Locale('en')]) {
    for (final width in [
      280.0,
      320.0,
      360.0,
      375.0,
      390.0,
      430.0,
      768.0,
      1200.0,
    ]) {
      testWidgets(
        'about social brand buttons fit ${locale.languageCode} at ${width.toInt()}px',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);

          final router = _createRouter();
          addTearDown(router.dispose);
          await tester.pumpWidget(_createApp(router, locale: locale));
          await tester.pump();
          router.push('/about-developer');
          await tester.pumpAndSettle();

          final linkedInButton = find.widgetWithText(
            OutlinedButton,
            'LinkedIn',
          );
          final githubButton = find.widgetWithText(OutlinedButton, 'GitHub');
          expect(linkedInButton, findsOneWidget);
          expect(githubButton, findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is FaIcon &&
                  widget.icon == FontAwesomeIcons.linkedinIn.data,
            ),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is FaIcon &&
                  widget.icon == FontAwesomeIcons.github.data,
            ),
            findsOneWidget,
          );
          for (final button in [linkedInButton, githubButton]) {
            final rect = tester.getRect(button);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(rect.height, greaterThanOrEqualTo(48));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

Widget _createApp(
  GoRouter router, {
  bool authenticated = false,
  Locale locale = const Locale('ar'),
}) => ProviderScope(
  overrides: [
    accountSessionProvider.overrideWith(
      authenticated
          ? _AuthenticatedAccountSession.new
          : _AnonymousAccountSession.new,
    ),
    adminSessionProvider.overrideWith(_AnonymousAdminSession.new),
    themeModeProvider.overrideWith(_FixedThemeMode.new),
  ],
  child: MaterialApp.router(
    routerConfig: router,
    locale: locale,
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) =>
        Directionality(textDirection: TextDirection.rtl, child: child!),
    theme: ThemeData(useMaterial3: true),
    darkTheme: ThemeData.dark(useMaterial3: true),
  ),
);

GoRouter _createRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) =>
          const PublicScaffold(child: SizedBox.expand()),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) =>
          const Scaffold(body: SizedBox(key: ValueKey('login-route'))),
    ),
    GoRoute(
      path: '/azkar',
      builder: (context, state) =>
          const PublicScaffold(child: SizedBox.expand()),
    ),
    GoRoute(
      path: '/about-developer',
      builder: (context, state) =>
          const PublicScaffold(child: AboutDeveloperPage()),
    ),
    GoRoute(
      path: '/m/:slug',
      builder: (context, state) =>
          const PublicScaffold(child: SizedBox.expand()),
    ),
    GoRoute(
      path: '/m/:slug/:type',
      builder: (context, state) =>
          const PublicScaffold(child: SizedBox.expand()),
    ),
  ],
);

class _AnonymousAccountSession extends AccountSessionController {
  @override
  User? build() => null;
}

class _AnonymousAdminSession extends AdminSessionController {
  @override
  AdminSession? build() => null;
}

class _AuthenticatedAccountSession extends AccountSessionController {
  @override
  User? build() => User(
    id: 'test-owner',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    email: 'owner@example.test',
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

class _FixedThemeMode extends ThemeModeNotifier {
  @override
  ThemeMode build() => ThemeMode.light;

  @override
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
  }
}
