import '../../domain/insights/insight_rule.dart';

/// Stable registry for the standalone deterministic insight module.
final class InsightRegistry {
  InsightRegistry(Iterable<AnalysisInsightRule> rules)
    : _rules = List<AnalysisInsightRule>.unmodifiable(rules.toList()) {
    final ids = _rules.map((rule) => rule.id).toSet();
    if (ids.length != _rules.length) {
      throw ArgumentError('Insight rule IDs must be unique.');
    }
  }

  final List<AnalysisInsightRule> _rules;

  List<AnalysisInsightRule> get rules => _rules;

  List<EvidenceBackedAnalysisInsight> evaluate(
    AnalysisInsightContext context,
  ) => _rules
      .map((rule) => rule.evaluate(context))
      .whereType<EvidenceBackedAnalysisInsight>()
      .toList(growable: false);
}
