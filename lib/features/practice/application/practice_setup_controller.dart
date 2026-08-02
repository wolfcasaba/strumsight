/// Setup screen state machine + the `PreparePractice` sink boundary
/// (ADR 0078 §5, E02-R12).
///
/// The Setup screen edits a [PracticeSessionConfig] seeded from one
/// [PracticeDefinition]. Domain validation
/// ([`PracticeSessionConfig.validate`]) is the single source of truth for
/// every limit — the UI does NOT carry its own copy of any min/max. The
/// Start action emits a [`PreparePractice`] command through an injectable
/// sink ([`practicePrepareSinkProvider`]); the production default is a
/// logger (the session controller lands in Kör 13 and swaps the same
/// provider). The controller imports NO `flutter/material.dart` and
/// references NO `BuildContext` (A9 guard).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/model/practice_definition.dart';
import '../domain/model/practice_session_config.dart';
import '../domain/model/practice_validation.dart';
import '../domain/model/tempo.dart';
import 'practice_session_command.dart';
import 'practice_session_providers.dart';

/// One boundary call from the Setup UI to the session runtime.
///
/// The function takes the compiled [`PreparePractice`] command and is
/// invoked at most once per valid Start tap. The production default logs
/// the command's fields via [`appLoggerProvider`]; Kör 13 replaces it with
/// the auto-dispose session controller.
typedef PracticePrepareSink = void Function(PreparePractice command);

/// Production [`PracticePrepareSink`] (E02-R21, ADR 0111 §2). The Setup
/// screen hands the validated [PreparePractice] command to this sink; the
/// sink activates the auto-dispose controller family for the matching
/// `(definition, config)` pair and dispatches the command through it.
///
/// The activation writes to [practiceActiveSessionInputsProvider] so the
/// presentation layer's [practiceSessionHostProvider] can publish the
/// controller as a [PracticeSessionHost]. Both writes are non-async — the
/// reducer transitions `idle → preparing` synchronously on `PreparePractice`,
/// so the host observable in the next microtask already carries a non-idle
/// status.
PracticePrepareSink _activateSessionSink(Ref ref) {
  return (command) {
    final inputs = (definition: command.definition, config: command.config);
    ref.read(practiceActiveSessionInputsProvider.notifier).activate(inputs);
    final controller = ref.read(practiceSessionControllerProvider(inputs));
    controller.dispatch(command);
  };
}

/// The shared [`PracticePrepareSink`]. Override in tests with a recording
/// fake to assert what the Setup screen sent.
final practicePrepareSinkProvider = Provider<PracticePrepareSink>((ref) {
  return _activateSessionSink(ref);
});

/// The mutable Setup state for one [PracticeDefinition]. Holds the
/// candidate [PracticeSessionConfig] plus the helper accessors the screen
/// uses to drive the Start button and its localized error message.
final class PracticeSetupState {
  const PracticeSetupState({required this.definition, required this.config});

  /// The definition the Setup screen is configuring.
  final PracticeDefinition definition;

  /// The candidate config — every setter returns a new instance.
  final PracticeSessionConfig config;

  /// The full list of validation problems for [config]. UI maps the first
  /// failure's [PracticeValidationFailure.code] to an ARB key.
  List<PracticeValidationFailure> get failures => config.validate();

  /// True iff [`failures`] is empty — the screen disables Start otherwise.
  bool get isValid => failures.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PracticeSetupState &&
          other.definition == definition &&
          other.config == config;

  @override
  int get hashCode => Object.hash(definition, config);
}

/// Seeds a [`PracticeSessionConfig`] from a [PracticeDefinition] (ADR 0078
/// §4). The defaults are the minimums for the numeric fields, except for
/// the definition-derived ones; the meter is read-only and is not part of
/// the config.
PracticeSessionConfig _seedConfigFromDefinition(PracticeDefinition definition) {
  return PracticeSessionConfig(
    definitionId: definition.id,
    definitionSnapshotVersion: definition.schemaVersion,
    effectiveTempo: definition.defaultTempo,
    countInBars: PracticeSessionConfig.minimumCountInBars,
    loopCount: PracticeSessionConfig.minimumLoopCount,
    metronomeEnabled: true,
    accentEnabled: false,
    backingEnabled: false,
    scoringProfileId: definition.scoringProfile.id,
    inputLatency: Duration.zero,
    visualLatency: Duration.zero,
    expectedChordHintEnabled: false,
    sessionTimeout: const Duration(minutes: 5),
    reducedMotion: false,
  );
}

/// The Setup screen's `Notifier`. Parameterised on the [PracticeDefinition]
/// being configured so the same controller shape serves every catalog entry
/// (and is deterministically rebuilt if the definition changes).
class PracticeSetupController extends Notifier<PracticeSetupState> {
  /// The definition this controller was created for. The Riverpod family
  /// factory (below) closes over the arg and stores it on the instance.
  PracticeSetupController(this.definition);

  final PracticeDefinition definition;

  @override
  PracticeSetupState build() {
    return PracticeSetupState(
      definition: definition,
      config: _seedConfigFromDefinition(definition),
    );
  }

  /// Updates the candidate tempo. The domain validator accepts only
  /// [Tempo.minimumBpm]..[Tempo.maximumBpm]; the screen shows the
  /// resulting failure code via [`PracticeSetupState.failures`].
  void setTempoBpm(double bpm) {
    state = PracticeSetupState(
      definition: state.definition,
      config: state.config.copyWith(effectiveTempo: Tempo(bpm)),
    );
  }

  /// Updates the count-in bars. [PracticeSessionConfig] clamps via
  /// [`PracticeSessionConfig.validate`], not here.
  void setCountInBars(int bars) {
    state = PracticeSetupState(
      definition: state.definition,
      config: state.config.copyWith(countInBars: bars),
    );
  }

  /// Updates the loop count. Same rule as count-in bars.
  void setLoopCount(int count) {
    state = PracticeSetupState(
      definition: state.definition,
      config: state.config.copyWith(loopCount: count),
    );
  }

  /// Toggles the metronome. The domain config carries the value verbatim.
  void setMetronomeEnabled(bool value) {
    state = PracticeSetupState(
      definition: state.definition,
      config: state.config.copyWith(metronomeEnabled: value),
    );
  }

  /// Toggles the count-1 accent.
  void setAccentEnabled(bool value) {
    state = PracticeSetupState(
      definition: state.definition,
      config: state.config.copyWith(accentEnabled: value),
    );
  }

  /// Toggles the expected-chord hint (the A5 rhythm-only control).
  void setChordHintEnabled(bool value) {
    state = PracticeSetupState(
      definition: state.definition,
      config: state.config.copyWith(expectedChordHintEnabled: value),
    );
  }

  /// The first failure code (or `null` when the config is valid). The
  /// screen uses it to pick which localized error to show next to the
  /// Start button.
  String? get firstFailureCode {
    final first = state.failures.isEmpty ? null : state.failures.first;
    return first?.code;
  }

  /// Sends the command through [`practicePrepareSinkProvider`] if the
  /// config is valid. Returns `true` when the command was sent, `false`
  /// when the config was invalid (the screen disables Start in that
  /// case — this branch is a defensive guard for the few tests that
  /// still want to call it programmatically).
  bool start() {
    if (!state.isValid) return false;
    final command = PreparePractice(
      definition: state.definition,
      config: state.config,
    );
    ref.read(practicePrepareSinkProvider).call(command);
    return true;
  }
}

final practiceSetupControllerProvider =
    NotifierProvider.family<
      PracticeSetupController,
      PracticeSetupState,
      PracticeDefinition
    >(PracticeSetupController.new);
