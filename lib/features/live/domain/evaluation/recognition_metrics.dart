/// Flutter-independent recognition-metric set (E14-R08, ADR 0509).
///
/// Every metric type carries its own [RecognitionMetricDefinition]
/// (tolerance, matching rule, numerator/denominator names, direction) in the
/// report itself, not only in a doc-comment (ADR 0509 D3) — the visible
/// BPM-mérce retraction (GOV-06b) measured that a number without its
/// definition stops being readable. `higherIsBetter` lives in the type, not
/// in the reader's head (D4). A zero-denominator ratio is always `null`,
/// never coerced to `0` (D6). Matching is Kuhn's maximum-cardinality
/// augmenting-path algorithm, copied from
/// `…/audio_analysis/data/evaluation/evaluation_runner.dart:227` (D5, D8) —
/// the greedy nearest-free-pair strategy measurably under-counts true
/// positives (`docs/LESSONS.md` L269). This file never imports
/// `package:strumsight/features/audio_analysis/…` and never opens a file or
/// a socket.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:strumsight/core/music/strum.dart';

/// The three kinds of timed events a recognition case can carry.
enum RecognitionEventKind { onset, strum, chord }

/// One ground-truth (expected) event. Enforces its own `kind` invariant at
/// construction — `strum` requires [direction], `chord` requires
/// [chordLabel] — the same guarantee [RecognitionManifestParseException]
/// gives a parsed event, so [computeRecognitionMetrics] (a public entry
/// point that dereferences these fields with `!`) never sees a
/// hand-built event that violates it and degrades to a raw [TypeError]
/// (precedent: `AnnotationEvent` in `recognition_annotation.dart`, E14-R07).
final class RecognitionExpectedEvent {
  RecognitionExpectedEvent({
    required this.timeMs,
    required this.kind,
    this.direction,
    this.chordLabel,
  }) {
    if (kind == RecognitionEventKind.strum && direction == null) {
      throw ArgumentError.value(
        direction,
        'direction',
        'is required when kind is RecognitionEventKind.strum',
      );
    }
    if (kind == RecognitionEventKind.chord && chordLabel == null) {
      throw ArgumentError.value(
        chordLabel,
        'chordLabel',
        'is required when kind is RecognitionEventKind.chord',
      );
    }
  }

  final int timeMs;
  final RecognitionEventKind kind;

  /// Set only when [kind] is [RecognitionEventKind.strum].
  final StrumDirection? direction;

  /// Set only when [kind] is [RecognitionEventKind.chord].
  final String? chordLabel;
}

/// One engine-produced event. [accepted] is `false` when the engine
/// internally detected the event but chose not to surface it to the user
/// (abstained) — an abstained detection is never treated as a false
/// positive by any metric, but it still counts toward `coverage`'s
/// denominator. Enforces the same `kind` invariant as
/// [RecognitionExpectedEvent], for the same reason.
final class RecognitionDetectedEvent {
  RecognitionDetectedEvent({
    required this.timeMs,
    required this.kind,
    required this.accepted,
    required this.confidence,
    this.direction,
    this.chordLabel,
  }) {
    if (kind == RecognitionEventKind.strum && direction == null) {
      throw ArgumentError.value(
        direction,
        'direction',
        'is required when kind is RecognitionEventKind.strum',
      );
    }
    if (kind == RecognitionEventKind.chord && chordLabel == null) {
      throw ArgumentError.value(
        chordLabel,
        'chordLabel',
        'is required when kind is RecognitionEventKind.chord',
      );
    }
  }

  final int timeMs;
  final RecognitionEventKind kind;
  final bool accepted;
  final double confidence;
  final StrumDirection? direction;
  final String? chordLabel;
}

/// One labelled confidence observation, feeding the ECE and Brier-score
/// calculation. `correct` is the ground-truth label an external judge (or
/// the case author) attached to the engine's confidence score.
final class RecognitionConfidenceObservation {
  const RecognitionConfidenceObservation({
    required this.rawScore,
    required this.correct,
  });

  final double rawScore;
  final bool correct;
}

/// One recording's ground truth vs. engine output, plus the group keys
/// ([player], [device], [guitar], [room]) `recognition_split.dart` groups
/// on. All collections default to empty and [durationMs] to `0` so a
/// split-only test can construct a case with just an id and group keys.
final class RecognitionCase {
  const RecognitionCase({
    required this.caseId,
    this.player,
    this.device,
    this.guitar,
    this.room,
    this.durationMs = 0,
    this.expectedEvents = const <RecognitionExpectedEvent>[],
    this.detectedEvents = const <RecognitionDetectedEvent>[],
    this.confidenceObservations = const <RecognitionConfidenceObservation>[],
    this.detectionLatenciesMs = const <int>[],
  });

  final String caseId;
  final String? player;
  final String? device;
  final String? guitar;
  final String? room;
  final int durationMs;
  final List<RecognitionExpectedEvent> expectedEvents;
  final List<RecognitionDetectedEvent> detectedEvents;
  final List<RecognitionConfidenceObservation> confidenceObservations;
  final List<int> detectionLatenciesMs;
}

/// A parsed manifest: a schema version plus the recording cases it names.
final class RecognitionManifest {
  const RecognitionManifest({required this.schemaVersion, required this.cases});

  final String schemaVersion;
  final List<RecognitionCase> cases;
}

/// A metric's definition: what it means, which direction is better, and
/// (when relevant) the tolerance and matching rule that produced it (ADR
/// 0509 D3/D4). This travels inside the report, not only in source comments.
final class RecognitionMetricDefinition {
  const RecognitionMetricDefinition({
    required this.higherIsBetter,
    required this.description,
    required this.numeratorDescription,
    required this.denominatorDescription,
    this.toleranceMs,
    this.matchingRule,
  });

  final bool higherIsBetter;
  final String description;
  final String numeratorDescription;
  final String denominatorDescription;
  final int? toleranceMs;
  final String? matchingRule;

  Map<String, Object?> toJson() => <String, Object?>{
    'higherIsBetter': higherIsBetter,
    'description': description,
    'numeratorDescription': numeratorDescription,
    'denominatorDescription': denominatorDescription,
    'toleranceMs': toleranceMs,
    'matchingRule': matchingRule,
  };
}

/// A precision/recall/F1 triple. `precision` is `null` only when there were
/// no accepted detections to compute a precision over; `recall` is `null`
/// only when there was nothing expected either (ADR 0509 D6).
final class RecognitionPrecisionRecallF1 {
  const RecognitionPrecisionRecallF1({
    required this.precision,
    required this.recall,
    required this.f1,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    required this.definition,
  });

  final double? precision;
  final double? recall;
  final double? f1;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final RecognitionMetricDefinition definition;

  Map<String, Object?> toJson() => <String, Object?>{
    'precision': precision,
    'recall': recall,
    'f1': f1,
    'truePositives': truePositives,
    'falsePositives': falsePositives,
    'falseNegatives': falseNegatives,
    'definition': definition.toJson(),
  };
}

/// A macro-averaged F1 across a fixed set of classes/labels. A label with
/// zero real support (no expected occurrence at all) is excluded from the
/// average; a label with real support but zero correct predictions (`f1`
/// `null` per D6) contributes `0` to the average — the per-label entry
/// itself keeps the honest `null`, only the roll-up statistic substitutes.
final class RecognitionMacroF1 {
  const RecognitionMacroF1({
    required this.value,
    required this.perLabel,
    required this.definition,
  });

  final double? value;
  final Map<String, RecognitionPrecisionRecallF1> perLabel;
  final RecognitionMetricDefinition definition;

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'perLabel': <String, Object?>{
      for (final entry in perLabel.entries) entry.key: entry.value.toJson(),
    },
    'definition': definition.toJson(),
  };
}

/// A plain `numerator / denominator` ratio, both integer counts.
final class RecognitionCountRatioMetric {
  const RecognitionCountRatioMetric({
    required this.value,
    required this.numerator,
    required this.denominator,
    required this.definition,
  });

  final double? value;
  final int numerator;
  final int denominator;
  final RecognitionMetricDefinition definition;

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'numerator': numerator,
    'denominator': denominator,
    'definition': definition.toJson(),
  };
}

/// An event-count-per-minute rate (`false visible event/min`).
final class RecognitionRateMetric {
  const RecognitionRateMetric({
    required this.value,
    required this.eventCount,
    required this.durationMinutes,
    required this.definition,
  });

  final double? value;
  final int eventCount;
  final double durationMinutes;
  final RecognitionMetricDefinition definition;

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'eventCount': eventCount,
    'durationMinutes': durationMinutes,
    'definition': definition.toJson(),
  };
}

/// A single scalar computed over a sample (latency percentile, Brier
/// score): `null` only when [sampleCount] is `0`.
final class RecognitionScalarMetric {
  const RecognitionScalarMetric({
    required this.value,
    required this.sampleCount,
    required this.definition,
  });

  final double? value;
  final int sampleCount;
  final RecognitionMetricDefinition definition;

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'sampleCount': sampleCount,
    'definition': definition.toJson(),
  };
}

/// One equal-width reliability-diagram bin (ADR 0509 D7): `[lowerBound,
/// upperBound)`, the last bin closed on both ends.
final class RecognitionCalibrationBin {
  const RecognitionCalibrationBin({
    required this.lowerBound,
    required this.upperBound,
    required this.observationCount,
    required this.meanConfidence,
    required this.empiricalAccuracy,
  });

  final double lowerBound;
  final double upperBound;
  final int observationCount;
  final double? meanConfidence;
  final double? empiricalAccuracy;

  Map<String, Object?> toJson() => <String, Object?>{
    'lowerBound': lowerBound,
    'upperBound': upperBound,
    'observationCount': observationCount,
    'meanConfidence': meanConfidence,
    'empiricalAccuracy': empiricalAccuracy,
  };
}

/// Expected Calibration Error over equal-width bins (ADR 0509 D7): `null`
/// only when there are zero confidence observations.
final class RecognitionCalibrationMetrics {
  const RecognitionCalibrationMetrics({
    required this.expectedCalibrationError,
    required this.observationCount,
    required this.bins,
    required this.definition,
  });

  final double? expectedCalibrationError;
  final int observationCount;
  final List<RecognitionCalibrationBin> bins;
  final RecognitionMetricDefinition definition;

  Map<String, Object?> toJson() => <String, Object?>{
    'expectedCalibrationError': expectedCalibrationError,
    'observationCount': observationCount,
    'bins': <Map<String, Object?>>[for (final bin in bins) bin.toJson()],
    'definition': definition.toJson(),
  };
}

/// The full grouped-recognition metric set (SDD Ch14 §7) for one set of
/// cases (the whole manifest, or a fold's eval slice).
final class RecognitionMetrics {
  const RecognitionMetrics({
    required this.caseCount,
    required this.onsetTolerance25Ms,
    required this.onsetTolerance50Ms,
    required this.onsetTolerance100Ms,
    required this.anyStrumF1,
    required this.directionF1,
    required this.acceptedAccuracy,
    required this.coverage,
    required this.falseVisibleEventsPerMinute,
    required this.latencyP50Ms,
    required this.latencyP95Ms,
    required this.calibration,
    required this.brierScore,
    required this.chordWeightedAccuracy,
    required this.chordMacroF1,
    required this.chordNoChordF1,
    required this.chordUnknownFalseAccept,
  });

  final int caseCount;
  final RecognitionPrecisionRecallF1 onsetTolerance25Ms;
  final RecognitionPrecisionRecallF1 onsetTolerance50Ms;
  final RecognitionPrecisionRecallF1 onsetTolerance100Ms;
  final RecognitionPrecisionRecallF1 anyStrumF1;
  final RecognitionMacroF1 directionF1;
  final RecognitionCountRatioMetric acceptedAccuracy;
  final RecognitionCountRatioMetric coverage;
  final RecognitionRateMetric falseVisibleEventsPerMinute;
  final RecognitionScalarMetric latencyP50Ms;
  final RecognitionScalarMetric latencyP95Ms;
  final RecognitionCalibrationMetrics calibration;
  final RecognitionScalarMetric brierScore;
  final RecognitionCountRatioMetric chordWeightedAccuracy;
  final RecognitionMacroF1 chordMacroF1;
  final RecognitionPrecisionRecallF1 chordNoChordF1;
  final RecognitionCountRatioMetric chordUnknownFalseAccept;

  Map<String, Object?> toJson() => <String, Object?>{
    'caseCount': caseCount,
    'onsetTolerance25Ms': onsetTolerance25Ms.toJson(),
    'onsetTolerance50Ms': onsetTolerance50Ms.toJson(),
    'onsetTolerance100Ms': onsetTolerance100Ms.toJson(),
    'anyStrumF1': anyStrumF1.toJson(),
    'directionF1': directionF1.toJson(),
    'acceptedAccuracy': acceptedAccuracy.toJson(),
    'coverage': coverage.toJson(),
    'falseVisibleEventsPerMinute': falseVisibleEventsPerMinute.toJson(),
    'latencyP50Ms': latencyP50Ms.toJson(),
    'latencyP95Ms': latencyP95Ms.toJson(),
    'calibration': calibration.toJson(),
    'brierScore': brierScore.toJson(),
    'chordWeightedAccuracy': chordWeightedAccuracy.toJson(),
    'chordMacroF1': chordMacroF1.toJson(),
    'chordNoChordF1': chordNoChordF1.toJson(),
    'chordUnknownFalseAccept': chordUnknownFalseAccept.toJson(),
  };
}

/// The complete evaluation output for one manifest run (ADR 0509 D6:
/// deterministic — the same manifest always serialises to the same bytes).
final class RecognitionEvaluationReport {
  const RecognitionEvaluationReport({
    required this.manifestSchemaVersion,
    required this.caseCount,
    required this.overall,
  });

  final String manifestSchemaVersion;
  final int caseCount;
  final RecognitionMetrics overall;

  Map<String, Object?> toJson() => <String, Object?>{
    'manifestSchemaVersion': manifestSchemaVersion,
    'caseCount': caseCount,
    'overall': overall.toJson(),
  };

  /// A stable, timestamp-free JSON rendering: the same report always
  /// produces byte-identical output.
  String toDeterministicJson() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}

const int onsetToleranceMsPrimary = 50;
const List<int> onsetTolerancesMs = [25, onsetToleranceMsPrimary, 100];
const int chordToleranceMs = 250;

/// Computes [RecognitionMetrics] over [cases] (ADR 0509).
RecognitionMetrics computeRecognitionMetrics(List<RecognitionCase> cases) {
  final allExpected = <RecognitionExpectedEvent>[];
  final allDetected = <RecognitionDetectedEvent>[];
  final allConfidence = <RecognitionConfidenceObservation>[];
  final allLatenciesMs = <int>[];
  var totalDurationMs = 0;
  for (final recognitionCase in cases) {
    allExpected.addAll(recognitionCase.expectedEvents);
    allDetected.addAll(recognitionCase.detectedEvents);
    allConfidence.addAll(recognitionCase.confidenceObservations);
    allLatenciesMs.addAll(recognitionCase.detectionLatenciesMs);
    totalDurationMs += recognitionCase.durationMs;
  }

  bool isOnsetLike(RecognitionEventKind kind) =>
      kind == RecognitionEventKind.onset || kind == RecognitionEventKind.strum;

  final expectedOnsetLike = allExpected
      .where((e) => isOnsetLike(e.kind))
      .toList(growable: false);
  final acceptedDetectedOnsetLike = allDetected
      .where((d) => isOnsetLike(d.kind) && d.accepted)
      .toList(growable: false);

  RecognitionMetricDefinition onsetDefinition(int toleranceMs) =>
      RecognitionMetricDefinition(
        higherIsBetter: true,
        description:
            'Precision/recall/F1 of accepted onset+strum detections '
            'against expected onset+strum events, maximum-cardinality '
            'matched within an inclusive time tolerance.',
        numeratorDescription: 'matched (true-positive) event pairs',
        denominatorDescription:
            'precision: accepted detections; recall: expected events',
        toleranceMs: toleranceMs,
        matchingRule:
            "Kuhn's maximum-cardinality one-to-one matching, closest-gap-"
            'first candidate order, boundary inclusive (<=)',
      );

  final onsetMatches = <int, List<_MatchedEventPair>>{
    for (final toleranceMs in onsetTolerancesMs)
      toleranceMs: _matchEvents(
        expectedOnsetLike,
        acceptedDetectedOnsetLike,
        toleranceMs,
      ),
  };
  final onsetMetrics = <int, RecognitionPrecisionRecallF1>{
    for (final toleranceMs in onsetTolerancesMs)
      toleranceMs: _eventPrf1(
        expectedOnsetLike,
        acceptedDetectedOnsetLike,
        onsetMatches[toleranceMs]!,
        onsetDefinition(toleranceMs),
      ),
  };

  final expectedStrum = allExpected
      .where((e) => e.kind == RecognitionEventKind.strum)
      .toList(growable: false);
  final acceptedDetectedStrum = allDetected
      .where((d) => d.kind == RecognitionEventKind.strum && d.accepted)
      .toList(growable: false);
  final strumMatches = _matchEvents(
    expectedStrum,
    acceptedDetectedStrum,
    onsetToleranceMsPrimary,
  );
  final anyStrumF1 = _eventPrf1(
    expectedStrum,
    acceptedDetectedStrum,
    strumMatches,
    RecognitionMetricDefinition(
      higherIsBetter: true,
      description:
          'Precision/recall/F1 of detecting that a strum happened at all, '
          'ignoring whether the predicted direction was correct.',
      numeratorDescription: 'matched strum event pairs',
      denominatorDescription:
          'precision: accepted strum detections; recall: expected strum '
          'events',
      toleranceMs: onsetToleranceMsPrimary,
      matchingRule:
          "Kuhn's maximum-cardinality one-to-one matching, closest-gap-"
          'first candidate order, boundary inclusive (<=)',
    ),
  );

  final directionDefinition = RecognitionMetricDefinition(
    higherIsBetter: true,
    description:
        'Macro-averaged per-direction (down/up) F1: a class\'s true '
        'positives come only from time-matched strum pairs whose expected '
        'and detected direction both equal that class, but its false '
        'positives and false negatives are counted over the FULL accepted-'
        'detected and expected populations for that class — a strum '
        'missed or falsely detected in time (never time-matched at all) '
        'still enters this metric, as a false negative/positive for its '
        'own class.',
    numeratorDescription:
        'per-class true-positive direction matches, from time-matched '
        'strum pairs',
    denominatorDescription:
        'per-class: FP = (all accepted detections labelled that class) − '
        'TP; FN = (all expected events labelled that class) − TP — not '
        'restricted to the time-matched set',
    toleranceMs: onsetToleranceMsPrimary,
    matchingRule:
        'true positives from the same time-matched strum pairs as '
        'anyStrumF1; false positives/negatives from the full per-class '
        'populations',
  );
  final directionF1 = _labelMacroF1(
    expectedLabels: [for (final e in expectedStrum) e.direction!.name],
    acceptedDetectedLabels: [
      for (final d in acceptedDetectedStrum) d.direction!.name,
    ],
    matches: strumMatches,
    expectedLabelOf: (pair) => pair.expected.direction!.name,
    detectedLabelOf: (pair) => pair.detected.direction!.name,
    labels: const ['down', 'up'],
    definition: directionDefinition,
  );

  final expectedChord = allExpected
      .where((e) => e.kind == RecognitionEventKind.chord)
      .toList(growable: false);
  final acceptedDetectedChord = allDetected
      .where((d) => d.kind == RecognitionEventKind.chord && d.accepted)
      .toList(growable: false);
  final chordMatches = _matchEvents(
    expectedChord,
    acceptedDetectedChord,
    chordToleranceMs,
  );

  final correctChordCount = chordMatches
      .where((pair) => pair.expected.chordLabel == pair.detected.chordLabel)
      .length;
  final chordWeightedAccuracy = RecognitionCountRatioMetric(
    value: expectedChord.isEmpty
        ? null
        : correctChordCount / expectedChord.length,
    numerator: correctChordCount,
    denominator: expectedChord.length,
    definition: RecognitionMetricDefinition(
      higherIsBetter: true,
      description:
          'Overall (frequency-weighted) chord-label accuracy: a matched '
          'pair counts as correct only when both label and time agree.',
      numeratorDescription: 'time-matched pairs with an equal chord label',
      denominatorDescription: 'expected chord events',
      toleranceMs: chordToleranceMs,
      matchingRule:
          "Kuhn's maximum-cardinality one-to-one matching, closest-gap-"
          'first candidate order, boundary inclusive (<=)',
    ),
  );

  final chordLabels = <String>{
    for (final e in expectedChord) e.chordLabel!,
  }.toList()..sort();
  final chordMacroDefinition = RecognitionMetricDefinition(
    higherIsBetter: true,
    description:
        'Macro-averaged per-chord-label F1: a label\'s true positives come '
        'only from time-matched chord pairs whose expected and detected '
        'label both equal that label, but its false positives and false '
        'negatives are counted over the FULL accepted-detected and '
        'expected populations for that label — a chord missed or falsely '
        'detected in time (never time-matched at all) still enters this '
        'metric, as a false negative/positive for its own label. A chord '
        'label absent from the expected set contributes nothing to the '
        'macro average.',
    numeratorDescription:
        'per-label true-positive label matches, from time-matched chord '
        'pairs',
    denominatorDescription:
        'per-label: FP = (all accepted detections labelled that label) − '
        'TP; FN = (all expected events labelled that label) − TP — not '
        'restricted to the time-matched set',
    toleranceMs: chordToleranceMs,
    matchingRule:
        'true positives from the same time-matched chord pairs as '
        'chordWeightedAccuracy; false positives/negatives from the full '
        'per-label populations',
  );
  final chordMacroF1 = _labelMacroF1(
    expectedLabels: [for (final e in expectedChord) e.chordLabel!],
    acceptedDetectedLabels: [
      for (final d in acceptedDetectedChord) d.chordLabel!,
    ],
    matches: chordMatches,
    expectedLabelOf: (pair) => pair.expected.chordLabel!,
    detectedLabelOf: (pair) => pair.detected.chordLabel!,
    labels: chordLabels,
    definition: chordMacroDefinition,
  );
  final chordNoChordF1 =
      chordMacroF1.perLabel['noChord'] ??
      _classPrf1(
        truePositives: 0,
        falsePositives: 0,
        falseNegatives: 0,
        definition: chordMacroDefinition,
      );

  final unknownAcceptedChordCount = acceptedDetectedChord
      .where((d) => d.chordLabel == 'unknown')
      .length;
  final chordUnknownFalseAccept = RecognitionCountRatioMetric(
    value: acceptedDetectedChord.isEmpty
        ? null
        : unknownAcceptedChordCount / acceptedDetectedChord.length,
    numerator: unknownAcceptedChordCount,
    denominator: acceptedDetectedChord.length,
    definition: RecognitionMetricDefinition(
      higherIsBetter: false,
      description:
          'How often the engine surfaces an "unknown" chord label instead '
          'of abstaining or naming a real chord.',
      numeratorDescription: 'accepted chord detections labelled "unknown"',
      denominatorDescription: 'accepted chord detections (any label)',
    ),
  );

  final correctAccepted = <RecognitionDetectedEvent>{
    for (final pair in onsetMatches[onsetToleranceMsPrimary]!)
      if (pair.detected.kind == RecognitionEventKind.onset) pair.detected,
    for (final pair in strumMatches)
      if (pair.expected.direction == pair.detected.direction) pair.detected,
    for (final pair in chordMatches)
      if (pair.expected.chordLabel == pair.detected.chordLabel) pair.detected,
  };
  final acceptedDetections = allDetected
      .where((d) => d.accepted)
      .toList(growable: false);
  final correctAcceptedCount = acceptedDetections
      .where(correctAccepted.contains)
      .length;

  final acceptedAccuracy = RecognitionCountRatioMetric(
    value: acceptedDetections.isEmpty
        ? null
        : correctAcceptedCount / acceptedDetections.length,
    numerator: correctAcceptedCount,
    denominator: acceptedDetections.length,
    definition: RecognitionMetricDefinition(
      higherIsBetter: true,
      description:
          'Among detections the engine chose to surface (accepted, not '
          'abstained), the fraction that are time- and label/direction-'
          'correct.',
      numeratorDescription: 'accepted detections that are correct',
      denominatorDescription: 'accepted detections',
      toleranceMs: onsetToleranceMsPrimary,
      matchingRule:
          '50ms match for onset/strum kind (direction must also agree for '
          'strum), ${chordToleranceMs}ms label-matching for chord kind',
    ),
  );

  final coverage = RecognitionCountRatioMetric(
    value: allDetected.isEmpty
        ? null
        : acceptedDetections.length / allDetected.length,
    numerator: acceptedDetections.length,
    denominator: allDetected.length,
    definition: const RecognitionMetricDefinition(
      higherIsBetter: true,
      description:
          'Fraction of all engine detections (accepted or abstained) that '
          'the engine chose to surface to the user.',
      numeratorDescription: 'accepted detections',
      denominatorDescription: 'all detections (accepted + abstained)',
    ),
  );

  final falsePositiveAcceptedCount =
      acceptedDetections.length - correctAcceptedCount;
  final durationMinutes = totalDurationMs / 60000;
  final falseVisibleEventsPerMinute = RecognitionRateMetric(
    value: durationMinutes == 0
        ? null
        : falsePositiveAcceptedCount / durationMinutes,
    eventCount: falsePositiveAcceptedCount,
    durationMinutes: durationMinutes,
    definition: const RecognitionMetricDefinition(
      higherIsBetter: false,
      description:
          'Rate of accepted (visible) detections that are wrong — '
          'unmatched, or matched with the wrong direction/chord label — '
          'per minute of recorded audio.',
      numeratorDescription: 'accepted detections that are not correct',
      denominatorDescription: 'total case duration, in minutes',
    ),
  );

  final latencyDefinition = const RecognitionMetricDefinition(
    higherIsBetter: false,
    description:
        'Nearest-rank percentile (rank = ceil(p/100 * n), 1-indexed into '
        'the ascending-sorted sample) of accepted-detection latency.',
    numeratorDescription: 'n/a — percentile, not a ratio',
    denominatorDescription: 'detection latency samples',
  );
  final latencyP50Ms = RecognitionScalarMetric(
    value: _percentile(allLatenciesMs, 50),
    sampleCount: allLatenciesMs.length,
    definition: latencyDefinition,
  );
  final latencyP95Ms = RecognitionScalarMetric(
    value: _percentile(allLatenciesMs, 95),
    sampleCount: allLatenciesMs.length,
    definition: latencyDefinition,
  );

  final calibrationResult = _calibration(allConfidence);
  final calibration = RecognitionCalibrationMetrics(
    expectedCalibrationError: calibrationResult.$1,
    observationCount: allConfidence.length,
    bins: calibrationResult.$2,
    definition: const RecognitionMetricDefinition(
      higherIsBetter: false,
      description:
          'Weighted mean absolute gap between each equal-width bin\'s mean '
          'predicted confidence and its empirical accuracy: '
          'sum(|bin| / n * |meanConfidence - empiricalAccuracy|).',
      numeratorDescription:
          'per-bin |meanConfidence - empiricalAccuracy|, '
          'weighted by bin size',
      denominatorDescription: 'total confidence observations',
    ),
  );
  final brierScore = RecognitionScalarMetric(
    value: _brier(allConfidence),
    sampleCount: allConfidence.length,
    definition: const RecognitionMetricDefinition(
      higherIsBetter: false,
      description:
          'Mean squared error between each confidence observation\'s raw '
          'score and its 0/1 correctness label.',
      numeratorDescription: 'sum((rawScore - correct) ^ 2)',
      denominatorDescription: 'total confidence observations',
    ),
  );

  return RecognitionMetrics(
    caseCount: cases.length,
    onsetTolerance25Ms: onsetMetrics[25]!,
    onsetTolerance50Ms: onsetMetrics[onsetToleranceMsPrimary]!,
    onsetTolerance100Ms: onsetMetrics[100]!,
    anyStrumF1: anyStrumF1,
    directionF1: directionF1,
    acceptedAccuracy: acceptedAccuracy,
    coverage: coverage,
    falseVisibleEventsPerMinute: falseVisibleEventsPerMinute,
    latencyP50Ms: latencyP50Ms,
    latencyP95Ms: latencyP95Ms,
    calibration: calibration,
    brierScore: brierScore,
    chordWeightedAccuracy: chordWeightedAccuracy,
    chordMacroF1: chordMacroF1,
    chordNoChordF1: chordNoChordF1,
    chordUnknownFalseAccept: chordUnknownFalseAccept,
  );
}

/// One matched expected/detected event pair.
final class _MatchedEventPair {
  const _MatchedEventPair(this.expected, this.detected);

  final RecognitionExpectedEvent expected;
  final RecognitionDetectedEvent detected;
}

/// Deterministic maximum-cardinality one-to-one matching of [expected]
/// against [detected] within [toleranceMs] (inclusive), via Kuhn's
/// augmenting-path algorithm — copied from `EvaluationRunner.matchEvents`
/// (ADR 0509 D5/D8): candidate edges are tried closest-gap-first (index as
/// tie-breaker), and a detected event is reassigned to a different expected
/// event whenever that grows the total number of matches.
List<_MatchedEventPair> _matchEvents(
  List<RecognitionExpectedEvent> expected,
  List<RecognitionDetectedEvent> detected,
  int toleranceMs,
) {
  final sortedExpected = [...expected]
    ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
  final sortedDetected = [...detected]
    ..sort((a, b) => a.timeMs.compareTo(b.timeMs));

  final candidatesByExpected = List<List<int>>.generate(sortedExpected.length, (
    i,
  ) {
    final expectedEvent = sortedExpected[i];
    final withGap =
        <MapEntry<int, int>>[
          for (var j = 0; j < sortedDetected.length; j++)
            if ((sortedDetected[j].timeMs - expectedEvent.timeMs).abs() <=
                toleranceMs)
              MapEntry(
                j,
                (sortedDetected[j].timeMs - expectedEvent.timeMs).abs(),
              ),
        ]..sort((a, b) {
          final byGap = a.value.compareTo(b.value);
          return byGap != 0 ? byGap : a.key.compareTo(b.key);
        });
    return [for (final entry in withGap) entry.key];
  });

  final matchOfDetected = _maxBipartiteMatching(
    leftCount: sortedExpected.length,
    candidatesByLeft: candidatesByExpected,
    rightCount: sortedDetected.length,
  );

  final matched = <_MatchedEventPair>[];
  for (var j = 0; j < sortedDetected.length; j++) {
    final i = matchOfDetected[j];
    if (i != -1) {
      matched.add(_MatchedEventPair(sortedExpected[i], sortedDetected[j]));
    }
  }
  matched.sort((a, b) => a.expected.timeMs.compareTo(b.expected.timeMs));
  return matched;
}

/// Kuhn's algorithm: finds a maximum-cardinality one-to-one matching
/// between `leftCount` left nodes and `rightCount` right nodes, given each
/// left node's admissible right-node candidates (ordered — ties are broken
/// by that order). Returns `matchOfRight`, where `matchOfRight[j]` is the
/// matched left index, or `-1` if unmatched.
List<int> _maxBipartiteMatching({
  required int leftCount,
  required List<List<int>> candidatesByLeft,
  required int rightCount,
}) {
  final matchOfRight = List<int>.filled(rightCount, -1);

  bool tryAugment(int leftIndex, List<bool> visited) {
    for (final rightIndex in candidatesByLeft[leftIndex]) {
      if (visited[rightIndex]) continue;
      visited[rightIndex] = true;
      if (matchOfRight[rightIndex] == -1 ||
          tryAugment(matchOfRight[rightIndex], visited)) {
        matchOfRight[rightIndex] = leftIndex;
        return true;
      }
    }
    return false;
  }

  for (var i = 0; i < leftCount; i++) {
    tryAugment(i, List<bool>.filled(rightCount, false));
  }
  return matchOfRight;
}

RecognitionPrecisionRecallF1 _eventPrf1(
  List<RecognitionExpectedEvent> expected,
  List<RecognitionDetectedEvent> detected,
  List<_MatchedEventPair> matched,
  RecognitionMetricDefinition definition,
) => _classPrf1(
  truePositives: matched.length,
  falsePositives: detected.length - matched.length,
  falseNegatives: expected.length - matched.length,
  definition: definition,
);

RecognitionPrecisionRecallF1 _classPrf1({
  required int truePositives,
  required int falsePositives,
  required int falseNegatives,
  required RecognitionMetricDefinition definition,
}) {
  final precision = (truePositives + falsePositives) == 0
      ? null
      : truePositives / (truePositives + falsePositives);
  final recall = (truePositives + falseNegatives) == 0
      ? null
      : truePositives / (truePositives + falseNegatives);
  return RecognitionPrecisionRecallF1(
    precision: precision,
    recall: recall,
    f1: _f1(precision, recall),
    truePositives: truePositives,
    falsePositives: falsePositives,
    falseNegatives: falseNegatives,
    definition: definition,
  );
}

double? _f1(double? precision, double? recall) {
  if (precision == null || recall == null) return null;
  final sum = precision + recall;
  if (sum == 0) return null;
  return 2 * precision * recall / sum;
}

/// Per-label precision/recall/F1 over [matches], macro-averaged across
/// [labels] that have real support (see [RecognitionMacroF1]).
RecognitionMacroF1 _labelMacroF1({
  required List<String> expectedLabels,
  required List<String> acceptedDetectedLabels,
  required List<_MatchedEventPair> matches,
  required String Function(_MatchedEventPair) expectedLabelOf,
  required String Function(_MatchedEventPair) detectedLabelOf,
  required List<String> labels,
  required RecognitionMetricDefinition definition,
}) {
  final perLabel = <String, RecognitionPrecisionRecallF1>{};
  for (final label in labels) {
    // Counted against the FULL expected/accepted-detected populations (not
    // only matched pairs), so an expected item that was never matched at
    // all — never even considered a candidate — still counts as a false
    // negative for its label, and a never-matched detection still counts
    // as a false positive for its label.
    final truePositives = matches
        .where(
          (pair) =>
              expectedLabelOf(pair) == label && detectedLabelOf(pair) == label,
        )
        .length;
    final totalExpected = expectedLabels.where((l) => l == label).length;
    final totalAcceptedDetected = acceptedDetectedLabels
        .where((l) => l == label)
        .length;
    perLabel[label] = _classPrf1(
      truePositives: truePositives,
      falsePositives: totalAcceptedDetected - truePositives,
      falseNegatives: totalExpected - truePositives,
      definition: definition,
    );
  }
  final supported = perLabel.values.where(
    (prf1) => (prf1.truePositives + prf1.falseNegatives) > 0,
  );
  final value = supported.isEmpty
      ? null
      : supported.map((prf1) => prf1.f1 ?? 0.0).reduce((a, b) => a + b) /
            supported.length;
  return RecognitionMacroF1(
    value: value,
    perLabel: perLabel,
    definition: definition,
  );
}

/// Nearest-rank percentile: `rank = ceil(p/100 * n)` (1-indexed) into the
/// ascending-sorted [values]. `null` when [values] is empty.
double? _percentile(List<int> values, int percentile) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final n = sorted.length;
  final rank = (percentile / 100 * n).ceil().clamp(1, n);
  return sorted[rank - 1].toDouble();
}

/// Equal-width (ADR 0509 D7) binning of [observations] into [binCount]
/// bins, `[i/binCount, (i+1)/binCount)`, the last bin closed on both ends.
/// Returns the weighted-mean-absolute-gap ECE (`null` when [observations]
/// is empty) and the per-bin breakdown.
(double?, List<RecognitionCalibrationBin>) _calibration(
  List<RecognitionConfidenceObservation> observations, {
  int binCount = 10,
}) {
  final buckets = List<List<RecognitionConfidenceObservation>>.generate(
    binCount,
    (_) => <RecognitionConfidenceObservation>[],
  );
  for (final observation in observations) {
    var index = (observation.rawScore * binCount).floor();
    if (index >= binCount) index = binCount - 1;
    if (index < 0) index = 0;
    buckets[index].add(observation);
  }

  final total = observations.length;
  var weightedGapSum = 0.0;
  final bins = <RecognitionCalibrationBin>[];
  for (var i = 0; i < binCount; i++) {
    final bucket = buckets[i];
    double? meanConfidence;
    double? empiricalAccuracy;
    if (bucket.isNotEmpty) {
      meanConfidence =
          bucket.fold<double>(0, (acc, o) => acc + o.rawScore) / bucket.length;
      empiricalAccuracy = bucket.where((o) => o.correct).length / bucket.length;
      weightedGapSum +=
          (bucket.length / total) * (meanConfidence - empiricalAccuracy).abs();
    }
    bins.add(
      RecognitionCalibrationBin(
        lowerBound: i / binCount,
        upperBound: (i + 1) / binCount,
        observationCount: bucket.length,
        meanConfidence: meanConfidence,
        empiricalAccuracy: empiricalAccuracy,
      ),
    );
  }
  return (total == 0 ? null : weightedGapSum, bins);
}

/// Mean squared error between raw confidence score and 0/1 correctness.
/// `null` when [observations] is empty.
double? _brier(List<RecognitionConfidenceObservation> observations) {
  if (observations.isEmpty) return null;
  final sum = observations.fold<double>(
    0,
    (acc, o) => acc + math.pow(o.rawScore - (o.correct ? 1 : 0), 2),
  );
  return sum / observations.length;
}
