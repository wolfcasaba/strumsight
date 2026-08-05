import '../../domain/models/debrief_fact.dart';

/// Session measurements accepted by the debrief builder.
final class SessionDebriefInput {
  SessionDebriefInput({
    required String sessionEvidenceRef,
    required String comparisonKey,
    required this.pairedEventCount,
    this.timingBiasMilliseconds,
    this.lateShareBasisPoints,
    this.wrongDirectionRateBasisPoints,
    this.chordAccuracyBasisPoints,
    this.sectionConsistencyBasisPoints,
    this.stableTempoBpm,
    this.currentScoreBasisPoints,
    String? previousEvidenceRef,
    String? previousComparisonKey,
    this.previousScoreBasisPoints,
  }) : sessionEvidenceRef = _requiredText(
         sessionEvidenceRef,
         'sessionEvidenceRef',
       ),
       comparisonKey = _requiredText(comparisonKey, 'comparisonKey'),
       previousEvidenceRef = previousEvidenceRef == null
           ? null
           : _requiredText(previousEvidenceRef, 'previousEvidenceRef'),
       previousComparisonKey = previousComparisonKey == null
           ? null
           : _requiredText(previousComparisonKey, 'previousComparisonKey') {
    if (pairedEventCount < 0) {
      throw ArgumentError.value(pairedEventCount, 'pairedEventCount');
    }
    _validateBasisPoints(lateShareBasisPoints, 'lateShareBasisPoints');
    _validateBasisPoints(
      wrongDirectionRateBasisPoints,
      'wrongDirectionRateBasisPoints',
    );
    _validateBasisPoints(chordAccuracyBasisPoints, 'chordAccuracyBasisPoints');
    _validateBasisPoints(
      sectionConsistencyBasisPoints,
      'sectionConsistencyBasisPoints',
    );
    _validateBasisPoints(currentScoreBasisPoints, 'currentScoreBasisPoints');
    _validateBasisPoints(previousScoreBasisPoints, 'previousScoreBasisPoints');
    if (stableTempoBpm != null && stableTempoBpm! < 1) {
      throw ArgumentError.value(stableTempoBpm, 'stableTempoBpm');
    }
    final hasPreviousEvidence = this.previousEvidenceRef != null;
    if (hasPreviousEvidence != (this.previousComparisonKey != null) ||
        hasPreviousEvidence != (previousScoreBasisPoints != null)) {
      throw ArgumentError(
        'Previous evidence, comparison key, and score must be supplied together.',
      );
    }
  }

  final String sessionEvidenceRef;
  final String comparisonKey;
  final int pairedEventCount;
  final int? timingBiasMilliseconds;
  final int? lateShareBasisPoints;
  final int? wrongDirectionRateBasisPoints;
  final int? chordAccuracyBasisPoints;
  final int? sectionConsistencyBasisPoints;
  final int? stableTempoBpm;
  final int? currentScoreBasisPoints;
  final String? previousEvidenceRef;
  final String? previousComparisonKey;
  final int? previousScoreBasisPoints;
}

/// Builds facts that a coach may prioritize.
final class SessionDebriefBuilder {
  const SessionDebriefBuilder();

  static const int minimumPairedEvidence = 8;

  List<DebriefFact> build(SessionDebriefInput input) {
    final facts = <DebriefFact>[];
    final confidence = _confidenceForPairedEvidence(input.pairedEventCount);

    if (input.pairedEventCount < minimumPairedEvidence) {
      facts.add(
        DebriefFact(
          code: DebriefFactCode.lowEvidence,
          value: input.pairedEventCount,
          provenance: DebriefFactProvenance.measuredFact,
          confidence: confidence,
          priority: _lowEvidencePriority,
          evidenceRefs: <String>[input.sessionEvidenceRef],
        ),
      );
    }

    if (input.pairedEventCount >= minimumPairedEvidence &&
        input.timingBiasMilliseconds != null &&
        input.timingBiasMilliseconds! > 0 &&
        (input.lateShareBasisPoints ?? 0) >= _biasMinShareBasisPoints) {
      facts.add(
        DebriefFact(
          code: DebriefFactCode.lateBias,
          value: input.lateShareBasisPoints!,
          provenance: DebriefFactProvenance.measuredFact,
          confidence: confidence,
          priority: _lateBiasPriority,
          evidenceRefs: <String>[input.sessionEvidenceRef],
        ),
      );
    }

    final wrongDirectionRate = input.wrongDirectionRateBasisPoints;
    if (wrongDirectionRate != null &&
        wrongDirectionRate >= _wrongDirectionRateThreshold) {
      facts.add(
        DebriefFact(
          code: DebriefFactCode.wrongDirectionRate,
          value: wrongDirectionRate,
          provenance: DebriefFactProvenance.measuredFact,
          confidence: confidence,
          priority: _wrongDirectionPriority,
          evidenceRefs: <String>[input.sessionEvidenceRef],
        ),
      );
    }

    final chordAccuracy = input.chordAccuracyBasisPoints;
    if (chordAccuracy != null && chordAccuracy < _chordAccuracyThreshold) {
      facts.add(
        DebriefFact(
          code: DebriefFactCode.lowChordAccuracy,
          value: chordAccuracy,
          provenance: DebriefFactProvenance.measuredFact,
          confidence: confidence,
          priority: _lowChordPriority,
          evidenceRefs: <String>[input.sessionEvidenceRef],
        ),
      );
    }

    final sectionConsistency = input.sectionConsistencyBasisPoints;
    if (sectionConsistency != null &&
        sectionConsistency < _sectionConsistencyThreshold) {
      facts.add(
        DebriefFact(
          code: DebriefFactCode.inconsistentSection,
          value: sectionConsistency,
          provenance: DebriefFactProvenance.measuredFact,
          confidence: confidence,
          priority: _sectionConsistencyPriority,
          evidenceRefs: <String>[input.sessionEvidenceRef],
        ),
      );
    }

    final previousEvidenceRef = input.previousEvidenceRef;
    if (previousEvidenceRef == null) {
      facts.add(
        DebriefFact(
          code: DebriefFactCode.firstEvidence,
          value: input.pairedEventCount,
          provenance: DebriefFactProvenance.measuredFact,
          confidence: confidence,
          priority: _firstEvidencePriority,
          evidenceRefs: <String>[input.sessionEvidenceRef],
        ),
      );
    } else if (input.previousComparisonKey != input.comparisonKey) {
      facts.add(
        DebriefFact(
          code: DebriefFactCode.notComparableToPrevious,
          value: _notComparableValue,
          provenance: DebriefFactProvenance.measuredFact,
          confidence: confidence,
          priority: _nonComparablePriority,
          evidenceRefs: <String>[input.sessionEvidenceRef, previousEvidenceRef],
        ),
      );
    } else if (input.currentScoreBasisPoints != null &&
        input.currentScoreBasisPoints! > input.previousScoreBasisPoints!) {
      facts.add(
        DebriefFact(
          code: DebriefFactCode.improvedFromPrevious,
          value:
              input.currentScoreBasisPoints! - input.previousScoreBasisPoints!,
          provenance: DebriefFactProvenance.computedTrend,
          confidence: _trendConfidence,
          priority: _improvedPriority,
          evidenceRefs: <String>[input.sessionEvidenceRef, previousEvidenceRef],
          comparableEvidenceGroupCount: _comparableGroupsForTrend,
        ),
      );
    }

    final stableTempoBpm = input.stableTempoBpm;
    if (stableTempoBpm != null) {
      facts.add(
        DebriefFact(
          code: DebriefFactCode.stableTempo,
          value: stableTempoBpm,
          provenance: DebriefFactProvenance.measuredFact,
          confidence: confidence,
          priority: _stableTempoPriority,
          evidenceRefs: <String>[input.sessionEvidenceRef],
        ),
      );
    }

    if (facts.isEmpty) {
      facts.add(
        DebriefFact(
          code: DebriefFactCode.measuredSession,
          value: input.pairedEventCount,
          provenance: DebriefFactProvenance.measuredFact,
          confidence: confidence,
          priority: _measuredSessionPriority,
          evidenceRefs: <String>[input.sessionEvidenceRef],
        ),
      );
    }

    facts.sort(_compareFacts);
    return List<DebriefFact>.unmodifiable(facts);
  }

  static const int _lowEvidencePriority = 0;
  static const int _lateBiasPriority = 10;
  static const int _wrongDirectionPriority = 20;
  static const int _lowChordPriority = 30;
  static const int _sectionConsistencyPriority = 40;
  static const int _nonComparablePriority = 50;
  static const int _improvedPriority = 60;
  static const int _firstEvidencePriority = 70;
  static const int _stableTempoPriority = 80;
  static const int _measuredSessionPriority = 90;
  static const int _biasMinShareBasisPoints = 7000;
  static const int _wrongDirectionRateThreshold = 4000;
  static const int _chordAccuracyThreshold = 6000;
  static const int _sectionConsistencyThreshold = 7000;
  static const int _trendConfidence = 4000;
  static const int _comparableGroupsForTrend = 2;
  static const int _notComparableValue = 0;
  static const int _confidencePerPairedEvent = 1000;
}

String _requiredText(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name);
  }
  return normalized;
}

void _validateBasisPoints(int? value, String name) {
  if (value != null && (value < 0 || value > DebriefFact.confidenceScale)) {
    throw ArgumentError.value(value, name);
  }
}

int _confidenceForPairedEvidence(int pairedEventCount) {
  final confidence =
      pairedEventCount * SessionDebriefBuilder._confidencePerPairedEvent;
  return confidence > DebriefFact.confidenceScale
      ? DebriefFact.confidenceScale
      : confidence;
}

int _compareFacts(DebriefFact left, DebriefFact right) {
  final priorityComparison = left.priority.compareTo(right.priority);
  return priorityComparison != 0
      ? priorityComparison
      : left.code.compareTo(right.code);
}
