// R13 (audit §5.2 "Song trainer sebesség-slider, pontozott munkamenet").
//
// A mid-session tempo change may not rewrite the part of the timeline the
// session has already played — verdicts were judged against those
// placements. `rescalePracticeTarget` is therefore the affine map about the
// bar boundary the session sits on, and these are its measured guarantees:
//
// S1 — everything at or before the pivot keeps its placement; everything
//      after it moves by the tempo ratio (both slower and faster).
// S2 — the derived durations stay consistent (countIn + musical + ringOut ==
//      total) and the compiled order survives.
// S3 — an unchanged tempo is exactly the identity.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_config.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_target_compiler.dart';
import 'package:strumsight/features/practice/domain/service/practice_target_rescaler.dart';

void main() {
  group('rescalePracticeTarget', () {
    test('S0 — the fixture the other cells are read against', () {
      final target = _target();

      expect(target.countInDuration, const Duration(seconds: 2));
      expect(
        target.events.map((event) => event.time).toList(),
        const <Duration>[Duration(seconds: 2), Duration(seconds: 4)],
      );
      expect(target.musicalDuration, const Duration(seconds: 4));
      expect(target.ringOutDuration, const Duration(seconds: 2));
      expect(target.totalDuration, const Duration(seconds: 8));
      expect(target.barBoundaries, const <Duration>[
        Duration.zero,
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 6),
      ]);
    });

    test('S1 — half tempo keeps the past and doubles the future', () {
      final target = _target();

      final rescaled = rescalePracticeTarget(
        target: target,
        tempo: const Tempo(60),
        position: const Duration(milliseconds: 2500),
      );

      // The bar boundary at or before 2.5 s — the anchor `ResumePractice`
      // re-enters the timeline on.
      expect(rescaled.pivot, const Duration(seconds: 2));
      expect(rescaled.position, const Duration(seconds: 3));
      expect(rescaled.target.tempo, const Tempo(60));
      expect(
        rescaled.target.events.map((event) => event.time).toList(),
        const <Duration>[Duration(seconds: 2), Duration(seconds: 6)],
      );
      expect(rescaled.target.countInDuration, const Duration(seconds: 2));
      expect(rescaled.target.musicalDuration, const Duration(seconds: 8));
      expect(rescaled.target.ringOutDuration, const Duration(seconds: 4));
      expect(rescaled.target.totalDuration, const Duration(seconds: 14));
      expect(rescaled.target.barBoundaries, const <Duration>[
        Duration.zero,
        Duration(seconds: 2),
        Duration(seconds: 6),
        Duration(seconds: 10),
      ]);
      // Event identity is untouched — only the placements move.
      expect(
        rescaled.target.events.map((event) => event.sourceEventId).toList(),
        target.events.map((event) => event.sourceEventId).toList(),
      );
      expect(
        rescaled.target.events.map((event) => event.position).toList(),
        target.events.map((event) => event.position).toList(),
      );
    });

    test('S1b — double tempo halves what is still to come', () {
      final target = _target();

      final rescaled = rescalePracticeTarget(
        target: target,
        tempo: const Tempo(240),
        position: const Duration(milliseconds: 2500),
      );

      expect(rescaled.pivot, const Duration(seconds: 2));
      expect(rescaled.position, const Duration(milliseconds: 2250));
      expect(
        rescaled.target.events.map((event) => event.time).toList(),
        const <Duration>[Duration(seconds: 2), Duration(seconds: 3)],
      );
      expect(rescaled.target.totalDuration, const Duration(seconds: 5));
      expect(rescaled.target.barBoundaries, const <Duration>[
        Duration.zero,
        Duration(seconds: 2),
        Duration(seconds: 3),
        Duration(seconds: 4),
      ]);
    });

    test('S2 — the derived durations and the compiled order survive', () {
      final target = _target();

      for (final tempo in const <Tempo>[Tempo(60), Tempo(90), Tempo(240)]) {
        final rescaled = rescalePracticeTarget(
          target: target,
          tempo: tempo,
          position: const Duration(milliseconds: 2500),
        ).target;

        expect(
          rescaled.countInDuration +
              rescaled.musicalDuration +
              rescaled.ringOutDuration,
          rescaled.totalDuration,
          reason: 'derived durations must still add up at ${tempo.bpm}',
        );
        for (var index = 1; index < rescaled.events.length; index++) {
          expect(
            rescaled.events[index].time >= rescaled.events[index - 1].time,
            isTrue,
            reason: 'event order broke at ${tempo.bpm}',
          );
        }
        for (var index = 1; index < rescaled.barBoundaries.length; index++) {
          expect(
            rescaled.barBoundaries[index] > rescaled.barBoundaries[index - 1],
            isTrue,
            reason: 'bar boundary order broke at ${tempo.bpm}',
          );
        }
        expect(rescaled.events.length, target.events.length);
        expect(
          rescaled.expectedChordSegments.length,
          target.expectedChordSegments.length,
        );
        final ratio = target.tempo.bpm / tempo.bpm;
        final segments = target.expectedChordSegments;
        for (var index = 0; index < segments.length; index++) {
          expect(
            rescaled.expectedChordSegments[index].start,
            _map(segments[index].start, ratio),
            reason: 'chord segment start at ${tempo.bpm}',
          );
          expect(
            rescaled.expectedChordSegments[index].end,
            _map(segments[index].end, ratio),
            reason: 'chord segment end at ${tempo.bpm}',
          );
        }
      }
    });

    test('S3 — an unchanged tempo is the identity', () {
      final target = _target();

      final rescaled = rescalePracticeTarget(
        target: target,
        tempo: const Tempo(120),
        position: const Duration(milliseconds: 2500),
      );

      expect(rescaled.target, target);
      expect(rescaled.position, const Duration(milliseconds: 2500));
    });

    test('S4 — a position before the first boundary pivots on zero', () {
      final target = _target();

      final rescaled = rescalePracticeTarget(
        target: target,
        tempo: const Tempo(60),
        position: const Duration(milliseconds: 500),
      );

      expect(rescaled.pivot, Duration.zero);
      expect(rescaled.position, const Duration(seconds: 1));
      expect(rescaled.target.countInDuration, const Duration(seconds: 4));
      expect(rescaled.target.totalDuration, const Duration(seconds: 16));
    });
  });
}

const Duration _pivot = Duration(seconds: 2);

Duration _map(Duration time, double ratio) =>
    time <= _pivot ? time : _pivot + (time - _pivot) * ratio;

CompiledPracticeTarget _target() {
  final compiled = compilePracticeTarget(
    definition: _definition,
    config: _config,
  );
  return compiled.valueOrNull!;
}

final PracticeDefinition _definition = PracticeDefinition(
  id: 'def.rescale',
  schemaVersion: 1,
  titleKey: 'def.rescale.title',
  descriptionKey: 'def.rescale.desc',
  mode: PracticeMode.chordProgression,
  source: PracticeSource.builtin,
  meter: Meter(beatsPerBar: 4),
  defaultTempo: Tempo(120),
  totalBeats: BeatPosition.fromTicks(8 * 480),
  events: <PracticeEvent>[
    PracticeEvent(
      id: 'event.0',
      position: BeatPosition.fromTicks(0),
      chord: 'C',
      direction: StrumDirection.down,
    ),
    PracticeEvent(
      id: 'event.1',
      position: BeatPosition.fromTicks(4 * 480),
      chord: 'G',
      direction: StrumDirection.up,
    ),
  ],
  scoringProfile: ScoringProfile.chordProgressionDefault,
  skillTags: <String>[],
);

final PracticeSessionConfig _config = PracticeSessionConfig(
  definitionId: _definition.id,
  definitionSnapshotVersion: _definition.schemaVersion,
  effectiveTempo: _definition.defaultTempo,
  countInBars: 1,
  loopCount: 1,
  metronomeEnabled: true,
  accentEnabled: true,
  backingEnabled: false,
  scoringProfileId: 'chordProgressionDefault',
  inputLatency: Duration.zero,
  visualLatency: Duration.zero,
  expectedChordHintEnabled: false,
  sessionTimeout: const Duration(minutes: 10),
  reducedMotion: false,
);
