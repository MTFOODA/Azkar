import 'package:azkar/features/content/data/quick_content_library.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/content/widgets/quick_content_picker.dart';
import 'package:azkar/features/quran/data/quran_dataset_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(
        find.byType(ListTile),
        type == ContentType.quran ? findsOneWidget : findsNothing,
      );
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

  test(
    'presets have unique IDs and create unpublished editable drafts',
    () async {
      final items = await QuickContentLibrary.load();
      final dataset = await QuranDatasetRepository().dataset();
      expect(items, hasLength(55));
      expect(items.map((item) => item.id).toSet(), hasLength(items.length));
      for (final preset in items) {
        final draft = preset.createDraft(dataset: dataset);
        expect(draft.id, isEmpty);
        expect(draft.isPublished, isFalse);
        expect(draft.arabicText, isNotEmpty);
        expect(draft.source, isNotEmpty);
        if (preset.type == ContentType.hadith) {
          expect(draft.authenticity, HadithAuthenticity.sahih);
          expect(draft.narrator, isNotEmpty);
          expect(draft.hadithNumber, isNotEmpty);
        }
      }
    },
  );

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
