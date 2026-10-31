import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/core/routing/app_router.dart';
import 'package:azkar/core/utils/app_exception.dart';
import 'package:azkar/features/account/domain/account_auth_service.dart';
import 'package:azkar/features/account/presentation/account_access_pages.dart';
import 'package:azkar/features/account/presentation/owner_dashboard_pages.dart';
import 'package:azkar/features/admin/authentication/domain/admin_auth_service.dart';
import 'package:azkar/features/admin/dashboard/presentation/admin_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('public navigation exposes one unified sign-in entry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSessionProvider.overrideWith(_AnonymousAccountSession.new),
        ],
        child: Consumer(
          builder: (context, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(routerProvider)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('دخول المشرف'), findsNothing);
    expect(find.byTooltip('تسجيل الدخول'), findsOneWidget);
    expect(find.text('إنشاء صفحة شخصية'), findsNothing);
  });

  testWidgets('dashboard redirects anonymous visitors to account login', (
    tester,
  ) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSessionProvider.overrideWith(_AnonymousAccountSession.new),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    router.go('/dashboard');
    await tester.pumpAndSettle();

    expect(find.byType(AccountLoginPage), findsOneWidget);
    expect(find.byType(OwnerDashboardHomePage), findsNothing);
  });

  testWidgets('legacy admin login URL opens the unified login screen', (
    tester,
  ) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSessionProvider.overrideWith(_AnonymousAccountSession.new),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    router.go('/admin/login');
    await tester.pumpAndSettle();

    expect(find.byType(AccountLoginPage), findsOneWidget);
    expect(find.text('دخول المشرف'), findsNothing);
  });

  testWidgets('registration stays disabled until schema verification', (
    tester,
  ) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isDemoBackendProvider.overrideWithValue(false),
          registrationUnavailableMessageProvider.overrideWithValue(
            'التسجيل مغلق حتى التحقق من المخطط.',
          ),
          accountSessionProvider.overrideWith(_AnonymousAccountSession.new),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    router.go('/register');
    await tester.pumpAndSettle();

    expect(find.byType(AccountRegistrationPage), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('التسجيل مغلق حتى التحقق من المخطط.'), findsOneWidget);
  });

  testWidgets('registration shows four fields and validates credentials', (
    tester,
  ) async {
    late GoRouter router;
    late _TestAccountSession session;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isDemoBackendProvider.overrideWithValue(false),
          isRegistrationEnabledProvider.overrideWithValue(true),
          accountSessionProvider.overrideWith(() {
            session = _TestAccountSession();
            return session;
          }),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    router.go('/register');
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.text('عنوان الصفحة'), findsNothing);
    expect(find.text('الرابط المختصر'), findsNothing);
    await tester.enterText(find.byType(TextFormField).at(0), 'Owner Name');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'owner@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'weakpass');
    await tester.enterText(find.byType(TextFormField).at(3), 'weakpass');
    final submit = find.text('إنشاء الحساب');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(
      find.text('يجب أن تحتوي كلمة المرور على حرف واحد ورقم واحد على الأقل.'),
      findsOneWidget,
    );
    expect(session.registerCalls, 0);
  });

  testWidgets('registration validates required identity and email fields', (
    tester,
  ) async {
    late GoRouter router;
    late _TestAccountSession session;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isDemoBackendProvider.overrideWithValue(false),
          isRegistrationEnabledProvider.overrideWithValue(true),
          accountSessionProvider.overrideWith(() {
            session = _TestAccountSession();
            return session;
          }),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    router.go('/register');
    await tester.pumpAndSettle();
    await tester.tap(find.text('إنشاء الحساب'));
    await tester.pumpAndSettle();

    expect(find.text('أدخل اسمك.'), findsOneWidget);
    expect(find.text('أدخل بريدًا إلكترونيًا صحيحًا.'), findsOneWidget);
    expect(find.text('استخدم 8 أحرف على الأقل.'), findsOneWidget);
    expect(session.registerCalls, 0);
  });

  testWidgets('authentication back button stays at physical left in RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSessionProvider.overrideWith(_AnonymousAccountSession.new),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(
              routerConfig: router,
              builder: (context, child) => Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            );
          },
        ),
      ),
    );
    router.go('/register');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('route-back-button')), findsOneWidget);
    final header = tester.getRect(find.byType(AppBar));
    final back = tester.getRect(
      find.byKey(const ValueKey('route-back-button')),
    );
    expect(back.left, lessThanOrEqualTo(header.left + 12));
    expect(back.width, 48);
  });

  testWidgets('public memorial routes do not require an account', (
    tester,
  ) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSessionProvider.overrideWith(_AnonymousAccountSession.new),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    router.go('/m/sample-page');
    await tester.pumpAndSettle();

    expect(find.byType(PublicMemorialPage), findsOneWidget);
    expect(find.byType(AccountLoginPage), findsNothing);
  });

  testWidgets('registration handles required email confirmation', (
    tester,
  ) async {
    late GoRouter router;
    late _TestAccountSession session;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isDemoBackendProvider.overrideWithValue(false),
          isRegistrationEnabledProvider.overrideWithValue(true),
          accountSessionProvider.overrideWith(() {
            session = _TestAccountSession(verifyImmediately: false);
            return session;
          }),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    router.go('/register');
    await tester.pumpAndSettle();

    expect(find.byType(TextFormField), findsNWidgets(4));
    await tester.enterText(find.byType(TextFormField).at(0), 'Owner Name');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'owner@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'secure-pass-123');
    await tester.enterText(find.byType(TextFormField).at(3), 'secure-pass-123');
    final submit = find.text('إنشاء الحساب');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.textContaining('راجع بريدك لتأكيده'), findsOneWidget);
    expect(find.byType(AccountRegistrationPage), findsOneWidget);
    expect(session.registration, {
      'displayName': 'Owner Name',
      'email': 'owner@example.test',
      'password': 'secure-pass-123',
    });
  });

  testWidgets(
    'a restored account session skips login and opens its dashboard',
    (tester) async {
      late GoRouter router;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isDemoBackendProvider.overrideWithValue(false),
            accountSessionProvider.overrideWith(_RestoredAccountSession.new),
            currentMemorialPageProvider.overrideWith((ref) async => null),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              router = ref.watch(routerProvider);
              return MaterialApp.router(routerConfig: router);
            },
          ),
        ),
      );
      router.go('/login');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(router.routeInformationProvider.value.uri.path, '/dashboard');
      expect(find.byType(AccountLoginPage), findsNothing);
    },
  );

  testWidgets(
    'logout clears the account through the shared authentication service',
    (tester) async {
      final service = _RecordingAccountAuthService();
      final container = ProviderContainer(
        overrides: [accountAuthServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      await container.read(accountSessionProvider.notifier).signOut();

      expect(service.signedOut, isTrue);
      expect(container.read(accountSessionProvider), isNull);
    },
  );

  testWidgets('a missing memorial page shows recovery without creating one', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMemorialPageProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(
          home: OwnerDashboardScope(child: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('لم تُجهّز الصفحة الشخصية بعد'), findsOneWidget);
    expect(
      find.textContaining('لن ينشئ التطبيق صفحة بديلة تلقائيًا'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('retry-memorial-page')));
    await tester.pumpAndSettle();
    expect(find.text('لم تُجهّز الصفحة الشخصية بعد'), findsOneWidget);
  });

  testWidgets('login failures display the supplied Arabic error', (
    tester,
  ) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isDemoBackendProvider.overrideWithValue(false),
          accountSessionProvider.overrideWith(
            () => _TestAccountSession(
              signInError: const AppException('بيانات الدخول غير صحيحة.'),
            ),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    router.go('/login');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'owner@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password1');
    await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الدخول'));
    await tester.pumpAndSettle();

    expect(find.text('بيانات الدخول غير صحيحة.'), findsOneWidget);
  });

  testWidgets('successful login opens the owner dashboard route', (
    tester,
  ) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isDemoBackendProvider.overrideWithValue(false),
          accountSessionProvider.overrideWith(_TestAccountSession.new),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    router.go('/login');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'owner@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secure-pass-123');
    await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الدخول'));
    await tester.pumpAndSettle();

    expect(find.byType(AccountLoginPage), findsNothing);
  });

  testWidgets(
    'active administrator uses the unified login and admin dashboard',
    (tester) async {
      late GoRouter router;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isDemoBackendProvider.overrideWithValue(false),
            accountSessionProvider.overrideWith(_TestAccountSession.new),
            adminSessionProvider.overrideWith(_VerifiedAdminSession.new),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              router = ref.watch(routerProvider);
              return MaterialApp.router(routerConfig: router);
            },
          ),
        ),
      );
      router.go('/login');
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'admin@example.test',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'secure-pass-123',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'تسجيل الدخول'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AdminDashboardPage), findsOneWidget);
    },
  );
}

class _AnonymousAccountSession extends AccountSessionController {
  @override
  User? build() => null;
}

class _TestAccountSession extends AccountSessionController {
  _TestAccountSession({this.verifyImmediately = true, this.signInError});

  final bool verifyImmediately;
  final Object? signInError;
  int registerCalls = 0;
  Map<String, String>? registration;

  @override
  User? build() => null;

  @override
  Future<bool> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    registerCalls++;
    registration = {
      'displayName': displayName,
      'email': email,
      'password': password,
    };
    if (verifyImmediately) state = _testUser;
    return verifyImmediately;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (signInError != null) throw signInError!;
    state = _testUser;
  }
}

class _RestoredAccountSession extends AccountSessionController {
  @override
  User? build() => _testUser;
}

class _RecordingAccountAuthService implements AccountAuthService {
  bool signedOut = false;

  @override
  Future<bool> register({
    required String displayName,
    required String email,
    required String password,
  }) async => false;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> updatePassword(String password) async {}

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

class _VerifiedAdminSession extends AdminSessionController {
  @override
  AdminSession? build() => null;

  @override
  Future<AdminSession?> refreshCurrentUser() async {
    state = const AdminSession(
      userId: 'test-admin',
      email: 'admin@example.test',
      role: 'owner',
    );
    return state;
  }
}

final _testUser = User(
  id: 'test-owner',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  email: 'owner@example.test',
  createdAt: '2026-01-01T00:00:00.000Z',
);
