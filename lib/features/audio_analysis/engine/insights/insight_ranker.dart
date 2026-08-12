import '../../domain/insights/insight_rule.dart';

/// Result of applying the E06-R20 maximum policy. The slots are intentionally
/// explicit so a later UI cannot accidentally display multiple negatives.
final class RankedAnalysisInsights {
  const RankedAnalysisInsights({
    required this.improvement,
    required this.strength,
    required this.nextAction,
    required this.qualityWarning,
    required this.additionalInsights,
  });

  final EvidenceBackedAnalysisInsight? improvement;
  final EvidenceBackedAnalysisInsight? strength;
  final EvidenceBackedAnalysisInsight? nextAction;
  final EvidenceBackedAnalysisInsight? qualityWarning;
  final List<EvidenceBackedAnalysisInsight> additionalInsights;

  List<EvidenceBackedAnalysisInsight> get visibleInsights =>
      <EvidenceBackedAnalysisInsight>[
        ?improvement,
        ?strength,
        ?nextAction,
        ?qualityWarning,
      ];
}

final class InsightRanker {
  const InsightRanker();

  RankedAnalysisInsights rank(Iterable<EvidenceBackedAnalysisInsight> values) {
    final ordered = values.toList()
      ..sort((left, right) {
        final priority = left.priority.index.compareTo(right.priority.index);
        return priority != 0 ? priority : left.ruleId.compareTo(right.ruleId);
      });
    EvidenceBackedAnalysisInsight? pick(EvidenceInsightKind kind) {
      for (final insight in ordered) {
        if (insight.kind == kind) return insight;
      }
      return null;
    }

    final selected = <EvidenceBackedAnalysisInsight>{
      ?pick(EvidenceInsightKind.improvement),
      ?pick(EvidenceInsightKind.strength),
      ?pick(EvidenceInsightKind.nextAction),
      ?pick(EvidenceInsightKind.qualityWarning),
    };
    return RankedAnalysisInsights(
      improvement: pick(EvidenceInsightKind.improvement),
      strength: pick(EvidenceInsightKind.strength),
      nextAction: pick(EvidenceInsightKind.nextAction),
      qualityWarning: pick(EvidenceInsightKind.qualityWarning),
      additionalInsights: List<EvidenceBackedAnalysisInsight>.unmodifiable(
        ordered.where((insight) => !selected.contains(insight)),
      ),
    );
  }
}
