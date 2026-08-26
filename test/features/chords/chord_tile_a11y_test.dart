import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/preference_store.dart';

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
    await tester.pumpWidget(
      ProviderScope(
        overrides: preferenceOverrides(),
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChordLibraryScreen(),
        ),
      ),
    );
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

    expect(
      hasTap,
      isTrue,
      reason: 'tap-to-hear must be reachable on the labelled node',
    );
  });

  /// Round E13-R20 MAJOR-1 — the detail-view entry point measured 40×40dp
  /// (ADR 0280 §Döntés 5 requires >= 48dp for a critical component). This
  /// pins the fix against `SsSemantics.minimumInteractiveDimension` so the
  /// touch target can never silently shrink back below the contract.
  testWidgets(
    'the chord-detail open button meets the 48dp minimum touch target',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: preferenceOverrides(),
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChordLibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byKey(const Key('chord-open-detail-C')));

      expect(
        size.width >= SsSemantics.minimumInteractiveDimension &&
            size.height >= SsSemantics.minimumInteractiveDimension,
        isTrue,
        reason:
            'ADR 0280 §Döntés 5 requires >= '
            '${SsSemantics.minimumInteractiveDimension}dp for a critical '
            'component; measured $size',
      );
    },
  );
}
