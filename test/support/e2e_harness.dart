import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/app/strumsight_app.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/core/network/dio_factory.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/application/practice_session_providers.dart';
import 'package:strumsight/features/practice/data/local_practice_history_repository.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_hub_screen.dart';
import 'package:strumsight/features/settings/providers/lab_mode_provider.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';

import 'fake_audio.dart';
import 'fake_auth.dart';
import 'fake_clock.dart';
import 'fake_engines.dart';
import 'fake_network_guard.dart';
import 'preference_store.dart';

export 'fake_clock.dart';
export 'fake_network_guard.dart';
export 'preference_store.dart';

const _apiBaseUrl = 'https://api.strumsight.test';
const _appVersion = 'e2e-harness-test';

/// The E12-R11 offline "first practice" fixture: the shipped catalog's first
/// entry, exactly what `PracticeHubScreen`'s Quick Start card opens (the
/// chain's own input choice — the harness picks WHICH definition to drive,
/// never a value the chain itself would have produced, ADR 0472 §5.5).
const String e2eQuickStartDefinitionId = 'builtin.quarterDownstrokes.v1';

/// A booted [StrumSightApp] instance plus every harness handle a flow needs
/// to drive it deterministically: the real `ProviderContainer`/`GoRouter`
/// pair, the single [HarnessClock] time source, and the installed
/// [FakeNetworkGuard].
final class E2eSession {
  E2eSession({
    required this.container,
    required this.router,
    required this.clock,
    required this.networkGuard,
    required this.strumEngine,
    required this.tunerEngine,
  });

  final ProviderContainer container;
  final GoRouter router;
  final HarnessClock clock;
  final FakeNetworkGuard networkGuard;
  final FakeStrumEngine strumEngine;
  final FakeTunerEngine tunerEngine;

  /// The ADR 0472 D6 teardown order: unmount the widget tree FIRST (so every
  /// screen's own `dispose()` cancels its stream subscriptions), then
  /// dispose the container. Never awaits a broadcast `StreamController`
  /// close — under `testWidgets`' fake-clock zone that Future does not
  /// resolve ([L513](../../docs/LESSONS.md#l513)); the container's own
  /// `onDispose` chain runs detached instead of being awaited here.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    unawaited(strumEngine.dispose());
    unawaited(tunerEngine.dispose());
    networkGuard.uninstall();
  }
}

/// The E12-R11 default flag set: Practice Engine V2 on (the round's whole
/// surface); adaptive shell OFF so `/practice` resolves to the legacy
/// `PracticeHubScreen` the flows below drive — the same choice
/// `practice_routing_test.dart` makes for the identical reason. Public
/// (E16-R05 §5.5) so a caller can name it explicitly when threading
/// [flags] through some but not all of a test's `bootE2eApp` calls.
const FeatureFlags e2eDefaultFlags = FeatureFlags(
  accountEnabled: false,
  diagnosticsEnabled: false,
  labModeAvailable: false,
  practiceEngineV2Enabled: true,
);

AppConfig _e2eConfig({FeatureFlags? flags}) => AppConfig.resolve(
  environment: AppEnvironment.development,
  apiBaseUrl: _apiBaseUrl,
  flags: flags ?? e2eDefaultFlags,
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: _appVersion,
);

/// Boots the REAL [StrumSightApp] on [store] with the E12-R11 deterministic
/// profile (ADR 0472): a [FakeNetworkGuard] installed before the first
/// frame, a single [HarnessClock] wired into the practice session's
/// clock/tick-source providers, and the existing platform-boundary fakes
/// (`fakeAudioOverrides`, the engines, the token store) — no new fake
/// behind the platform boundary, only the wiring that ties the existing
/// ones into one full-app bootstrap. Returns once the first frame settles.
Future<E2eSession> bootE2eApp(
  WidgetTester tester, {
  required InMemoryKeyValueStore store,
  required bool onboardingSeen,
  FeatureFlags? flags,
}) async {
  final guard = FakeNetworkGuard()..install();
  final clock = HarnessClock();
  final strumEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final config = _e2eConfig(flags: flags);

  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      keyValueStoreProvider.overrideWithValue(store),
      appLoggerProvider.overrideWithValue(const NoopAppLogger()),
      onboardingSeenProvider.overrideWith(
        () => OnboardingController(onboardingSeen),
      ),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      // Both guarded, in case a future flag flip enables account/diagnostics
      // — the guard, not the flag, is what A3 pins down.
      accountDioFactoryProvider.overrideWith(
        (ref) => DioFactory(
          baseUrl: config.apiBaseUrl,
          appVersion: config.appVersion,
          logger: ref.watch(appLoggerProvider),
          adapter: guard.dioAdapter,
        ),
      ),
      diagnosticsConsentProvider.overrideWith(
        (ref) => ref.watch(labModeProvider),
      ),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(strumEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      // The E12-R11 single time source (ADR 0472 D3) — replaces the
      // production Stopwatch clock and the 16 ms real timer wherever the
      // practice session controller reads them.
      practiceSessionClockProvider.overrideWithValue(clock.clock),
      practiceTickSourceProvider.overrideWithValue(clock.tickSource),
      // Platform-boundary no-op: haptics/count-in-click/announce all reach a
      // real platform channel in production. Faking this edge keeps the
      // practice flow's own side effects off the channel the
      // FakeNetworkGuard watches, exactly like `fakeAudioOverrides()` keeps
      // the mic off it.
      practiceFeedbackOutputProvider.overrideWithValue(
        const _NoopPracticeFeedbackOutput(),
      ),
    ],
  );
  final router = container.read(routerProvider);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const StrumSightApp(),
    ),
  );
  await tester.pumpAndSettle();

  return E2eSession(
    container: container,
    router: router,
    clock: clock,
    networkGuard: guard,
    strumEngine: strumEngine,
    tunerEngine: tunerEngine,
  );
}

/// The A2 "app restart" (ADR 0472 §0.0/R6, kötelező alak): unmount the tree,
/// dispose the FIRST container, then boot a brand-new container + router on
/// the SAME [store] instance. Reusing a container would prove nothing about
/// persistence surviving a real restart.
Future<E2eSession> restartE2eApp(
  WidgetTester tester,
  E2eSession previous, {
  required InMemoryKeyValueStore store,
  required bool onboardingSeen,
  FeatureFlags? flags,
}) async {
  await previous.dispose(tester);
  return bootE2eApp(
    tester,
    store: store,
    onboardingSeen: onboardingSeen,
    flags: flags,
  );
}

final class _NoopPracticeFeedbackOutput implements PracticeFeedbackOutput {
  const _NoopPracticeFeedbackOutput();
  @override
  void haptic() {}
  @override
  void countInClick(int beatIndex) {}
  @override
  void announce(String message) {}
  @override
  void openPermissionSettings() {}
}

// ---------------------------------------------------------------------------
// Onboarding
// ---------------------------------------------------------------------------

/// Walks the welcome carousel's quiet exit (the "Skip" affordance on page
/// one) — completes onboarding without requesting the microphone, matching
/// this lane's offline scope. Real tap, real routing, no injected artifact.
Future<void> walkOnboardingViaSkip(WidgetTester tester) async {
  expect(
    find.text('Skip'),
    findsOneWidget,
    reason: 'a fresh install must land on the onboarding welcome carousel',
  );
  await tester.tap(find.text('Skip'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Practice flow
// ---------------------------------------------------------------------------

/// Walks the E12-R11 "first offline practice" vertical slice through the
/// REAL widget tree (ADR 0472 §5.5): Hub → Quick Start → Setup → Start →
/// Session (Start → drive to `running` → Finish → drive to `completed`).
/// Every status transition is driven by [HarnessClock.tick] — never
/// `pumpAndSettle` on a wall-clock duration, never a real `Timer`.
Future<void> runFirstPracticeSession(
  WidgetTester tester,
  E2eSession session,
) async {
  session.router.go(AppRoutes.practiceHub);
  await tester.pumpAndSettle();
  expect(find.byType(PracticeHubScreen), findsOneWidget);

  await tester.tap(find.text('Quick start'));
  await tester.pumpAndSettle();

  // The Start button sits at the bottom of a long form — scroll it into
  // the viewport before tapping (the same pattern
  // `practice_setup_screen_test.dart` uses).
  final setupStart = find.widgetWithText(FilledButton, 'Start practice');
  await tester.scrollUntilVisible(
    setupStart,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  // The Setup screen's own Start handler both activates the session and
  // navigates to `/practice/session` (ADR 0470) — the harness drives the
  // tap and lets the product's own hand-off land the flow on the Session
  // screen, no test-side navigation or provider-lifetime priming needed.
  await tester.tap(setupStart);
  await tester.pumpAndSettle();

  // PracticeControls lives in the Stage scaffold's fixed `bottomAction`
  // slot, not inside a scrollable — always on screen, no scroll needed.
  await tester.tap(find.widgetWithText(ElevatedButton, 'Start'));
  await tester.pump();
  await _driveSessionUntil(
    tester,
    session,
    (status) => status == PracticeSessionStatus.running,
  );

  await tester.tap(find.widgetWithText(ElevatedButton, 'Finish'));
  await tester.pump();
  await _driveSessionUntil(
    tester,
    session,
    (status) => status == PracticeSessionStatus.completed,
  );
  await tester.pumpAndSettle();
}

/// Advances [session]'s [HarnessClock] in small, fixed steps until the
/// active [PracticeSessionHost]'s status satisfies [reached], or fails
/// loudly after [maxTicks] — a stuck reducer must not hang the suite.
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

// ---------------------------------------------------------------------------
// Persisted-history verification
// ---------------------------------------------------------------------------

/// Loads every persisted [PracticeHistoryEntry] through the SAME repository
/// the production recorder writes through — the chain's own output, not a
/// side channel.
Future<List<PracticeHistoryEntry>> loadPracticeHistory(
  ProviderContainer container,
) async {
  final loaded = await container.read(practiceHistoryRepositoryProvider).load();
  return switch (loaded) {
    Success(:final value) => value,
    Failure(:final error) => fail('practice history load failed: $error'),
  };
}

/// A comparable projection of a [PracticeHistoryEntry] for the A4
/// determinism cell.
///
/// Deliberately excludes `createdAt`: the production mapper
/// (`PracticeSessionResultHistoryMapper`, `lib/**`, out of this round's
/// allowed-files list) stamps it with a real wall-clock read, so two
/// otherwise-identical runs of the SAME deterministic flow still differ on
/// that one field. Every field kept here is fully governed by this
/// harness's [HarnessClock] and fixed inputs.
typedef PracticeHistorySnapshot = ({
  String id,
  String modeCode,
  String sourceCode,
  String definitionId,
  String finishReasonCode,
  Duration activeDuration,
  Duration pausedDuration,
  int attemptsCount,
  int totalTargets,
  int resolvedTargets,
  int scorePoints,
  int maxCombo,
});

PracticeHistorySnapshot snapshotHistoryEntry(PracticeHistoryEntry entry) => (
  id: entry.id,
  modeCode: entry.modeCode,
  sourceCode: entry.sourceCode,
  definitionId: entry.definitionId,
  finishReasonCode: entry.finishReasonCode,
  activeDuration: entry.activeDuration,
  pausedDuration: entry.pausedDuration,
  attemptsCount: entry.attemptsCount,
  totalTargets: entry.totalTargets,
  resolvedTargets: entry.resolvedTargets,
  scorePoints: entry.scorePoints,
  maxCombo: entry.maxCombo,
);
