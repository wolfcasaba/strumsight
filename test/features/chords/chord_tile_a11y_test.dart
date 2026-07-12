import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/screens/chord_library_screen.dart';
import 'package:music_theory/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 131 — the r130 B1 finding (a label without a tap action is a
/// half-broken a11y control) prompted a sweep of every excludeSemantics
/// wrapper. The chord-library tile is the one interactive case left: its
/// InkWell (tap-to-hear, r90) is the ANCESTOR of the ChordDiagram's labelled
/// Semantics, so the label and the tap action can land on SEPARATE, unmerged
/// nodes — a screen reader would then read the fingering but not offer to
/// activate it. This test pins that the tile exposes BOTH on one node.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a chord-library tile is one node with BOTH the fingering label '
      'and a tap action', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ChordLibraryScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // The C tile: its accessible node must speak the fingering AND be
    // activatable (tap = play the pad) in the SAME node. Capture the fact
    // BEFORE any assertion so the handle is always disposed (a thrown
    // expect would otherwise leak it and mask the real failure).
    final data = tester
        .getSemantics(find.bySemanticsLabel(RegExp(r'^C chord diagram')).first)
        .getSemanticsData();
    final hasTap = data.hasAction(SemanticsAction.tap);
    handle.dispose();

    expect(hasTap, isTrue,
        reason: 'tap-to-hear must be reachable on the labelled node');
  });
}
