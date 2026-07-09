import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/chord_shape.dart';
import 'package:music_theory/features/chords/widgets/chord_diagram.dart';
import 'package:music_theory/features/learn/model/lesson.dart';
import 'package:music_theory/features/settings/providers/left_handed_provider.dart';

Future<void> pumpDiagram(WidgetTester tester, String label,
        {bool leftHanded = false}) =>
    tester.pumpWidget(ProviderScope(
      overrides: [
        if (leftHanded)
          leftHandedProvider.overrideWith(() => _FixedLeftHanded()),
      ],
      child: MaterialApp(
        home: Scaffold(body: Center(child: ChordDiagram(label: label))),
      ),
    ));

class _FixedLeftHanded extends LeftHandedController {
  @override
  bool build() => true;
}

void main() {
  group('ChordShapes', () {
    test('looks up known shapes and returns null for unknown', () {
      final c = ChordShapes.forLabel('C');
      expect(c, isNotNull);
      expect(c!.frets.length, 6);
      expect(c.frets, [-1, 3, 2, 0, 1, 0]);
      expect(ChordShapes.forLabel('Zz9'), isNull);
      expect(ChordShapes.has('Em'), isTrue);
    });

    test('every chord used by the built-in lessons has a diagram', () {
      final used = <String>{
        for (final lesson in Lessons.all)
          for (final e in lesson.events)
            if (e.chord.isNotEmpty) e.chord,
      };
      final missing = used.where((c) => !ChordShapes.has(c)).toList();
      expect(missing, isEmpty, reason: 'no diagram for: $missing');
    });
  });

  group('ChordDiagram', () {
    testWidgets('renders the label + a painted grid for a known chord',
        (tester) async {
      await pumpDiagram(tester, 'Am');
      expect(find.text('Am'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('draws nothing for a chord we have no shape for',
        (tester) async {
      await pumpDiagram(tester, 'Zz9');
      expect(find.text('Zz9'), findsNothing);
    });

    testWidgets('renders in left-handed mode without error', (tester) async {
      await pumpDiagram(tester, 'C', leftHanded: true);
      expect(find.text('C'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
