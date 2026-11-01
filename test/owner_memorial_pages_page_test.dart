import 'package:azkar/core/design/app_theme.dart';
import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/core/design/theme_settings.dart';
import 'package:azkar/features/account/presentation/owner_memorial_pages_page.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/home/data/homepage_repository.dart';
import 'package:azkar/features/home/domain/homepage_entry.dart';
import 'package:azkar/features/memorial/data/memorial_page_repository.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:azkar/features/memorial/presentation/memorial_gender_segmented_control.dart';
import 'package:azkar/features/sharing/public_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0, 1440.0]) {
    testWidgets('uses shared chrome and fits at ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _app([
          _page(id: 'draft-${width.toInt()}', slug: 'draft'),
          _page(
            id: 'published-${width.toInt()}',
            slug: 'published',
            isPublished: true,
          ),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PublicScaffold), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byKey(const ValueKey('public-header-menu')), findsOneWidget);
      expect(find.byKey(const ValueKey('public-header-theme')), findsOneWidget);
      expect(find.byKey(const ValueKey('public-header-share')), findsOneWidget);
      expect(find.byKey(const ValueKey('route-back-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('public-header-brand')), findsOneWidget);
      expect(find.text('صفحاتي وروابطي'), findsOneWidget);

      final header = tester.getRect(find.byType(AppBar));
      final back = tester.getRect(
        find.byKey(const ValueKey('route-back-button')),
      );
      expect(back.left, lessThanOrEqualTo(header.left + 12));
      for (final pageId in [
        'draft-${width.toInt()}',
        'published-${width.toInt()}',
      ]) {
        final card = tester.getRect(
          find.byKey(ValueKey('memorial-page-$pageId')),
        );
        expect(card.left, greaterThanOrEqualTo(0));
        expect(card.right, lessThanOrEqualTo(width));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'keeps two independent pages and their publication states unchanged',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repository = _RecordingMemorialPageRepository();
      final pages = [
        _page(
          id: 'draft-fixture-id',
          slug: 'draft-fixture-long-address-0123456789abcdefgh',
          deceasedName: 'Draft fixture page',
          isPublished: false,
          dedicationMessage: 'دعاء تجريبي',
        ),
        _page(
          id: 'published-fixture-id',
          slug: 'published-fixture',
          deceasedName: 'Published fixture page',
          isPublished: true,
        ),
      ];

      await tester.pumpWidget(_app(pages, repository: repository));
      await tester.pumpAndSettle();

      final draft = find.byKey(
        const ValueKey('memorial-page-draft-fixture-id'),
      );
      final published = find.byKey(
        const ValueKey('memorial-page-published-fixture-id'),
      );
      expect(draft, findsOneWidget);
      expect(published, findsOneWidget);
      expect(
        find.descendant(of: draft, matching: find.text('مسودة')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: published, matching: find.text('منشورة')),
        findsOneWidget,
      );
      expect(find.textContaining('Draft fixture page'), findsOneWidget);
      expect(find.textContaining('Published fixture page'), findsOneWidget);
      expect(
        find.textContaining('/m/draft-fixture-long-address-0123456789abcdefgh'),
        findsOneWidget,
      );
      expect(find.textContaining('/m/published-fixture'), findsOneWidget);
      expect(find.text('نسخ الصفحة'), findsNWidgets(2));
      expect(find.text('نسخ الرابط'), findsNWidgets(2));
      expect(find.text('فتح الصفحة'), findsNWidgets(2));
      expect(find.text('تعديل الصفحة'), findsNWidgets(2));
      expect(find.text('مشاركة'), findsNWidgets(2));
      expect(find.text('نشر'), findsOneWidget);
      expect(find.text('إلغاء النشر'), findsOneWidget);

      final shareButton = find.descendant(
        of: draft,
        matching: find.widgetWithText(OutlinedButton, 'مشاركة'),
      );
      await tester.ensureVisible(shareButton);
      await tester.tap(shareButton);
      await tester.pumpAndSettle();
      expect(find.text('الصفحة غير منشورة'), findsOneWidget);
      await tester.tap(find.text('حسنًا'));
      await tester.pumpAndSettle();

      final copiedTexts = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedTexts.add(
              (call.arguments as Map<Object?, Object?>)['text'] as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final copyLinkButton = find.descendant(
        of: draft,
        matching: find.widgetWithText(OutlinedButton, 'نسخ الرابط'),
      );
      await tester.ensureVisible(copyLinkButton);
      await tester.tap(copyLinkButton);
      await tester.pumpAndSettle();
      expect(find.text('تم نسخ الرابط.'), findsOneWidget);
      expect(copiedTexts, hasLength(1));
      expect(copiedTexts.single, contains('draft-fixture-long-address'));
      expect(repository.updates, isEmpty);
      expect(repository.duplicates, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('back button and system back return to the previous screen', (
    tester,
  ) async {
    await tester.pumpWidget(_app([], initialLocation: '/'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('open-dashboard-for-back-test')),
    );
    await tester.pumpAndSettle();
    expect(find.text('صفحاتي وروابطي'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('صفحة البداية للاختبار'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('open-dashboard-for-back-test')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('route-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('صفحة البداية للاختبار'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open and edit actions target the selected page', (tester) async {
    final pages = [
      _page(
        id: 'draft-id',
        slug: 'draft-slug',
        deceasedName: 'Draft fixture',
        isPublished: false,
      ),
      _page(
        id: 'published-id',
        slug: 'published-slug',
        deceasedName: 'Published fixture',
        isPublished: true,
      ),
    ];

    await tester.pumpWidget(_app(pages));
    await tester.pumpAndSettle();
    final draft = find.byKey(const ValueKey('memorial-page-draft-id'));
    final draftOpen = find.descendant(
      of: draft,
      matching: find.widgetWithText(FilledButton, 'فتح الصفحة'),
    );
    await tester.ensureVisible(draftOpen);
    await tester.tap(draftOpen);
    await tester.pumpAndSettle();
    expect(find.text('معاينة خاصة draft-id'), findsOneWidget);

    await tester.pumpWidget(_app(pages));
    await tester.pumpAndSettle();
    final published = find.byKey(const ValueKey('memorial-page-published-id'));
    final publishedOpen = find.descendant(
      of: published,
      matching: find.widgetWithText(FilledButton, 'فتح الصفحة'),
    );
    await tester.ensureVisible(publishedOpen);
    await tester.tap(publishedOpen);
    await tester.pumpAndSettle();
    expect(find.text('صفحة عامة published-slug'), findsOneWidget);

    await tester.pumpWidget(_app(pages));
    await tester.pumpAndSettle();
    final publishedEdit = find.descendant(
      of: find.byKey(const ValueKey('memorial-page-published-id')),
      matching: find.widgetWithText(OutlinedButton, 'تعديل الصفحة'),
    );
    await tester.ensureVisible(publishedEdit);
    await tester.tap(publishedEdit);
    await tester.pumpAndSettle();
    expect(find.text('selected published-id'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lists every owned memorial with its unique URL and status', (
    tester,
  ) async {
    final pages = [
      _page(
        id: 'page-a',
        slug: 'memorial-a',
        deceasedName: 'أحمد',
        deceasedGender: 'male',
        isPublished: true,
        dedicationMessage: 'دعاء أحمد',
      ),
      _page(
        id: 'page-b',
        slug: 'memorial-b',
        deceasedName: 'فاطمة',
        deceasedGender: 'female',
      ),
    ];

    await tester.pumpWidget(_app(pages));
    await tester.pumpAndSettle();

    expect(find.text('صفحاتي وروابطي'), findsOneWidget);
    expect(find.byKey(const ValueKey('create-memorial-page')), findsOneWidget);
    expect(find.textContaining('المرحوم أحمد'), findsOneWidget);
    expect(find.textContaining('المرحومة فاطمة'), findsOneWidget);
    expect(find.textContaining('/m/memorial-a'), findsOneWidget);
    expect(find.textContaining('/m/memorial-b'), findsOneWidget);
    expect(find.text('منشورة'), findsOneWidget);
    expect(find.text('مسودة — الرابط غير متاح للعامة'), findsOneWidget);
    expect(find.text('دعاء أحمد'), findsOneWidget);
    expect(find.text('الأقسام الظاهرة: 2'), findsOneWidget);
    expect(find.text('الأقسام الظاهرة: 1'), findsOneWidget);
    expect(find.textContaining('Private account display name'), findsNothing);
    expect(find.textContaining('private-owner@example.test'), findsNothing);
    expect(find.text('نسخ الصفحة'), findsNWidgets(2));
    expect(find.text('إلغاء النشر'), findsOneWidget);
    expect(find.text('نشر'), findsNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('draft pages clearly identify owner-only previews', (
    tester,
  ) async {
    await tester.pumpWidget(_app([_page(id: 'draft', slug: 'draft-page')]));
    await tester.pumpAndSettle();

    expect(
      find.text('المعاينة خاصة بك؛ لن يتمكن الزوار من فتح الرابط قبل النشر.'),
      findsOneWidget,
    );
    expect(find.text('فتح الصفحة'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('publishing one page updates only that selected page', (
    tester,
  ) async {
    final repository = _RecordingMemorialPageRepository();
    await tester.pumpWidget(
      _app([
        _page(id: 'page-a', slug: 'memorial-a'),
        _page(id: 'page-b', slug: 'memorial-b'),
      ], repository: repository),
    );
    await tester.pumpAndSettle();

    final pageB = find.byKey(const ValueKey('memorial-page-page-b'));
    final publishButton = find.descendant(
      of: pageB,
      matching: find.widgetWithText(FilledButton, 'نشر'),
    );
    await tester.ensureVisible(publishButton);
    await tester.tap(publishButton);
    await tester.pumpAndSettle();

    expect(repository.updates, hasLength(1));
    expect(repository.updates.single.id, 'page-b');
    expect(repository.updates.single.isPublished, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('copying a page calls duplication with that source page ID', (
    tester,
  ) async {
    final repository = _RecordingMemorialPageRepository();
    await tester.pumpWidget(
      _app([
        _page(
          id: 'page-a',
          slug: 'memorial-a',
          deceasedName: 'أحمد',
          deceasedGender: 'male',
          dedicationMessage: 'دعاء أحمد',
        ),
      ], repository: repository),
    );
    await tester.pumpAndSettle();

    final pageA = find.byKey(const ValueKey('memorial-page-page-a'));
    final copyPageButton = find.descendant(
      of: pageA,
      matching: find.widgetWithText(OutlinedButton, 'نسخ الصفحة'),
    );
    await tester.ensureVisible(copyPageButton);
    await tester.tap(copyPageButton);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('نسخ الصفحة'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'اسم المتوفى'),
      'محمد',
    );
    await tester.tap(find.byKey(const ValueKey('memorial-gender-female')));
    final duplicateButton = find.widgetWithText(FilledButton, 'إنشاء نسخة');
    await tester.ensureVisible(duplicateButton);
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(duplicateButton);
    await tester.pumpAndSettle();

    expect(repository.duplicatedSourcePageIds, ['page-a']);
    expect(repository.duplicates.single.deceasedName, 'محمد');
    expect(repository.duplicates.single.deceasedGender, 'female');
    expect(repository.duplicates.single.dedicationMessage, 'دعاء أحمد');
    expect(find.text('selected duplicate-page-a'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new memorial requires one of the two gender segments', (
    tester,
  ) async {
    await tester.pumpWidget(_app([]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('create-memorial-page')));
    await tester.pumpAndSettle();
    expect(find.text('المرحوم'), findsOneWidget);
    expect(find.text('المرحومة'), findsOneWidget);
    expect(
      tester
          .widget<MemorialGenderSegmentedControl>(
            find.byType(MemorialGenderSegmentedControl),
          )
          .value,
      isNull,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    final createButton = find.widgetWithText(FilledButton, 'إنشاء مسودة');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.text('اختر المرحوم أو المرحومة.'), findsOneWidget);
    expect(find.text('selected page-id'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  List<MemorialPage> pages, {
  _RecordingMemorialPageRepository? repository,
  String initialLocation = '/dashboard',
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: TextButton(
            key: const ValueKey('open-dashboard-for-back-test'),
            onPressed: () => context.push('/dashboard'),
            child: const Text('صفحة البداية للاختبار'),
          ),
        ),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) =>
            const PublicScaffold(child: OwnerMemorialPagesPage()),
      ),
      GoRoute(
        path: '/dashboard/pages/:pageId',
        builder: (context, state) =>
            Scaffold(body: Text('selected ${state.pathParameters['pageId']}')),
      ),
      GoRoute(
        path: '/dashboard/pages/:pageId/preview',
        builder: (context, state) => Scaffold(
          body: Text('معاينة خاصة ${state.pathParameters['pageId']}'),
        ),
      ),
      GoRoute(
        path: '/m/:slug',
        builder: (context, state) =>
            Scaffold(body: Text('صفحة عامة ${state.pathParameters['slug']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      ownedMemorialPagesProvider.overrideWith((ref) async => pages),
      memorialPageRepositoryProvider.overrideWithValue(
        repository ?? _RecordingMemorialPageRepository(),
      ),
      pageHomepageRepositoryProvider.overrideWith(
        (ref, pageId) => _PageHomepageRepository(pageId),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.light(ThemeSettings.defaults),
      darkTheme: AppTheme.dark(ThemeSettings.defaults),
      themeMode: ThemeMode.light,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

MemorialPage _page({
  required String id,
  required String slug,
  String deceasedName = 'اسم الصفحة',
  String? deceasedGender = 'male',
  bool isPublished = false,
  String? dedicationMessage,
}) => MemorialPage(
  id: id,
  ownerUserId: 'private-owner@example.test',
  slug: slug,
  title: 'Private account display name',
  deceasedName: deceasedName,
  deceasedGender: deceasedGender,
  dedicationMessage: dedicationMessage,
  isPublished: isPublished,
  updatedAt: DateTime.utc(2026, 1, 2),
);

class _PageHomepageRepository implements HomepageRepository {
  _PageHomepageRepository(this.pageId);

  final String pageId;

  @override
  Future<List<HomeCard>> fetchPublishedLayout() async {
    final types = pageId == 'page-a'
        ? [ContentType.azkar, ContentType.quran]
        : [ContentType.dua];
    return [
      for (var index = 0; index < types.length; index++)
        HomeCard(
          entry: HomepageEntry(
            id: '$pageId-entry-$index',
            contentType: types[index],
            contentId: '$pageId-content-$index',
          ),
          item: ContentItem(
            id: '$pageId-content-$index',
            type: types[index],
            title: '$pageId item $index',
            isPublished: true,
          ),
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingMemorialPageRepository implements MemorialPageRepository {
  final updates = <MemorialPage>[];
  final duplicates = <MemorialPage>[];
  final duplicatedSourcePageIds = <String>[];

  @override
  Future<List<MemorialPage>> fetchOwnedPages() async => const [];

  @override
  Future<MemorialPage?> fetchOwnedById(String pageId) async => null;

  @override
  Future<MemorialPage?> fetchPublishedBySlug(String slug) async => null;

  @override
  Future<MemorialPage> create({
    required String slug,
    required String deceasedName,
    required String deceasedGender,
    String? dedicationMessage,
  }) async => throw UnimplementedError();

  @override
  Future<MemorialPage> duplicate({
    required String sourcePageId,
    required String slug,
    required String deceasedName,
    required String deceasedGender,
    String? dedicationMessage,
  }) async {
    duplicatedSourcePageIds.add(sourcePageId);
    final page = MemorialPage(
      id: 'duplicate-$sourcePageId',
      ownerUserId: 'owner-id',
      slug: slug,
      title: deceasedName,
      deceasedName: deceasedName,
      deceasedGender: deceasedGender,
      dedicationMessage: dedicationMessage,
    );
    duplicates.add(page);
    return page;
  }

  @override
  Future<MemorialPage> update(MemorialPage page) async {
    updates.add(page);
    return page;
  }
}
