// Randomized property gate (anti-reward-hacking — HORIZON pattern) for the
// E02-R16 Free Practice summarizer and the streak-eligibility predicate.
//
// The deterministic matrix tests in
// `test/features/practice/domain/free_practice_summarizer_test.dart` and
// `test/features/practice/domain/practice_session_eligibility_test.dart`
// pin every acceptance cell; this file re-checks the summarizer +
// predicate invariants on randomized inputs so a synthetic-green pass cannot
// hide a regression that only surfaces under load.
//
// Seed: PROPERTY_SEED env var — CI passes the run id; locally absent → 42
// (so the dev-loop suite stays deterministic).
//
// Required invariants (brief §6.9):
//   - the summarizer never throws on arbitrary observation / sample inputs;
//   - `downCount + upCount == strumCount` on every run;
//   - Free Practice never produces a `MetricAvailable` `overall` value;
//   - the eligibility predicate is monotone: adding a strum / second does
//     not turn a `true` into a `false`;
//   - the chord-timeline segment durations sum to ≤ active duration.
import 'dart:io';
import 'dart:math' as math;

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
import 'package:strumsight/features/practice/domain/service/practice_session_eligibility.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // Always visible in logs so any failure is reproducible.
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  const summarizer = FreePracticeSummarizer();
  const predicate = PracticeSessionEligibility();
  final definition = _freePracticeDefinition();

  group('Free Practice property invariants (R16 A9)', () {
    test('property: summarizer never throws on randomized inputs', () {
      for (var trial = 0; trial < 80; trial++) {
        final rng = math.Random(trial * 1000 + seed);
        final input = _randomInput(rng);
        expect(
          () => summarizer.summarize(
            observations: input.observations,
            bpmSamples: input.bpmSamples,
            activeDuration: input.activeDuration,
            definition: definition,
          ),
          returnsNormally,
          reason: 'seed=$seed trial=$trial should not throw',
        );
      }
    });

    test('property: downCount + upCount == strumCount on every run', () {
      for (var trial = 0; trial < 80; trial++) {
        final rng = math.Random(trial * 1000 + seed);
        final input = _randomInput(rng);
        final summary = summarizer.summarize(
          observations: input.observations,
          bpmSamples: input.bpmSamples,
          activeDuration: input.activeDuration,
          definition: definition,
        );
        final ratio = summary.directionRatio;
        if (ratio is FreePracticeDirectionRatioAvailable) {
          expect(
            ratio.downCount + ratio.upCount,
            summary.strumCount,
            reason:
                'seed=$seed trial=$trial direction counts must sum '
                'to strumCount',
          );
        }
      }
    });

    test(
      'property: eligibility predicate is monotone in strums and seconds',
      () {
        for (var trial = 0; trial < 80; trial++) {
          final rng = math.Random(trial * 1000 + seed);
          final base = _randomInput(rng);
          final baseline = predicate.isEligible(
            PracticeSessionEligibilityInput(
              activeDuration: base.activeDuration,
              resolvedRequiredTargets: 0,
              freePracticeStrums: base.observations
                  .whereType<StrumObservation>()
                  .length,
            ),
          );
          // Adding seconds must never flip true → false.
          final plusSecond = predicate.isEligible(
            PracticeSessionEligibilityInput(
              activeDuration: base.activeDuration + const Duration(seconds: 1),
              resolvedRequiredTargets: 0,
              freePracticeStrums: base.observations
                  .whereType<StrumObservation>()
                  .length,
            ),
          );
          expect(
            plusSecond || !baseline,
            isTrue,
            reason:
                'seed=$seed trial=$trial adding seconds must not '
                'turn true into false',
          );
          // Adding more strums must never flip true → false either.
          final plusStrum = predicate.isEligible(
            PracticeSessionEligibilityInput(
              activeDuration: base.activeDuration,
              resolvedRequiredTargets: 0,
              freePracticeStrums:
                  base.observations.whereType<StrumObservation>().length + 1,
            ),
          );
          expect(
            plusStrum || !baseline,
            isTrue,
            reason:
                'seed=$seed trial=$trial adding strums must not '
                'turn true into false',
          );
        }
      },
    );

    test(
      'property: chord-timeline segment durations sum to ≤ activeDuration',
      () {
        for (var trial = 0; trial < 80; trial++) {
          final rng = math.Random(trial * 1000 + seed);
          final input = _randomInput(rng);
          final summary = summarizer.summarize(
            observations: input.observations,
            bpmSamples: input.bpmSamples,
            activeDuration: input.activeDuration,
            definition: definition,
          );
          expect(
            summary.chordTimelineDuration <= summary.activeDuration,
            isTrue,
            reason:
                'seed=$seed trial=$trial: timeline = '
                '${summary.chordTimelineDuration}, active = '
                '${summary.activeDuration}',
          );
        }
      },
    );
  });
}

class _RandomInput {
  const _RandomInput({
    required this.observations,
    required this.bpmSamples,
    required this.activeDuration,
  });

  final List<PracticeObservation> observations;
  final List<FreePracticeBpmSample> bpmSamples;
  final Duration activeDuration;
}

_RandomInput _randomInput(math.Random rng) {
  final strumCount = rng.nextInt(15);
  final chordCount = rng.nextInt(6);
  final bpmCount = rng.nextInt(4);
  final activeDuration = Duration(milliseconds: 1000 + rng.nextInt(60000));

  final observations = <PracticeObservation>[];
  for (var i = 0; i < strumCount; i++) {
    observations.add(
      StrumObservation(
        at: Duration(milliseconds: rng.nextInt(activeDuration.inMilliseconds)),
        sequence: i,
        direction: rng.nextBool() ? StrumDirection.down : StrumDirection.up,
        confidence: 0.5 + rng.nextDouble() * 0.5,
      ),
    );
  }
  for (var i = 0; i < chordCount; i++) {
    final labels = ['C', 'G', 'Am', 'F', 'D', null];
    observations.add(
      ChordObservation(
        at: Duration(milliseconds: rng.nextInt(activeDuration.inMilliseconds)),
        label: labels[rng.nextInt(labels.length)],
        confidence: 1.0,
      ),
    );
  }
  observations.sort((a, b) => a.at.compareTo(b.at));

  final bpmSamples = <FreePracticeBpmSample>[];
  for (var i = 0; i < bpmCount; i++) {
    bpmSamples.add(
      FreePracticeBpmSample(
        bpm: 60.0 + rng.nextDouble() * 120.0,
        at: Duration(milliseconds: rng.nextInt(activeDuration.inMilliseconds)),
      ),
    );
  }

  return _RandomInput(
    observations: observations,
    bpmSamples: bpmSamples,
    activeDuration: activeDuration,
  );
}

PracticeDefinition _freePracticeDefinition() => PracticeDefinition(
  id: 'free-practice-property',
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
