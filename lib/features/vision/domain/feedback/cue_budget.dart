import 'feedback_policy.dart';
import 'insight_code.dart';

/// Stateful, deterministic budget for realtime cues and session summaries.
final class CueBudget {
  CueBudget({required this.now});

  final DateTime Function() now;
  final Map<InsightCode, DateTime> _lastEmittedAt = <InsightCode, DateTime>{};

  VisionInsight? selectRealtime(Iterable<VisionInsight> insights) {
    final timestamp = now().toUtc();
    final eligible =
        insights
            .where((insight) => _isCooldownComplete(insight, timestamp))
            .toList()
          ..sort(_compareInsights);
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
    final priority = second.priority.compareTo(first.priority);
    if (priority != 0) return priority;
    return first.code.safetyCode.compareTo(second.code.safetyCode);
  }
}
