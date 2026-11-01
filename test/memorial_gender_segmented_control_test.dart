import 'package:azkar/features/memorial/presentation/memorial_gender_segmented_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'gender segments are equal, single-select, and non-deselectable',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, setState) =>
                      MemorialGenderSegmentedControl(
                        value: selected,
                        onChanged: (value) => setState(() => selected = value),
                      ),
                ),
              ),
            ),
          ),
        ),
      );

      final male = find.byKey(const ValueKey('memorial-gender-male'));
      final female = find.byKey(const ValueKey('memorial-gender-female'));
      expect(find.text('المرحوم'), findsOneWidget);
      expect(find.text('المرحومة'), findsOneWidget);
      expect(
        tester.getSize(male).width,
        closeTo(tester.getSize(female).width, 0.1),
      );

      await tester.tap(male);
      await tester.pump();
      expect(selected, 'male');
      await tester.tap(male);
      await tester.pump();
      expect(selected, 'male');
      await tester.tap(female);
      await tester.pump();
      expect(selected, 'female');
    },
  );
}
