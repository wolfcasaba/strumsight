// Riverpod bindings for the practice-session runtime — the controller and its
// injectable dependencies (ADR 0077, E02-R11 brief §5.1).
//
// This file wires the **production-default** implementations that the Kör 12/13
// UI will read. Tests inject fakes directly into the controller constructor,
// bypassing the provider graph.
//
// What this file wires:
//   - clock           MonotonicPracticeSessionClock (Stopwatch-backed)
//   - tickSource      TimerPracticeTickSource (16 ms period)
//   - recorder        NoopPracticeSessionRecorder (Kör 18 will replace)
//   - sessionIdFactory monotonically incrementing 'ps-<n>'
//   - observationConfig default 0.55 / 0.60 / 180 ms / 500 ms
//   - compileTarget   the R06 compilePracticeTarget function
//   - logger          core `appLoggerProvider` (direct import)
//
// The `PracticeObservationGateway` provider is intentionally NOT defined here:
// its production implementation lives in `lib/features/practice/data/` and
// depends on the strum engine + the audio session lease. That wiring belongs
// to the E02-R13 pre-flight, where the first real Live → Practice caller
// lands. Tests inject the gateway directly into the controller.
//
// Forbidden under the ADR 0077 §10 / R10d / R13 revízió: this file MUST NOT
// reference `AudioSessionCoordinator`, `audioSessionCoordinatorProvider`,
// `StrumEngine(`, `BuildContext`, `Navigator`, `GoRouter`,
// `SharedPreferences`, `dart:ui`, or `DateTime.now(`. The A9 layer-purity
// guard asserts this.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../../app/config/app_config.dart';
import '../../../core/audio/audio_providers.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../core/platform/microphone_permission.dart';
import '../data/local_practice_history_repository.dart';
import '../data/practice_history_recorder.dart';
import '../data/practice_observation_gateway_provider.dart';
import '../data/practice_session_result_history_mapper.dart';
import '../domain/model/compiled_practice_target.dart';
import '../domain/model/practice_definition.dart';
import '../domain/model/practice_session_config.dart';
import '../domain/repository/practice_history_repository.dart';
import '../domain/repository/practice_session_recorder.dart';
import '../domain/service/practice_target_compiler.dart';
import 'practice_observation_gateway.dart';
import 'practice_session_clock.dart';
import 'practice_session_controller.dart';
import 'practice_tick_source.dart';

/// The clock every practice session starts with. Production uses the
/// monotonic Stopwatch-backed implementation; tests override with the fake.
final practiceSessionClockProvider = Provider<PracticeSessionClock>(
  (_) => MonotonicPracticeSessionClock(),
);

/// Production tick source — a 16 ms periodic timer (≈60 Hz, the legacy
/// cadence). Tests override with [FakePracticeTickSource] for determinism.
final practiceTickSourceProvider = Provider<PracticeTickSource>(
  (_) => TimerPracticeTickSource(),
);

/// Default persistence boundary. Kör 18 ships the real recorder backed by
/// the versioned [PracticeHistoryRepository]; the controller's finish path
/// reads through this provider.
///
/// The recorder is wired with **placeholder** mode/source/definition codes
/// today — the controller does not surface the session's
/// `PracticeSessionConfig`, so the real metadata plumbing belongs to R19.
/// Until then, the persistence layer MUST NOT write records the serializer
/// would reject on read (a write-then-drop trap, see brief B2): the provider
/// resolves to a [NoopPracticeSessionRecorder] whenever the wired codes are
/// still the placeholders, so a production record() returns `Success` without
/// writing anything that would be discarded by the reader.
final practiceSessionRecorderProvider = Provider<PracticeSessionRecorder>((
  ref,
) {
  final repository = ref.watch(practiceHistoryRepositoryProvider);
  final detailed = ref.watch(
    appConfigProvider.select((cfg) => cfg.flags.practiceDetailedHistoryEnabled),
  );
  const modeCode = 'practice.mode.unknown';
  const sourceCode = 'practice.source.unknown';
  const definitionId = 'practice.definition.unknown';
  if (_isPlaceholderMetadata(
    modeCode: modeCode,
    sourceCode: sourceCode,
    definitionId: definitionId,
  )) {
    // R19: real session metadata plumbing — when the controller exposes
    // `PracticeSessionConfig`, this branch disappears and the real recorder
    // writes loadable records. Today, the real recorder would emit records
    // the reader drops (unknown enum code → JsonRecordException), so we
    // intentionally return the no-op recorder instead.
    return const NoopPracticeSessionRecorder();
  }
  return PracticeHistoryRecorder(
    repository: repository,
    mapperFactory: () => PracticeSessionResultHistoryMapper(
      now: DateTime.now,
      detailEnabled: detailed,
      modeCode: modeCode,
      sourceCode: sourceCode,
      definitionId: definitionId,
      displayTitle: '',
      skillTags: const <String>[],
    ),
  );
});

/// True when the wired session metadata still uses the R18 placeholder
/// values. Exposed at library scope so the B2 test can prove the wiring is
/// locked behind the same gate as the live provider.
@visibleForTesting
bool isPlaceholderPracticeMetadata({
  required String modeCode,
  required String sourceCode,
  required String definitionId,
}) => _isPlaceholderMetadata(
  modeCode: modeCode,
  sourceCode: sourceCode,
  definitionId: definitionId,
);

bool _isPlaceholderMetadata({
  required String modeCode,
  required String sourceCode,
  required String definitionId,
}) {
  return modeCode == 'practice.mode.unknown' ||
      sourceCode == 'practice.source.unknown' ||
      definitionId == 'practice.definition.unknown';
}

/// Deterministic-then-monotonic session-id factory. Defaults to a
/// counter-based factory so production builds get unique ids while tests
/// can override it for value-equality.
final practiceSessionIdFactoryProvider = Provider<String Function()>((_) {
  var counter = 0;
  return () {
    counter++;
    return 'ps-$counter';
  };
});

/// The default observation configuration. The controller holds this
/// instance — its `chordStableDuration` is also fed to the chord scorer
/// (ADR 0077 §4 / brief A8).
final practiceObservationConfigProvider = Provider<PracticeObservationConfig>(
  (_) => const PracticeObservationConfig(),
);

/// Compiler bridge — delegates to the pure R06 [compilePracticeTarget].
/// Indirected through a provider so tests can override with a hand-built
/// target if needed. The compiler returns its [AppResult] synchronously;
/// the controller surface requires a `Future`, so the closure wraps it in
/// `Future.value`.
final practiceCompileTargetProvider =
    Provider<
      Future<AppResult<CompiledPracticeTarget>> Function(
        PracticeDefinition definition,
        PracticeSessionConfig config,
      )
    >((_) {
      return (definition, config) => Future.value(
        compilePracticeTarget(definition: definition, config: config),
      );
    });

/// The shared logger for practice-session diagnostics. Aliases the core
/// provider under a feature-namespace name.
final practiceSessionLoggerProvider = Provider<AppLogger>(
  (ref) => ref.watch(appLoggerProvider),
);

/// Alias of the core microphone-permission provider under the practice
/// feature namespace, for symmetry with [practiceSessionLoggerProvider].
final practiceMicrophonePermissionProvider =
    Provider<MicrophonePermissionGateway>(
      (ref) => ref.watch(microphonePermissionGatewayProvider),
    );

// ---------------------------------------------------------------------------
// E02-R21 — production controller wiring (ADR 0111 §1–§4)
// ---------------------------------------------------------------------------

/// The session inputs that parameterise the auto-dispose controller family
/// (A1, ADR 0111 §1). Two fields — the definition being configured and the
/// user-edited config — are the complete "session identity" the rest of the
/// wiring observes.
///
/// Records are value-equal in Dart 3; both [PracticeDefinition] and
/// [PracticeSessionConfig] define their own `==`/`hashCode` so a Riverpod
/// family keyed on this record treats equivalent inputs as one session.
typedef PracticeSessionInputs = ({
  PracticeDefinition definition,
  PracticeSessionConfig config,
});

/// The active session identity (A2 host bridge, ADR 0111 §2). The prepare
/// sink writes here after the Setup dispatches `PreparePractice`; the host
/// provider reads it to expose the controller to the screen layer.
///
/// AutoDispose: when the screen unmounts, the inputs are cleared so a stale
/// session cannot leak into the next setup.
class PracticeActiveSessionInputsController
    extends Notifier<PracticeSessionInputs?> {
  @override
  PracticeSessionInputs? build() => null;

  /// Set the active session identity. Called by the prepare sink after the
  /// Setup dispatches `PreparePractice` through the wired sink.
  void activate(PracticeSessionInputs inputs) => state = inputs;

  /// Clear the active session identity. Called when the host tears down
  /// (screen unmount, terminal state cleanup) so a stale session does not
  /// leak into the next setup.
  void clear() => state = null;
}

final practiceActiveSessionInputsProvider =
    NotifierProvider.autoDispose<
      PracticeActiveSessionInputsController,
      PracticeSessionInputs?
    >(PracticeActiveSessionInputsController.new);

/// The auto-dispose controller family (A1, ADR 0111 §1). One instance per
/// `(definition, config)` pair — the prepare sink reads the family with the
/// Setup's `PreparePractice` payload, and the host provider keeps the
/// controller alive while the screen watches it.
///
/// The recorder is built here with the **real** mode/source/definition codes
/// from the session definition (A3, ADR 0111 §3). The placeholder-gated
/// provider above still guards direct reads without session context so the
/// B2 write-then-drop trap stays sealed.
final practiceSessionControllerProvider = Provider.autoDispose
    .family<PracticeSessionController, PracticeSessionInputs>((ref, inputs) {
      final repository = ref.watch(practiceHistoryRepositoryProvider);
      final detailed = ref.watch(
        appConfigProvider.select(
          (cfg) => cfg.flags.practiceDetailedHistoryEnabled,
        ),
      );
      final recorder = PracticeHistoryRecorder(
        repository: repository,
        mapperFactory: () => PracticeSessionResultHistoryMapper(
          now: DateTime.now,
          detailEnabled: detailed,
          modeCode: inputs.definition.mode.code,
          sourceCode: inputs.definition.source.code,
          definitionId: inputs.definition.id,
          displayTitle: inputs.definition.displayTitle ?? '',
          skillTags: inputs.definition.skillTags,
        ),
      );
      final clock = ref.watch(practiceSessionClockProvider);
      final tickSource = ref.watch(practiceTickSourceProvider);
      final logger = ref.watch(practiceSessionLoggerProvider);
      final permissions = ref.watch(practiceMicrophonePermissionProvider);
      final observationConfig = ref.watch(practiceObservationConfigProvider);
      final sessionIdFactory = ref.watch(practiceSessionIdFactoryProvider);
      final compileTarget = ref.watch(practiceCompileTargetProvider);
      final observationGateway = ref.watch(
        livePracticeObservationGatewayProvider,
      );
      final controller = PracticeSessionController(
        clock: clock,
        tickSource: tickSource,
        recorder: recorder,
        logger: logger,
        permissions: permissions,
        observationConfig: observationConfig,
        sessionIdFactory: sessionIdFactory,
        compileTarget: compileTarget,
        observationGateway: observationGateway,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });
