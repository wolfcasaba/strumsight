// E12-R20 accessibility/localization RELEASE AUDIT (brief §1/§3, A3/A4):
// walks the SAME core flow as `release_flow_text_scale_test.dart` — boot →
// onboarding skip → practice hub → setup → session → result — and asserts
// screen-reader reachability and focus order using the ACTUAL simulated
// accessibility traversal (`tester.semantics.simulatedAccessibilityTraversal`),
// never a single `find.bySemanticsLabel` presence check
// (§0.0.A/R9/docs/LESSONS.md L460): a presence-only guard cannot tell
// whether an element is reachable in a sensible order, only that a label
// exists somewhere in the tree.
//
// This round audits; it does not fix (brief §0.0/§5.2). Any missing label
// or scrambled order this file finds is a LELET recorded in
// `docs/accessibility/known-exceptions.yaml` and `release-audit.md` — never
// patched in `lib/**` (this round's tilos zona, brief §4).
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart'
    show PracticeResultFallback;
import 'package:strumsight/l10n/app_localizations.dart';

import '../support/e2e_harness.dart';

/// §0.0.A/R5: the same mandatory phone viewport as the text-scale file —
/// the default flutter_test 800x600 is not evidence of anything here either.
const _phoneViewport = Size(412, 915);

Future<void> _setPhoneViewport(WidgetTester tester) async {
  tester.view.physicalSize = _phoneViewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Drives the session from `running` to `completed` and asserts the
/// `NavigateToResult` effect lands the flow on the result route — shared
/// by both locale cells in `main()` below.
///
/// MÉRT (2026-09-01): the router's `AppRoutes.practiceResult` route always
/// builds `PracticeResultFallback`, never `PracticeResultScreen` directly
/// (`lib/app/routing/app_router.dart:346-348`) — the detailed result view
/// is reached only via a `Navigator.push` with an explicit
/// `PracticeHistoryEntry`, not through this round-trip. This is the
/// documented, intentional landing state (practice_result_screen.dart:
/// 765-775), not a defect.
Future<void> _finishToResult(
  WidgetTester tester,
  E2eSession session,
  AppLocalizations l10n,
) async {
  await tester.tap(
    find.widgetWithText(ElevatedButton, l10n.practiceSessionFinish),
  );
  await tester.pump();
  await _driveSessionUntil(
    tester,
    session,
    (status) => status == PracticeSessionStatus.completed,
  );
  await tester.pumpAndSettle();
  expect(find.byType(PracticeResultFallback), findsOneWidget);
}

Future<void> _driveSessionUntil(
  WidgetTester tester,
  E2eSession session,
  bool Function(PracticeSessionStatus status) reached, {
  int maxTicks = 100,
}) async {
  for (var i = 0; i < maxTicks; i++) {
    final host = session.container.read(practiceSessionHostProvider);
    if (host != null && reached(host.state.status)) return;
    await session.clock.tick(tester, const Duration(milliseconds: 200));
  }
  fail(
    'fake_clock ticked $maxTicks times without the practice session '
    'reaching the expected status',
  );
}

/// A3 helper: every node the simulated traversal actually reaches that
/// carries a tap action must expose a non-empty label — the traversal
/// itself is the reachability proof (§0.0.A/R9), not a separate finder call.
///
/// [knownUnlabeledCount] tolerates an EXACT, already-measured, dated count
/// of unlabeled-but-tappable nodes on [screen] (mirrored in
/// `docs/accessibility/known-exceptions.yaml`) — `lib/**` is this round's
/// tilos zona (brief §4), so a real `lib/**` defect this audit finds cannot
/// be fixed here. The count is exact, not a ceiling: if it no longer
/// matches (fixed, or a NEW unlabeled node appeared), this fails loudly
/// instead of silently tolerating a changed shape — the same "can only
/// shrink" discipline as `_excludedByKey` in
/// `e13_r36_variant_matrix_test.dart`.
void _expectEveryTappableNodeIsLabeled(
  Iterable<SemanticsNode> traversal, {
  required String screen,
  int knownUnlabeledCount = 0,
  bool requireAtLeastOneTappable = true,
}) {
  final tappable = traversal
      .where((node) => node.getSemanticsData().hasAction(SemanticsAction.tap))
      .toList();
  if (requireAtLeastOneTappable) {
    expect(
      tappable,
      isNotEmpty,
      reason: '$screen: the traversal found no tappable node at all',
    );
  }
  final unlabeled = tappable
      .where((node) => node.getSemanticsData().label.isEmpty)
      .toList();
  expect(
    unlabeled.length,
    knownUnlabeledCount,
    reason:
        '$screen: expected exactly $knownUnlabeledCount known-unlabeled '
        'tappable node(s) per docs/accessibility/known-exceptions.yaml, '
        'found ${unlabeled.length}: a screen-reader user landing on one of '
        'these hears nothing ($unlabeled)',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final localeCode in ['en', 'hu']) {
    testWidgets(
      'core flow ($localeCode): every screen up to the running session '
      'exposes a reachable, labeled traversal (A3)',
      (tester) async {
        await _setPhoneViewport(tester);
        final l10n = lookupAppLocalizations(Locale(localeCode));
        final store = InMemoryKeyValueStore({'ss.settings.locale': localeCode});
        final handle = tester.ensureSemantics();
        final session = await bootE2eApp(
          tester,
          store: store,
          onboardingSeen: false,
        );

        _expectEveryTappableNodeIsLabeled(
          tester.semantics.simulatedAccessibilityTraversal(),
          screen: 'onboarding ($localeCode)',
        );

        await tester.tap(find.text(l10n.onboardSkip));
        await tester.pumpAndSettle();
        session.router.go(AppRoutes.practiceHub);
        await tester.pumpAndSettle();

        _expectEveryTappableNodeIsLabeled(
          tester.semantics.simulatedAccessibilityTraversal(),
          screen: 'practice hub ($localeCode)',
        );

        await tester.tap(find.text(l10n.practiceHubQuickStartLabel));
        await tester.pumpAndSettle();

        // MÉRT (2026-09-01): `SsSwitchRow` (lib/core/design_system/
        // components/inputs/ss_switch_row.dart) splits into TWO adjacent
        // traversal stops instead of one — the outer `InkWell`'s own
        // tap-semantics node (the FULL-row, 48dp-tall touch target §5.4
        // requires) carries NO label, while the inner `MergeSemantics` node
        // carries the label ("Metronome"/"Accent on count 1"/"Show chord
        // hint") but no tap action. A screen-reader user landing on the
        // silent outer node hears nothing before double-tapping it — a real
        // `lib/**` defect (LELET, docs/accessibility/known-exceptions.yaml)
        // this round cannot fix (brief §4). Exactly 3 — the Metronome,
        // Accent and Chord-hint switches this screen renders (chord hint is
        // absent only for `rhythmOnly`, not this flow's `strumPattern`
        // fixture) — in BOTH locales.
        _expectEveryTappableNodeIsLabeled(
          tester.semantics.simulatedAccessibilityTraversal(),
          screen: 'practice setup ($localeCode)',
          knownUnlabeledCount: 3,
        );

        final setupStart = find.widgetWithText(
          FilledButton,
          l10n.practiceSetupStart,
        );
        // Two steps, not one: the Setup form is a lazily-built `ListView`,
        // so the button does not exist in the element tree until
        // `scrollUntilVisible` scrolls far enough for the sliver to build
        // it; `ensureVisible` then centers it precisely before the tap —
        // see the identical comment in `release_flow_text_scale_test.dart`.
        await tester.scrollUntilVisible(
          setupStart,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(setupStart);
        await tester.pumpAndSettle();
        await tester.tap(setupStart);
        await tester.pumpAndSettle();

        await tester.tap(
          find.widgetWithText(ElevatedButton, l10n.practiceSessionStart),
        );
        await tester.pump();
        await _driveSessionUntil(
          tester,
          session,
          (status) => status == PracticeSessionStatus.running,
        );

        final runningTraversal = tester.semantics
            .simulatedAccessibilityTraversal()
            .toList();
        _expectEveryTappableNodeIsLabeled(
          runningTraversal,
          screen: 'practice session, running ($localeCode)',
        );
        // A3 "meaningful focus order": at `running` `PracticeControls`
        // (lib/features/practice/presentation/widgets/practice_controls.dart)
        // adds exactly Pause, Finish, Exit, in that order — the traversal
        // must present them in that same reading order, not merely contain
        // all three labels somewhere.
        expect(
          runningTraversal,
          containsAllInOrder(<Matcher>[
            isSemantics(
              label: l10n.practiceSessionPause,
              isButton: true,
              hasTapAction: true,
            ),
            isSemantics(
              label: l10n.practiceSessionFinish,
              isButton: true,
              hasTapAction: true,
            ),
            isSemantics(
              label: l10n.practiceSessionExit,
              isButton: true,
              hasTapAction: true,
            ),
          ]),
          reason:
              '$localeCode: Pause -> Finish -> Exit must appear in that '
              'reading order in the simulated traversal',
        );

        // A4: `PracticeReadinessRow` (practice_readiness_row.dart:5-11,
        // built into the session screen at practice_session_screen.dart:233)
        // renders its weak-signal/degraded-capability state as an icon
        // colour AND a `_ReadinessChip.label` on the SAME semantics node
        // ("status is never conveyed by colour alone", its own doc
        // comment) — the traversal must expose one of the two localised
        // texts for each indicator, proving the state reads as text.
        final readinessLabels = <String>{
          l10n.practiceSessionReadinessWeakSignal,
          l10n.practiceSessionReadinessSignalOk,
          l10n.practiceSessionReadinessDegraded,
          l10n.practiceSessionReadinessCapabilityOk,
        };
        expect(
          runningTraversal.any(
            (node) => readinessLabels.contains(node.getSemanticsData().label),
          ),
          isTrue,
          reason:
              '$localeCode: the session readiness row must expose its '
              'weak-signal/degraded-capability state as one of '
              '$readinessLabels, not colour alone',
        );

        await _finishToResult(tester, session, l10n);

        final resultTraversal = tester.semantics
            .simulatedAccessibilityTraversal()
            .toList();
        // `PracticeResultFallback` (practice_result_screen.dart:776-815) is
        // a static icon+title+body message with NO interactive control at
        // all — `requireAtLeastOneTappable: false` reflects that measured
        // fact rather than masking a real gap; the unlabeled-count check
        // below still runs (trivially 0/0) so a FUTURE unlabeled control
        // added to this screen would still be caught.
        _expectEveryTappableNodeIsLabeled(
          resultTraversal,
          screen: 'practice result fallback ($localeCode)',
          requireAtLeastOneTappable: false,
        );

        await session.dispose(tester);
        handle.dispose();
      },
    );
  }
}
