import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/features/account/presentation/owner_dashboard_pages.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:azkar/features/home/domain/homepage_entry.dart';
import 'package:azkar/core/design/azkar_brand.dart';
import 'package:azkar/features/sharing/public_scaffold.dart';
import 'package:azkar/features/sharing/share_widgets.dart';
import 'package:azkar/features/tasbeeh/domain/tasbeeh_counter_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:azkar/features/admin/authentication/domain/admin_auth_service.dart';

void main() {
  testWidgets('public memorial homepage shows its deceased and dedication', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, _page));
    await tester.pumpAndSettle();

    expect(find.text('أحمد محمد'), findsOneWidget);
    expect(find.text('نسألكم الدعاء له ولأسرته.'), findsOneWidget);
    expect(find.byKey(const ValueKey('first-memorial-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-memorial-card')), findsNothing);
    expect(find.byType(AzkarBrandLockup), findsOneWidget);
    expect(find.text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text(_page.title), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing deceased details use Arabic placeholders', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(router, _page.copyWith(deceasedName: '', dedicationMessage: '')),
    );
    await tester.pumpAndSettle();

    expect(find.text('اسم الفقيد/الفقيدة غير محدد'), findsOneWidget);
    expect(find.text('رسالة الإهداء لم تُضف بعد.'), findsOneWidget);
  });

  testWidgets('published sections share one page in configured order', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(
        router,
        _page,
        homepageCards: [
          _homeCard(ContentType.quran, 'quran-page', 0),
          _homeCard(ContentType.tasbeeh, 'tasbeeh-page', 1),
          _homeCard(ContentType.dua, 'dua-page', 2),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('محتوى quran-page'), findsOneWidget);
    expect(find.text('محتوى tasbeeh-page'), findsOneWidget);
    expect(find.text('محتوى dua-page'), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-memorial-card')), findsOneWidget);
    expect(find.text('أحمد محمد'), findsNWidgets(2));
    expect(find.text('نسألكم الدعاء له ولأسرته.'), findsNWidgets(2));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('memorial-section-quran')))
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('memorial-section-tasbeeh')))
            .dy,
      ),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('memorial-section-tasbeeh')))
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('memorial-section-dua')))
            .dy,
      ),
    );
    expect(find.byType(ActionChip), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('category navigation scrolls without changing the memorial URL', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(
        router,
        _page,
        homepageCards: [
          _homeCard(ContentType.azkar, 'azkar-page', 0),
          _homeCard(ContentType.quran, 'quran-page', 1),
          _homeCard(ContentType.dua, 'dua-page', 2),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'الآيات القرآنية'));
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/m/member-page');
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('memorial-section-quran')))
          .dy,
      lessThan(120),
    );
    expect(find.text('محتوى quran-page'), findsOneWidget);
    expect(find.text('محتوى azkar-page'), findsOneWidget);
    expect(find.text('محتوى dua-page'), findsOneWidget);
  });

  testWidgets('disabled and unpublished cards are hidden', (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(
        router,
        _page,
        homepageCards: [
          _homeCard(ContentType.azkar, 'visible', 0),
          _homeCard(ContentType.quran, 'disabled', 1, enabled: false),
          _homeCard(ContentType.dua, 'unpublished', 2, published: false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('محتوى visible'), findsOneWidget);
    expect(find.text('محتوى disabled'), findsNothing);
    expect(find.text('محتوى unpublished'), findsNothing);
    expect(find.byType(ActionChip), findsOneWidget);
    expect(
      find.byKey(const ValueKey('memorial-section-azkar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('memorial-section-quran')), findsNothing);
    expect(find.byKey(const ValueKey('memorial-section-dua')), findsNothing);
  });

  testWidgets('empty memorial layout displays one card and its empty state', (
    tester,
  ) async {
    final router = _router(initialLocation: '/m/member-page');
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, _page));
    await tester.pumpAndSettle();

    expect(find.text('لا يوجد محتوى منشور بعد'), findsOneWidget);
    expect(find.byKey(const ValueKey('first-memorial-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-memorial-card')), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy category URLs render the complete memorial page', (
    tester,
  ) async {
    final router = _router(initialLocation: '/m/member-page/quran');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(
        router,
        _page,
        homepageCards: [
          _homeCard(ContentType.azkar, 'azkar-page', 0),
          _homeCard(ContentType.quran, 'quran-page', 1),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/m/member-page/quran',
    );
    expect(find.byKey(const ValueKey('first-memorial-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-memorial-card')), findsOneWidget);
    expect(find.text('محتوى azkar-page'), findsOneWidget);
    expect(find.text('محتوى quran-page'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('memorial-section-azkar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('memorial-section-quran')),
      findsOneWidget,
    );
  });

  testWidgets('Tasbeeh counter state survives scrolling between sections', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(
        router,
        _page,
        homepageCards: [
          _homeCard(ContentType.tasbeeh, 'tasbeeh-page', 0),
          _homeCard(ContentType.quran, 'quran-page', 1),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('تسبيح +'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تسبيح +'));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    final quranCategory = find.widgetWithText(ActionChip, 'الآيات القرآنية');
    await tester.ensureVisible(quranCategory);
    await tester.tap(quranCategory);
    await tester.pumpAndSettle();
    final tasbeehCategory = find.widgetWithText(ActionChip, 'التسبيح');
    await tester.ensureVisible(tasbeehCategory);
    await tester.tap(tasbeehCategory);
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer categories scroll only to rendered memorial sections', (
    tester,
  ) async {
    final router = _router(scaffoldPublicPage: true);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(
        router,
        _page,
        homepageCards: [_homeCard(ContentType.azkar, 'azkar-page', 0)],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('القائمة'));
    await tester.pumpAndSettle();
    expect(find.text('الآيات القرآنية'), findsNothing);
    await tester.tap(find.text('الأذكار').last);
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/m/member-page');
    expect(
      find.byKey(const ValueKey('memorial-section-azkar')),
      findsOneWidget,
    );
  });

  testWidgets('memorial clipboard sharing includes page details and URL', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String;
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
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, _page));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ShareMemorialButton));
    await tester.pumpAndSettle();
    final copyAction = find.text('نسخ الرابط');
    await tester.ensureVisible(copyAction);
    await tester.tap(copyAction);
    await tester.pumpAndSettle();

    expect(copiedText, contains('أحمد محمد'));
    expect(copiedText, contains('نسألكم الدعاء له ولأسرته.'));
    expect(copiedText, contains('/m/member-page'));
    expect(copiedText, isNot(contains(_page.ownerUserId)));
    expect(copiedText, isNot(contains(_page.title)));
  });

  testWidgets('memorial identity and categories fit mobile widths', (
    tester,
  ) async {
    for (final width in [320.0, 360.0, 393.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      final router = _router();
      await tester.pumpWidget(_app(router, _page));
      await tester.pumpAndSettle();

      expect(find.text('أحمد محمد'), findsOneWidget, reason: 'width: $width');
      expect(tester.takeException(), isNull, reason: 'width: $width');
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
    }
    addTearDown(tester.view.resetPhysicalSize);
  });
}

const _page = MemorialPage(
  id: 'memorial-page-id',
  ownerUserId: 'private-owner-id',
  slug: 'member-page',
  title: 'حساب صاحب الصفحة',
  deceasedName: 'أحمد محمد',
  dedicationMessage: 'نسألكم الدعاء له ولأسرته.',
  isPublished: true,
);

Widget _app(
  GoRouter router,
  MemorialPage page, {
  List<HomeCard> homepageCards = const [],
}) => ProviderScope(
  overrides: [
    publicMemorialPageProvider.overrideWith((ref, slug) async {
      return slug == page.slug ? page : null;
    }),
    accountSessionProvider.overrideWith(_AnonymousAccountSession.new),
    adminSessionProvider.overrideWith(_AnonymousAdminSession.new),
    pageThemeSettingsProvider.overrideWith((ref, pageId) async => null),
    tasbeehCounterStoreProvider.overrideWithValue(_MemoryCounterStore()),
    publicMemorialLayoutProvider.overrideWith((ref, pageId) async {
      return pageId == page.id ? homepageCards : const [];
    }),
  ],
  child: MaterialApp.router(
    routerConfig: router,
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: child!),
    ),
    theme: ThemeData(useMaterial3: true),
  ),
);

HomeCard _homeCard(
  ContentType type,
  String id,
  int order, {
  bool enabled = true,
  bool published = true,
}) => HomeCard(
  entry: HomepageEntry(
    id: 'entry-$id',
    contentType: type,
    contentId: id,
    displayOrder: order,
    isEnabled: enabled,
  ),
  item: ContentItem(
    id: id,
    type: type,
    title: '${type.labelAr} $id',
    arabicText: 'محتوى $id',
    isPublished: published,
  ),
);

class _MemoryCounterStore implements TasbeehCounterStore {
  final Map<String, BigInt> _values = {};

  @override
  String get backendLabel => 'test';

  @override
  Future<void> delete(String tasbeehId, {String? pageId}) async {
    _values.remove(tasbeehId);
  }

  @override
  Future<BigInt> read(String tasbeehId, {String? pageId}) async =>
      _values[tasbeehId] ?? BigInt.zero;

  @override
  Future<Map<String, BigInt>> readMany(
    Iterable<String> tasbeehIds, {
    String? pageId,
  }) async => {for (final id in tasbeehIds) id: _values[id] ?? BigInt.zero};

  @override
  Future<void> write(String tasbeehId, BigInt value, {String? pageId}) async {
    _values[tasbeehId] = value;
  }
}

GoRouter _router({
  String initialLocation = '/m/member-page',
  bool scaffoldPublicPage = false,
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/m/:slug',
      builder: (context, state) {
        final page = PublicMemorialPage(slug: state.pathParameters['slug']!);
        return scaffoldPublicPage ? PublicScaffold(child: page) : page;
      },
    ),
    GoRoute(
      path: '/m/:slug/:type',
      builder: (context, state) {
        final page = PublicMemorialPage(
          slug: state.pathParameters['slug']!,
        );
        return scaffoldPublicPage ? PublicScaffold(child: page) : page;
      },
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
