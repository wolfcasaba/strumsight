import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/widgets/chord_diagram.dart';
import 'package:music_theory/features/settings/providers/left_handed_provider.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 88 — the chord diagram is painter-only: a screen-reader user gets
/// no fingering at all. The label speaks the standard tab notation
/// ("x 3 2 0 1 0", low-E → high-E), which is exactly how fingerings are
/// dictated between players.
Future<void> pumpDiagram(WidgetTester tester, String label,
        {bool leftHanded = false}) =>
    tester.pumpWidget(ProviderScope(
      overrides: [
        if (leftHanded)
          leftHandedProvider.overrideWith(() => _FixedLeftHanded()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: ChordDiagram(label: label))),
      ),
    ));

class _FixedLeftHanded extends LeftHandedController {
  @override
  bool build() => true;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('speaks the chord name and the tab-notation fingering',
      (tester) async {
    await pumpDiagram(tester, 'C');
    expect(find.bySemanticsLabel('C chord diagram, fingering: x 3 2 0 1 0'),
        findsOneWidget);
  });

  testWidgets('left-handed mirroring flips the DRAWING only — the spoken '
      'fingering stays low-E to high-E', (tester) async {
    await pumpDiagram(tester, 'C', leftHanded: true);
    expect(find.bySemanticsLabel('C chord diagram, fingering: x 3 2 0 1 0'),
        findsOneWidget);
  });

  testWidgets('a movable barre shape speaks its absolute frets',
      (tester) async {
    // C#m = x 4 6 6 5 4 — absolute fret numbers carry the base-fret window.
    await pumpDiagram(tester, 'C#m');
    expect(find.bySemanticsLabel('C#m chord diagram, fingering: x 4 6 6 5 4'),
        findsOneWidget);
  });
}
