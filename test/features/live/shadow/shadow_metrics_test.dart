// E14-R23 / E14-R26 — the shadow measurement primitives.
//
// RED before this round: none of these types existed, so every cell here is
// red-before by construction. What they PIN:
//   1. the ring is bounded and its storage never grows (the R22 memory claim);
//   2. an empty window has NO agreement rate — `null`, never 0.0 or 1.0;
//   3. the chord class taxonomy keeps "no chord" and "unreadable label"
//      apart, and reduces labels exactly like the shipped ML chord path.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/analyze/engine/ml_chord_decoder.dart';
import 'package:strumsight/features/live/data/shadow/shadow_metrics.dart';

void main() {
  group('ShadowRingBuffer — bounded by construction', () {
    test('storage is allocated once and never grows', () {
      final ring = ShadowRingBuffer<String>(capacity: 4);
      expect(ring.slotCount, 4);
      for (var i = 0; i < 10000; i++) {
        ring.add('sample $i');
      }
      expect(ring.slotCount, 4, reason: 'the slot array must never grow');
      expect(ring.length, 4);
      expect(ring.dropped, 10000 - 4);
    });

    test('keeps the NEWEST samples, oldest first', () {
      final ring = ShadowRingBuffer<int>(capacity: 3);
      for (var i = 0; i < 5; i++) {
        ring.add(i);
      }
      expect(ring.toList(), [2, 3, 4]);
    });

    test('a partially filled ring reports only what it holds', () {
      final ring = ShadowRingBuffer<int>(capacity: 5);
      ring
        ..add(1)
        ..add(2);
      expect(ring.toList(), [1, 2]);
      expect(ring.dropped, 0);
    });

    test('clear() releases the samples but keeps the storage', () {
      final ring = ShadowRingBuffer<int>(capacity: 3);
      for (var i = 0; i < 7; i++) {
        ring.add(i);
      }
      ring.clear();
      expect(ring.length, 0);
      expect(ring.dropped, 0);
      expect(ring.slotCount, 3);
      expect(ring.toList(), isEmpty);
    });
  });

  group('ShadowLatencyBucket', () {
    test('an unusable latency stays UNKNOWN, never a plausible bucket', () {
      expect(ShadowLatencyBucket.forSeconds(null), ShadowLatencyBucket.unknown);
      expect(
        ShadowLatencyBucket.forSeconds(double.nan),
        ShadowLatencyBucket.unknown,
      );
      expect(
        ShadowLatencyBucket.forSeconds(-0.01),
        ShadowLatencyBucket.unknown,
      );
    });

    test('boundaries are inclusive-low / exclusive-high', () {
      expect(ShadowLatencyBucket.forSeconds(0), ShadowLatencyBucket.under20ms);
      expect(
        ShadowLatencyBucket.forSeconds(0.0199),
        ShadowLatencyBucket.under20ms,
      );
      expect(
        ShadowLatencyBucket.forSeconds(0.02),
        ShadowLatencyBucket.under50ms,
      );
      expect(
        ShadowLatencyBucket.forSeconds(0.05),
        ShadowLatencyBucket.under100ms,
      );
      expect(
        ShadowLatencyBucket.forSeconds(0.1),
        ShadowLatencyBucket.under200ms,
      );
      expect(
        ShadowLatencyBucket.forSeconds(0.2),
        ShadowLatencyBucket.atLeast200ms,
      );
    });
  });

  group('ShadowChordClass', () {
    test('the no-chord spellings all read as N.C.', () {
      for (final label in [null, '', '   ', 'N.C.', 'N', 'NC', 'X']) {
        expect(ShadowChordClass.parse(label), ShadowChordClass.noChord);
      }
    });

    test('an unreadable label is UNKNOWN, not N.C.', () {
      final parsed = ShadowChordClass.parse('Hmaj7');
      expect(parsed, ShadowChordClass.unknown);
      expect(
        parsed,
        isNot(ShadowChordClass.noChord),
        reason: '"I cannot read this" must not be reported as silence',
      );
    });

    test('majmin reduction matches the shipped ML chord path exactly', () {
      const labels = [
        'C',
        'Cm',
        'C#',
        'Db',
        'Dm7',
        'Emaj7',
        'F#m7b5',
        'Gsus4',
        'A/C#',
        'Bbdim',
        'Ebmin',
        'GM7',
        'Am',
        'N.C.',
      ];
      for (final label in labels) {
        expect(
          ShadowChordClass.parse(label).label,
          MlChordDecoder.majminReduce(label),
          reason: 'divergence on "$label"',
        );
      }
    });

    test('the class index set is dense, closed and collision-free', () {
      final indices = <int>{
        ShadowChordClass.noChord.index,
        ShadowChordClass.unknown.index,
      };
      for (final label in MlChordDecoder.majmin25Labels) {
        indices.add(ShadowChordClass.parse(label).index);
      }
      // 25 shipped labels (N.C. included) + the unknown class.
      expect(indices.length, 26);
      expect(indices.reduce((a, b) => a > b ? a : b), 25);
      expect(ShadowChordClass.classCount, 26);
    });
  });

  group('aggregates never invent a rate', () {
    test('an empty strum aggregate has a NULL agreement rate', () {
      const aggregate = StrumShadowAggregate.empty;
      expect(aggregate.agreementRate, isNull);
      expect(aggregate.candidateAbstentionRate, isNull);
    });

    test('an empty chord aggregate has NULL rates and a zero matrix', () {
      final aggregate = ChordShadowAggregate.empty();
      expect(aggregate.exactAgreementRate, isNull);
      expect(aggregate.rootAgreementRate, isNull);
      expect(aggregate.qualityAgreementRate, isNull);
      expect(
        aggregate.countFor(ShadowChordClass.noChord, ShadowChordClass.noChord),
        0,
      );
      expect(aggregate.confusionCells, isEmpty);
    });

    test('a populated strum aggregate reports the real fraction', () {
      const aggregate = StrumShadowAggregate(
        observedFrames: 20,
        candidateVerdicts: 5,
        comparedVerdicts: 4,
        agreed: 3,
        disagreed: 1,
        candidateAbstained: 1,
        productionAbstained: 0,
        bothAbstained: 0,
        candidateUnavailableFrames: 2,
        latencyHistogram: <ShadowLatencyBucket, int>{
          ShadowLatencyBucket.under50ms: 5,
        },
      );
      expect(aggregate.agreementRate, closeTo(0.75, 1e-12));
      expect(aggregate.candidateAbstentionRate, closeTo(0.2, 1e-12));
      expect(aggregate.toJson()['agreementRate'], closeTo(0.75, 1e-12));
      expect(
        (aggregate.toJson()['latency']! as Map<String, int>)['under50ms'],
        5,
      );
    });
  });
}
