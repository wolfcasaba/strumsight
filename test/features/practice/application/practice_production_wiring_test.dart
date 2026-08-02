// E02-R21 — Practice V2 production wiring integration test (ADR 0111 §3).
//
// The single A5 acceptance criterion: a session launched through the
// production provider graph (not via constructor-injected fakes) must
//
// 1. publish a non-null `PracticeSessionHost` to the screen layer;
// 2. walk the session reducer to a terminal state;
// 3. leave a loadable record in the history repository;
// 4. release every active resource once terminal.
//
// This file is the red→green cell of the round: with the production
// wiring as of `main @ 6d61e23`, the `practiceSessionHostProvider`
// resolves to `null`, so the first assertion is the round's piros
// evidence; with the round's wirings in place, the test reaches the
// `completed` terminal, the history is non-empty, and every counter on
// the resource fakes reports a clean shutdown.
//
// Platform-boundary providers (StrumEngine, MicrophonePermissionGateway)
// are overridable — the brief allows fakes at the platform edge but
// forbids constructor-injected fakes that bypass the provider graph.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_setup_controller.dart';
import 'package:strumsight/features/practice/data/local_practice_history_repository.dart';
import 'package:strumsight/features/practice/data/practice_history_serializer.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_history_entry.dart';
import 'package:strumsight/features/practice/domain/repository/practice_history_repository.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/core/audio/audio_providers.dart';

import '../../../support/fake_audio.dart';
import '../../../support/fake_engines.dart';
import '../../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // -----------------------------------------------------------------
  // A5 — production wiring round-trip
  // -----------------------------------------------------------------
  group('A5 — production wiring drives a session to a loadable record', () {
    test('the published host, the state stream, the terminal, the history '
        'and the resource shutdown all hold at once', () async {
      final container = _buildContainer();
      addTearDown(container.dispose);

      // Read the host BEFORE the Setup dispatches — this is the round's
      // piros cell: today the provider returns null, the production
      // wiring makes it return the controller that the prepare sink
      // just constructed.
      final hostBefore = container.read(practiceSessionHostProvider);
      expect(
        hostBefore,
        isNull,
        reason:
            'pre-flight: the production wiring returns null until '
            'the Setup dispatches a PreparePractice command through '
            'the wired prepare sink (brief §2 / ADR 0111 §2).',
      );

      // Run the Setup → Session hand-off through the wired sink.
      final definition = _definition();
      final setupNotifier = container.read(
        practiceSetupControllerProvider(definition).notifier,
      );
      final sent = setupNotifier.start();
      expect(
        sent,
        isTrue,
        reason:
            'Setup accepted a valid config and forwarded the '
            'PreparePractice command through the wired prepare sink.',
      );

      // After the wired prepare sink runs, the host must be non-null
      // and the state stream must emit a non-initial state.
      final host = container.read(practiceSessionHostProvider);
      expect(
        host,
        isNotNull,
        reason:
            'A2: the wired prepare sink must expose the controller '
            'as the PracticeSessionHost — not a logger (ADR 0111 §1).',
      );
      final initialState = host!.state;
      expect(
        initialState.status,
        isNot(PracticeSessionStatus.idle),
        reason:
            'A1: the controller is wired with real dependencies; '
            'the initial state must show preparation already in flight.',
      );

      // Subscribe to the state stream to verify it actually emits.
      final states = <PracticeSessionState>[];
      final stateSub = host.states.listen(states.add);
      addTearDown(() async => stateSub.cancel());

      // Drive the session through to the completed terminal.
      await _driveToCompleted(host);

      // 1. terminal — the state stream must contain a `completed`
      // snapshot at the end.
      expect(
        host.state.status,
        PracticeSessionStatus.completed,
        reason: 'A5.2: the session reached a terminal status.',
      );
      expect(
        states.last.status,
        PracticeSessionStatus.completed,
        reason:
            'A5.2: the terminal status was actually emitted on '
            'the state stream — not only the final `host.state` getter.',
      );

      // 2. history — the recorder wrote one loadable record (A5.3 +
      // A3 round-trip).
      //
      // `PracticeSessionHost.send` is `void` by contract (A2: the screen
      // layer fires commands without awaiting a controller Future) — the
      // controller emits the `completed` state on `_statesController` and
      // only THEN awaits `_finalizeSession`'s `recorder.record()` call
      // (`practice_session_controller.dart` `_applySideEffects`). Observing
      // `completed` on the state stream therefore does not imply the write
      // has landed yet; polling for the record is the wired sink's actual
      // contract, not a fixed delay (E02-R21 H4, measured after the Update 8
      // provider-alias fix: the timeout disappeared and this race surfaced
      // as the next genuine failure).
      final repository = container.read(practiceHistoryRepositoryProvider);
      final loaded = await _waitForHistoryRecord(repository);
      expect(loaded, isA<Success<List<PracticeHistoryEntry>>>());
      final records = (loaded as Success<List<PracticeHistoryEntry>>).value;
      expect(
        records,
        isNotEmpty,
        reason: 'A5.3: the wired recorder wrote at least one record.',
      );
      // Round-trip: the serializer must read back the same record the
      // mapper wrote. The mode/source/definitionId codes come from the
      // real PracticeDefinition, NOT the placeholder `*.unknown`
      // strings (A3 / ADR 0084 B2).
      final written = records.single;
      expect(
        written.modeCode,
        PracticeMode.strumPattern.code,
        reason:
            'A3: the wired recorder used the real mode code, not '
            'the placeholder "practice.mode.unknown".',
      );
      expect(
        written.sourceCode,
        PracticeSource.builtin.code,
        reason: 'A3: the wired recorder used the real source code.',
      );
      expect(
        written.definitionId,
        definition.id,
        reason: 'A3: the wired recorder used the real definition id.',
      );
      final json = const PracticeHistorySerializer().toJson(written);
      final roundTripped = const PracticeHistorySerializer().fromJson(json);
      expect(roundTripped, written, reason: 'A3 round-trip.');

      // 3. resource shutdown — the leak counters on the platform
      // fakes must be zero (A5.4).
      final engine = container.read(strumEngineProvider) as FakeStrumEngine;
      final permissions =
          container.read(microphonePermissionGatewayProvider)
              as FakeMicrophonePermissionGateway;
      expect(
        engine.stopCalls,
        engine.startCalls,
        reason:
            'A5.4: the gateway started/stopped the engine the same '
            'number of times (every start was followed by a stop).',
      );
      expect(
        permissions.requestCalls,
        0,
        reason:
            'A5.4: the permission gateway was already granted — no '
            'extra request issued in the success path.',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Container factory
// ---------------------------------------------------------------------------

ProviderContainer _buildContainer() {
  final engine = FakeStrumEngine();
  final permissions = FakeMicrophonePermissionGateway();
  return ProviderContainer(
    overrides: [
      preferenceStoreOverride(InMemoryKeyValueStore()),
      appConfigProvider.overrideWithValue(_prodLikeConfig()),
      // Platform-boundary overrides — brief allows fakes at the edge. These
      // MUST be the real providers the production wiring watches
      // (`strumEngineProvider` / `microphonePermissionGatewayProvider`), not
      // test-local aliases — a private alias never reaches the controller,
      // which then falls through to the real platform gateway and times out
      // under `flutter test` (E02-R21 H4, docs/reviews/e02-r21-review.md
      // Update 8).
      strumEngineProvider.overrideWithValue(engine),
      microphonePermissionGatewayProvider.overrideWithValue(permissions),
      appLoggerProvider.overrideWithValue(const _NoopLogger()),
    ],
  );
}

class _NoopLogger implements AppLogger {
  const _NoopLogger();
  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}
  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {}
  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {}
  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {}
}

// ---------------------------------------------------------------------------
// Drive the controller from `preparing` → `completed`.
// ---------------------------------------------------------------------------

Future<void> _driveToCompleted(PracticeSessionHost host) async {
  // Wait for the preparation reducer to settle.
  await _waitForStatus(host, const {
    PracticeSessionStatus.ready,
    PracticeSessionStatus.permissionRequired,
  });
  // User accepts the prepared target.
  host.send(const StartPractice());
  await _waitForStatus(host, const {PracticeSessionStatus.running});
  // User finishes the session.
  host.send(const FinishPractice());
  await _waitForStatus(host, const {PracticeSessionStatus.completed});
}

Future<void> _waitForStatus(
  PracticeSessionHost host,
  Set<PracticeSessionStatus> target,
) async {
  if (target.contains(host.state.status)) return;
  await host.states
      .firstWhere((state) => target.contains(state.status))
      .timeout(const Duration(seconds: 5));
}

/// Polls the repository until it holds a loadable, non-empty record, or
/// gives up after 5 seconds. See the call site for why the `completed`
/// state alone does not prove the write has landed.
Future<AppResult<List<PracticeHistoryEntry>>> _waitForHistoryRecord(
  PracticeHistoryRepository repository,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    final loaded = await repository.load();
    final isNonEmptySuccess =
        loaded is Success<List<PracticeHistoryEntry>> &&
        loaded.value.isNotEmpty;
    if (isNonEmptySuccess || DateTime.now().isAfter(deadline)) {
      return loaded;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

PracticeDefinition _definition() {
  return PracticeDefinition(
    id: 'wiring.test.definition',
    schemaVersion: 1,
    titleKey: 'wiring.test.title',
    descriptionKey: 'wiring.test.desc',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    meter: const Meter(beatsPerBar: 4),
    defaultTempo: const Tempo(120),
    totalBeats: BeatPosition.quarters(8),
    events: <PracticeEvent>[
      PracticeEvent(
        id: 'wiring.test.e0',
        position: BeatPosition.fromTicks(0),
        direction: StrumDirection.down,
      ),
      PracticeEvent(
        id: 'wiring.test.e1',
        position: BeatPosition.fromTicks(4 * 480),
        direction: StrumDirection.up,
      ),
    ],
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: const ['wiring-test'],
    displayTitle: 'Wiring test',
  );
}

AppConfig _prodLikeConfig() {
  return AppConfig.resolve(
    environment: AppEnvironment.development,
    apiBaseUrl: AppConfig.devApiBaseUrl,
    flags: const FeatureFlags(
      accountEnabled: false,
      diagnosticsEnabled: false,
      labModeAvailable: false,
      practiceEngineV2Enabled: true,
      practiceDetailedHistoryEnabled: true,
    ),
    diagnosticsToken: AppConfig.devDiagnosticsToken,
    buildMode: 'debug',
    appVersion: 'test',
  );
}
