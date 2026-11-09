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
    'presets have unique IDs and create unpublished editable drafts',
    () async {
      final items = await QuickContentLibrary.load();
      final dataset = await QuranDatasetRepository().dataset();
      expect(items, hasLength(49));
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
