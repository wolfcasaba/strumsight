import '../../domain/models/coaching_insight.dart';
import '../../domain/models/debrief_fact.dart';

/// Localized coaching output.
final class LocalizedCoachingOutput {
  const LocalizedCoachingOutput({
    required this.insight,
    required this.title,
    required this.explanation,
    required this.action,
    required this.uncertaintyText,
  });

  final CoachingInsight insight;
  final String title;
  final String explanation;
  final String action;
  final String? uncertaintyText;
}

/// Selects one grounded focus from a deterministic fact list.
final class DeterministicCoach {
  const DeterministicCoach();

  CoachingInsight coach(Iterable<DebriefFact> facts) {
    final ordered = facts.toList()..sort(_compareFacts);
    if (ordered.isEmpty) {
      throw ArgumentError.value(
        facts,
        'facts',
        'At least one fact is required.',
      );
    }
    return _insightFor(ordered.first);
  }

  LocalizedCoachingOutput localize({
    required CoachingInsight insight,
    required String Function(String key) lookup,
  }) {
    return LocalizedCoachingOutput(
      insight: insight,
      title: lookup(insight.titleLocalizationKey),
      explanation: lookup(insight.explanationLocalizationKey),
      action: lookup(insight.suggestedActionTemplate),
      uncertaintyText: switch (insight.uncertainty) {
        CoachingUncertainty.none => null,
        CoachingUncertainty.lowEvidence => lookup(
          CoachingLocalizationKey.lowEvidenceUncertainty,
        ),
      },
    );
  }

  CoachingInsight _insightFor(DebriefFact fact) => switch (fact.code) {
    DebriefFactCode.lowEvidence => _insight(
      fact: fact,
      code: CoachingInsightCode.lowEvidence,
      title: CoachingLocalizationKey.lowEvidenceTitle,
      explanation: CoachingLocalizationKey.lowEvidenceExplanation,
      action: CoachingLocalizationKey.collectEvidenceAction,
      uncertainty: CoachingUncertainty.lowEvidence,
    ),
    DebriefFactCode.lateBias => _insight(
      fact: fact,
      code: CoachingInsightCode.lateBias,
      title: CoachingLocalizationKey.lateBiasTitle,
      explanation: CoachingLocalizationKey.lateBiasExplanation,
      action: CoachingLocalizationKey.rhythmOnlyAction,
    ),
    DebriefFactCode.wrongDirectionRate => _insight(
      fact: fact,
      code: CoachingInsightCode.wrongDirection,
      title: CoachingLocalizationKey.directionTitle,
      explanation: CoachingLocalizationKey.directionExplanation,
      action: CoachingLocalizationKey.directionAction,
    ),
    DebriefFactCode.lowChordAccuracy => _insight(
      fact: fact,
      code: CoachingInsightCode.lowChordAccuracy,
      title: CoachingLocalizationKey.chordTitle,
      explanation: CoachingLocalizationKey.chordExplanation,
      action: CoachingLocalizationKey.chordChangesAction,
    ),
    DebriefFactCode.inconsistentSection => _insight(
      fact: fact,
      code: CoachingInsightCode.inconsistentSection,
      title: CoachingLocalizationKey.sectionTitle,
      explanation: CoachingLocalizationKey.sectionExplanation,
      action: CoachingLocalizationKey.repeatSectionAction,
    ),
    DebriefFactCode.notComparableToPrevious => _insight(
      fact: fact,
      code: CoachingInsightCode.notComparable,
      title: CoachingLocalizationKey.notComparableTitle,
      explanation: CoachingLocalizationKey.notComparableExplanation,
      action: CoachingLocalizationKey.comparableSessionAction,
      hasConflictingEvidence: true,
    ),
    DebriefFactCode.improvedFromPrevious => _insight(
      fact: fact,
      code: CoachingInsightCode.improvedFromPrevious,
      title: CoachingLocalizationKey.improvedTitle,
      explanation: CoachingLocalizationKey.improvedExplanation,
      action: CoachingLocalizationKey.keepTempoAction,
    ),
    DebriefFactCode.firstEvidence => _insight(
      fact: fact,
      code: CoachingInsightCode.firstEvidence,
      title: CoachingLocalizationKey.firstEvidenceTitle,
      explanation: CoachingLocalizationKey.firstEvidenceExplanation,
      action: CoachingLocalizationKey.collectEvidenceAction,
    ),
    DebriefFactCode.stableTempo => _insight(
      fact: fact,
      code: CoachingInsightCode.stableTempo,
      title: CoachingLocalizationKey.stableTempoTitle,
      explanation: CoachingLocalizationKey.stableTempoExplanation,
      action: CoachingLocalizationKey.keepTempoAction,
    ),
    DebriefFactCode.measuredSession => _insight(
      fact: fact,
      code: CoachingInsightCode.measuredSession,
      title: CoachingLocalizationKey.measuredSessionTitle,
      explanation: CoachingLocalizationKey.measuredSessionExplanation,
      action: CoachingLocalizationKey.collectEvidenceAction,
    ),
    _ => throw ArgumentError.value(fact.code, 'fact.code'),
  };

  CoachingInsight _insight({
    required DebriefFact fact,
    required String code,
    required String title,
    required String explanation,
    required String action,
    CoachingUncertainty uncertainty = CoachingUncertainty.none,
    bool hasConflictingEvidence = false,
  }) => CoachingInsight(
    code: code,
    titleLocalizationKey: title,
    explanationLocalizationKey: explanation,
    evidenceRefs: fact.evidenceRefs,
    priority: fact.priority,
    suggestedActionTemplate: action,
    uncertainty: uncertainty,
    hasConflictingEvidence: hasConflictingEvidence,
  );
}

int _compareFacts(DebriefFact left, DebriefFact right) {
  final priorityComparison = left.priority.compareTo(right.priority);
  return priorityComparison != 0
      ? priorityComparison
      : left.code.compareTo(right.code);
}
