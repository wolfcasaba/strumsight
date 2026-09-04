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
import 'package:strumsight/features/library_v2/screens/unified_library_screen.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart'
    show PracticeResultFallback;
import 'package:strumsight/features/practice/presentation/screens/practice_session_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/features/progress/public.dart'
    show PracticeStats, practiceLogProvider;
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

  // 1. Indítás -> onboarding (real welcome carousel, explicit "Skip" exit).
  expect(find.byType(OnboardingScreen), findsOneWidget);
  walked.add('OnboardingScreen');
  await walkOnboardingViaSkip(tester);

  // MÉRT LELET: `OnboardingScreen._completeFinish` (`onboarding_screen.dart`)
  // always calls `router.go(AppRoutes.live)` after Skip/finish, regardless
  // of `adaptiveShellEnabled` — under this build's redirect table that
  // becomes `/practice/live` (a Stage route, no primary navigation), never
  // `/today`, even though the router's OWN `initialLocation` logic
  // (`app_router.dart`) picks `/today` first whenever the shell is on. A
  // direct `router.go(AppRoutes.today)` reaches the real Today experience
  // this walkthrough is chartered to measure — recorded in
  // docs/release/full-app-verification.md, not fixed here (§5.2).
  session.router.go(AppRoutes.today);
  await tester.pumpAndSettle();

  // 2. Today Hub — a fresh install is the REAL "new user" state (zero
  // sessions, zero streak, no plan) — its own doc-comment (A8) requires
  // this be derived from real zero-state signals, never an invented number.
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

  // 3. Practice Area Hub (adaptive shell) — static content, no provider
  // feed (ADR 0276 A4): the only "real data" assertion available is its
  // own localized copy actually rendering.
  expect(find.byType(PracticeAreaHubScreen), findsOneWidget);
  walked.add('PracticeAreaHubScreen');
  expect(find.text(l10n.practiceAreaHubRecommendedTitle), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey('practice-hub-recommended-cta')));
  await tester.pumpAndSettle();

  // MÉRT LELET (recorded in docs/release/full-app-verification.md, §5.2 —
  // NOT fixed here, lib/** is this round's forbidden zone): the adaptive
  // shell's "start recommended practice" CTA calls
  // `context.go(AppRoutes.practiceSetup)` with NO `?id=` query parameter
  // (`practice_area_hub_screen.dart:55`), unlike the legacy Hub's
  // `_openSetup` (`practice_hub_screen.dart:370-375`), which always builds
  // the URI with `id: definition.id`. `PracticeSetupScreen._readArgs`
  // therefore resolves `PracticeSetupRequest.missing` and the screen
  // renders its own `_RouteError` branch — a real, localized, EXPLICIT
  // error state (not a placeholder literal; §5.1 still holds), but the
  // shell's only advertised entry point into a scored practice session is
  // measurably a dead end today.
  expect(find.byType(PracticeSetupScreen), findsOneWidget);
  walked.add('PracticeSetupScreen');
  expect(
    find.text(l10n.practiceRouteErrorTitle),
    findsOneWidget,
    reason:
        'MÉRT LELET: PracticeAreaHubScreen\'s recommended CTA never passes '
        '?id=, so Setup renders its explicit "not found" error branch — '
        'see docs/release/full-app-verification.md',
  );

  // Complete a REAL session anyway, through the same URL shape the legacy
  // Hub's own Quick Start already uses in production
  // (`practice_hub_screen.dart`'s `_openSetup`) — real, supported
  // navigation, not a test-only shortcut — so the downstream
  // Library/Progress/Profile stops have real, persisted data to show.
  // Bounces off `/practice` first: go_router keeps a query-only change to
  // the SAME path on the SAME page (no rebuild of `PracticeSetupScreen`,
  // which reads its args straight from `routeInformationProvider` on
  // build), so navigating straight from the id-less `/practice/setup` to
  // the id-bearing one would render the stale `_RouteError` forever.
  session.router.go(AppRoutes.practiceHub);
  await tester.pumpAndSettle();
  session.router.go('${AppRoutes.practiceSetup}?id=$e2eQuickStartDefinitionId');
  await tester.pumpAndSettle();
  expect(find.byType(PracticeSetupScreen), findsOneWidget);
  expect(
    find.text(l10n.practiceRouteErrorTitle),
    findsNothing,
    reason: 'with a real id, Setup must render the form, not the error branch',
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

  // 4. "Eredmény" — the NavigateToResult effect lands on `/practice/result`,
  // which always builds `PracticeResultFallback` — an explicit, already
  // MÉRT (E12-R20) "no detailed result on this route" state, not a
  // placeholder. `PracticeResultFallback`'s class name does not end in
  // "Screen" (it is not one of the 96 `tool/ui_inventory.dart`-measured
  // classes), so it is intentionally NOT added to [walked] — the A4
  // partition tracks the measured `PracticeResultScreen` class separately
  // (see the round doc's exclusion table).
  expect(find.byType(PracticeResultFallback), findsOneWidget);
  expect(find.text(l10n.practiceResultUnavailableTitle), findsOneWidget);

  final history = await loadPracticeHistory(session.container);
  expect(
    history,
    hasLength(1),
    reason: 'the finished session must leave exactly one persisted record',
  );

  // MÉRT LELET (recorded in docs/release/full-app-verification.md, §5.2 —
  // not fixed here): `practiceHistoryV2ListProvider`
  // (`practice_progress_providers.dart`) is a plain `FutureProvider` —
  // never `.family`, never invalidated anywhere in `lib/` — so its FIRST
  // read permanently caches whatever the practice-history repository held
  // AT THAT MOMENT for the rest of THIS container's life. The Today Hub
  // stop above already forced that first read (via
  // `dailyGoalActiveSecondsProvider` -> `aggregatedPracticeFeedProvider` ->
  // `practiceProgressFeedProvider`), before this session existed — so
  // `progressPracticeHistoryProvider` (which reads the SAME cached
  // provider) would stay empty in THIS container even though the session
  // above genuinely persisted. A real app restart is the only way any
  // container ever observes a session recorded after its own first Today
  // Hub render — so this walkthrough restarts here, exactly like a user
  // relaunching the app, before continuing to Library/Progress/Profile.
  session = await restartE2eApp(
    tester,
    session,
    store: store,
    onboardingSeen: true,
    flags: _shippedBeFlags(),
  );
  await tester.pumpAndSettle();

  // 5. Library. MÉRT LELET (recorded in
  // docs/release/full-app-verification.md, §5.2 — not fixed here):
  // `libraryV2SourcesProvider` (`library_v2_providers.dart`) unconditionally
  // reads `analysisRepositoryProvider`/`songRepositoryProvider`/
  // `setlistRepositoryProvider`, three providers whose base declarations
  // (`analysis_providers.dart`) deliberately `throw StateError` until the
  // PRODUCTION bootstrap (`main.dart`) wires them from the boot variants —
  // `bootE2eApp` builds its `ProviderContainer` directly (E12-R11, ADR
  // 0472), never runs that bootstrap, and does not override these three.
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

  // 7. Profile. MÉRT LELET (recorded in
  // docs/release/full-app-verification.md, §5.2 — not fixed here):
  // `ProfileHubScreen`'s "sessions" metric reads `practiceLogProvider`
  // (`lib/features/progress/providers/practice_log_provider.dart`) — the V1
  // "Learn" practice log (`PracticeSessionRecording`,
  // `practice_session_recording.dart`) — which is a DIFFERENT store from
  // the Practice Engine V2 history repository this walkthrough's session
  // just wrote to (`practiceHistoryRepositoryProvider`, read by Library/
  // Progress above). A completed V2 quick-start session never appends to
  // the V1 log, so this metric's value is REAL (a genuinely computed read
  // of its own real source, §5.1 — not a P1/P2/P3 placeholder literal) but
  // stays exactly what it was before the session: this round's own
  // `progressPracticeHistoryProvider`/Library read the V2 store correctly;
  // this metric simply reads a different, V2-blind store.
  session.router.go(AppRoutes.profileHome);
  await tester.pumpAndSettle();
  expect(find.byType(ProfileHubScreen), findsOneWidget);
  walked.add('ProfileHubScreen');
  final v1SessionCount = PracticeStats(
    session.container.read(practiceLogProvider),
  ).totalSessions;
  // Scoped to the "Sessions" _Metric tile's OWN Column (found by walking up
  // from its label text), not `ProfileHubScreen` at large — a bare
  // `find.text('$v1SessionCount')` under the whole screen would also match
  // the streak tile whenever both render `0` (MINOR-2, review §4), which
  // would pass even if the sessions metric rendered nothing at all.
  final sessionsMetricColumn = find
      .ancestor(
        of: find.text(l10n.progressSessions),
        matching: find.byType(Column),
      )
      .first;
  expect(
    find.descendant(
      of: sessionsMetricColumn,
      matching: find.text('$v1SessionCount'),
    ),
    findsOneWidget,
    reason:
        'the sessions metric must reflect its own real (V1 log) source '
        'value, whatever that measurably is — scoped to the sessions tile '
        'so the streak tile (which also renders 0 for a fresh install) '
        'cannot satisfy this assertion',
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
            'TodayHubScreen',
            'PracticeAreaHubScreen',
            'PracticeSetupScreen',
            'PracticeSessionScreen',
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
}
