enum AnalysisInsightPriority { low, medium, high }

enum AnalysisInsightKind { observation, recommendation, caution }

enum AnalysisRecommendedAction {
  repeatSection,
  slowDown,
  adjustInput,
  continuePractice,
}

/// Localisation-neutral deterministic coaching fact (SDD Ch7 §9.10).
final class AnalysisInsight {
  AnalysisInsight({
    required this.id,
    required this.ruleId,
    required this.ruleVersion,
    required this.priority,
    required this.kind,
    required List<String> factIds,
    required this.messageKey,
    Map<String, String> messageArgs = const <String, String>{},
    required this.recommendedAction,
  }) : factIds = List<String>.unmodifiable(factIds),
       messageArgs = Map<String, String>.unmodifiable(messageArgs) {
    if (<String>[
      id,
      ruleId,
      ruleVersion,
      messageKey,
    ].any((value) => value.trim().isEmpty)) {
      throw ArgumentError('Insight identifiers must be non-empty.');
    }
  }
  final String id;
  final String ruleId;
  final String ruleVersion;
  final AnalysisInsightPriority priority;
  final AnalysisInsightKind kind;
  final List<String> factIds;
  final String messageKey;
  final Map<String, String> messageArgs;
  final AnalysisRecommendedAction recommendedAction;
}
