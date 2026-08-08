import 'feedback_policy.dart';
import 'insight_code.dart';

/// Stateful, deterministic budget for realtime cues and session summaries.
final class CueBudget {
  CueBudget({required this.now});

  final DateTime Function() now;
  final Map<InsightCode, DateTime> _lastEmittedAt = <InsightCode, DateTime>{};

  VisionInsight? selectRealtime(Iterable<VisionInsight> insights) {
    final timestamp = now().toUtc();
    final candidates = insights.toList()..sort(_compareInsights);
    final setup = candidates
        .where((insight) => insight.direction == InsightDirection.setup)
        .toList();
    if (setup.isNotEmpty) {
      final selected = setup.first;
      _lastEmittedAt[selected.code] = timestamp;
      return selected;
    }

    final eligible = candidates
        .where((insight) => _isCooldownComplete(insight, timestamp))
        .toList();
    if (eligible.isEmpty) return null;

    final selected = eligible.first;
    _lastEmittedAt[selected.code] = timestamp;
    return selected;
  }

  List<VisionInsight> sessionSummary(Iterable<VisionInsight> insights) {
    final technical =
        insights
            .where((insight) => insight.direction != InsightDirection.setup)
            .toList()
          ..sort(_compareInsights);
    return List<VisionInsight>.unmodifiable(technical.take(2));
  }

  bool _isCooldownComplete(VisionInsight insight, DateTime timestamp) {
    final previous = _lastEmittedAt[insight.code];
    if (previous == null) return true;
    final cooldown = FeedbackPolicies.catalog[insight.code]!.cooldown;
    return timestamp.difference(previous) > cooldown;
  }

  static int _compareInsights(VisionInsight first, VisionInsight second) {
    // Intentional, direction-safe order: priority, confidence, positive before
    // negative, then code for a stable final key.
    final priority = second.priority.compareTo(first.priority);
    if (priority != 0) return priority;
    final confidence = second.confidence.compareTo(first.confidence);
    if (confidence != 0) return confidence;
    final direction = _directionTieRank(
      first.direction,
    ).compareTo(_directionTieRank(second.direction));
    if (direction != 0) return direction;
    return first.code.safetyCode.compareTo(second.code.safetyCode);
  }

  static int _directionTieRank(InsightDirection direction) =>
      switch (direction) {
        InsightDirection.setup => 0,
        InsightDirection.positive => 1,
        InsightDirection.negative => 2,
      };
}
