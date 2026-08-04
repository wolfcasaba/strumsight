// Randomized property gate for the E02-R15 chord-change analyzer.
//
// Seed: PROPERTY_SEED from CI; locally absent -> 42 for reproducibility.
//
// The five invariants are the E02-R15 brief §A9 acceptance criteria. The
// analyzer is supposed to be pure, deterministic, and exact about which
// outcomes may carry a delay; the property gate locks all three at once.
//
//   1. analyzer.analyze never throws on any observation sequence;
//   2. the per-change outcomes sum to the number of changes (each change
//      gets exactly one outcome);
//   3. recognizedChangeDelay is only set on `correct` changes;
//   4. shuffling the input does not change the output;
//   5. if no ChordObservation was supplied, no pair may carry a median.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/chord_pair_stats.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/chord_change_analyzer.dart';

const _labels = [
  'C',
  'Cm',
  'C#',
  'C#m',
  'D',
  'Dm',
  'D#',
  'D#m',
  'E',
  'Em',
  'F',
  'Fm',
  'F#',
  'F#m',
  'G',
  'Gm',
  'G#',
  'G#m',
  'A',
  'Am',
  'A#',
  'A#m',
  'B',
  'Bm',
];

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  const analyzer = ChordChangeAnalyzer();

  group('Chord-change analyzer randomized invariants', () {
    test('never throws on any observation sequence', () {
      for (var trial = 0; trial < 160; trial++) {
        final rng = math.Random(seed + trial * 977);
        final run = _randomRun(rng);
        try {
          final analysis = analyzer.analyze(
            target: run.target,
            verdicts: run.verdicts,
            observations: run.observations,
          );
          expect(
            analysis.changes,
            isNotEmpty,
            reason: 'seed=$seed trial=$trial produced no changes',
          );
        } catch (error) {
          fail('seed=$seed trial=$trial analyzer threw: $error');
        }
      }
    });

    test('CI regression seed generates at least one expected chord change', () {
      const ciSeed = 30881015002;
      const failingTrial = 90;
      final run = _randomRun(math.Random(ciSeed + failingTrial * 977));

      expect(
        _hasExpectedChordChange(run.target.expectedChordSegments),
        isTrue,
        reason:
            'seed=$ciSeed trial=$failingTrial must satisfy the generator '
            'precondition for the randomized analyzer invariants',
      );
    });

    test('per-change outcomes sum to the change count', () {
      for (var trial = 0; trial < 160; trial++) {
        final rng = math.Random(seed + 100000 + trial * 991);
        final run = _randomRun(rng);
        final analysis = analyzer.analyze(
          target: run.target,
          verdicts: run.verdicts,
          observations: run.observations,
        );
        final totals = <ChordPair, int>{};
        for (final change in analysis.changes) {
          totals.update(change.pair, (value) => value + 1, ifAbsent: () => 1);
        }
        for (final stats in analysis.pairStats) {
          final observed = totals[stats.pair] ?? 0;
          expect(
            stats.outcomeCount,
            observed,
            reason:
                'seed=$seed trial=$trial pair=${stats.pair} '
                'outcomeCount=${stats.outcomeCount} '
                'changesForPair=$observed',
          );
          expect(
            stats.outcomeCount,
            stats.attempts,
            reason:
                'seed=$seed trial=$trial pair=${stats.pair} '
                'outcomeCount!=attempts',
          );
        }
        final totalAttempted = analysis.pairStats.fold<int>(
          0,
          (acc, stats) => acc + stats.attempts,
        );
        expect(
          totalAttempted,
          analysis.changes.length,
          reason:
              'seed=$seed trial=$trial '
              'pairStats total $totalAttempted != changes '
              '${analysis.changes.length}',
        );
      }
    });

    test('recognizedChangeDelay only exists on correct changes', () {
      for (var trial = 0; trial < 160; trial++) {
        final rng = math.Random(seed + 200000 + trial * 1009);
        final run = _randomRun(rng);
        final analysis = analyzer.analyze(
          target: run.target,
          verdicts: run.verdicts,
          observations: run.observations,
        );
        for (final change in analysis.changes) {
          if (change.outcome == ChordChangeOutcome.correct) {
            continue;
          }
          expect(
            change.recognizedChangeDelay,
            isNull,
            reason:
                'seed=$seed trial=$trial outcome=${change.outcome} '
                'pair=${change.pair} carried a non-correct delay',
          );
        }
        for (final stats in analysis.pairStats) {
          for (final delay in stats.recognizedChangeDelays) {
            expect(
              delay,
              isNotNull,
              reason:
                  'seed=$seed trial=$trial pair=${stats.pair} '
                  'null delay slipped into the list',
            );
          }
          expect(
            stats.recognizedChangeDelays.length,
            stats.correctChanges,
            reason:
                'seed=$seed trial=$trial pair=${stats.pair} '
                'delay count ${stats.recognizedChangeDelays.length} '
                '!= correct ${stats.correctChanges}',
          );
        }
      }
    });

    test('shuffling the input does not change the output', () {
      for (var trial = 0; trial < 120; trial++) {
        final rng = math.Random(seed + 300000 + trial * 1013);
        final run = _randomRun(rng);
        final baseline = analyzer.analyze(
          target: run.target,
          verdicts: run.verdicts,
          observations: run.observations,
        );

        final shuffledObservations = _deterministicShuffle(
          List<ChordObservation>.of(run.observations),
          seed + trial,
        );
        final shuffledVerdicts = _deterministicShuffle(
          List<PracticeVerdict>.of(run.verdicts),
          seed + trial + 1,
        );
        final shuffled = analyzer.analyze(
          target: run.target,
          verdicts: shuffledVerdicts,
          observations: shuffledObservations,
        );
        expect(
          shuffled,
          baseline,
          reason:
              'seed=$seed trial=$trial '
              'analyzer depended on input order',
        );
      }
    });

    test('no ChordObservation means no pair carries a median', () {
      for (var trial = 0; trial < 120; trial++) {
        final rng = math.Random(seed + 400000 + trial * 1019);
        final run = _randomRun(rng);
        final analysis = analyzer.analyze(
          target: run.target,
          verdicts: run.verdicts,
          observations: const [],
        );
        for (final stats in analysis.pairStats) {
          expect(
            stats.medianRecognizedChangeDelay,
            isNull,
            reason:
                'seed=$seed trial=$trial pair=${stats.pair} '
                'produced a median without observations',
          );
          expect(
            stats.recognizedChangeDelays,
            isEmpty,
            reason:
                'seed=$seed trial=$trial pair=${stats.pair} '
                'recorded delays without observations',
          );
        }
      }
    });
  });
}

class _RandomRun {
  _RandomRun({
    required this.target,
    required this.verdicts,
    required this.observations,
  });

  final CompiledPracticeTarget target;
  final List<PracticeVerdict> verdicts;
  final List<ChordObservation> observations;
}

_RandomRun _randomRun(math.Random rng) {
  final chordCount = 2 + rng.nextInt(6); // 2..7 segments
  final chordSequence = List<String>.generate(
    chordCount,
    (_) => _labels[rng.nextInt(_labels.length)],
  );
  // Force at least one transition by guaranteeing the first != the second.
  if (chordCount > 1 && chordSequence[0] == chordSequence[1]) {
    final duplicateIndex = _labels.indexOf(chordSequence[1]);
    chordSequence[1] = _labels[(duplicateIndex + 1) % _labels.length];
  }
  final segments = <ExpectedChordSegment>[];
  for (var index = 0; index < chordSequence.length; index++) {
    final start = Duration(seconds: index * 2);
    final end = index + 1 < chordSequence.length
        ? Duration(seconds: (index + 1) * 2)
        : Duration(seconds: chordSequence.length * 2);
    segments.add(
      ExpectedChordSegment(chord: chordSequence[index], start: start, end: end),
    );
  }
  final transitions = <Duration>[
    for (var index = 1; index < chordSequence.length; index++)
      Duration(seconds: index * 2),
  ];
  final observationCount = rng.nextInt(40);
  final observations = <ChordObservation>[];
  for (var index = 0; index < observationCount; index++) {
    final transitionIndex = rng.nextInt(transitions.length);
    final transition = transitions[transitionIndex];
    final mode = rng.nextInt(4);
    final offset = Duration(microseconds: rng.nextInt(600001) - 200000);
    final at = transition + offset;
    if (at < Duration.zero) continue;
    final label = switch (mode) {
      0 => null,
      1 => chordSequence[transitionIndex],
      _ => _labels[rng.nextInt(_labels.length)],
    };
    final confidence = mode == 0 ? 1.0 : 0.5 + rng.nextDouble() * 0.5;
    observations.add(
      ChordObservation(at: at, label: label, confidence: confidence),
    );
  }
  final verdictCount = rng.nextInt(8);
  final verdicts = <PracticeVerdict>[];
  for (var index = 0; index < verdictCount; index++) {
    final transitionIndex = rng.nextInt(transitions.length);
    final transition = transitions[transitionIndex];
    final matched = rng.nextBool();
    verdicts.add(
      PracticeVerdict(
        targetEventId: 'strum-prop-$index',
        matchedObservationSequence: matched ? index : null,
        targetAt: transition,
        observedAt: transition,
        timingOffset: Duration.zero,
        timingGrade: TimingGrade.perfect,
        expectedDirection: StrumDirection.down,
        observedDirection: StrumDirection.down,
        directionOutcome: DirectionOutcome.correct,
        expectedChord: chordSequence[transitionIndex],
        observedChord: chordSequence[transitionIndex],
        chordOutcome: ChordOutcome.correct,
        eventScore: 1,
        missReasonCode: null,
        coachingCode: null,
      ),
    );
  }
  final target = CompiledPracticeTarget(
    definitionId: 'chord-change-property',
    definitionSnapshotVersion: 1,
    tempo: const Tempo(120),
    meter: const Meter(beatsPerBar: 4),
    countInBars: 0,
    countInDuration: Duration.zero,
    events: const [],
    musicalDuration: Duration(seconds: chordSequence.length * 2),
    ringOutDuration: Duration.zero,
    totalDuration: Duration(seconds: chordSequence.length * 2),
    barBoundaries: const [],
    loopCount: 1,
    loopRange: null,
    expectedChordSegments: segments,
    scoringApplicable: true,
  );
  return _RandomRun(
    target: target,
    verdicts: verdicts,
    observations: observations,
  );
}

bool _hasExpectedChordChange(List<ExpectedChordSegment> segments) {
  for (var index = 1; index < segments.length; index++) {
    if (segments[index - 1].chord != segments[index].chord) return true;
  }
  return false;
}

List<T> _deterministicShuffle<T>(List<T> input, int seed) {
  if (input.length < 2) return input;
  final output = List<T>.of(input);
  final rng = math.Random(seed);
  for (var index = output.length - 1; index > 0; index--) {
    final swap = rng.nextInt(index + 1);
    final tmp = output[index];
    output[index] = output[swap];
    output[swap] = tmp;
  }
  return output;
}
