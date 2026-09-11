/// The shared one-to-one time matcher, and the measured tolerance it runs at.
///
/// ## Why this is shared, and not a local helper
///
/// `docs/LESSONS.md` L269 (E06-R29) measured that the obvious strategy — walk
/// both lists and take the closest still-free partner — does NOT maximise the
/// number of matches. Its counterexample: expected `50, 90`, detected `0, 55`,
/// tolerance 50. Greedy pairs `50↔55` and then has nothing left for `90`, for
/// one match; pairing `50↔0` and `90↔55` gives two. Under-counting matches is
/// not a neutral rounding error — in an evaluation it understates the
/// recogniser, and in a practice exercise it tells a learner they missed a
/// stroke they actually played.
///
/// L269's instruction is therefore not "fix each path" but "**every**
/// time-windowed one-to-one metric uses the SAME maximum-cardinality helper —
/// the shared matcher is part of the contract". This file is that home.
///
/// Pure Dart, no Flutter, no I/O (SDD Ch2 §10.1).
library;

/// The onset tolerance the recogniser is MEASURED against.
///
/// The recognition release gate reports `onsetTolerance50Ms`, and the
/// real-audio baseline harness matches onsets at `toleranceUs: 50000`. Anything
/// that needs a notion of "in time" takes it from here, so the app has ONE such
/// notion and it is the one with a measured basis — not a second, guessed
/// window that happens to look reasonable.
const int onsetToleranceMsPrimary = 50;

/// Maximum-cardinality one-to-one matching (Kuhn's augmenting-path algorithm)
/// between `leftCount` left nodes and `rightCount` right nodes.
///
/// [candidatesByLeft] gives each left node's admissible right nodes, in
/// preference order — ties in cardinality are broken by that order, so the
/// caller controls WHICH maximum matching is returned, and the result is
/// deterministic.
///
/// Returns `matchOfRight`: `matchOfRight[j]` is the left index matched to right
/// node `j`, or `-1` when `j` is unmatched.
List<int> maxCardinalityMatching({
  required int leftCount,
  required List<List<int>> candidatesByLeft,
  required int rightCount,
}) {
  final matchOfRight = List<int>.filled(rightCount, -1);

  bool tryAugment(int leftIndex, List<bool> visited) {
    for (final rightIndex in candidatesByLeft[leftIndex]) {
      if (visited[rightIndex]) continue;
      visited[rightIndex] = true;
      if (matchOfRight[rightIndex] == -1 ||
          tryAugment(matchOfRight[rightIndex], visited)) {
        matchOfRight[rightIndex] = leftIndex;
        return true;
      }
    }
    return false;
  }

  for (var i = 0; i < leftCount; i++) {
    tryAugment(i, List<bool>.filled(rightCount, false));
  }
  return matchOfRight;
}

/// Matches [expected] times to [detected] times, one-to-one, within
/// [tolerance], maximising the number of matched pairs.
///
/// All three arguments are in the SAME unit — milliseconds, microseconds or
/// ticks — and this function never converts between units. The boundary is
/// inclusive (`<=`), matching the evaluation harness.
///
/// Indices in the result refer to the positions in the lists AS GIVEN. Callers
/// that need time order must sort before calling; sorting here would silently
/// renumber their own events.
///
/// Returns `matchOfDetected`: `matchOfDetected[j]` is the index in [expected]
/// matched to `detected[j]`, or `-1` when nothing matched it.
List<int> matchWithinTolerance({
  required List<int> expected,
  required List<int> detected,
  required int tolerance,
}) {
  if (tolerance < 0) {
    throw ArgumentError.value(
      tolerance,
      'tolerance',
      'a negative window would match nothing and says nothing',
    );
  }
  // Closest-gap-first, then lowest index: the preference order that makes the
  // chosen maximum matching deterministic and the nearest pairing preferred
  // whenever preferring it costs no cardinality.
  final candidatesByExpected = List<List<int>>.generate(expected.length, (i) {
    final gaps =
        <({int index, int gap})>[
          for (var j = 0; j < detected.length; j++)
            if ((detected[j] - expected[i]).abs() <= tolerance)
              (index: j, gap: (detected[j] - expected[i]).abs()),
        ]..sort((a, b) {
          final byGap = a.gap.compareTo(b.gap);
          return byGap != 0 ? byGap : a.index.compareTo(b.index);
        });
    return [for (final candidate in gaps) candidate.index];
  });

  return maxCardinalityMatching(
    leftCount: expected.length,
    candidatesByLeft: candidatesByExpected,
    rightCount: detected.length,
  );
}
