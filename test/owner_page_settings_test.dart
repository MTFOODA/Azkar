import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/features/account/presentation/owner_dashboard_pages.dart';
import 'package:azkar/features/memorial/data/memorial_page_repository.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:azkar/core/utils/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('page settings previews title and relative public URL', (
    tester,
  ) async {
    final repository = _RecordingMemorialPageRepository();
    await tester.pumpWidget(_settingsApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('عنوان الصفحة'), findsOneWidget);
    expect(find.text('الرابط المختصر'), findsOneWidget);
    expect(find.text('صدقة جارية على روح والدي.').last, findsOneWidget);
    expect(find.text('/m/owner-page'), findsOneWidget);
    final preview = tester.widget<Text>(find.text('/m/owner-page'));
    expect(preview.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'page settings stay readable without overflow on narrow screens',
    (tester) async {
      for (final width in [320.0, 360.0, 393.0, 412.0, 600.0, 768.0, 1200.0]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          _settingsApp(_RecordingMemorialPageRepository()),
        );
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNWidgets(5));
        expect(tester.takeException(), isNull, reason: 'width: $width');
      }
      addTearDown(tester.view.resetPhysicalSize);
    },
  );

  testWidgets('editing page title updates its preview and saves', (
    tester,
  ) async {
    final repository = _RecordingMemorialPageRepository();
    await tester.pumpWidget(_settingsApp(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'صفحة جديدة');
    await tester.pump();
    expect(find.text('صفحة جديدة').last, findsOneWidget);

    final save = find.widgetWithText(FilledButton, 'حفظ التغييرات');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.updates.single.title, 'صفحة جديدة');
  });

  testWidgets('deceased name and dedication are saved in page settings', (
    tester,
  ) async {
    final repository = _RecordingMemorialPageRepository();
    await tester.pumpWidget(_settingsApp(repository));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller!
          .text,
      'اسم محفوظ سابقًا',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(3))
          .controller!
          .text,
      'رسالة محفوظة سابقًا',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'أحمد محمد');
    await tester.enterText(
      find.byType(TextFormField).at(3),
      'نسألكم الدعاء له بالرحمة.',
    );
    final save = find.widgetWithText(FilledButton, 'حفظ التغييرات');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.updates.single.deceasedName, 'أحمد محمد');
    expect(
      repository.updates.single.dedicationMessage,
      'نسألكم الدعاء له بالرحمة.',
    );
  });

  testWidgets('changing a slug requires confirmation before saving', (
    tester,
  ) async {
    final repository = _RecordingMemorialPageRepository();
    await tester.pumpWidget(_settingsApp(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), 'new-owner-page');
    final save = find.widgetWithText(FilledButton, 'حفظ التغييرات');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text('تغيير الرابط المختصر؟'), findsOneWidget);
    expect(find.textContaining('لن يتم توجيهها تلقائيًا'), findsOneWidget);
    expect(repository.updates, isEmpty);

    await tester.tap(find.text('إلغاء'));
    await tester.pumpAndSettle();
    expect(repository.updates, isEmpty);

    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تغيير الرابط'));
    await tester.pumpAndSettle();

    expect(repository.updates, hasLength(1));
    expect(repository.updates.single.slug, 'new-owner-page');
  });

  testWidgets('a duplicate slug is rejected by the repository result', (
    tester,
  ) async {
    final repository = _RecordingMemorialPageRepository(
      updateError: const AppException(
        'هذا الرابط مستخدم بالفعل. اختر رابطًا آخر.',
      ),
    );
    await tester.pumpWidget(_settingsApp(repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(1), 'taken-page');
    final save = find.widgetWithText(FilledButton, 'حفظ التغييرات');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.text('تغيير الرابط'));
    await tester.pumpAndSettle();

    expect(
      find.text('هذا الرابط مستخدم بالفعل. اختر رابطًا آخر.'),
      findsOneWidget,
    );
  });
}

Widget _settingsApp(_RecordingMemorialPageRepository repository) =>
    ProviderScope(
      overrides: [
        currentMemorialPageProvider.overrideWith((ref) async => _page),
        memorialPageRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(home: Scaffold(body: OwnerPageSettingsPage())),
    );

const _page = MemorialPage(
  id: 'page-id',
  ownerUserId: 'owner-id',
  slug: 'owner-page',
  title: 'صدقة جارية على روح والدي.',
  deceasedName: 'اسم محفوظ سابقًا',
  dedicationMessage: 'رسالة محفوظة سابقًا',
);

class _RecordingMemorialPageRepository implements MemorialPageRepository {
  _RecordingMemorialPageRepository({this.updateError});

  final Object? updateError;
  final List<MemorialPage> updates = [];

  @override
  Future<MemorialPage?> fetchMine() async => _page;

  @override
  Future<MemorialPage?> fetchPublishedBySlug(String slug) async => null;

  @override
  Future<MemorialPage> update(MemorialPage page) async {
    final error = updateError;
    if (error != null) throw error;
    updates.add(page);
    return page;
  }
}
