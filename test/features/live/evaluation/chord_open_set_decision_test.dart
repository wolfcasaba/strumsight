// E14-R32 (ADR 0540): the open-set chord decision.
//
// What these cells prove:
//   * the SHIPPED default policy is the identity — it can emit neither
//     `noChord` nor `unknownChord`, so wiring the function in changes
//     nothing until a MEASURED policy exists;
//   * `noChord` and `unknownChord` are different answers and never collapse;
//   * an out-of-vocabulary chord (two near-equal maj/min candidates, the
//     sus4/add9 signature) goes to `unknownChord` rather than to the nearest
//     supported class — ONCE a policy says so;
//   * the boundary belongs to the more informative side.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/chord_open_set_decision.dart';

void main() {
  group('shipped default: disabled policy is the identity', () {
    test('every evidence shape stays a supported chord', () {
      const policy = ChordOpenSetPolicy.disabled();

      expect(policy.emitsUnknown, isFalse);
      for (final winSim in <double>[0, 0.01, 0.4, 0.75, 1]) {
        for (final margin in <double>[0, 0.02, 0.5, 1]) {
          expect(
            decideChordOpenSet(
              evidence: ChordOpenSetEvidence(winSim: winSim, margin: margin),
              policy: policy,
            ),
            ChordOpenSetOutcome.supportedChord,
            reason: 'winSim=$winSim margin=$margin',
          );
        }
      }
    });

    test('the N.C.-only policy still never emits unknown', () {
      const policy = ChordOpenSetPolicy.noChordOnly(similarityFloor: 0.3);

      expect(policy.emitsUnknown, isFalse);
      expect(
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.2, margin: 0),
          policy: policy,
        ),
        ChordOpenSetOutcome.noChord,
      );
      expect(
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.9, margin: 0),
          policy: policy,
        ),
        ChordOpenSetOutcome.supportedChord,
      );
    });
  });

  group('a measured policy separates the three answers', () {
    const policy = ChordOpenSetPolicy(
      noChordSimilarityFloor: 0.3,
      unknownSimilarityFloor: 0.6,
      unknownMarginFloor: 0.05,
    );

    test('silence-shaped evidence is noChord, not unknown', () {
      expect(
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.1, margin: 0.9),
          policy: policy,
        ),
        ChordOpenSetOutcome.noChord,
      );
    });

    test('audible but weak evidence is unknown, not noChord', () {
      expect(
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.45, margin: 0.9),
          policy: policy,
        ),
        ChordOpenSetOutcome.unknownChord,
      );
    });

    test('a strong winner with a near-tied runner-up (the sus4/add9 shape) '
        'is unknown, NOT the nearest supported maj/min', () {
      expect(
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.95, margin: 0.01),
          policy: policy,
        ),
        ChordOpenSetOutcome.unknownChord,
      );
    });

    test('a strong, clearly separated winner is a supported chord', () {
      expect(
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.95, margin: 0.4),
          policy: policy,
        ),
        ChordOpenSetOutcome.supportedChord,
      );
    });

    test('the three outcomes are pairwise distinct for these evidences — '
        'noChord and unknownChord never collapse into one state', () {
      final outcomes = <ChordOpenSetOutcome>{
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.1, margin: 0.9),
          policy: policy,
        ),
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.45, margin: 0.9),
          policy: policy,
        ),
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.95, margin: 0.4),
          policy: policy,
        ),
      };

      expect(outcomes.length, 3);
    });

    test('the boundary belongs to the more informative side', () {
      // Exactly ON the no-chord floor: a chord, not silence.
      expect(
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.3, margin: 0.9),
          policy: policy,
        ),
        ChordOpenSetOutcome.unknownChord,
      );
      // Exactly ON the unknown floors: named, not withheld.
      expect(
        decideChordOpenSet(
          evidence: ChordOpenSetEvidence(winSim: 0.6, margin: 0.05),
          policy: policy,
        ),
        ChordOpenSetOutcome.supportedChord,
      );
    });
  });

  group('evidence validation', () {
    test('evidence outside 0..1 is a typed error, never clamped silently', () {
      expect(
        () => ChordOpenSetEvidence(winSim: 1.2, margin: 0.5),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ChordOpenSetEvidence(winSim: 0.5, margin: -0.1),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => ChordOpenSetEvidence(winSim: double.nan, margin: 0.5),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
