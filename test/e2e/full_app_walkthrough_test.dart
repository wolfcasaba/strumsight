// E16-R05 — the sáv-záró full-app walkthrough (round brief §1/§3/§5.4/1).
//
// Boots the SHIPPED "BE" (nonProd) capability set —
// `FeatureFlags.forEnvironment(AppEnvironment.development, accountEnabled:
// false)` — on the REAL StrumSightApp tree via the E12-R11 deterministic
// harness (`bootE2eApp`), and walks the core route the brief names:
// indítás → Today → gyakorlás → eredmény → Library → Progress → Profile
// (+ Settings, a natural sub-stop off Profile). Every stop asserts REAL,
// persisted data or an EXPLICIT state (§5.1) — never mere widget presence.
//
// `runCoreWalkthrough` is exported (not `_`-private) so
// `test/tooling/placeholder_wiring_test.dart`'s A4 cell can run the SAME
// walk itself and read back the exact set of measured screen classes it
// actually built — observed from the run, never a hand-copied list
// (§5.4/1, L606/L558 hibaosztály).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/features/curriculum/presentation/screens/curriculum_ladder_screen.dart';
import 'package:strumsight/features/analyze/screens/analyze_screen.dart';
import 'package:strumsight/features/library_v2/screens/unified_library_screen.dart';
import 'package:strumsight/features/onboarding/screens/first_win_stage_screen.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart'
    show PracticeResultScreen;
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/features/progress/public.dart'
    show PracticeStats, practiceLogProvider, practiceStatsProvider;
import 'package:strumsight/features/progress_v2/application/progress_providers.dart'
    show progressPracticeHistoryProvider;
import 'package:strumsight/features/progress_v2/screens/progress_dashboard_screen.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../support/e2e_harness.dart';

/// The BE flag set this round measures against (§0.0.1/R2, §5.5): the
/// SHIPPED non-production default, not a hand-picked subset.
FeatureFlags _shippedBeFlags() => FeatureFlags.forEnvironment(
  AppEnvironment.development,
  accountEnabled: false,
);

/// The flag set the R30 cell at the bottom of this file measures against.
///
/// MÉRT: `forEnvironment` resolves every dart-define it reads to `false`
/// when the define is absent, and `audioAnalysisV2Enabled` is one of those —
/// so [_shippedBeFlags] alone does NOT register the `/analysis/*` routes.
/// The shipped development artifact reaches them through the preview
/// overlay (`forShippedBuild` passes `previewAll: true` for development);
/// this asks for exactly that overlay, and leaves the account layer off so
/// the cell needs no auth surface.
FeatureFlags _shippedPreviewFlags() => FeatureFlags.forEnvironment(
  AppEnvironment.development,
  accountEnabled: false,
  previewAll: true,
);

/// Pumps FIXED frames until [finder] matches nothing, at most [maxFrames].
///
/// MÉRT (run 564/565): a popped route is NOT gone when the pop is issued —
/// it stays on stage for its whole reverse transition, and its overlay
/// entry is removed a frame after that, while the route it uncovers is
/// already found underneath. So "the arriving screen is here" needs no
/// waiting, but "the leaving one is gone" is not measurable on a fixed pump
/// budget. `pumpAndSettle` is out for the reason the cell below states
/// (Riverpod 3 auto-retries a failing `FutureProvider`), so this is the
/// same bounded shape `analysis_exit_chain_test` and the R18 entry-point
/// cells already use.
Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int maxFrames = 40,
}) async {
  await tester.pump();
  for (var frame = 0; frame < maxFrames; frame++) {
    if (finder.evaluate().isEmpty) return;
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Advances [session]'s fake clock in small, fixed steps until the active
/// session's status satisfies [reached] — the same bounded-tick pattern
/// `e2e_harness.dart`'s own private `_driveSessionUntil` and every
/// accessibility-flow test already use; re-implemented locally because this
/// round's allowed-files list does not extend to adding a new exported
/// helper to `e2e_harness.dart` (§4 — only the additive `flags` param is
/// in scope there).
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

/// Runs the E16-R05 core walkthrough end to end and returns the exact set
/// of MEASURED screen classes (`tool/ui_inventory.dart`'s `*_screen.dart`
/// convention) actually built along the way — derived from `find.byType`
/// observations during this very run, never a hand-maintained constant.
Future<Set<String>> runCoreWalkthrough(WidgetTester tester) async {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final walked = <String>{};

  final store = InMemoryKeyValueStore();
  var session = await bootE2eApp(
    tester,
    store: store,
    onboardingSeen: false,
    flags: _shippedBeFlags(),
  );

  // 1. Indítás -> onboarding (real welcome carousel), THROUGH the "first
  // win" CTA rather than the quiet Skip exit (ADR 0534, E17-R01): Next ->
  // Next -> the first-win CTA -> the (auto-granted, `fakeAudioOverrides()`'s
  // default) permission checkpoint -> `_completeFirstWin`'s hand-off, which
  // pushes the bekötött `FirstWinStageScreen` on top of `entryLocation`. Real
  // taps throughout, no test-side bridge (§4/allowed_paths — this file, not
  // `e2e_harness.dart`, owns the flow-specific steps not already shared).
  expect(find.byType(OnboardingScreen), findsOneWidget);
  walked.add('OnboardingScreen');
  await tester.tap(find.text(l10n.onboardNext));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.onboardNext));
  await tester.pumpAndSettle();

  expect(find.text(l10n.onboardFirstWin), findsOneWidget);
  await tester.tap(find.text(l10n.onboardFirstWin));
  await tester.pump();
  await tester.pumpAndSettle();

  expect(
    find.byType(FirstWinStageScreen),
    findsOneWidget,
    reason: 'the first-win CTA must land on the bekötött Stage (ADR 0534 D1)',
  );
  walked.add('FirstWinStageScreen');

  // "Not now" — the Stage's OWN dismissal (real tap), popping its pushed
  // route and landing back on `entryLocation` (already reached by
  // `_completeFirstWin`'s `router.go` before the push) — so every stop below
  // continues exactly as the Skip path used to leave it.
  await tester.tap(find.byKey(const ValueKey('onboard-first-win-skip')));
  await tester.pumpAndSettle();

  // E16-R06 (ADR 0508 D1/D2, L2 feloldva) — `OnboardingScreen._completeFinish`
  // (and, since E17-R01, `_completeFirstWin`) navigates via
  // `entryLocationFor(adaptiveShellEnabled)`, the SAME source
  // `app_router.dart`'s own entry-point logic reads, so this walk lands
  // directly on the real Today experience with no teszt-oldali híd.

  // 2. Today Hub — a fresh install is the REAL "new user" state (zero
  // sessions, zero streak) — its own doc-comment (A8) requires this be
  // derived from real zero-state signals, never an invented number.
  //
  // It does, however, have a PLAN. `CurriculumTodayPlanRepository.load()`
  // asks `curriculumNextStep` and the shipped course always offers a first
  // rung, so `recommendedMissionId` is non-null from the very first launch.
  // This comment used to say "no plan", and that stale clause is exactly what
  // made the next stop wrong for a while — see stop 3.
  expect(find.byType(TodayHubScreen), findsOneWidget);
  walked.add('TodayHubScreen');
  expect(
    find.text(l10n.todayHubNewUserTitle),
    findsOneWidget,
    reason:
        'a fresh install must show the real new-user hero, not a '
        'silently-wrong "continue" message',
  );

  await tester.tap(find.byKey(const ValueKey('today-hub-primary-cta')));
  await tester.pumpAndSettle();

  // 3. Curriculum ladder — the Today CTA's REAL destination.
  //
  // `TodayHubScreen` picks `curriculumLadder` whenever the plan names a rung
  // and `practiceHub` only when it does not, and its own comment says why:
  // "a button labelled 'continue' that goes somewhere else is the hub lying
  // about what it just offered." Since the plan always names one (stop 2),
  // this tap has always landed here.
  //
  // This walkthrough asserted `PracticeAreaHubScreen` instead, and went red
  // when `677b72e6 feat(today): the daily loop` made the shipped course the
  // plan. The expectation was stale, NOT the product — so the fix is to
  // assert the real destination rather than to bend the assertion back.
  // Static content, no provider feed, so the available "real data" assertion
  // is its own localized copy actually rendering (same standard as stop 3b).
  expect(find.byType(CurriculumLadderScreen), findsOneWidget);
  walked.add('CurriculumLadderScreen');
  expect(find.text(l10n.curriculumLadderTitle), findsOneWidget);

  // 3b. Practice Area Hub (adaptive shell) — no longer on the Today CTA's
  // path, so it is reached the way stops 5-8 below already reach theirs:
  // `session.router.go`, this file's own navigation idiom. Keeping the stop
  // matters because everything from Setup onwards hangs off its CTA, and
  // dropping it would shrink A2/A3 coverage silently.
  session.router.go(AppRoutes.practiceHub);
  await tester.pumpAndSettle();
  expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
  walked.add('PracticeAreaHubScreen');
  expect(find.text(l10n.practiceAreaHubRecommendedTitle), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey('practice-hub-recommended-cta')));
  await tester.pumpAndSettle();

  // E16-R06 (ADR 0508 D3, L1 feloldva) — the adaptive shell's "start
  // recommended practice" CTA now builds the SAME `?id=<definíció id>` URI
  // shape as the legacy Hub's `_openSetup`, using the catalog's first entry
  // (`e2eQuickStartDefinitionId`). Setup therefore renders the real form
  // directly off the CTA tap — no teszt-oldali híd.
  expect(find.byType(PracticeSetupScreen), findsOneWidget);
  walked.add('PracticeSetupScreen');
  expect(
    find.text(l10n.practiceRouteErrorTitle),
    findsNothing,
    reason:
        'the CTA now carries a real id, so Setup must render the form, '
        'not the error branch',
  );

  final setupStart = find.widgetWithText(FilledButton, l10n.practiceSetupStart);
  await tester.scrollUntilVisible(
    setupStart,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(setupStart);
  await tester.pumpAndSettle();

  expect(find.byType(PracticeSessionScreen), findsOneWidget);
  walked.add('PracticeSessionScreen');

  await tester.tap(
    find.widgetWithText(ElevatedButton, l10n.practiceSessionStart),
  );
  await tester.pump();
  await _driveSessionUntil(
    tester,
    session,
    (status) => status == PracticeSessionStatus.running,
  );
  expect(
    find.text(l10n.practiceSessionPause),
    findsOneWidget,
    reason: 'a running session must show its real live controls',
  );

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

  // 4. "Eredmény" — the NavigateToResult effect lands on `/practice/result`.
  // Javító sáv 2026-09-06: the route no longer builds
  // `PracticeResultFallback` unconditionally — `PracticeResultRoute`
  // resolves the ending session's OWN entry (the `practice_result_target.dart`
  // hand-off plus the after-record hook's `practiceHistoryV2ListProvider`
  // invalidation) and builds the real `PracticeResultScreen`. That class IS
  // one of the measured `tool/ui_inventory.dart` classes, so this stop now
  // joins [walked], and `practice_result_screen.dart` is no longer an
  // excluded row in `docs/release/full-app-verification.md` §3.2.
  expect(find.byType(PracticeResultScreen), findsOneWidget);
  walked.add('PracticeResultScreen');

  final history = await loadPracticeHistory(session.container);
  expect(
    history,
    hasLength(1),
    reason: 'the finished session must leave exactly one persisted record',
  );
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is PracticeResultScreen &&
          widget.entry.id == history.single.id,
    ),
    findsOneWidget,
    reason:
        'the result route must render the entry the just-finished session '
        'actually persisted — real data, never an empty fallback',
  );

  // §5.2 L5 (docs/release/full-app-verification.md) used to hold here:
  // `practiceHistoryV2ListProvider` (`practice_progress_providers.dart`)
  // is a plain `FutureProvider`, and the Today Hub stop above already
  // forced its first read before this session existed, so a container
  // never observed a later session. Learner-loop round 2 resolved it (the
  // effect listener invalidates the provider on `NavigateToResult`). The
  // restart below is kept on purpose: it measures a real relaunch on the
  // same store, exactly like a user reopening the app, before the
  // Library/Progress/Profile stops read the persisted session.
  session = await restartE2eApp(
    tester,
    session,
    store: store,
    onboardingSeen: true,
    flags: _shippedBeFlags(),
  );
  await tester.pumpAndSettle();

  // 5. Library. MÉRT LELET (recorded in
  // docs/release/full-app-verification.md, §5.2): `libraryV2SourcesProvider`
  // (`library_v2_providers.dart`) unconditionally reads
  // `analysisRepositoryProvider`/`songRepositoryProvider`/
  // `setlistRepositoryProvider`, three providers whose base declarations
  // (`analysis_providers.dart`) deliberately `throw StateError` until the
  // PRODUCTION bootstrap (`main.dart`) wires them from the boot variants.
  // Until E18-R01 F5 the production bootstrap wired only the song store —
  // the SAME error state shipped to every device; `main.dart` now wires all
  // three (`production_repository_overrides.dart`, guarded by
  // `test/app/bootstrap/production_repository_overrides_test.dart`).
  // `bootE2eApp` builds its `ProviderContainer` directly (E12-R11, ADR
  // 0472), never runs that bootstrap, and does not override these three,
  // so THIS harness still measures the error branch.
  // `LibraryV2Controller.build()` therefore fails for EVERY item source,
  // and `UnifiedLibraryScreen` renders its own real, localized, EXPLICIT
  // `libraryV2LoadFailed` error state (§5.1's "or an explicit state" branch
  // — not a placeholder literal) instead of the persisted practice session.
  session.router.go(AppRoutes.profileLibrary);
  await tester.pumpAndSettle();
  expect(find.byType(UnifiedLibraryScreen), findsOneWidget);
  walked.add('UnifiedLibraryScreen');
  expect(
    find.text(l10n.libraryV2LoadFailed),
    findsOneWidget,
    reason:
        'MÉRT LELET: the harness never wires analysis/song/setlist '
        'repositories, so every UnifiedLibraryScreen source fails to load — '
        'see docs/release/full-app-verification.md',
  );

  // 6. Progress — same practice-history repository, read through
  // `progressPracticeHistoryProvider` (this round's own §6.1 mutation
  // target). The dashboard's OWN new-user/skills branch depends on whether
  // any mastery milestone accrued evidence — not merely on the history
  // list being non-empty — so a screen-only assertion here cannot tell
  // "real one-session history" apart from "mutated to always-empty" (both
  // land on the SAME new-user view for this session's practice
  // definition, MÉRT). The provider-level check below is what actually
  // falsifies the §6.1 mutation.
  session.router.go(AppRoutes.profileProgress);
  await tester.pumpAndSettle();
  expect(find.byType(ProgressDashboardScreen), findsOneWidget);
  walked.add('ProgressDashboardScreen');
  expect(
    session.container.read(progressPracticeHistoryProvider),
    hasLength(1),
    reason:
        'the just-completed session must reach the Progress V2 '
        'composition layer through progressPracticeHistoryProvider',
  );
  final isProgressNewUser = find
      .byKey(const Key('progress-dashboard-new-user'))
      .evaluate()
      .isNotEmpty;
  if (isProgressNewUser) {
    expect(find.text(l10n.progressV2NewUserTitle), findsOneWidget);
  } else {
    expect(find.text(l10n.progressV2SkillsSectionTitle), findsOneWidget);
  }

  // 7. Profile. The §5.2 L4 finding (recorded in
  // docs/release/full-app-verification.md) used to hold here: the
  // "sessions" metric read `practiceLogProvider` — the V1 "Learn" log — a
  // DIFFERENT store from the Practice Engine V2 history this walkthrough's
  // session just wrote to, so the tile stayed at its pre-session value.
  // Learner-loop round 4 ("one progress model") resolved it: every hub
  // reads `practiceStatsProvider`, built from the V1 + V2 aggregated feed,
  // so the session completed above now counts here exactly as it does on
  // Library/Progress. Both halves are asserted: the tile renders the
  // unified rollup, and that rollup is the V1 count plus this walk's one
  // V2 session (the restart above made the V2 list observable).
  session.router.go(AppRoutes.profileHome);
  await tester.pumpAndSettle();
  expect(find.byType(ProfileHubScreen), findsOneWidget);
  walked.add('ProfileHubScreen');
  final v1SessionCount = PracticeStats(
    session.container.read(practiceLogProvider),
  ).totalSessions;
  final unifiedSessionCount = session.container
      .read(practiceStatsProvider)
      .totalSessions;
  expect(
    unifiedSessionCount,
    v1SessionCount + 1,
    reason:
        'the unified rollup must count the V1 log plus the ONE Practice '
        'V2 session this walkthrough completed (learner-loop round 4)',
  );
  // Scoped to the "Sessions" _Metric tile's OWN Column (found by walking up
  // from its label text), not `ProfileHubScreen` at large — a bare
  // `find.text('$unifiedSessionCount')` under the whole screen could also
  // match the streak tile (MINOR-2, review §4), which would pass even if
  // the sessions metric rendered nothing at all.
  final sessionsMetricColumn = find
      .ancestor(
        of: find.text(l10n.progressSessions),
        matching: find.byType(Column),
      )
      .first;
  expect(
    find.descendant(
      of: sessionsMetricColumn,
      matching: find.text('$unifiedSessionCount'),
    ),
    findsOneWidget,
    reason:
        'the sessions metric must render the unified (V1 + V2) rollup, '
        'scoped to the sessions tile so the streak tile cannot satisfy '
        'this assertion',
  );

  await tester.tap(find.widgetWithText(OutlinedButton, l10n.settingsTitle));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsScreen), findsOneWidget);
  walked.add('SettingsScreen');

  await session.dispose(tester);
  // ADR 0472 D6 / brief §9 — flutter_animate's teardown timer.
  await tester.pump(const Duration(milliseconds: 400));

  return walked;
}

void main() {
  group('E16-R05 A2/A3 — the BE-flagged core walkthrough asserts real data '
      'or an explicit state at every stop', () {
    testWidgets(
      'indítás -> Today -> gyakorlás -> eredmény -> Library -> Progress -> '
      'Profile -> Settings, on the shipped forEnvironment(development) '
      'flag set',
      (tester) async {
        final walked = await runCoreWalkthrough(tester);

        expect(
          walked,
          {
            'OnboardingScreen',
            'FirstWinStageScreen',
            'TodayHubScreen',
            'CurriculumLadderScreen',
            'PracticeAreaHubScreen',
            'PracticeSetupScreen',
            'PracticeSessionScreen',
            'PracticeResultScreen',
            'UnifiedLibraryScreen',
            'ProgressDashboardScreen',
            'ProfileHubScreen',
            'SettingsScreen',
          },
          reason:
              'the walked-screen set must be exactly what this run actually '
              'built — a shrinking set silently drops A2/A3 coverage, a '
              'growing set means this expectation is stale',
        );
      },
    );
  });

  // R30 (re-audit #2 §7 DoD) — the STRUCTURAL reason CI never caught the
  // dead ends this round closes: every stop of the walk above ARRIVES with
  // a test-side `router.go` and LEAVES the same way, so a screen with no
  // on-screen exit reads exactly like a screen with one. This cell leaves
  // by tapping what a user can actually see, and fails if that control is
  // missing or dead.
  //
  // It deliberately does NOT extend `runCoreWalkthrough`: that function's
  // returned set is the A4 partition against
  // `docs/release/full-app-verification.md` §3.2, where both screens below
  // are documented EXCLUSIONS. Walking them there would flip A4 from
  // "disjoint" to overlapping — a documentation change this round is not
  // scoped to make.
  group('E16-R05 A2/A3 + R30 — the Analysis door is left by TAPPING, not by '
      'a test-side router.go', () {
    testWidgets(
      'Today -> Practice -> Analyze -> the detailed-analysis door, and back '
      'out again through the controls actually on screen',
      (tester) async {
        final store = InMemoryKeyValueStore();
        final session = await bootE2eApp(
          tester,
          store: store,
          onboardingSeen: true,
          flags: _shippedPreviewFlags(),
        );

        expect(find.byType(TodayHubScreen), findsOneWidget);
        // The Today CTA lands on the curriculum LADDER whenever the plan
        // names a rung, and the shipped course always does (see stop 3a
        // above) — so the Practice hub is reached the way stops 3b/5-8
        // reach theirs. What this cell measures starts one screen later:
        // the Analysis door is opened AND left through the controls on
        // screen, never a test-side `router.go`.
        session.router.go(AppRoutes.practiceHub);
        await tester.pumpAndSettle();
        expect(find.byType(PracticeAreaHubScreen), findsOneWidget);

        final analyzeTile = find.byKey(const ValueKey('practice-hub-analyze'));
        await tester.scrollUntilVisible(
          analyzeTile,
          120,
          scrollable: find
              .descendant(
                of: find.byType(PracticeAreaHubScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        // `scrollUntilVisible` stops as soon as the target is BUILT, which
        // for a `ListView` happens inside the cache extent — below the
        // viewport, where a tap would not hit it.
        await tester.ensureVisible(analyzeTile);
        await tester.pumpAndSettle();
        await tester.tap(analyzeTile);
        await tester.pumpAndSettle();
        expect(find.byType(AnalyzeScreen), findsOneWidget);

        final door = find.byKey(const Key('analyze-open-analysis-v2'));
        await tester.ensureVisible(door);
        await tester.pumpAndSettle();
        await tester.tap(door);
        await tester.pump();
        // Bounded pumps, never `pumpAndSettle`: Riverpod 3 auto-retries a
        // `FutureProvider` that throws, and a settle would chase that retry.
        // 400 ms is past the push transition.
        await tester.pump(const Duration(milliseconds: 400));

        // MÉRT LELET: `bootE2eApp` never wires the analysis repository (the
        // same gap the Library stop above records), so the recent-analyses
        // read fails and the route renders its OWN error frame instead of
        // the capture home. R18 made that frame honest; R30 is what puts a
        // control on it — the assertion below is that exit, not the read.
        expect(
          find.byKey(const Key('analysis-home-route-error')),
          findsOneWidget,
        );

        final errorFrame = find.byKey(const Key('analysis-home-route-error'));
        await tester.tap(find.byKey(const Key('route-frame-back')));
        // The pushed frame has to be OFF STAGE before the next tap: while it
        // is still transitioning out it sits above the Analyze page, and the
        // exit tapped below would land on the leaving route instead.
        await _pumpUntilGone(tester, errorFrame);
        expect(
          errorFrame,
          findsNothing,
          reason: 'the pushed error frame is popped by its own control',
        );
        expect(
          find.byType(AnalyzeScreen),
          findsOneWidget,
          reason:
              'the frame was PUSHED, so its control pops back to the screen '
              'that opened it',
        );

        // R30 (M4) — the Analyze page itself: the screen brings no
        // `Scaffold`, and before this round the pushed page carried no exit
        // either. The route's adapter is what this tap proves.
        //
        // MÉRT LELET (run 565): that exit is REAL, but it is not a
        // DESCENDANT of `AnalyzeScreen` — the adapter WRAPS the screen, so
        // the `BackButton` sits in the `AppBar` of the `Scaffold` ABOVE it.
        // The original descendant finder could therefore never match, no
        // matter how the page was reached. The closest `Scaffold` ancestor
        // IS that frame (the shell's own `Scaffold` is further up), which
        // is the finder `r18_entry_points_test`'s M4 cell already drives.
        final analyzeFrame = find
            .ancestor(
              of: find.byType(AnalyzeScreen),
              matching: find.byType(Scaffold),
            )
            .first;
        final analyzeBack = find.descendant(
          of: analyzeFrame,
          matching: find.byType(BackButton),
        );
        expect(analyzeBack, findsOneWidget);
        await tester.tap(analyzeBack);
        await tester.pumpAndSettle();
        expect(find.byType(AnalyzeScreen), findsNothing);
        expect(find.byType(PracticeAreaHubScreen), findsOneWidget);

        await session.dispose(tester);
        // ADR 0472 D6 / brief §9 — flutter_animate's teardown timer.
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });
}
