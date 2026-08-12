import 'dart:math' as math;

import '../../domain/analysis_capability.dart';
import '../../domain/analysis_event.dart';
import '../../domain/analysis_metric.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/analysis_segment.dart';
import '../../domain/harmony/chord_frame_evidence.dart';
import 'transition_analysis.dart';

/// Above this recovered top-label confidence, a chord decision is treated as
/// settled again after a change (used only for [ChordFrameEvidence.complete]
/// evidence — `derived` evidence never reaches this comparison, OD-01).
const double confidenceCollapseRecoveryThreshold = 0.5;

/// How long after a transition's window a sustained chord is probed for a
/// silence dropout, before the note is judged not-sustained.
const Duration sustainedNoteProbeDuration = Duration(milliseconds: 300);

/// Minimum attack-strength samples inside one transition's post-change span
/// before that transition contributes to the attack-instability proxy.
const int minimumAttackSamplesPerTransition = 2;

/// Fail-closed gate verdict for the whole technique-proxy suite (ADR 0236 §5,
/// SDD §18.4): every one of the four conditions is required, never partial.
final class TechniqueProxyGateResult {
  TechniqueProxyGateResult({required this.status, this.reason}) {
    if (status == CapabilityStatus.unavailable && reason == null) {
      throw ArgumentError('Unavailable technique-proxy gate needs a reason.');
    }
    if (status != CapabilityStatus.unavailable && reason != null) {
      throw ArgumentError('Only an unavailable gate carries a reason.');
    }
  }

  final CapabilityStatus status;
  final CapabilityUnavailableReason? reason;
}

/// The four required technique-proxy preconditions (ADR 0236 §5): a known
/// target, an unclipped input, a non-backing-track-dominant signal, and at
/// least [minimumRepetitions] recurrences of the same chord-pair transition.
/// Any single failing condition blocks the ENTIRE suite — there is no
/// partial gate.
final class TechniqueProxyGate {
  TechniqueProxyGate({this.minimumRepetitions = minimumTransitionRepetitions}) {
    if (minimumRepetitions <= 0) {
      throw ArgumentError.value(
        minimumRepetitions,
        'minimumRepetitions',
        'must be > 0',
      );
    }
  }

  final int minimumRepetitions;

  TechniqueProxyGateResult evaluate({
    required bool hasKnownTarget,
    required bool inputClipped,
    required bool backingTrackDominant,
    required int maxTransitionRepetition,
  }) {
    if (!hasKnownTarget) {
      return TechniqueProxyGateResult(
        status: CapabilityStatus.unavailable,
        reason: CapabilityUnavailableReason.noReferenceTarget,
      );
    }
    if (inputClipped) {
      return TechniqueProxyGateResult(
        status: CapabilityStatus.unavailable,
        reason: CapabilityUnavailableReason.inputClipped,
      );
    }
    if (backingTrackDominant) {
      return TechniqueProxyGateResult(
        status: CapabilityStatus.unavailable,
        reason: CapabilityUnavailableReason.backingTrackDominant,
      );
    }
    if (maxTransitionRepetition < minimumRepetitions) {
      return TechniqueProxyGateResult(
        status: CapabilityStatus.unavailable,
        reason: CapabilityUnavailableReason.insufficientEvents,
      );
    }
    return TechniqueProxyGateResult(status: CapabilityStatus.available);
  }
}

/// The testable call-count seam (brief §8 step 5): production code passes
/// the default calculator; tests inject a counting wrapper to prove the Lab
/// and confidence gates block computation before this ever runs.
typedef TechniqueProxyCalculator = List<AnalysisMetricResult> Function();

/// Standalone, non-persisted diagnostic result (ADR 0236 §4). Never added to
/// `AnalysisDocument.metrics`, never wired into the pipeline or codec in this
/// round.
final class TechniqueProxyReport {
  TechniqueProxyReport._({
    required this.status,
    this.reason,
    List<AnalysisMetricResult> metrics = const <AnalysisMetricResult>[],
  }) : metrics = List<AnalysisMetricResult>.unmodifiable(metrics) {
    if (status == CapabilityStatus.unavailable && reason == null) {
      throw ArgumentError('Unavailable technique-proxy report needs a reason.');
    }
  }

  /// The flag or Lab-mode input was off — the calculator never ran.
  factory TechniqueProxyReport.disabled() =>
      TechniqueProxyReport._(status: CapabilityStatus.notApplicable);

  /// The Lab/flag gate was open but the confidence gate blocked computation.
  factory TechniqueProxyReport.unavailable(
    CapabilityUnavailableReason reason,
  ) => TechniqueProxyReport._(
    status: CapabilityStatus.unavailable,
    reason: reason,
    metrics: _unavailableMetrics(reason),
  );

  factory TechniqueProxyReport.available(List<AnalysisMetricResult> metrics) =>
      TechniqueProxyReport._(
        status: CapabilityStatus.available,
        metrics: metrics,
      );

  final CapabilityStatus status;
  final CapabilityUnavailableReason? reason;
  final List<AnalysisMetricResult> metrics;
}

/// Entry point (brief §8): computes nothing unless BOTH
/// [analysisTechniqueProxiesEnabled] and [labModeActive] are true — the
/// calculator seam is never invoked otherwise. When both are true, the
/// four-condition [TechniqueProxyGate] still applies before any calculation.
TechniqueProxyReport buildTechniqueProxyReport({
  required bool analysisTechniqueProxiesEnabled,
  required bool labModeActive,
  required bool hasKnownTarget,
  required bool inputClipped,
  required bool backingTrackDominant,
  required List<ChordSegment> chordSegments,
  required List<OnsetEvent> onsets,
  List<ChordFrameEvidence> chordFrameEvidence = const <ChordFrameEvidence>[],
  List<SilenceRegionEvent> silenceRegions = const <SilenceRegionEvent>[],
  TechniqueProxyGate? gate,
  TechniqueProxyCalculator? calculator,
}) {
  if (!analysisTechniqueProxiesEnabled || !labModeActive) {
    return TechniqueProxyReport.disabled();
  }
  final transitions = buildChordTransitions(chordSegments);
  final gateResult = (gate ?? TechniqueProxyGate()).evaluate(
    hasKnownTarget: hasKnownTarget,
    inputClipped: inputClipped,
    backingTrackDominant: backingTrackDominant,
    maxTransitionRepetition: maxTransitionRepetition(transitions),
  );
  if (gateResult.status != CapabilityStatus.available) {
    return TechniqueProxyReport.unavailable(gateResult.reason!);
  }
  final compute =
      calculator ??
      () => computeTechniqueProxyMetrics(
        chordSegments: chordSegments,
        transitions: transitions,
        onsets: onsets,
        chordFrameEvidence: chordFrameEvidence,
        silenceRegions: silenceRegions,
      );
  return TechniqueProxyReport.available(compute());
}

/// Computes the five technique proxies from already-gated evidence. Public
/// so the default [TechniqueProxyCalculator] and direct fixture tests share
/// one implementation.
List<AnalysisMetricResult> computeTechniqueProxyMetrics({
  required List<ChordSegment> chordSegments,
  required List<ChordTransition> transitions,
  required List<OnsetEvent> onsets,
  List<ChordFrameEvidence> chordFrameEvidence = const <ChordFrameEvidence>[],
  List<SilenceRegionEvent> silenceRegions = const <SilenceRegionEvent>[],
}) {
  final confidence = _mean(<double>[
    for (final segment in chordSegments) segment.confidence,
  ]);
  return List<AnalysisMetricResult>.unmodifiable(<AnalysisMetricResult>[
    _chordChangeGap(transitions, onsets, confidence),
    _confidenceCollapseDuration(transitions, chordFrameEvidence, confidence),
    _unexpectedExtraOnsets(transitions, onsets, confidence),
    _sustainedNoteDropout(transitions, silenceRegions, confidence),
    _attackInstability(transitions, onsets, confidence),
  ]);
}

AnalysisMetricResult _chordChangeGap(
  List<ChordTransition> transitions,
  List<OnsetEvent> onsets,
  double confidence,
) {
  final gaps = <double>[];
  for (final transition in transitions) {
    final window = TransitionWindow(transition);
    final nearby = onsetsInWindow(window, onsets);
    if (nearby.isEmpty) continue;
    final nearest = nearby.reduce(
      (a, b) =>
          _absMicros(a.time, transition.time) <
              _absMicros(b.time, transition.time)
          ? a
          : b,
    );
    gaps.add(_absMicros(nearest.time, transition.time).toDouble());
  }
  if (gaps.isEmpty) {
    return _unavailableMetric(
      TechniqueProxyMetricIds.chordChangeGap,
      CapabilityUnavailableReason.insufficientEvents,
    );
  }
  return _durationMetric(
    TechniqueProxyMetricIds.chordChangeGap,
    Duration(microseconds: _median(gaps).round()),
    confidence: confidence,
    sampleCount: gaps.length,
  );
}

AnalysisMetricResult _confidenceCollapseDuration(
  List<ChordTransition> transitions,
  List<ChordFrameEvidence> evidence,
  double confidence,
) {
  // OD-01: `derived` evidence has no ranked probabilities to reconstruct a
  // collapse from — fabricating one from segment confidence is forbidden.
  final complete =
      evidence
          .where(
            (entry) =>
                entry.evidenceCompleteness == EvidenceCompleteness.complete,
          )
          .toList()
        ..sort((a, b) => a.time.compareTo(b.time));
  if (complete.isEmpty) {
    return _unavailableMetric(
      TechniqueProxyMetricIds.confidenceCollapseDuration,
      CapabilityUnavailableReason.modelUnavailable,
    );
  }
  final collapses = <double>[];
  for (final transition in transitions) {
    final window = TransitionWindow(transition);
    final inWindow = complete
        .where((entry) => window.contains(entry.time))
        .toList();
    if (inWindow.isEmpty) continue;
    final recovered = inWindow.firstWhere(
      (entry) =>
          (entry.topConfidence ?? 0) >= confidenceCollapseRecoveryThreshold,
      orElse: () => inWindow.last,
    );
    collapses.add(_absMicros(recovered.time, window.start).toDouble());
  }
  if (collapses.isEmpty) {
    return _unavailableMetric(
      TechniqueProxyMetricIds.confidenceCollapseDuration,
      CapabilityUnavailableReason.modelUnavailable,
    );
  }
  return _durationMetric(
    TechniqueProxyMetricIds.confidenceCollapseDuration,
    Duration(microseconds: _median(collapses).round()),
    confidence: confidence,
    sampleCount: collapses.length,
  );
}

AnalysisMetricResult _unexpectedExtraOnsets(
  List<ChordTransition> transitions,
  List<OnsetEvent> onsets,
  double confidence,
) {
  if (transitions.isEmpty) {
    return _unavailableMetric(
      TechniqueProxyMetricIds.unexpectedExtraOnsets,
      CapabilityUnavailableReason.insufficientEvents,
    );
  }
  var totalExtra = 0;
  for (final transition in transitions) {
    final count = onsetsInWindow(TransitionWindow(transition), onsets).length;
    if (count > 1) totalExtra += count - 1;
  }
  return AnalysisMetricResult(
    id: TechniqueProxyMetricIds.unexpectedExtraOnsets,
    version: 1,
    status: CapabilityStatus.available,
    confidence: confidence,
    unit: 'count_per_transition',
    sampleCount: transitions.length,
    evidence: _evidenceIds(transitions),
    value: ScalarMetricValue(totalExtra / transitions.length),
  );
}

AnalysisMetricResult _sustainedNoteDropout(
  List<ChordTransition> transitions,
  List<SilenceRegionEvent> silenceRegions,
  double confidence,
) {
  if (transitions.isEmpty) {
    return _unavailableMetric(
      TechniqueProxyMetricIds.sustainedNoteDropout,
      CapabilityUnavailableReason.insufficientEvents,
    );
  }
  var dropouts = 0;
  for (final transition in transitions) {
    final probeStart = TransitionWindow(transition).end;
    final probeEnd = probeStart + sustainedNoteProbeDuration;
    final overlaps = silenceRegions.any(
      (region) => region.time <= probeEnd && region.end >= probeStart,
    );
    if (overlaps) dropouts += 1;
  }
  return AnalysisMetricResult(
    id: TechniqueProxyMetricIds.sustainedNoteDropout,
    version: 1,
    status: CapabilityStatus.available,
    confidence: confidence,
    unit: 'ratio',
    sampleCount: transitions.length,
    evidence: _evidenceIds(transitions),
    value: PercentageMetricValue(dropouts / transitions.length),
  );
}

AnalysisMetricResult _attackInstability(
  List<ChordTransition> transitions,
  List<OnsetEvent> onsets,
  double confidence,
) {
  final coefficients = <double>[];
  for (final transition in transitions) {
    final window = TransitionWindow(transition);
    final strengths = <double>[
      for (final onset in onsetsInWindow(window, onsets))
        if (onset.time >= transition.time && onset.attackStrength != null)
          onset.attackStrength!,
    ];
    if (strengths.length < minimumAttackSamplesPerTransition) continue;
    final mean = _mean(strengths);
    if (mean == 0) continue;
    final variance =
        strengths.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        strengths.length;
    coefficients.add(math.sqrt(variance) / mean);
  }
  if (coefficients.isEmpty) {
    return _unavailableMetric(
      TechniqueProxyMetricIds.attackInstability,
      CapabilityUnavailableReason.insufficientEvents,
    );
  }
  return AnalysisMetricResult(
    id: TechniqueProxyMetricIds.attackInstability,
    version: 1,
    status: CapabilityStatus.available,
    confidence: confidence,
    unit: 'cv',
    sampleCount: coefficients.length,
    evidence: _evidenceIds(transitions),
    value: ScalarMetricValue(_median(coefficients)),
  );
}

List<AnalysisMetricResult> _unavailableMetrics(
  CapabilityUnavailableReason reason,
) => List<AnalysisMetricResult>.unmodifiable(<AnalysisMetricResult>[
  for (final id in TechniqueProxyMetricIds.all) _unavailableMetric(id, reason),
]);

AnalysisMetricResult _unavailableMetric(
  String id,
  CapabilityUnavailableReason reason,
) => AnalysisMetricResult(
  id: id,
  version: 1,
  status: CapabilityStatus.unavailable,
  confidence: 0,
  unit: _unitFor(id),
  sampleCount: 0,
  evidence: const <String>[],
  unavailableReason: reason,
);

AnalysisMetricResult _durationMetric(
  String id,
  Duration value, {
  required double confidence,
  required int sampleCount,
}) => AnalysisMetricResult(
  id: id,
  version: 1,
  status: CapabilityStatus.available,
  confidence: confidence,
  unit: 'ms',
  sampleCount: sampleCount,
  evidence: const <String>[],
  value: DurationMetricValue(value),
);

String _unitFor(String id) => switch (id) {
  TechniqueProxyMetricIds.chordChangeGap ||
  TechniqueProxyMetricIds.confidenceCollapseDuration => 'ms',
  TechniqueProxyMetricIds.sustainedNoteDropout => 'ratio',
  TechniqueProxyMetricIds.unexpectedExtraOnsets => 'count_per_transition',
  _ => 'cv',
};

List<String> _evidenceIds(List<ChordTransition> transitions) => <String>[
  for (var index = 0; index < transitions.length; index += 1)
    'transition-$index',
];

int _absMicros(Duration a, Duration b) => (a - b).inMicroseconds.abs();

double _mean(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
