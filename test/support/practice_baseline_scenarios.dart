import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/model/lesson.dart';

/// Scorer-neutral inputs that freeze the legacy Learn scoring baseline.
///
/// The legacy scorer replay owns the assertions and JSON serialization; this
/// file contains only deterministic lesson, tempo, count-in, strum, latency and
/// chord-observation data. The legacy [Lesson] is defensively copied as an
/// immutable transport snapshot; Practice Engine V2 can translate that snapshot
/// and replay this exact list without depending on the legacy replay logic.
final class PracticeBaselineScenario {
  PracticeBaselineScenario({
    required this.id,
    required Lesson lesson,
    required this.bpm,
    required this.countInBeats,
    this.inputLatencySec = 0,
    required List<PracticeBaselineStrum> strums,
    required List<PracticeBaselineChordObservation> chordObservations,
  }) : assert(countInBeats == lesson.beatsPerBar),
       lesson = Lesson.fromEvents(
         id: lesson.id,
         name: lesson.name,
         bpm: lesson.bpm,
         events: List.unmodifiable(lesson.events),
         totalBeats: lesson.totalBeats,
         difficulty: lesson.difficulty,
         beatsPerBar: lesson.beatsPerBar,
       ),
       strums = List.unmodifiable(strums),
       chordObservations = List.unmodifiable(chordObservations);

  final String id;
  final Lesson lesson;
  final double bpm;

  /// The real Learn path counts in one bar, including three beats for 3/4.
  final int countInBeats;

  /// Raw detection timestamps are corrected by this amount inside the scorer.
  final double inputLatencySec;
  final List<PracticeBaselineStrum> strums;
  final List<PracticeBaselineChordObservation> chordObservations;

  /// Mirrors the screen's one-bar ring-out before it finalizes the scorer.
  double get finishAtSec =>
      (countInBeats + lesson.totalBeats + lesson.beatsPerBar) * 60 / bpm;
}

final class PracticeBaselineStrum {
  const PracticeBaselineStrum({
    required this.elapsedSec,
    required this.direction,
    required this.targetEventIndex,
    this.frameArrivalSec,
    this.legacyMatchedEventIndex,
  }) : assert(
         legacyMatchedEventIndex == null || targetEventIndex == null,
         'A legacy-consumed extra must remain targetEventIndex: null.',
       );

  /// Timestamp passed to the scorer.
  ///
  /// For the de-jitter scenario this is already corrected by the screen. For
  /// the input-latency scenario this is the raw detection timestamp, because
  /// [PracticeBaselineScenario.inputLatencySec] is applied inside the scorer.
  final double elapsedSec;
  final StrumDirection direction;

  /// Intended target, or null for a deliberately extra strum.
  ///
  /// A non-null target can still resolve to null when the observation is
  /// outside the legacy match window.
  final int? targetEventIndex;

  /// Target consumed by legacy matching despite this being an intended extra.
  ///
  /// This stays separate from [targetEventIndex] so later V2 parity replays
  /// retain both the musical intent and today's observed matcher result.
  final int? legacyMatchedEventIndex;

  /// Frame-dispatch time for de-jitter cases.
  ///
  /// The replay advances the scorer on this clock before registering the
  /// already corrected [elapsedSec], matching the screen's ticker/attack split.
  /// Null means dispatch and observation use the same timestamp.
  final double? frameArrivalSec;
}

final class PracticeBaselineChordObservation {
  const PracticeBaselineChordObservation({
    required this.elapsedSec,
    required this.label,
  });

  final double elapsedSec;
  final String label;
}

const _down = StrumDirection.down;
const _up = StrumDirection.up;

const _quarterLesson = Lesson.fromEvents(
  id: 'baseline-quarter-pattern',
  name: 'Baseline quarter pattern',
  bpm: 60,
  totalBeats: 8,
  events: [
    LessonEvent(beat: 0, chord: 'C', direction: _down),
    LessonEvent(beat: 1, chord: 'C', direction: _down),
    LessonEvent(beat: 2, chord: 'C', direction: _down),
    LessonEvent(beat: 3, chord: 'C', direction: _down),
    LessonEvent(beat: 4, chord: 'G', direction: _down),
    LessonEvent(beat: 5, chord: 'G', direction: _down),
    LessonEvent(beat: 6, chord: 'G', direction: _down),
    LessonEvent(beat: 7, chord: 'G', direction: _down),
  ],
);

const _chordLagLesson = Lesson.fromEvents(
  id: 'baseline-chord-lag',
  name: 'Baseline chord lag',
  bpm: 60,
  totalBeats: 8,
  events: [
    LessonEvent(beat: 0, chord: 'C', direction: _down),
    LessonEvent(beat: 1, chord: 'G', direction: _down),
    LessonEvent(beat: 2, chord: 'Am', direction: _down),
    LessonEvent(beat: 3, chord: 'F', direction: _down),
    LessonEvent(beat: 4, chord: 'C', direction: _down),
    LessonEvent(beat: 5, chord: 'G', direction: _down),
    LessonEvent(beat: 6, chord: 'Am', direction: _down),
    LessonEvent(beat: 7, chord: 'F', direction: _down),
  ],
);

const _contendedEighthsLesson = Lesson.fromEvents(
  id: 'baseline-contended-eighths',
  name: 'Baseline contended eighths',
  bpm: 96,
  totalBeats: 4,
  events: [
    LessonEvent(beat: 0, chord: '', direction: _down),
    LessonEvent(beat: 0.5, chord: '', direction: _up),
    LessonEvent(beat: 1, chord: '', direction: _down),
    LessonEvent(beat: 1.5, chord: '', direction: _up),
    LessonEvent(beat: 2, chord: '', direction: _down),
    LessonEvent(beat: 2.5, chord: '', direction: _up),
    LessonEvent(beat: 3, chord: '', direction: _down),
    LessonEvent(beat: 3.5, chord: '', direction: _up),
  ],
);

const _quarterChordObservations = [
  PracticeBaselineChordObservation(elapsedSec: 3.9, label: 'C'),
  PracticeBaselineChordObservation(elapsedSec: 7.9, label: 'G'),
];

final List<PracticeBaselineScenario> legacyPracticeBaselineScenarios =
    List.unmodifiable([
      PracticeBaselineScenario(
        id: 'p44_basic_all_perfect',
        lesson: _quarterLesson,
        bpm: 60,
        countInBeats: 4,
        strums: const [
          PracticeBaselineStrum(
            elapsedSec: 4,
            direction: _down,
            targetEventIndex: 0,
          ),
          PracticeBaselineStrum(
            elapsedSec: 5,
            direction: _down,
            targetEventIndex: 1,
          ),
          PracticeBaselineStrum(
            elapsedSec: 6,
            direction: _down,
            targetEventIndex: 2,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7,
            direction: _down,
            targetEventIndex: 3,
          ),
          PracticeBaselineStrum(
            elapsedSec: 8,
            direction: _down,
            targetEventIndex: 4,
          ),
          PracticeBaselineStrum(
            elapsedSec: 9,
            direction: _down,
            targetEventIndex: 5,
          ),
          PracticeBaselineStrum(
            elapsedSec: 10,
            direction: _down,
            targetEventIndex: 6,
          ),
          PracticeBaselineStrum(
            elapsedSec: 11,
            direction: _down,
            targetEventIndex: 7,
          ),
        ],
        chordObservations: _quarterChordObservations,
      ),
      PracticeBaselineScenario(
        id: 'p44_all_late',
        lesson: _quarterLesson,
        bpm: 60,
        countInBeats: 4,
        strums: const [
          PracticeBaselineStrum(
            elapsedSec: 4.2,
            direction: _down,
            targetEventIndex: 0,
          ),
          PracticeBaselineStrum(
            elapsedSec: 5.2,
            direction: _down,
            targetEventIndex: 1,
          ),
          PracticeBaselineStrum(
            elapsedSec: 6.2,
            direction: _down,
            targetEventIndex: 2,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7.2,
            direction: _down,
            targetEventIndex: 3,
          ),
          PracticeBaselineStrum(
            elapsedSec: 8.2,
            direction: _down,
            targetEventIndex: 4,
          ),
          PracticeBaselineStrum(
            elapsedSec: 9.2,
            direction: _down,
            targetEventIndex: 5,
          ),
          PracticeBaselineStrum(
            elapsedSec: 10.2,
            direction: _down,
            targetEventIndex: 6,
          ),
          PracticeBaselineStrum(
            elapsedSec: 11.2,
            direction: _down,
            targetEventIndex: 7,
          ),
        ],
        chordObservations: _quarterChordObservations,
      ),
      PracticeBaselineScenario(
        id: 'p44_timing_tiers',
        lesson: _quarterLesson,
        bpm: 60,
        countInBeats: 4,
        strums: const [
          PracticeBaselineStrum(
            elapsedSec: 4,
            direction: _down,
            targetEventIndex: 0,
          ),
          PracticeBaselineStrum(
            elapsedSec: 5.05,
            direction: _down,
            targetEventIndex: 1,
          ),
          PracticeBaselineStrum(
            elapsedSec: 6.051,
            direction: _down,
            targetEventIndex: 2,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7.12,
            direction: _down,
            targetEventIndex: 3,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7.879,
            direction: _down,
            targetEventIndex: 4,
          ),
          PracticeBaselineStrum(
            elapsedSec: 8.72,
            direction: _down,
            targetEventIndex: 5,
          ),
          PracticeBaselineStrum(
            elapsedSec: 10.28,
            direction: _down,
            targetEventIndex: 6,
          ),
          PracticeBaselineStrum(
            elapsedSec: 11.281,
            direction: _down,
            targetEventIndex: 7,
          ),
        ],
        chordObservations: _quarterChordObservations,
      ),
      PracticeBaselineScenario(
        id: 'p44_wrong_direction',
        lesson: _quarterLesson,
        bpm: 60,
        countInBeats: 4,
        strums: const [
          PracticeBaselineStrum(
            elapsedSec: 4,
            direction: _down,
            targetEventIndex: 0,
          ),
          PracticeBaselineStrum(
            elapsedSec: 5,
            direction: _down,
            targetEventIndex: 1,
          ),
          PracticeBaselineStrum(
            elapsedSec: 6,
            direction: _down,
            targetEventIndex: 2,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7,
            direction: _down,
            targetEventIndex: 3,
          ),
          PracticeBaselineStrum(
            elapsedSec: 8,
            direction: _down,
            targetEventIndex: 4,
          ),
          PracticeBaselineStrum(
            elapsedSec: 9,
            direction: _up,
            targetEventIndex: 5,
          ),
          PracticeBaselineStrum(
            elapsedSec: 10,
            direction: _up,
            targetEventIndex: 6,
          ),
          PracticeBaselineStrum(
            elapsedSec: 11,
            direction: _up,
            targetEventIndex: 7,
          ),
        ],
        chordObservations: _quarterChordObservations,
      ),
      PracticeBaselineScenario(
        id: 'p44_extra_strums',
        lesson: _quarterLesson,
        bpm: 60,
        countInBeats: 4,
        strums: const [
          PracticeBaselineStrum(
            elapsedSec: 4,
            direction: _down,
            targetEventIndex: 0,
          ),
          PracticeBaselineStrum(
            elapsedSec: 4.5,
            direction: _up,
            targetEventIndex: null,
          ),
          PracticeBaselineStrum(
            elapsedSec: 5,
            direction: _down,
            targetEventIndex: 1,
          ),
          PracticeBaselineStrum(
            elapsedSec: 5.5,
            direction: _up,
            targetEventIndex: null,
          ),
          PracticeBaselineStrum(
            elapsedSec: 6,
            direction: _down,
            targetEventIndex: 2,
          ),
          PracticeBaselineStrum(
            elapsedSec: 6.5,
            direction: _up,
            targetEventIndex: null,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7,
            direction: _down,
            targetEventIndex: 3,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7.5,
            direction: _up,
            targetEventIndex: null,
          ),
          PracticeBaselineStrum(
            elapsedSec: 8,
            direction: _down,
            targetEventIndex: 4,
          ),
          PracticeBaselineStrum(
            elapsedSec: 8.5,
            direction: _up,
            targetEventIndex: null,
          ),
          PracticeBaselineStrum(
            elapsedSec: 9,
            direction: _down,
            targetEventIndex: 5,
          ),
          PracticeBaselineStrum(
            elapsedSec: 9.5,
            direction: _up,
            targetEventIndex: null,
          ),
          PracticeBaselineStrum(
            elapsedSec: 10,
            direction: _down,
            targetEventIndex: 6,
          ),
          PracticeBaselineStrum(
            elapsedSec: 10.5,
            direction: _up,
            targetEventIndex: null,
          ),
          PracticeBaselineStrum(
            elapsedSec: 11,
            direction: _down,
            targetEventIndex: 7,
          ),
        ],
        chordObservations: _quarterChordObservations,
      ),
      PracticeBaselineScenario(
        id: 'p44_chord_lag',
        lesson: _chordLagLesson,
        bpm: 60,
        countInBeats: 4,
        strums: const [
          PracticeBaselineStrum(
            elapsedSec: 4,
            direction: _down,
            targetEventIndex: 0,
          ),
          PracticeBaselineStrum(
            elapsedSec: 5,
            direction: _down,
            targetEventIndex: 1,
          ),
          PracticeBaselineStrum(
            elapsedSec: 6,
            direction: _down,
            targetEventIndex: 2,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7,
            direction: _down,
            targetEventIndex: 3,
          ),
          PracticeBaselineStrum(
            elapsedSec: 8,
            direction: _down,
            targetEventIndex: 4,
          ),
          PracticeBaselineStrum(
            elapsedSec: 9,
            direction: _down,
            targetEventIndex: 5,
          ),
          PracticeBaselineStrum(
            elapsedSec: 10,
            direction: _down,
            targetEventIndex: 6,
          ),
          PracticeBaselineStrum(
            elapsedSec: 11,
            direction: _down,
            targetEventIndex: 7,
          ),
        ],
        chordObservations: const [
          PracticeBaselineChordObservation(elapsedSec: 4.3, label: 'C'),
          PracticeBaselineChordObservation(elapsedSec: 5.3, label: 'G'),
          PracticeBaselineChordObservation(elapsedSec: 6.3, label: 'Am'),
          PracticeBaselineChordObservation(elapsedSec: 7.3, label: 'F'),
          PracticeBaselineChordObservation(elapsedSec: 8.3, label: 'C'),
          PracticeBaselineChordObservation(elapsedSec: 9.3, label: 'G'),
          PracticeBaselineChordObservation(elapsedSec: 10.3, label: 'Am'),
          PracticeBaselineChordObservation(elapsedSec: 11.3, label: 'F'),
        ],
      ),
      PracticeBaselineScenario(
        id: 'p44_input_latency',
        lesson: _quarterLesson,
        bpm: 60,
        countInBeats: 4,
        inputLatencySec: 0.08,
        strums: const [
          PracticeBaselineStrum(
            elapsedSec: 4.08,
            direction: _down,
            targetEventIndex: 0,
          ),
          PracticeBaselineStrum(
            elapsedSec: 5.08,
            direction: _down,
            targetEventIndex: 1,
          ),
          PracticeBaselineStrum(
            elapsedSec: 6.08,
            direction: _down,
            targetEventIndex: 2,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7.08,
            direction: _down,
            targetEventIndex: 3,
          ),
          PracticeBaselineStrum(
            elapsedSec: 8.08,
            direction: _down,
            targetEventIndex: 4,
          ),
          PracticeBaselineStrum(
            elapsedSec: 9.08,
            direction: _down,
            targetEventIndex: 5,
          ),
          PracticeBaselineStrum(
            elapsedSec: 10.08,
            direction: _down,
            targetEventIndex: 6,
          ),
          PracticeBaselineStrum(
            elapsedSec: 11.08,
            direction: _down,
            targetEventIndex: 7,
          ),
        ],
        chordObservations: const [
          PracticeBaselineChordObservation(elapsedSec: 3.98, label: 'C'),
          PracticeBaselineChordObservation(elapsedSec: 7.98, label: 'G'),
        ],
      ),
      PracticeBaselineScenario(
        id: 'p44_dejittered',
        lesson: _quarterLesson,
        bpm: 60,
        countInBeats: 4,
        strums: const [
          PracticeBaselineStrum(
            elapsedSec: 4,
            frameArrivalSec: 4.10,
            direction: _down,
            targetEventIndex: 0,
          ),
          PracticeBaselineStrum(
            elapsedSec: 5,
            frameArrivalSec: 5.14,
            direction: _down,
            targetEventIndex: 1,
          ),
          PracticeBaselineStrum(
            elapsedSec: 6,
            frameArrivalSec: 6.07,
            direction: _down,
            targetEventIndex: 2,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7,
            frameArrivalSec: 7.12,
            direction: _down,
            targetEventIndex: 3,
          ),
          PracticeBaselineStrum(
            elapsedSec: 8,
            frameArrivalSec: 8.06,
            direction: _down,
            targetEventIndex: 4,
          ),
          PracticeBaselineStrum(
            elapsedSec: 9,
            frameArrivalSec: 9.18,
            direction: _down,
            targetEventIndex: 5,
          ),
          PracticeBaselineStrum(
            elapsedSec: 10,
            frameArrivalSec: 10.09,
            direction: _down,
            targetEventIndex: 6,
          ),
          PracticeBaselineStrum(
            elapsedSec: 11,
            frameArrivalSec: 11.11,
            direction: _down,
            targetEventIndex: 7,
          ),
        ],
        chordObservations: _quarterChordObservations,
      ),
      PracticeBaselineScenario(
        id: 'p44_eighths_contended',
        lesson: _contendedEighthsLesson,
        bpm: 96,
        countInBeats: 4,
        strums: const [
          PracticeBaselineStrum(
            elapsedSec: 2.5,
            direction: _down,
            targetEventIndex: 0,
          ),
          // (a) Exactly midway between open targets 1 and 2; target 1 wins.
          PracticeBaselineStrum(
            elapsedSec: 2.96875,
            direction: _up,
            targetEventIndex: 1,
          ),
          // (b) Intended extra; legacy consumes target 2 as wrong-direction.
          PracticeBaselineStrum(
            elapsedSec: 3.25,
            direction: _up,
            targetEventIndex: null,
            legacyMatchedEventIndex: 2,
          ),
          // (c) Dispatch closes target 3 before its in-window observation.
          PracticeBaselineStrum(
            elapsedSec: 3.4375,
            frameArrivalSec: 3.734375,
            direction: _up,
            targetEventIndex: 3,
          ),
          PracticeBaselineStrum(
            elapsedSec: 3.75,
            direction: _down,
            targetEventIndex: 4,
          ),
          PracticeBaselineStrum(
            elapsedSec: 4.0625,
            direction: _up,
            targetEventIndex: 5,
          ),
          PracticeBaselineStrum(
            elapsedSec: 4.375,
            direction: _down,
            targetEventIndex: 6,
          ),
          PracticeBaselineStrum(
            elapsedSec: 4.6875,
            direction: _up,
            targetEventIndex: 7,
          ),
        ],
        chordObservations: const [],
      ),
      PracticeBaselineScenario(
        id: 'p34_waltz',
        lesson: Lessons.firstWaltz,
        bpm: 76,
        countInBeats: 3,
        strums: const [
          PracticeBaselineStrum(
            elapsedSec: 2.3684210526315788,
            direction: _down,
            targetEventIndex: 0,
          ),
          PracticeBaselineStrum(
            elapsedSec: 3.2478947368421053,
            direction: _down,
            targetEventIndex: 1,
          ),
          PracticeBaselineStrum(
            elapsedSec: 4.147368421052632,
            direction: _down,
            targetEventIndex: 2,
          ),
          PracticeBaselineStrum(
            elapsedSec: 4.7368421052631575,
            direction: _up,
            targetEventIndex: 3,
          ),
          PracticeBaselineStrum(
            elapsedSec: 6.315789473684211,
            direction: _down,
            targetEventIndex: 5,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7.015263157894737,
            direction: _down,
            targetEventIndex: 6,
          ),
          PracticeBaselineStrum(
            elapsedSec: 7.694736842105264,
            direction: _down,
            targetEventIndex: 7,
          ),
          PracticeBaselineStrum(
            elapsedSec: 8.68421052631579,
            direction: _down,
            targetEventIndex: 8,
          ),
          PracticeBaselineStrum(
            elapsedSec: 9.673684210526315,
            direction: _down,
            targetEventIndex: 9,
          ),
          PracticeBaselineStrum(
            elapsedSec: 10.563157894736842,
            direction: _down,
            targetEventIndex: 10,
          ),
          PracticeBaselineStrum(
            elapsedSec: 11.052631578947368,
            direction: _down,
            targetEventIndex: 11,
          ),
        ],
        chordObservations: const [
          PracticeBaselineChordObservation(
            elapsedSec: 2.268421052631579,
            label: 'Em',
          ),
          PracticeBaselineChordObservation(
            elapsedSec: 4.636842105263158,
            label: 'C',
          ),
          PracticeBaselineChordObservation(
            elapsedSec: 7.005263157894738,
            label: 'Em',
          ),
          PracticeBaselineChordObservation(
            elapsedSec: 9.373684210526315,
            label: 'C',
          ),
        ],
      ),
    ]);
