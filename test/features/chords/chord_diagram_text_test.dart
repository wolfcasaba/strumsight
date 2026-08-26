import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/chords/widgets/chord_diagram.dart';
import 'package:strumsight/features/settings/providers/left_handed_provider.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

/// A1/A2 (ADR 0282 §1/§2) — the diagram's drawing and its spoken fingering
/// derive from ONE mapping (`SsChordDiagram.readingOrder`), so a left-handed
/// mirror can never apply to only one of the two channels.

class _FixedLeftHanded extends LeftHandedController {
  @override
  bool build() => true;
}

Future<void> _pump(
  WidgetTester tester,
  String label, {
  bool leftHanded = false,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      ...preferenceOverrides(),
      if (leftHanded) leftHandedProvider.overrideWith(() => _FixedLeftHanded()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: ChordDiagram(label: label)),
      ),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group(
    'SsChordDiagram.readingOrder — the single source for drawing + text',
    () {
      test('is the identity order when unmirrored (right-handed)', () {
        expect(
          SsChordDiagram.readingOrder(const [
            -1,
            3,
            2,
            0,
            1,
            0,
          ], mirrored: false),
          [-1, 3, 2, 0, 1, 0],
        );
      });

      test('reverses the string order when mirrored — the exact mapping the '
          'painter uses to place each string', () {
        expect(
          SsChordDiagram.readingOrder(const [
            -1,
            3,
            2,
            0,
            1,
            0,
          ], mirrored: true),
          [0, 1, 0, 2, 3, -1],
        );
      });
    },
  );

  group('three-cell handedness matrix (§6.1)', () {
    testWidgets('below the threshold: right-handed keeps the standard order', (
      tester,
    ) async {
      await _pump(tester, 'C');
      expect(
        find.bySemanticsLabel('C chord diagram, fingering: x 3 2 0 1 0'),
        findsOneWidget,
      );
    });

    testWidgets(
      'at the threshold: left-handed mirrors BOTH the drawing and the '
      'spoken fingering',
      (tester) async {
        await _pump(tester, 'C', leftHanded: true);
        expect(
          find.bySemanticsLabel('C chord diagram, fingering: 0 1 0 2 3 x'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'above the threshold: a screen reader on a barre shape also follows '
      'the mirrored order',
      (tester) async {
        // C#m = x 4 6 6 5 4 low-E → high-E; mirrored reads high-E → low-E.
        await _pump(tester, 'C#m', leftHanded: true);
        expect(
          find.bySemanticsLabel('C#m chord diagram, fingering: 4 5 6 6 4 x'),
          findsOneWidget,
        );
      },
    );
  });

  testWidgets(
    'A1: the alternative is a real fingering description, not just the '
    'chord name',
    (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, 'Am');
      final label = tester
          .getSemantics(find.bySemanticsLabel(RegExp('^Am chord diagram')))
          .getSemanticsData()
          .label;
      handle.dispose();

      expect(label, isNot('Am'));
      expect(label, contains('fingering:'));
    },
  );
}
