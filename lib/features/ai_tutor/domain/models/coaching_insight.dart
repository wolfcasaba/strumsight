import 'package:meta/meta.dart';

/// Codes emitted by deterministic coaching.
abstract final class CoachingInsightCode {
  static const String lowEvidence = 'ai_tutor.insight.low_evidence';
  static const String lateBias = 'practice.insight.bias_late';
  static const String wrongDirection = 'practice.insight.direction_error';
  static const String lowChordAccuracy = 'practice.insight.chord_error';
  static const String inconsistentSection =
      'ai_tutor.insight.section_inconsistent';
  static const String notComparable = 'ai_tutor.insight.not_comparable';
  static const String improvedFromPrevious =
      'ai_tutor.insight.improved_from_previous';
  static const String firstEvidence = 'ai_tutor.insight.first_evidence';
  static const String stableTempo = 'ai_tutor.insight.stable_tempo';
  static const String measuredSession = 'ai_tutor.insight.measured_session';
}

/// Localization keys used by deterministic coaching.
abstract final class CoachingLocalizationKey {
  static const String lowEvidenceTitle = 'aiTutorCoachLowEvidenceTitle';
  static const String lowEvidenceExplanation =
      'aiTutorCoachLowEvidenceExplanation';
  static const String lowEvidenceUncertainty =
      'aiTutorCoachLowEvidenceUncertainty';
  static const String lateBiasTitle = 'aiTutorCoachLateBiasTitle';
  static const String lateBiasExplanation = 'aiTutorCoachLateBiasExplanation';
  static const String directionTitle = 'aiTutorCoachDirectionTitle';
  static const String directionExplanation = 'aiTutorCoachDirectionExplanation';
  static const String chordTitle = 'aiTutorCoachChordTitle';
  static const String chordExplanation = 'aiTutorCoachChordExplanation';
  static const String sectionTitle = 'aiTutorCoachSectionTitle';
  static const String sectionExplanation = 'aiTutorCoachSectionExplanation';
  static const String notComparableTitle = 'aiTutorCoachNotComparableTitle';
  static const String notComparableExplanation =
      'aiTutorCoachNotComparableExplanation';
  static const String improvedTitle = 'aiTutorCoachImprovedTitle';
  static const String improvedExplanation = 'aiTutorCoachImprovedExplanation';
  static const String firstEvidenceTitle = 'aiTutorCoachFirstEvidenceTitle';
  static const String firstEvidenceExplanation =
      'aiTutorCoachFirstEvidenceExplanation';
  static const String stableTempoTitle = 'aiTutorCoachStableTempoTitle';
  static const String stableTempoExplanation =
      'aiTutorCoachStableTempoExplanation';
  static const String measuredSessionTitle = 'aiTutorCoachMeasuredSessionTitle';
  static const String measuredSessionExplanation =
      'aiTutorCoachMeasuredSessionExplanation';
  static const String collectEvidenceAction =
      'aiTutorCoachActionCollectEvidence';
  static const String rhythmOnlyAction = 'aiTutorCoachActionRhythmOnly';
  static const String directionAction = 'aiTutorCoachActionDirection';
  static const String chordChangesAction = 'aiTutorCoachActionChordChanges';
  static const String repeatSectionAction = 'aiTutorCoachActionRepeatSection';
  static const String comparableSessionAction =
      'aiTutorCoachActionComparableSession';
  static const String keepTempoAction = 'aiTutorCoachActionKeepTempo';
}

/// How firmly an insight can be stated from its available evidence.
enum CoachingUncertainty { none, lowEvidence }

/// A coaching output with evidence and localization keys.
@immutable
final class CoachingInsight {
  CoachingInsight({
    required String code,
    required String titleLocalizationKey,
    required String explanationLocalizationKey,
    required Iterable<String> evidenceRefs,
    required this.priority,
    required String suggestedActionTemplate,
    required this.uncertainty,
    required this.hasConflictingEvidence,
  }) : code = _requiredText(code, 'code'),
       titleLocalizationKey = _requiredText(
         titleLocalizationKey,
         'titleLocalizationKey',
       ),
       explanationLocalizationKey = _requiredText(
         explanationLocalizationKey,
         'explanationLocalizationKey',
       ),
       evidenceRefs = List<String>.unmodifiable(
         evidenceRefs.map((ref) => _requiredText(ref, 'evidenceRefs')),
       ),
       suggestedActionTemplate = _requiredText(
         suggestedActionTemplate,
         'suggestedActionTemplate',
       ) {
    if (priority < 0) {
      throw ArgumentError.value(priority, 'priority');
    }
    if (this.evidenceRefs.isEmpty) {
      throw ArgumentError.value(evidenceRefs, 'evidenceRefs');
    }
  }

  final String code;
  final String titleLocalizationKey;
  final String explanationLocalizationKey;
  final List<String> evidenceRefs;
  final int priority;
  final String suggestedActionTemplate;
  final CoachingUncertainty uncertainty;
  final bool hasConflictingEvidence;
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name);
  }
  return normalized;
}
