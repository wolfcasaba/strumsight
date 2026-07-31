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

import '../../../core/audio/audio_providers.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/logger_provider.dart';
import '../../../core/platform/microphone_permission.dart';
import '../domain/model/compiled_practice_target.dart';
import '../domain/model/practice_definition.dart';
import '../domain/model/practice_session_config.dart';
import '../domain/repository/practice_session_recorder.dart';
import '../domain/service/practice_target_compiler.dart';
import 'practice_observation_gateway.dart';
import 'practice_session_clock.dart';
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

/// Default persistence boundary. Kör 18 swaps this for a real repository;
/// until then the no-op returns `Success` without writing.
final practiceSessionRecorderProvider = Provider<PracticeSessionRecorder>(
  (_) => const NoopPracticeSessionRecorder(),
);

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

// Note: `practiceSessionControllerProvider` itself is **not** defined here.
// The controller is short-lived — one provider creates, one session runs,
// then disposed — and parameterised on session inputs that Kör 12/13 will
// collect. The Kör 13 pre-flight will define the auto-dispose `family`
// with the configuration parameters wired in. Stay tuned.
