/// Stable machine-readable codes emitted by Practice domain validation.
abstract final class PracticeValidationCode {
  static const String tempoBpmNotFinite = 'tempo.bpm.notFinite';
  static const String tempoBpmOutOfRange = 'tempo.bpm.outOfRange';
  static const String meterBeatsPerBarOutOfRange =
      'meter.beatsPerBar.outOfRange';
  static const String meterBeatUnitUnsupported = 'meter.beatUnit.unsupported';
  static const String beatPositionNegative = 'beatPosition.negative';
  static const String eventIdEmpty = 'event.id.empty';
  static const String eventChordInvalid = 'event.chord.invalid';
  static const String eventDurationNonPositive = 'event.duration.nonPositive';
  static const String eventScorableMissing = 'event.scorable.missing';
  static const String eventMarkerScorable = 'event.marker.scorable';
  static const String eventsEmpty = 'events.empty';
  static const String eventsUnsorted = 'events.unsorted';
  static const String eventsIdDuplicate = 'events.idDuplicate';
  static const String eventsPositionDuplicate = 'events.positionDuplicate';
  static const String eventPositionOutOfRange = 'event.position.outOfRange';
  static const String definitionIdEmpty = 'definition.id.empty';
  static const String definitionSchemaVersionInvalid =
      'definition.schemaVersion.invalid';
  static const String definitionTitleKeyEmpty = 'definition.titleKey.empty';
  static const String definitionDescriptionKeyEmpty =
      'definition.descriptionKey.empty';
  static const String definitionTotalBeatsNonPositive =
      'definition.totalBeats.nonPositive';
  static const String definitionScoringProfileIncompatibleWithMode =
      'definition.scoringProfile.incompatibleWithMode';
  static const String definitionDisplayTitleBlank =
      'definition.displayTitle.blank';
  static const String configDefinitionIdEmpty = 'config.definitionId.empty';
  static const String configSnapshotVersionInvalid =
      'config.snapshotVersion.invalid';
  static const String configCountInBarsOutOfRange =
      'config.countInBars.outOfRange';
  static const String configLoopCountOutOfRange = 'config.loopCount.outOfRange';
  static const String configInputLatencyOutOfRange =
      'config.inputLatency.outOfRange';
  static const String configVisualLatencyOutOfRange =
      'config.visualLatency.outOfRange';
  static const String configSessionTimeoutNonPositive =
      'config.sessionTimeout.nonPositive';
  static const String configScoringProfileIdEmpty =
      'config.scoringProfileId.empty';
  static const String observationAtNegative = 'observation.at.negative';
  static const String observationSequenceNegative =
      'observation.sequence.negative';
  static const String observationConfidenceNotFinite =
      'observation.confidence.notFinite';
  static const String observationConfidenceOutOfRange =
      'observation.confidence.outOfRange';
  static const String observationChordInvalid = 'observation.chord.invalid';
  static const String verdictTargetEventIdEmpty = 'verdict.targetEventId.empty';
  static const String verdictEventScoreNotFinite =
      'verdict.eventScore.notFinite';
  static const String verdictEventScoreOutOfRange =
      'verdict.eventScore.outOfRange';
  static const String verdictMatchInconsistent = 'verdict.match.inconsistent';
  static const String verdictCoachingCodeUnknown =
      'verdict.coachingCode.unknown';
  static const String metricValueNotFinite = 'metric.value.notFinite';
  static const String metricValueOutOfRange = 'metric.value.outOfRange';
  static const String metricInsufficientDataReasonEmpty =
      'metric.insufficientData.reasonEmpty';
  static const String metricsTotalTargetsNegative =
      'metrics.totalTargets.negative';
  static const String metricsResolvedTargetsExceedsTotal =
      'metrics.resolvedTargets.exceedsTotal';
  static const String metricsMaxComboNegative = 'metrics.maxCombo.negative';
  static const String metricsScorePointsNegative =
      'metrics.scorePoints.negative';
  static const String metricsMeanAbsoluteOffsetNegative =
      'metrics.meanAbsoluteOffset.negative';
  static const String attemptIndexNegative = 'attempt.index.negative';
  static const String attemptVerdictsTargetDuplicate =
      'attempt.verdicts.targetDuplicate';
  static const String sessionIdEmpty = 'session.id.empty';
  static const String sessionAttemptsEmpty = 'session.attempts.empty';
  static const String sessionAttemptsUnordered = 'session.attempts.unordered';
  static const String sessionDurationNegative = 'session.duration.negative';
  static const String sessionCoachingSummaryUnknownCode =
      'session.coachingSummary.unknownCode';
  static const String scoringProfileIdEmpty = 'scoringProfile.id.empty';
  static const String scoringProfileWindowNonPositive =
      'scoringProfile.window.nonPositive';
  static const String scoringProfileWindowOrdering =
      'scoringProfile.window.ordering';
  static const String scoringProfileWeightsNegative =
      'scoringProfile.weights.negative';
  static const String scoringProfileWeightsSumNotHundred =
      'scoringProfile.weights.sumNotHundred';
  static const String scoringProfileThresholdOutOfRange =
      'scoringProfile.threshold.outOfRange';

  /// The complete validation-code catalogue for the current Practice domain.
  static const Set<String> values = {
    tempoBpmNotFinite,
    tempoBpmOutOfRange,
    meterBeatsPerBarOutOfRange,
    meterBeatUnitUnsupported,
    beatPositionNegative,
    eventIdEmpty,
    eventChordInvalid,
    eventDurationNonPositive,
    eventScorableMissing,
    eventMarkerScorable,
    eventsEmpty,
    eventsUnsorted,
    eventsIdDuplicate,
    eventsPositionDuplicate,
    eventPositionOutOfRange,
    definitionIdEmpty,
    definitionSchemaVersionInvalid,
    definitionTitleKeyEmpty,
    definitionDescriptionKeyEmpty,
    definitionTotalBeatsNonPositive,
    definitionScoringProfileIncompatibleWithMode,
    definitionDisplayTitleBlank,
    configDefinitionIdEmpty,
    configSnapshotVersionInvalid,
    configCountInBarsOutOfRange,
    configLoopCountOutOfRange,
    configInputLatencyOutOfRange,
    configVisualLatencyOutOfRange,
    configSessionTimeoutNonPositive,
    configScoringProfileIdEmpty,
    observationAtNegative,
    observationSequenceNegative,
    observationConfidenceNotFinite,
    observationConfidenceOutOfRange,
    observationChordInvalid,
    verdictTargetEventIdEmpty,
    verdictEventScoreNotFinite,
    verdictEventScoreOutOfRange,
    verdictMatchInconsistent,
    verdictCoachingCodeUnknown,
    metricValueNotFinite,
    metricValueOutOfRange,
    metricInsufficientDataReasonEmpty,
    metricsTotalTargetsNegative,
    metricsResolvedTargetsExceedsTotal,
    metricsMaxComboNegative,
    metricsScorePointsNegative,
    metricsMeanAbsoluteOffsetNegative,
    attemptIndexNegative,
    attemptVerdictsTargetDuplicate,
    sessionIdEmpty,
    sessionAttemptsEmpty,
    sessionAttemptsUnordered,
    sessionDurationNegative,
    sessionCoachingSummaryUnknownCode,
    scoringProfileIdEmpty,
    scoringProfileWindowNonPositive,
    scoringProfileWindowOrdering,
    scoringProfileWeightsNegative,
    scoringProfileWeightsSumNotHundred,
    scoringProfileThresholdOutOfRange,
  };
}

/// One data-driven Practice domain validation problem.
///
/// [code] is stable and machine-readable. [message] is a human-readable
/// diagnostic for developers and adapters; presentation layers localize by
/// [code] instead of displaying this text directly.
final class PracticeValidationFailure {
  const PracticeValidationFailure({required this.code, required this.message});

  final String code;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is PracticeValidationFailure &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() =>
      'PracticeValidationFailure(code: $code, message: $message)';
}
