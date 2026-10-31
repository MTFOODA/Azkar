import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/features/account/presentation/owner_memorial_pages_page.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/home/data/homepage_repository.dart';
import 'package:azkar/features/home/domain/homepage_entry.dart';
import 'package:azkar/features/memorial/data/memorial_page_repository.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
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
    await tester.tap(
      find.descendant(
        of: pageA,
        matching: find.widgetWithText(OutlinedButton, 'نسخ الصفحة'),
      ),
    );
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
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أنثى — المرحومة').last);
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
}

Widget _app(
  List<MemorialPage> pages, {
  _RecordingMemorialPageRepository? repository,
}) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      GoRoute(
        path: '/dashboard',
        builder: (context, state) =>
            const Scaffold(body: OwnerMemorialPagesPage()),
      ),
      GoRoute(
        path: '/dashboard/pages/:pageId',
        builder: (context, state) =>
            Scaffold(body: Text('selected ${state.pathParameters['pageId']}')),
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
    child: MaterialApp.router(routerConfig: router),
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
