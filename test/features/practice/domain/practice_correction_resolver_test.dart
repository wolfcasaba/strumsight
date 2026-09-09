// E14-R38 (ADR 0551 D6) — the correction loop, at the level it actually
// lives: a PURE projection over the matcher + the chord scorer.
//
// No reducer state was added for it, so there is nothing to drive through a
// state machine here — which is the point. The resolver is total and
// deterministic, so every rule below is a plain function call.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/compiled_practice_target.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_correction.dart';
import 'package:strumsight/features/practice/domain/model/practice_observation.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/practice/domain/service/practice_chord_scorer.dart';
import 'package:strumsight/features/practice/domain/service/practice_correction_resolver.dart';
import 'package:strumsight/features/practice/domain/service/practice_event_matcher.dart';

const _stableDuration = Duration(milliseconds: 180);

void main() {
  group('nothing to correct', () {
    test('an unfinished attempt corrects nothing — a target still open is '
        'not a mistake', () {
      final matcher = _matcher(['G']);
      final correction = _resolve(matcher, const []);
      expect(correction, isNull);
    });

    test('a clean, correctly played target corrects nothing', () {
      final matcher = _matcher(['G']);
      matcher.registerStrum(
        const StrumObservation(
          at: Duration(seconds: 1),
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.9,
        ),
      );
      final correction = _resolve(matcher, const [
        ChordObservation(
          at: Duration(seconds: 1),
          label: 'G',
          confidence: null,
        ),
        ChordObservation(
          at: Duration(milliseconds: 1300),
          label: 'G',
          confidence: null,
        ),
      ]);
      expect(correction, isNull);
    });
  });

  group('the recognizer abstained — the correction is the RECOGNIZER\'s', () {
    test('an uncertain target yields the reject reason, not an accusation', () {
      final matcher = _matcher(['G']);
      matcher.registerStrum(
        const StrumObservation(
          at: Duration(seconds: 1),
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.9,
        ),
      );
      final correction = _resolve(matcher, const [
        ChordObservation(
          at: Duration(seconds: 1),
          label: 'C',
          confidence: null,
          evidence: ChordEvidence.uncertain,
          rejectReasonCode: 'signalTooQuiet',
        ),
        ChordObservation(
          at: Duration(milliseconds: 1300),
          label: 'C',
          confidence: null,
          evidence: ChordEvidence.uncertain,
          rejectReasonCode: 'signalTooQuiet',
        ),
      ]);

      expect(correction, isNotNull);
      expect(correction!.kind, PracticeCorrectionKind.recognitionUnclear);
      expect(correction.rejectReasonCode, 'signalTooQuiet');
      expect(
        correction.expectedChord,
        isNull,
        reason: 'naming the expected chord here would blame the player for '
            'the app being unable to hear',
      );
    });

    test('the NEWEST reason wins — conditions change during an attempt', () {
      final matcher = _matcher(['G']);
      matcher.registerStrum(
        const StrumObservation(
          at: Duration(seconds: 1),
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.9,
        ),
      );
      final correction = _resolve(matcher, const [
        ChordObservation(
          at: Duration(milliseconds: 900),
          label: null,
          confidence: null,
          evidence: ChordEvidence.rejected,
          rejectReasonCode: 'signalTooQuiet',
        ),
        ChordObservation(
          at: Duration(seconds: 1),
          label: 'C',
          confidence: null,
          evidence: ChordEvidence.uncertain,
          rejectReasonCode: 'signalTooNoisy',
        ),
      ]);

      expect(correction!.rejectReasonCode, 'signalTooNoisy');
    });

    test('an abstention with no stated reason keeps the kind and reports no '
        'reason — the UI then says the generic sentence, not a guess', () {
      final matcher = _matcher(['G']);
      matcher.registerStrum(
        const StrumObservation(
          at: Duration(seconds: 1),
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.9,
        ),
      );
      final correction = _resolve(matcher, const [
        ChordObservation(
          at: Duration(seconds: 1),
          label: 'C',
          confidence: null,
          evidence: ChordEvidence.uncertain,
        ),
      ]);

      expect(correction!.kind, PracticeCorrectionKind.recognitionUnclear);
      expect(correction.rejectReasonCode, isNull);
    });
  });

  group('the app was confident — the correction is the TARGET', () {
    test('a confidently wrong chord names the expected chord', () {
      final matcher = _matcher(['G']);
      matcher.registerStrum(
        const StrumObservation(
          at: Duration(seconds: 1),
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.9,
        ),
      );
      final correction = _resolve(matcher, const [
        ChordObservation(
          at: Duration(seconds: 1),
          label: 'C',
          confidence: null,
        ),
        ChordObservation(
          at: Duration(milliseconds: 1300),
          label: 'C',
          confidence: null,
        ),
      ]);

      expect(correction!.kind, PracticeCorrectionKind.playExpectedChord);
      expect(correction.expectedChord, 'G');
    });

    test('a missed chord target names the expected chord', () {
      final matcher = _matcher(['G']);
      matcher.advance(const Duration(seconds: 5));
      final correction = _resolve(matcher, const []);

      expect(correction!.kind, PracticeCorrectionKind.playExpectedChord);
      expect(correction.expectedChord, 'G');
    });

    test('a missed CHORD-LESS target names the target, never a chord', () {
      final matcher = _matcher([null]);
      matcher.advance(const Duration(seconds: 5));
      final correction = _resolve(matcher, const []);

      expect(correction!.kind, PracticeCorrectionKind.hitTheTarget);
      expect(correction.expectedChord, isNull);
    });
  });

  group('the loop looks at the LATEST resolved target only', () {
    test('an old mistake stops being reported once a later target is '
        'clean', () {
      final matcher = _matcher(['G', 'C']);
      // Target 0 (t = 1 s) is missed; target 1 (t = 2 s) is played cleanly.
      matcher.advance(const Duration(milliseconds: 1500));
      matcher.registerStrum(
        const StrumObservation(
          at: Duration(seconds: 2),
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.9,
        ),
      );
      final correction = _resolve(matcher, const [
        ChordObservation(
          at: Duration(seconds: 2),
          label: 'C',
          confidence: null,
        ),
        ChordObservation(
          at: Duration(milliseconds: 2300),
          label: 'C',
          confidence: null,
        ),
      ]);

      expect(
        correction,
        isNull,
        reason: 'a correction loop nags about the last thing, not about the '
            'whole session history',
      );
    });

    test('a fresh mistake replaces the previous advice', () {
      final matcher = _matcher(['G', 'C']);
      matcher.registerStrum(
        const StrumObservation(
          at: Duration(seconds: 1),
          sequence: 0,
          direction: StrumDirection.down,
          confidence: 0.9,
        ),
      );
      matcher.advance(const Duration(milliseconds: 2500));
      final correction = _resolve(matcher, const []);

      expect(correction!.kind, PracticeCorrectionKind.playExpectedChord);
      expect(correction.expectedChord, 'C');
      expect(correction.targetIndex, 1);
    });
  });

  test('misaligned inputs are a programming error, not a silent null', () {
    final matcher = _matcher(['G']);
    final chord = const PracticeChordScorer().score(
      matches: _matcher(['G', 'C']).results,
      observations: const [],
      chordStableDuration: _stableDuration,
    );
    expect(
      () => resolvePracticeCorrection(
        matches: matcher.results,
        chord: chord,
        observations: const [],
      ),
      throwsArgumentError,
    );
  });
}

PracticeCorrection? _resolve(
  PracticeEventMatcher matcher,
  List<ChordObservation> observations,
) {
  final chord = const PracticeChordScorer().score(
    matches: matcher.results,
    observations: observations,
    chordStableDuration: _stableDuration,
  );
  return resolvePracticeCorrection(
    matches: matcher.results,
    chord: chord,
    observations: observations,
  );
}

PracticeEventMatcher _matcher(List<String?> chords) => PracticeEventMatcher(
  target: _target(chords),
  scoringProfile: ScoringProfile.legacyLearnParity,
  inputLatency: Duration.zero,
);

CompiledPracticeTarget _target(List<String?> chords) => CompiledPracticeTarget(
  definitionId: 'correction-test',
  definitionSnapshotVersion: 1,
  tempo: const Tempo(120),
  meter: const Meter(beatsPerBar: 4),
  countInBars: 0,
  countInDuration: Duration.zero,
  events: [
    for (var index = 0; index < chords.length; index++)
      CompiledTargetEvent(
        sourceEventId: 'event-$index',
        loopIndex: 0,
        position: BeatPosition.fromTicks(index),
        time: Duration(seconds: index + 1),
        barIndex: 0,
        chord: chords[index],
        direction: StrumDirection.down,
        accent: false,
        optional: false,
      ),
  ],
  musicalDuration: Duration(seconds: chords.length + 1),
  ringOutDuration: Duration.zero,
  totalDuration: Duration(seconds: chords.length + 1),
  barBoundaries: const [],
  loopCount: 1,
  loopRange: null,
  expectedChordSegments: const [],
  scoringApplicable: chords.isNotEmpty,
);
