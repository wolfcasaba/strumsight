/// Minimum matched-pair gate for timing metric publication (ADR 0232 §4,
/// R14 brief OD-01). Below the gate, a metric is `unavailable` with
/// [CapabilityUnavailableReason.insufficientEvents] and no value — never a
/// synthetic zero.
final class MetricGate {
  const MetricGate({
    this.minimumMatchedPairs = 8,
    this.minimumStreakMatchedPairs = 3,
  }) : assert(minimumMatchedPairs > 0),
       assert(minimumStreakMatchedPairs > 0);

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
