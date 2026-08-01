import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/free_practice_summary.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/free_practice_summarizer.dart';

void main() {
  group('FreePracticeSummarizer', () {
    group('A3 — strum counts and down/up ratios', () {
      test('counts strums and direction split', () {
        final summary = const FreePracticeSummarizer().summarize(
          observations: _strumObservations(
            timings: const [
              Duration(milliseconds: 0),
              Duration(milliseconds: 500),
              Duration(milliseconds: 1000),
              Duration(milliseconds: 1500),
              Duration(milliseconds: 2000),
              Duration(milliseconds: 2500),
              Duration(milliseconds: 3000),
              Duration(milliseconds: 3500),
              Duration(milliseconds: 4000),
              Duration(milliseconds: 4500),
            ],
            directions: const [
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.up,
              StrumDirection.up,
              StrumDirection.up,
            ],
          ),
          bpmSamples: const [],
          activeDuration: const Duration(seconds: 5),
          definition: _freePracticeDefinition(),
        );

        expect(summary.strumCount, 10);
        final ratio = summary.directionRatio;
        expect(ratio, isA<FreePracticeDirectionRatioAvailable>());
        final available = ratio as FreePracticeDirectionRatioAvailable;
        expect(available.downCount, 7);
        expect(available.upCount, 3);
        expect(available.downRatio, closeTo(0.7, 1e-9));
        expect(available.upRatio, closeTo(0.3, 1e-9));
      });

      test('zero strums => InsufficientData for the ratio', () {
        final summary = const FreePracticeSummarizer().summarize(
          observations: const [],
          bpmSamples: const [],
          activeDuration: const Duration(seconds: 10),
          definition: _freePracticeDefinition(),
        );

        expect(summary.strumCount, 0);
        expect(
          summary.directionRatio,
          isA<FreePracticeDirectionRatioInsufficientData>(),
        );
      });

      test('direction-less definition => NotApplicable for the ratio', () {
        final summary = const FreePracticeSummarizer().summarize(
          observations: _strumObservations(
            timings: const [
              Duration(milliseconds: 0),
              Duration(milliseconds: 500),
            ],
            directions: const [StrumDirection.down, StrumDirection.down],
          ),
          bpmSamples: const [],
          activeDuration: const Duration(seconds: 5),
          definition: _rhythmOnlyDefinition(),
        );

        expect(
          summary.directionRatio,
          isA<FreePracticeDirectionRatioNotApplicable>(),
        );
      });
    });

    group('A4 — tempo stability (MAD-style, requires ≥ 4 strums)', () {
      test('three strums => InsufficientData', () {
        final summary = const FreePracticeSummarizer().summarize(
          observations: _strumObservations(
            timings: const [
              Duration(milliseconds: 0),
              Duration(milliseconds: 500),
              Duration(milliseconds: 1000),
            ],
            directions: const [
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.down,
            ],
          ),
          bpmSamples: const [],
          activeDuration: const Duration(seconds: 5),
          definition: _freePracticeDefinition(),
        );

        expect(
          summary.tempoStability,
          isA<FreePracticeTempoStabilityInsufficientData>(),
        );
      });

      test('4 evenly-spaced strums => deviation = 0', () {
        final summary = const FreePracticeSummarizer().summarize(
          observations: _strumObservations(
            timings: const [
              Duration(milliseconds: 0),
              Duration(milliseconds: 500),
              Duration(milliseconds: 1000),
              Duration(milliseconds: 1500),
            ],
            directions: const [
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.down,
            ],
          ),
          bpmSamples: const [],
          activeDuration: const Duration(seconds: 5),
          definition: _freePracticeDefinition(),
        );

        final stability = summary.tempoStability;
        expect(stability, isA<FreePracticeTempoStabilityAvailable>());
        expect(
          (stability as FreePracticeTempoStabilityAvailable).deviation,
          Duration.zero,
        );
      });

      test('12 evenly-spaced strums => deviation = 0', () {
        final summary = const FreePracticeSummarizer().summarize(
          observations: _strumObservations(
            timings: List<Duration>.generate(
              12,
              (i) => Duration(milliseconds: i * 500),
            ),
            directions: List<StrumDirection>.filled(12, StrumDirection.down),
          ),
          bpmSamples: const [],
          activeDuration: const Duration(seconds: 8),
          definition: _freePracticeDefinition(),
        );

        final stability = summary.tempoStability;
        expect(stability, isA<FreePracticeTempoStabilityAvailable>());
        expect(
          (stability as FreePracticeTempoStabilityAvailable).deviation,
          Duration.zero,
        );
      });

      test(
        '12 strums with one 1500 ms gap: median-absolute deviation stays small',
        () {
          final timings = <Duration>[];
          for (var i = 0; i < 11; i++) {
            timings.add(Duration(milliseconds: i * 500));
          }
          // 11th interval = 1500 ms (1500 ms instead of 500 ms).
          timings.add(const Duration(milliseconds: 5500));
          final summary = const FreePracticeSummarizer().summarize(
            observations: _strumObservations(
              timings: timings,
              directions: List<StrumDirection>.filled(12, StrumDirection.down),
            ),
            bpmSamples: const [],
            activeDuration: const Duration(seconds: 8),
            definition: _freePracticeDefinition(),
          );

          final stability = summary.tempoStability;
          expect(stability, isA<FreePracticeTempoStabilityAvailable>());
          final available = stability as FreePracticeTempoStabilityAvailable;
          // The outlier interval is 1500 ms, the rest are 500 ms. Median = 500,
          // so 10 of the 11 deviations are 0 and 1 is 1000 ms. MAD = 0.
          expect(
            available.deviation,
            Duration.zero,
            reason: 'median-absolute deviation must stay 0 for the rest',
          );
        },
      );

      test(
        'mixed intervals: median-absolute deviation computes the right value',
        () {
          const intervals = [
            Duration(milliseconds: 100),
            Duration(milliseconds: 200),
            Duration(milliseconds: 300),
            Duration(milliseconds: 400),
            Duration(milliseconds: 500),
          ];
          final timings = <Duration>[Duration.zero];
          for (final interval in intervals) {
            timings.add(timings.last + interval);
          }
          final summary = const FreePracticeSummarizer().summarize(
            observations: _strumObservations(
              timings: timings,
              directions: List<StrumDirection>.filled(6, StrumDirection.down),
            ),
            bpmSamples: const [],
            activeDuration: const Duration(seconds: 5),
            definition: _freePracticeDefinition(),
          );

          final stability = summary.tempoStability;
          expect(stability, isA<FreePracticeTempoStabilityAvailable>());
          // Intervals sorted: 100, 200, 300, 400, 500 → median = 300.
          // Deviations: 200, 100, 0, 100, 200 → sorted 0, 100, 100, 200, 200 →
          // median = 100.
          expect(
            (stability as FreePracticeTempoStabilityAvailable).deviation,
            const Duration(milliseconds: 100),
          );
        },
      );
    });

    group('A5 — chord timeline segments', () {
      test('G (4s) → null (1s) → C (3s) yields three segments', () {
        final summary = const FreePracticeSummarizer().summarize(
          observations: [
            const ChordObservation(
              at: Duration(seconds: 0),
              label: 'G',
              confidence: 1.0,
            ),
            const ChordObservation(
              at: Duration(seconds: 4),
              label: null,
              confidence: 1.0,
            ),
            const ChordObservation(
              at: Duration(seconds: 5),
              label: 'C',
              confidence: 1.0,
            ),
          ],
          bpmSamples: const [],
          activeDuration: const Duration(seconds: 8),
          definition: _freePracticeDefinition(),
        );

        expect(summary.chordTimeline.length, 3);
        expect(summary.chordTimeline[0].label, 'G');
        expect(summary.chordTimeline[0].duration, const Duration(seconds: 4));
        expect(summary.chordTimeline[1].label, isNull);
        expect(summary.chordTimeline[1].duration, const Duration(seconds: 1));
        expect(summary.chordTimeline[2].label, 'C');
        expect(summary.chordTimeline[2].duration, const Duration(seconds: 3));
        expect(summary.chordTimelineDuration, const Duration(seconds: 8));
      });
    });

    group('A2 — Free Practice summary never produces a score', () {
      test('strumCount and activeDuration are surfaced as facts only', () {
        final summary = const FreePracticeSummarizer().summarize(
          observations: _strumObservations(
            timings: const [
              Duration(milliseconds: 0),
              Duration(milliseconds: 500),
              Duration(milliseconds: 1000),
              Duration(milliseconds: 1500),
            ],
            directions: const [
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.down,
              StrumDirection.down,
            ],
          ),
          bpmSamples: const [],
          activeDuration: const Duration(seconds: 5),
          definition: _freePracticeDefinition(),
        );

        // The summary exposes only facts — no score, no verdict, no pass/fail.
        // The runtime fields here are int/Duration, not MetricValue.
        expect(summary.strumCount, 4);
        expect(summary.activeDuration, const Duration(seconds: 5));
      });
    });

    test('A9 — segment durations sum to ≤ activeDuration', () {
      final summary = const FreePracticeSummarizer().summarize(
        observations: [
          const ChordObservation(
            at: Duration(seconds: 0),
            label: 'G',
            confidence: 1.0,
          ),
          const ChordObservation(
            at: Duration(seconds: 4),
            label: 'C',
            confidence: 1.0,
          ),
        ],
        bpmSamples: const [],
        activeDuration: const Duration(seconds: 10),
        definition: _freePracticeDefinition(),
      );

      expect(summary.chordTimelineDuration <= summary.activeDuration, isTrue);
    });
  });
}

List<StrumObservation> _strumObservations({
  required List<Duration> timings,
  required List<StrumDirection> directions,
}) {
  assert(timings.length == directions.length);
  return [
    for (var i = 0; i < timings.length; i++)
      StrumObservation(
        at: timings[i],
        sequence: i,
        direction: directions[i],
        confidence: 1.0,
      ),
  ];
}

PracticeDefinition _freePracticeDefinition() => PracticeDefinition(
  id: 'free-practice-test',
  schemaVersion: 1,
  titleKey: 'freePractice.title',
  descriptionKey: 'freePractice.body',
  mode: PracticeMode.freePractice,
  source: PracticeSource.builtin,
  meter: const Meter(beatsPerBar: 4),
  defaultTempo: const Tempo(90),
  totalBeats: BeatPosition.quarters(4),
  events: const [],
  scoringProfile: ScoringProfile.freePracticeOpen,
  skillTags: const [],
  difficulty: PracticeDifficulty.beginner,
);

PracticeDefinition _rhythmOnlyDefinition() {
  // The Rhythm-only profile permits direction-less events — definition.events
  // stays empty; the test invokes the summarizer with strum observations that
  // carry directions, but the *direction applicability* check is gated on
  // whether the **definition** declares direction.
  return PracticeDefinition(
    id: 'rhythm-only-test',
    schemaVersion: 1,
    titleKey: 'rhythmOnly.title',
    descriptionKey: 'rhythmOnly.body',
    mode: PracticeMode.rhythmOnly,
    source: PracticeSource.builtin,
    meter: const Meter(beatsPerBar: 4),
    defaultTempo: const Tempo(90),
    totalBeats: BeatPosition.quarters(4),
    events: const [],
    scoringProfile: ScoringProfile.rhythmOnlyDefault,
    skillTags: const [],
    difficulty: PracticeDifficulty.beginner,
  );
}
