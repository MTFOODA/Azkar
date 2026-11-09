import 'package:azkar/core/design/app_theme.dart';
import 'package:azkar/core/design/theme_repository.dart';
import 'package:azkar/core/design/theme_settings.dart';
import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/core/routing/app_router.dart';
import 'package:azkar/features/account/presentation/owner_dashboard_pages.dart';
import 'package:azkar/features/content/data/content_repository.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/home/data/homepage_repository.dart';
import 'package:azkar/features/home/domain/homepage_entry.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('content back returns to page dashboard and can reopen it', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.mount(tester);
    for (var attempt = 0; attempt < 3; attempt++) {
      harness.router.go('/dashboard');
      await tester.pumpAndSettle();
      await tester.tap(find.text('تعديل الصفحة').first);
      await tester.pumpAndSettle();
      expect(find.byType(OwnerDashboardHomePage), findsOneWidget);
      await tester.tap(find.text('التسبيح (0)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('route-back-button')));
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard/pages/page-a');
      expect(find.byType(OwnerDashboardHomePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  for (final type in ContentType.values) {
    testWidgets('${type.id}: add, cancel, system back and reopen', (
      tester,
    ) async {
      final harness = _Harness();
      await harness.mount(tester);
      harness.router.go('/dashboard/pages/page-a');
      await tester.pumpAndSettle();
      await tester.tap(find.text('${type.pluralLabelAr} (0)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إضافة'));
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard/pages/page-a/content/${type.id}/new');
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard/pages/page-a/content/${type.id}');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard/pages/page-a');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard');
      await tester.tap(find.text('تعديل الصفحة').first);
      await tester.pumpAndSettle();
      expect(find.byType(OwnerDashboardHomePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'dirty editor confirms before cancel and before menu navigation',
    (tester) async {
      final harness = _Harness();
      await harness.mount(tester);
      harness.router.go('/dashboard/pages/page-a/content/tasbeeh/new');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'مسودة للتجربة');
      await tester.pump();
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('مغادرة الصفحة؟'), findsOneWidget);
      await tester.tap(find.text('متابعة التعديل'));
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard/pages/page-a/content/tasbeeh/new');
      expect(find.text('مسودة للتجربة'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('owner-shell-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('الأذكار').last);
      await tester.pumpAndSettle();
      expect(find.text('مغادرة الصفحة؟'), findsOneWidget);
      await tester.tap(find.text('تجاهل التغييرات'));
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard/pages/page-a/content/azkar');
      await tester.tap(find.byKey(const ValueKey('route-back-button')));
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard/pages/page-a');
      expect(harness.repositories['page-a']!.items, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved draft refreshes list and dashboard without leaking pages',
    (tester) async {
      final harness = _Harness();
      await harness.mount(tester);
      harness.router.go('/dashboard/pages/page-a/content/tasbeeh/new');
      await tester.pumpAndSettle();
      final body = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'نص التسبيح',
      );
      await tester.enterText(body, 'سبحان الله');
      final save = find.text('حفظ كمسودة');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard/pages/page-a/content/tasbeeh');
      expect(find.text('سبحان الله'), findsWidgets);
      await tester.tap(find.text('تعديل'));
      await tester.pumpAndSettle();
      expect(
        harness.path,
        '/dashboard/pages/page-a/content/tasbeeh/item-0/edit',
      );
      expect(find.text('سبحان الله'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('route-back-button')));
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard/pages/page-a/content/tasbeeh');
      await tester.tap(find.byKey(const ValueKey('route-back-button')));
      await tester.pumpAndSettle();
      expect(find.text('التسبيح (1)'), findsOneWidget);
      harness.router.go('/dashboard/pages/page-b/content/tasbeeh');
      await tester.pumpAndSettle();
      expect(find.text('سبحان الله'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('route-back-button')));
      await tester.pumpAndSettle();
      expect(harness.path, '/dashboard/pages/page-b');
      expect(find.text('التسبيح (0)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'owner menu sections and private preview back return to dashboard',
    (tester) async {
      final harness = _Harness();
      await harness.mount(tester);
      for (final entry in [
        ('إعدادات الصفحة', 'settings'),
        ('ترتيب الرئيسية', 'homepage'),
        ('المظهر والخطوط', 'appearance'),
        ('معاينة خاصة للمالك', 'preview'),
      ]) {
        harness.router.go('/dashboard/pages/page-a/content/tasbeeh');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('owner-shell-menu')));
        await tester.pumpAndSettle();
        final target = find.widgetWithText(ListTile, entry.$1).last;
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(harness.path, '/dashboard/pages/page-a/${entry.$2}');
        await tester.tap(find.byKey(const ValueKey('route-back-button')));
        await tester.pumpAndSettle();
        expect(harness.path, '/dashboard/pages/page-a');
        expect(find.byType(OwnerDashboardHomePage), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
}

class _Harness {
  late GoRouter router;
  final repositories = <String, _Content>{};
  final pages = [
    for (final id in ['page-a', 'page-b'])
      MemorialPage(
        id: id,
        ownerUserId: 'owner',
        slug: id,
        title: id,
        deceasedName: id,
      ),
  ];

  String get path => router.routeInformationProvider.value.uri.path;

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSessionProvider.overrideWith(_Account.new),
          adminSessionProvider.overrideWith(_Admin.new),
          mobileRuntimeProvider.overrideWithValue(
            const MobileRuntime(
              isWeb: true,
              targetPlatform: TargetPlatform.android,
            ),
          ),
          ownedMemorialPagesProvider.overrideWith((ref) async => pages),
          ownedMemorialPageProvider.overrideWith(
            (ref, id) async => pages.firstWhere((page) => page.id == id),
          ),
          pageContentRepositoryProvider.overrideWith(
            (ref, id) => repositories.putIfAbsent(id, () => _Content()),
          ),
          themeRepositoryProvider.overrideWithValue(_Theme()),
          pageThemeRepositoryProvider.overrideWith((ref, id) => _Theme()),
          pageHomepageRepositoryProvider.overrideWith((ref, id) => _Homepage()),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.light(ThemeSettings.defaults),
              builder: (context, child) => Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            );
          },
        ),
      ),
    );
    router.go('/dashboard');
    await tester.pumpAndSettle();
  }
}

class _Account extends AccountSessionController {
  @override
  User? build() => const User(
    id: 'owner',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '',
  );
}

class _Admin extends AdminSessionController {
  @override
  build() => null;
}

class _Content extends Fake implements ContentRepository {
  final items = <ContentItem>[];

  @override
  Future<ContentItem> save(ContentItem item) async {
    final saved = item.copyWith(
      id: item.id.isEmpty ? 'item-${items.length}' : item.id,
    );
    items.removeWhere((existing) => existing.id == saved.id);
    items.add(saved);
    return saved;
  }

  @override
  Future<List<ContentItem>> fetchAll(ContentType type) async =>
      items.where((item) => item.type == type).toList();

  @override
  Future<List<ContentItem>> fetchPublished(ContentType type) async =>
      items.where((item) => item.type == type && item.isPublished).toList();

  @override
  Future<ContentItem?> fetchById(ContentType type, String id) async =>
      items.where((item) => item.type == type && item.id == id).firstOrNull;

  @override
  Future<Map<ContentType, TypeCounts>> counts() async => {
    for (final type in ContentType.values)
      type: TypeCounts(
        published: items.where((i) => i.type == type && i.isPublished).length,
        drafts: items.where((i) => i.type == type && !i.isPublished).length,
      ),
  };
}

class _Theme implements ThemeRepository {
  @override
  Future<ThemeSettings?> load() async => ThemeSettings.defaults;

  @override
  Future<ThemeSettings> save(ThemeSettings settings) async => settings;
}

class _Homepage extends Fake implements HomepageRepository {
  @override
  Future<HomepageEntry> add({
    required ContentType contentType,
    required String contentId,
  }) async => HomepageEntry(
    id: contentId,
    contentType: contentType,
    contentId: contentId,
  );

  @override
  Future<List<HomepageEntry>> fetchEntries() async => [];

  @override
  Future<List<HomeCard>> fetchPublishedLayout() async => [];
}
