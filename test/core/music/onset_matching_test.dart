// The shared one-to-one time matcher.
//
// `docs/LESSONS.md` L269 requires that every time-windowed one-to-one metric
// use THIS helper, and that its test carry at least one counterexample where
// the locally-closest choice and the maximum match count differ. That
// counterexample is the first cell below, with L269's own numbers.
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/onset_matching.dart';

/// Matched (expected index, detected index) pairs, in detected order.
List<(int, int)> _pairs(List<int> matchOfDetected) => [
  for (var j = 0; j < matchOfDetected.length; j++)
    if (matchOfDetected[j] != -1) (matchOfDetected[j], j),
];

int _matchCount(List<int> matchOfDetected) =>
    matchOfDetected.where((i) => i != -1).length;

void main() {
  group('L269: the greedy counterexample', () {
    test('expected 50,90 against detected 0,55 yields TWO matches', () {
      // Greedy takes 50↔55 (gap 5) and then has nothing within 50 of 90, for
      // one match. The maximum matching is 50↔0 and 90↔55, for two.
      final matchOfDetected = matchWithinTolerance(
        expected: const [50, 90],
        detected: const [0, 55],
        tolerance: 50,
      );
      expect(_matchCount(matchOfDetected), 2);
      expect(_pairs(matchOfDetected), [(0, 0), (1, 1)]);
    });

    test('the same counterexample mirrored in time', () {
      // Guards against an asymmetry in the preference order: the mirror image
      // must also find both pairs.
      final matchOfDetected = matchWithinTolerance(
        expected: const [0, 40],
        detected: const [35, 90],
        tolerance: 50,
      );
      expect(_matchCount(matchOfDetected), 2);
    });
  });

  group('one-to-one', () {
    test('one detection cannot satisfy two expected events', () {
      final matchOfDetected = matchWithinTolerance(
        expected: const [100, 110],
        detected: const [105],
        tolerance: 50,
      );
      expect(_matchCount(matchOfDetected), 1);
      // The nearer of the two wins, because preferring it costs no cardinality.
      expect(matchOfDetected.single, 0);
    });

    test('a surplus detection stays unmatched', () {
      final matchOfDetected = matchWithinTolerance(
        expected: const [100],
        detected: const [100, 120],
        tolerance: 50,
      );
      expect(matchOfDetected, [0, -1]);
    });
  });

  group('the window', () {
    test('the boundary is inclusive, as the evaluation harness has it', () {
      expect(
        matchWithinTolerance(
          expected: const [0],
          detected: const [50],
          tolerance: 50,
        ),
        [0],
      );
      expect(
        matchWithinTolerance(
          expected: const [0],
          detected: const [51],
          tolerance: 50,
        ),
        [-1],
      );
    });

    test('a zero window matches only exact coincidence', () {
      expect(
        matchWithinTolerance(
          expected: const [7],
          detected: const [7, 8],
          tolerance: 0,
        ),
        [0, -1],
      );
    });

    test(
      'a negative window is rejected rather than silently matching none',
      () {
        expect(
          () => matchWithinTolerance(
            expected: const [0],
            detected: const [0],
            tolerance: -1,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('empty input on either side matches nothing', () {
      expect(
        matchWithinTolerance(
          expected: const [],
          detected: const [1, 2],
          tolerance: 50,
        ),
        [-1, -1],
      );
      expect(
        matchWithinTolerance(
          expected: const [1, 2],
          detected: const [],
          tolerance: 50,
        ),
        isEmpty,
      );
    });
  });

  group('indices refer to the lists as given', () {
    test('an unsorted input is not silently renumbered', () {
      // The helper must not sort: a caller's event indices are its own.
      final matchOfDetected = matchWithinTolerance(
        expected: const [200, 100],
        detected: const [100, 200],
        tolerance: 10,
      );
      expect(matchOfDetected, [1, 0]);
    });
  });

  group('the raw Kuhn helper', () {
    test('an augmenting path reassigns an already-matched right node', () {
      // Left 0 admits only right 0; left 1 prefers right 0 but also admits
      // right 1. Taking left 1's preference first and then augmenting is what
      // gets both matched — the behaviour the greedy strategy lacks.
      final matchOfRight = maxCardinalityMatching(
        leftCount: 2,
        candidatesByLeft: const [
          [0],
          [0, 1],
        ],
        rightCount: 2,
      );
      expect(matchOfRight, [0, 1]);
    });

    test('candidate order breaks ties, so the result is deterministic', () {
      expect(
        maxCardinalityMatching(
          leftCount: 1,
          candidatesByLeft: const [
            [1, 0],
          ],
          rightCount: 2,
        ),
        [-1, 0],
      );
    });

    test('a left node with no candidates stays unmatched', () {
      expect(
        maxCardinalityMatching(
          leftCount: 2,
          candidatesByLeft: const [
            [],
            [0],
          ],
          rightCount: 1,
        ),
        [1],
      );
    });
  });

  test('the measured tolerance is the one the release gate reports', () {
    // `onsetTolerance50Ms` in the recognition release gate, and
    // `toleranceUs: 50000` in the real-audio baseline harness.
    expect(onsetToleranceMsPrimary, 50);
  });
}
