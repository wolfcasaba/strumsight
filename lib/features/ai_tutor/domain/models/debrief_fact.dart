import 'package:meta/meta.dart';

/// Fact codes accepted by [DebriefFact].
abstract final class DebriefFactCode {
  static const String lowEvidence = 'practice.lowEvidence';
  static const String lateBias = 'timing.lateBias';
  static const String wrongDirectionRate = 'strum.wrongDirectionRate';
  static const String lowChordAccuracy = 'chord.lowAccuracy';
  static const String inconsistentSection = 'section.inconsistent';
  static const String notComparableToPrevious =
      'practice.notComparableToPrevious';
  static const String improvedFromPrevious = 'practice.improvedFromPrevious';
  static const String firstEvidence = 'practice.firstEvidence';
  static const String stableTempo = 'speed.stableAtBpm';
  static const String measuredSession = 'practice.measuredSession';
}

/// Origin type for a fact used by deterministic coaching.
enum DebriefFactProvenance { measuredFact, computedTrend }

/// A fact with evidence refs for coaching.
@immutable
final class DebriefFact {
  DebriefFact({
    required String code,
    required this.value,
    required this.provenance,
    required this.confidence,
    required this.priority,
    required Iterable<String> evidenceRefs,
    this.comparableEvidenceGroupCount = 1,
  }) : code = _requiredText(code, 'code'),
       evidenceRefs = List<String>.unmodifiable(
         evidenceRefs.map((ref) => _requiredText(ref, 'evidenceRefs')),
       ) {
    if (confidence < 0 || confidence > confidenceScale) {
      throw ArgumentError.value(confidence, 'confidence');
    }
    if (priority < 0) {
      throw ArgumentError.value(priority, 'priority');
    }
    if (this.evidenceRefs.isEmpty) {
      throw ArgumentError.value(evidenceRefs, 'evidenceRefs');
    }
    if (comparableEvidenceGroupCount < 1) {
      throw ArgumentError.value(
        comparableEvidenceGroupCount,
        'comparableEvidenceGroupCount',
      );
    }
    if (provenance == DebriefFactProvenance.computedTrend &&
        comparableEvidenceGroupCount < 2) {
      throw ArgumentError.value(
        comparableEvidenceGroupCount,
        'comparableEvidenceGroupCount',
      );
    }
  }

  static const int confidenceScale = 10000;

  final String code;
  final int value;
  final DebriefFactProvenance provenance;
  final int confidence;
  final int priority;
  final List<String> evidenceRefs;
  final int comparableEvidenceGroupCount;
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name);
  }
  return normalized;
}
