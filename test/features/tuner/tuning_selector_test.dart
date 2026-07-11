import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/model/tuning.dart';
import 'package:music_theory/features/tuner/screens/tuner_screen.dart';
import 'package:music_theory/features/tuner/providers/tuner_providers.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

/// Round 89 — the tuner's tuning selector: picking Drop D re-labels the
/// string chips (D2 replaces E2) so the player tunes to the RIGHT targets.
Future<void> pumpTuner(WidgetTester tester, FakeTunerEngine engine) =>
    tester.pumpWidget(ProviderScope(
      overrides: [tunerEngineProvider.overrideWithValue(engine)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TunerScreen(),
      ),
    ));

/// The whole menu item, not its Text — a ListTile's title rect and its hit
/// region don't coincide, which trips tap()'s missed-hit warning.
Finder menuItem(String label) => find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is PopupMenuItem<Tuning>));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('standard tuning is the default; the selector shows it',
      (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    await pumpTuner(tester, engine);
    await tester.pumpAndSettle();

    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('E2'), findsOneWidget);
  });

  testWidgets('selecting Drop D swaps the low chip from E2 to D2',
      (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    await pumpTuner(tester, engine);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('Drop D'));
    await tester.pumpAndSettle();

    expect(find.text('D2'), findsOneWidget);
    expect(find.text('E2'), findsNothing);
  });

  testWidgets('DADGAD relabels the top strings too', (tester) async {
    final engine = FakeTunerEngine();
    addTearDown(engine.dispose);
    await pumpTuner(tester, engine);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();
    await tester.tap(menuItem('DADGAD'));
    await tester.pumpAndSettle();

    for (final label in ['D2', 'A2', 'D3', 'G3', 'A3', 'D4']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('B3'), findsNothing);
  });
}
