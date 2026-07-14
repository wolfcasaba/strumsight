import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/engine/ml/live_crnn_classifier.dart';
import 'package:music_theory/features/live/model/strum.dart';

/// r175 — the learned no-strum reject in the LIVE path. The 3-class model
/// emits [P(down), P(up), P(no-strum)]; when P(no-strum) clears the calibrated
/// threshold (fit to keep >=95 % of true strums, chunk 018 r174/r175) the arrow
/// is SUPPRESSED. `classifyProbs` is the pure decision rule — tested here
/// against crafted probabilities so it is deterministic and model-independent.
void main() {
  group('r175 no-strum reject — classifyProbs suppression gate', () {
    final thr = LiveCrnnStrumClassifier.noStrumThreshold;

    test('the shipped no-strum threshold is a valid probability', () {
      expect(thr, greaterThan(0.0));
      expect(thr, lessThan(1.0));
    });

    test('P(no-strum) above the threshold suppresses the arrow', () {
      final pNo = (thr + 1.0) / 2; // strictly between thr and 1
      final rest = (1 - pNo) / 2;
      final c = LiveCrnnStrumClassifier.classifyProbs([rest, rest, pNo]);
      expect(c.suppressed, isTrue);
      expect(c.direction, isNull, reason: 'a suppressed onset has no arrow');
    });

    test('P(no-strum) below the threshold emits the winning direction', () {
      final pNo = thr / 2; // strictly below thr
      final rest = 1 - pNo;
      final down =
          LiveCrnnStrumClassifier.classifyProbs([0.8 * rest, 0.2 * rest, pNo]);
      expect(down.suppressed, isFalse);
      expect(down.direction, StrumDirection.down);

      final up =
          LiveCrnnStrumClassifier.classifyProbs([0.2 * rest, 0.8 * rest, pNo]);
      expect(up.suppressed, isFalse);
      expect(up.direction, StrumDirection.up);
    });

    test('direction confidence stays in the r170 calibrated band', () {
      final pNo = thr / 2;
      final rest = 1 - pNo;
      final c =
          LiveCrnnStrumClassifier.classifyProbs([0.9 * rest, 0.1 * rest, pNo]);
      expect(c.confidence, inInclusiveRange(0.5, 0.9),
          reason: 'the r170 down/up calibration is preserved for 3-class');
    });

    test('a 2-class prob vector never suppresses (r139 fallback behaviour)',
        () {
      final down = LiveCrnnStrumClassifier.classifyProbs([0.7, 0.3]);
      expect(down.suppressed, isFalse);
      expect(down.direction, StrumDirection.down);

      final up = LiveCrnnStrumClassifier.classifyProbs([0.3, 0.7]);
      expect(up.suppressed, isFalse);
      expect(up.direction, StrumDirection.up);
    });
  });
}
