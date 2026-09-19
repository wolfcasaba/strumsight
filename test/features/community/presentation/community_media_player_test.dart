/// Community media player widget tests (E09-R19).
///
/// Covers the §6 acceptance matrix for the Flutter half of the
/// round. The backend half (A1 / A3 / A4 / A5 / A6 / A7) lives
/// in ``backend/tests/community/test_media_processing.py``.
///
/// Cells exercised here:
///
/// * A2 — pending media (any of ``uploaded`` / ``scanning`` /
///   ``transcoding`` / ``review``) MUST render the placeholder
///   card AND MUST NOT render the player card. The test
///   enumerates each non-ready state independently so a
///   default-fixture vakfolt cannot hide a regression.
/// * A3 (Flutter half) — rejected media MUST render the
///   rejected card and MUST NOT render the player card.
///
/// The widget is a pure presentation primitive (no provider
/// dependency) — every test injects the
/// ``processingState`` literal directly and asserts the
/// rendered face. The test harness is a minimal
/// ``MaterialApp`` wrapper so the widget's ``Theme.of(context)``
/// and ``Card`` rendering work; no providers.
///
/// R21 (audit M9): the widget's English placeholder strings moved into
/// ``lib/l10n/features/community_{en,hu}.arb``, so the harness now
/// installs the localization delegates and every assertion reads the
/// expected text from the ARB (``lookupAppLocalizations``) instead of
/// repeating the literal — a copy edit can no longer silently pass a
/// test that pins the old wording.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/features/community/presentation/widgets/community_media_player.dart';
import 'package:strumsight/l10n/app_localizations.dart';

/// The English strings the widget renders — the same source the widget
/// itself reads, so the assertions cannot drift from the ARB.
final _l10n = lookupAppLocalizations(const Locale('en'));

/// Minimal harness — the widget reads ``Theme.of(context)`` and
/// uses ``Card`` + ``CircularProgressIndicator`` / ``Icon`` / ``Text``,
/// all of which need a ``MaterialApp`` ancestor. No providers; the
/// localization delegates are installed because the widget's copy is
/// ARB-backed (R21).
Widget _harness(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  group('A2 — pending media renders placeholder, never the player', () {
    // The §6.1 fixture-default vakfolt measure-matrix: every
    // pending state is exercised independently, not only the
    // first one. A buggy implementation that maps multiple
    // states to the same literal would have been caught by
    // this parametrization.
    for (final state in <CommunityMediaProcessingState>[
      CommunityMediaProcessingState.uploaded,
      CommunityMediaProcessingState.scanning,
      CommunityMediaProcessingState.transcoding,
      CommunityMediaProcessingState.review,
    ]) {
      testWidgets('${state.name} renders placeholder, NO play affordance', (
        tester,
      ) async {
        await tester.pumpWidget(
          _harness(
            const CommunityMediaPlayer(
              processingState: CommunityMediaProcessingState.uploaded,
            ).copyWithState(state),
          ),
        );
        // pump (NOT pumpAndSettle) — the pending face carries
        // a CircularProgressIndicator that animates forever;
        // pumpAndSettle would hang the test.
        await tester.pump();

        // The "Play" button is the player-affordance — the
        // pending face MUST NOT render it (A2 invariant).
        expect(find.text(_l10n.communityMediaPlay), findsNothing);

        // The pending face renders a CircularProgressIndicator
        // — proves the placeholder branch is taken.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });
    }
  });

  testWidgets(
    'A3 — rejected media renders rejected card, NO player affordance',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          const CommunityMediaPlayer(
            processingState: CommunityMediaProcessingState.rejected,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No "Play" affordance.
      expect(find.text(_l10n.communityMediaPlay), findsNothing);
      // No CircularProgressIndicator (the pending face is
      // distinct from the rejected face — a buggy
      // implementation that reused the pending face for
      // rejected would have the spinner here).
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // The rejected-card text is rendered.
      expect(find.text(_l10n.communityMediaRejectedBody), findsOneWidget);
    },
  );

  testWidgets('deleted media renders deleted card, NO player affordance', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const CommunityMediaPlayer(
          processingState: CommunityMediaProcessingState.deleted,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(_l10n.communityMediaPlay), findsNothing);
    expect(find.text(_l10n.communityMediaDeletedBody), findsOneWidget);
  });

  testWidgets('ready media renders the player card with the Play affordance', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const CommunityMediaPlayer(
          processingState: CommunityMediaProcessingState.ready,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The "Play" button IS rendered (the ready face).
    expect(find.text(_l10n.communityMediaPlay), findsOneWidget);
    // The play icon is rendered.
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    // No spinner (the player face is distinct).
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('ready media invokes onTapPlay when the Play button is pressed', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      _harness(
        CommunityMediaPlayer(
          processingState: CommunityMediaProcessingState.ready,
          onTapPlay: () => tapped += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_l10n.communityMediaPlay));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });
}

/// Internal helper that lets the parametrized pending-state
/// tests pass an arbitrary state literal into a const-constructed
/// widget. Const constructors cannot take a variable, so the
/// helper builds a fresh instance with the right field.
extension on CommunityMediaPlayer {
  CommunityMediaPlayer copyWithState(CommunityMediaProcessingState newState) {
    return CommunityMediaPlayer(
      processingState: newState,
      title: title,
      aspectRatio: aspectRatio,
      onTapPlay: onTapPlay,
    );
  }
}
