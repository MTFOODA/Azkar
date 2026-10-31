import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/features/account/presentation/owner_dashboard_pages.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:azkar/core/design/azkar_brand.dart';
import 'package:azkar/features/sharing/public_scaffold.dart';
import 'package:azkar/features/sharing/share_widgets.dart';
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
    expect(find.byType(AzkarBrandLockup), findsOneWidget);
    expect(find.text('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ'), findsOneWidget);
    expect(
      find.byType(ActionChip),
      findsNWidgets(ContentType.values.length + 1),
    );
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

  testWidgets('category navigation stays on the memorial and shows its items', (
    tester,
  ) async {
    final requestedKeys = <({String pageId, ContentType type})>[];
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _app(
        router,
        _page,
        requestedKeys: requestedKeys,
        categoryItems: [
          const ContentItem(
            id: 'published-azkar',
            type: ContentType.azkar,
            title: 'ذكر الصفحة الحاليّة',
            arabicText: 'محتوى منشور للصفحة',
            isPublished: true,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'الأذكار'));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/m/member-page/azkar',
    );
    expect(find.text('ذكر الصفحة الحاليّة'), findsOneWidget);
    expect(requestedKeys, [(pageId: _page.id, type: ContentType.azkar)]);
    expect(find.widgetWithText(ActionChip, 'الرئيسية'), findsOneWidget);
  });

  testWidgets('empty memorial categories show the Arabic empty state', (
    tester,
  ) async {
    final router = _router(initialLocation: '/m/member-page/azkar');
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, _page));
    await tester.pumpAndSettle();

    expect(find.text('لا يوجد الأذكار منشور'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'الرئيسية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('drawer categories preserve the current memorial slug', (
    tester,
  ) async {
    final router = _router(scaffoldPublicPage: true);
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, _page));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('القائمة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الأذكار').last);
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/m/member-page/azkar',
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
  title: 'عنوان الصفحة',
  deceasedName: 'أحمد محمد',
  dedicationMessage: 'نسألكم الدعاء له ولأسرته.',
  isPublished: true,
);

Widget _app(
  GoRouter router,
  MemorialPage page, {
  List<ContentItem> categoryItems = const [],
  List<({String pageId, ContentType type})>? requestedKeys,
}) => ProviderScope(
  overrides: [
    publicMemorialPageProvider.overrideWith((ref, slug) async {
      return slug == page.slug ? page : null;
    }),
    accountSessionProvider.overrideWith(_AnonymousAccountSession.new),
    adminSessionProvider.overrideWith(_AnonymousAdminSession.new),
    pageThemeSettingsProvider.overrideWith((ref, pageId) async => null),
    publicMemorialLayoutProvider.overrideWith((ref, pageId) async => const []),
    pagePublishedContentProvider.overrideWith((ref, key) async {
      requestedKeys?.add(key);
      return key.pageId == page.id ? categoryItems : const [];
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
          type: ContentTypeX.fromId(state.pathParameters['type'])!,
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
