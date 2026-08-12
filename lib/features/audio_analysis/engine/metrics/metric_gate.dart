/// Minimum matched-pair gate for timing metric publication (ADR 0232 §4,
/// R14 brief OD-01). Below the gate, a metric is `unavailable` with
/// [CapabilityUnavailableReason.insufficientEvents] and no value — never a
/// synthetic zero.
///
/// Both thresholds are validated in the constructor body (not `assert`), so
/// an invalid gate (e.g. `minimumMatchedPairs: 0`) fails closed with an
/// [ArgumentError] in release builds too, instead of letting `_buildSuite`
/// divide a zero-sample suite into a NaN ratio (security review R14 §1).
final class MetricGate {
  MetricGate({
    this.minimumMatchedPairs = 8,
    this.minimumStreakMatchedPairs = 3,
  }) {
    if (minimumMatchedPairs <= 0) {
      throw ArgumentError.value(
        minimumMatchedPairs,
        'minimumMatchedPairs',
        'must be > 0',
      );
    }
    if (minimumStreakMatchedPairs <= 0) {
      throw ArgumentError.value(
        minimumStreakMatchedPairs,
        'minimumStreakMatchedPairs',
        'must be > 0',
      );
    }
  }

  /// Minimum MATCHED pairs (not total observed) for the nine error/ratio
  /// metrics. Inclusive: exactly this many pairs is `available`.
  final int minimumMatchedPairs;

  /// Separate, lower minimum for `longest stable streak` — below this the
  /// notion of a streak is meaningless (OD-01).
  final int minimumStreakMatchedPairs;

  bool isAvailable(int matchedCount) => matchedCount >= minimumMatchedPairs;

  bool isStreakAvailable(int matchedCount) =>
      matchedCount >= minimumStreakMatchedPairs;
}
