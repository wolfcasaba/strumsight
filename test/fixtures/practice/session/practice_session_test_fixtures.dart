// Shared fixtures for the E13-R21 practice-session UI test files under
// `test/features/practice/session/`. Kept in `test/fixtures/practice/session/`
// (round brief §4/allowed_paths) so the four new test files don't each
// hand-roll their own copy of the same fake host and fixture definition.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/platform/app_lifecycle.dart';
import 'package:strumsight/features/practice/application/practice_session_command.dart';
import 'package:strumsight/features/practice/application/practice_session_effect.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';

/// A fixture [PracticeDefinition] — strum-pattern mode, 4/4, 16 quarter-note
/// down-strums. Deterministic and self-contained; nothing here is load
/// bearing for the runtime session, only for shape (id, mode, meter).
PracticeDefinition practiceSessionFixtureDefinition({
  String id = 'fixture.session-ui',
}) => PracticeDefinition(
  id: id,
  schemaVersion: 1,
  titleKey: 'practiceCatalogTestSetupTitle',
  descriptionKey: 'practiceCatalogTestSetupDescription',
  mode: PracticeMode.strumPattern,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(100),
  totalBeats: BeatPosition.quarters(16),
  events: List<PracticeEvent>.unmodifiable([
    for (var i = 0; i < 16; i++)
      PracticeEvent(
        id: '$id.e$i',
        position: BeatPosition.quarters(i),
        direction: StrumDirection.down,
      ),
  ]),
  scoringProfile: ScoringProfile.legacyLearnParity,
  skillTags: const ['session-ui-fixture'],
  displayTitle: 'Session UI fixture',
);

/// A valid, in-range fixture [PracticeSessionConfig] for
/// [practiceSessionFixtureDefinition].
PracticeSessionConfig practiceSessionFixtureConfig({
  String definitionId = 'fixture.session-ui',
  int countInBars = 1,
  int loopCount = 1,
}) => PracticeSessionConfig(
  definitionId: definitionId,
  definitionSnapshotVersion: 1,
  effectiveTempo: const Tempo(100),
  countInBars: countInBars,
  loopCount: loopCount,
  metronomeEnabled: true,
  accentEnabled: false,
  backingEnabled: false,
  scoringProfileId: 'legacyLearnParity',
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: true,
  sessionTimeout: const Duration(minutes: 10),
  reducedMotion: false,
);

/// Builds a [PracticeSessionState] snapshot for one [status], with the
/// commonly-varied fields exposed as named parameters. Every other field
/// keeps [PracticeSessionState]'s own default.
PracticeSessionState practiceSessionStateFor(
  PracticeSessionStatus status, {
  PracticeDefinition? definition,
  PracticeSessionConfig? config,
  int attemptIndex = 0,
  int countInSpanBeats = 0,
  int emittedCountInClicks = 0,
  Duration activeElapsed = Duration.zero,
  PauseCause? pauseCause,
}) => PracticeSessionState(
  status: status,
  definition: definition,
  config: config,
  attemptIndex: attemptIndex,
  countInSpanBeats: countInSpanBeats,
  emittedCountInClicks: emittedCountInClicks,
  activeElapsed: activeElapsed,
  pauseCause: pauseCause,
);

/// A fully controllable [PracticeSessionHost] test double. Every one of the
/// four new session-UI test files drives the presentation layer through
/// this fake rather than a real [PracticeSessionController] — the
/// controller's own dedup/threshold guarantees are already covered by
/// `test/features/practice/application/practice_session_*_test.dart`; these
/// tests prove the UI layer faithfully reflects (and does not duplicate)
/// what the fake reports.
class FakeSessionHost implements PracticeSessionHost {
  final StreamController<PracticeSessionState> _statesController =
      StreamController<PracticeSessionState>.broadcast();
  final StreamController<PracticeSessionEffect> _effectsController =
      StreamController<PracticeSessionEffect>.broadcast();

  /// Every command the presentation layer has sent, in order.
  final List<PracticeSessionCommand> sent = <PracticeSessionCommand>[];

  int? liveScore;
  PracticeSessionState _state = PracticeSessionState.initial;

  @override
  Stream<PracticeSessionState> get states => _statesController.stream;

  @override
  PracticeSessionState get state => _state;

  @override
  Stream<PracticeSessionEffect> get effects => _effectsController.stream;

  @override
  int? get liveOverallPerMille => liveScore;

  @override
  void send(PracticeSessionCommand command) => sent.add(command);

  void emitState(PracticeSessionState state) {
    _state = state;
    _statesController.add(state);
  }

  void emitEffect(PracticeSessionEffect effect) =>
      _effectsController.add(effect);

  Future<void> close() async {
    await _statesController.close();
    await _effectsController.close();
  }
}

/// Drivable app lifecycle double — duplicated here (rather than imported
/// from `test/support/fake_audio.dart`) because that file pulls in the
/// full `core/audio` fixture surface (mic capture, wakelock, coordinator)
/// that these presentation-only tests don't need.
class FakeLifecycleEvents implements AppLifecycleEvents {
  final List<void Function(AppLifecycleState)> listeners = [];

  @override
  void addListener(void Function(AppLifecycleState state) listener) =>
      listeners.add(listener);

  @override
  void removeListener(void Function(AppLifecycleState state) listener) =>
      listeners.remove(listener);

  @override
  void dispose() {}

  void emit(AppLifecycleState state) {
    for (final listener in List.of(listeners)) {
      listener(state);
    }
  }
}
