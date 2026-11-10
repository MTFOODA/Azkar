import 'package:azkar/features/content/data/quick_content_library.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/content/widgets/quick_content_picker.dart';
import 'package:azkar/features/quran/data/quran_dataset_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'category lookup never returns a preset from another category',
    () async {
      for (final type in ContentType.values) {
        final items = await QuickContentLibrary.forType(type);
        if (QuickContentLibrary.supports(type)) {
          expect(items, isNotEmpty, reason: type.name);
          expect(items.every((item) => item.type == type), isTrue);
        } else {
          expect(items, isEmpty);
        }
      }
      final tasbeeh = await QuickContentLibrary.forType(ContentType.tasbeeh);
      expect(tasbeeh, hasLength(6));
      for (final preset in tasbeeh) {
        expect(preset.createDraft().type, ContentType.tasbeeh);
        expect(preset.createDraft().arabicText, isNotEmpty);
      }
    },
  );

  for (final type in QuickContentLibrary.supportedTypes) {
    testWidgets('picker search and selection stay inside ${type.id}', (
      tester,
    ) async {
      final items = await tester.runAsync(
        () => QuickContentLibrary.forType(type),
      );
      QuickContentPreset? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('open'),
                onPressed: () async {
                  selected = await showModalBottomSheet<QuickContentPreset>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => QuickContentPicker(type: type),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.text('اختيارات سريعة — ${type.pluralLabelAr}'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'سورة الفاتحة');
      await tester.pumpAndSettle();
      if (type == ContentType.quran) {
        expect(find.byType(ListTile), findsOneWidget);
      }
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
        expect(
          (tile.key! as ValueKey<String>).value,
          startsWith('quick-preset-${type.id}-'),
        );
      }
      await tester.enterText(find.byType(TextField), items!.first.title);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, items.first.title).first);
      await tester.pumpAndSettle();
      expect(selected?.type, type);
      expect(selected?.id, items.first.id);
    });
  }

  testWidgets('changing category clears old results and the search field', (
    tester,
  ) async {
    await tester.runAsync(() => QuickContentLibrary.load());
    Widget app(ContentType type) => MaterialApp(
      home: Scaffold(body: QuickContentPicker(type: type)),
    );
    await tester.pumpWidget(app(ContentType.quran));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'الكرسي');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'آية الكرسي'), findsOneWidget);
    await tester.pumpWidget(app(ContentType.tasbeeh));
    await tester.pumpAndSettle();
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    expect(find.text('آية الكرسي'), findsNothing);
    expect(find.widgetWithText(ListTile, 'التسبيح'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'chapter filter narrows a large library and resets when the content type changes',
    (tester) async {
      final items = await tester.runAsync(
        () => QuickContentLibrary.forType(ContentType.azkar),
      );
      final hadith = await tester.runAsync(
        () => QuickContentLibrary.forType(ContentType.hadith),
      );
      final category = items!
          .firstWhere(
            (item) => item.categories.any((name) => name != 'مختارات أساسية'),
          )
          .categories
          .first;
      Widget app(ContentType type) => MaterialApp(
        home: Scaffold(body: QuickContentPicker(type: type)),
      );
      await tester.pumpWidget(app(ContentType.azkar));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('quick-content-category-azkar')),
      );
      await tester.pumpAndSettle();
      final option = find.text(category).last;
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pumpAndSettle();
      final expected = items
          .where((item) => item.categories.contains(category))
          .toList();
      expect(find.text('${expected.length} اختيار متاح'), findsOneWidget);
      final titles = expected.map((item) => item.title).toSet();
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
        expect(titles, contains((tile.title! as Text).data));
      }
      await tester.pumpWidget(app(ContentType.hadith));
      await tester.pumpAndSettle();
      expect(find.text('كل الأبواب'), findsOneWidget);
      expect(find.text('${hadith!.length} اختيار متاح'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'presets have unique IDs and create unpublished editable drafts',
    () async {
      final items = await QuickContentLibrary.load();
      final dataset = await QuranDatasetRepository().dataset();
      final manifest = jsonDecode(
        await rootBundle.loadString(
          'assets/data/quick_content_library/sources.json',
        ),
      ) as Map;
      expect(items, hasLength(manifest['totalWithBase'] as int));
      expect(items.length, greaterThan(3000));
      expect(items.map((item) => item.id).toSet(), hasLength(items.length));
      for (final preset in items) {
        final draft = preset.createDraft(dataset: dataset);
        expect(draft.id, isEmpty);
        expect(draft.isPublished, isFalse);
        expect(draft.arabicText, isNotEmpty);
        expect(draft.source, isNotEmpty);
        if (preset.type == ContentType.hadith) {
          expect(draft.authenticity.isVerified, isTrue);
          expect(draft.hadithNumber, isNotEmpty);
        }
      }
    },
  );

  test('expanded assets match their recorded counts and checksums', () async {
    final manifest = jsonDecode(
      await rootBundle.loadString(
        'assets/data/quick_content_library/sources.json',
      ),
    ) as Map;
    final files = manifest['files'] as Map;
    for (final kind in ['azkar', 'dua', 'hadith']) {
      final data = await rootBundle.load(
        'assets/data/quick_content_library/$kind.json',
      );
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final content = jsonDecode(utf8.decode(bytes)) as Map;
      final records = content['items'] as List;
      expect(records, hasLength((files[kind] as Map)['items'] as int));
      expect(sha256.convert(bytes).toString(), (files[kind] as Map)['sha256']);
      for (final record in records.cast<Map>()) {
        expect(record['type'], kind);
        expect(record['text'], isNot(contains('\uFFFD')));
        expect(Uri.parse(record['url'] as String).scheme, 'https');
      }
    }
  });

  test(
    'all five Quran choices match the bundled verified verse ranges',
    () async {
      final items = await QuickContentLibrary.load();
      final dataset = await QuranDatasetRepository().dataset();
      final ranges = <String, (int, int, int)>{
        'quran-kursi': (2, 255, 255),
        'quran-fatiha': (1, 1, 7),
        'quran-ikhlas': (112, 1, 4),
        'quran-falaq': (113, 1, 5),
        'quran-nas': (114, 1, 6),
      };
      final quran = items.where((item) => item.type == ContentType.quran);
      expect(quran, hasLength(ranges.length));
      for (final preset in quran) {
        final (surah, from, to) = ranges[preset.id]!;
        final draft = preset.createDraft(dataset: dataset);
        expect(
          (draft.surahNumber, draft.ayahFrom, draft.ayahTo),
          (surah, from, to),
        );
        expect(draft.arabicText, dataset.rangeText(surah, from, to));
        final validation = dataset.validateRange(
          surahNumber: surah,
          from: from,
          to: to,
          text: draft.arabicText,
        );
        expect(validation.isValid, isTrue);
        expect(draft.validationHash, validation.fingerprint);
        expect(draft.datasetVersion, validation.datasetVersion);
      }
    },
  );

  testWidgets(
    'picker searches Arabic without diacritics and returns a choice',
    (tester) async {
      await tester.runAsync(() => QuickContentLibrary.load());
      QuickContentPreset? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: TextButton(
                  child: const Text('open'),
                  onPressed: () async {
                    selected = await showModalBottomSheet<QuickContentPreset>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) =>
                          const QuickContentPicker(type: ContentType.quran),
                    );
                  },
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'الْكُرْسِي');
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(selected?.id, 'quran-kursi');
    },
  );
}
