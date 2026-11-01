import 'package:azkar/core/design/azkar_brand.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/content/widgets/content_card.dart';
import 'package:azkar/features/home/domain/homepage_entry.dart';
import 'package:azkar/features/home/presentation/home_page.dart';
import 'package:azkar/features/content/providers/content_providers.dart';
import 'package:azkar/core/widgets/adaptive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('general homepage keeps branding without loading content', (
    tester,
  ) async {
    var homepageLoads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeLayoutProvider.overrideWith((ref) async {
            homepageLoads++;
            return const [];
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: HomePage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(homepageLoads, 0);
    expect(find.byType(AzkarBrandLockup), findsOneWidget);
    expect(find.byType(ContentCard), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
    expect(find.text('لم تُضف بطاقات للرئيسية بعد'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AZKAR wordmark exposes an accessible bilingual brand label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        home: const Scaffold(
          body: Center(child: AzkarBrandLockup(markSize: 64)),
        ),
      ),
    );

    expect(find.bySemanticsLabel('AZKAR | أذكار'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('public text card renders Arabic content and actions', (
    tester,
  ) async {
    const item = ContentItem(
      id: 'test-azkar',
      type: ContentType.azkar,
      title: 'ذكر',
      arabicText: 'سبحان الله وبحمده',
      isPublished: true,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: ContentCard(item: item)),
        ),
      ),
    );
    expect(find.text('سبحان الله وبحمده'), findsOneWidget);
    expect(find.text('ذكر'), findsOneWidget);
    expect(find.text('نسخ'), findsOneWidget);
    expect(find.text('مشاركة'), findsOneWidget);
  });

  test('wide homepage cards retain their span and stable key', () {
    const item = ContentItem(
      id: 'wide-quran',
      type: ContentType.quran,
      arabicText: 'text',
      isPublished: true,
    );
    const entry = HomepageEntry(
      id: 'homepage-entry',
      contentType: ContentType.quran,
      contentId: 'wide-quran',
    );
    final widget = homeCardWidget(
      const HomeCard(entry: entry, item: item, span: 2),
      key: const ValueKey('homepage-entry'),
    );

    expect(widget, isA<GridSpan>());
    expect(widget.key, const ValueKey('homepage-entry'));
  });
}
