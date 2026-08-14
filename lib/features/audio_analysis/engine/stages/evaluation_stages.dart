import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import '../../domain/analysis_capability.dart';
import '../../domain/analysis_event.dart';
import '../../domain/analysis_metric.dart';
import '../../domain/analysis_metric_catalog.dart';
import '../../domain/rhythm/beat_grid.dart';
import '../../domain/target/alignment_result.dart';
import '../../domain/target/expected_event.dart';
import '../alignment/event_aligner.dart';
import '../alignment/tolerance_policy.dart';
import '../analysis_context.dart';
import '../analysis_stage.dart';
import '../analysis_work_state.dart';
import '../confidence/capability_resolver.dart';
import '../metrics/accent_analysis.dart';
import '../metrics/dynamics_metrics.dart';
import '../metrics/pitch_metrics.dart';
import '../metrics/rhythm_metrics.dart';
import '../metrics/subdivision_analysis.dart';
import '../metrics/technique_proxies.dart';
import '../metrics/timing_hotspots.dart';
import '../metrics/timing_metrics.dart';
import '../metrics/transition_analysis.dart';

/// IDs shared by the evaluation adapters and their composition-owned failure
/// classifier (ADR 0251 §2–§3).
abstract final class EvaluationStageIds {
  static const String alignment = 'target-alignment';
  static const String timing = 'target-timing-metrics';
  static const String timingHotspots = 'timing-hotspots';
  static const String rhythm = 'rhythm-metrics';
  static const String pitch = 'pitch-metrics';
  static const String dynamics = 'dynamics-metrics';
  static const String accent = 'accent-analysis';
  static const String subdivision = 'subdivision-analysis';
  static const String transitions = 'transition-analysis';
  static const String technique = 'technique-proxies';
  static const String capability = 'capability-confidence';
}

/// Composition-owned degradation policy. Every optional metric adapter can
/// degrade independently; the resolver is fatal because later document
/// assembly must know what evidence is safe to publish (ADR 0251 §3).
StageFailure classifyEvaluationStageFailure(
  String stageId,
  AppFailure failure,
) {
  switch (stageId) {
    case EvaluationStageIds.capability:
      return StageFailure.fatal(failure);
    case EvaluationStageIds.alignment:
      return StageFailure.degradable(
        failure,
        unavailableCapabilities: const <AnalysisCapability>{
          AnalysisCapability.targetAlignment,
          AnalysisCapability.timingAccuracy,
        },
      );
    case EvaluationStageIds.timing:
    case EvaluationStageIds.timingHotspots:
      return StageFailure.degradable(
        failure,
        unavailableCapabilities: const <AnalysisCapability>{
          AnalysisCapability.timingAccuracy,
        },
      );
    case EvaluationStageIds.rhythm:
    case EvaluationStageIds.subdivision:
      return StageFailure.degradable(
        failure,
        unavailableCapabilities: const <AnalysisCapability>{
          AnalysisCapability.beatGrid,
          AnalysisCapability.tempoCurve,
        },
      );
    case EvaluationStageIds.pitch:
      return StageFailure.degradable(
        failure,
        unavailableCapabilities: const <AnalysisCapability>{
          AnalysisCapability.monophonicPitch,
          AnalysisCapability.intonation,
          AnalysisCapability.noteStability,
        },
      );
    case EvaluationStageIds.dynamics:
    case EvaluationStageIds.accent:
      return StageFailure.degradable(
        failure,
        unavailableCapabilities: const <AnalysisCapability>{
          AnalysisCapability.dynamicConsistency,
        },
      );
    case EvaluationStageIds.transitions:
    case EvaluationStageIds.technique:
      return StageFailure.degradable(
        failure,
        unavailableCapabilities: const <AnalysisCapability>{
          AnalysisCapability.transitionSmoothness,
        },
      );
    default:
      return StageFailure.fatal(failure);
  }
}

/// Test seam for proving that an empty expected list never reaches the
/// reviewed [EventAligner] (E99-R10 A6).
typedef EventAlignmentCalculator =
    AlignmentResult Function({
      required List<AnalysisEvent> observed,
      required List<ExpectedEvent> expected,
      required Duration beatDuration,
    });

/// Runs target alignment only when the caller supplied at least one expected
/// event. Missing target evidence is a successful degraded condition, not a
/// fabricated all-missed alignment (ADR 0251 §2).
final class AlignmentEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  AlignmentEvaluationStage({EventAlignmentCalculator? align})
    : _align = align ?? const EventAligner().align;

  final EventAlignmentCalculator _align;

  @override
  String get id => EvaluationStageIds.alignment;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    final target = input.target;
    if (target == null || target.expectedEvents.isEmpty) return input;
    final alignment = _align(
      observed: _metricEvents(input),
      expected: target.expectedEvents,
      beatDuration: _beatDuration(input.beatGrid),
    );
    return input.copyWith(alignment: alignment);
  });
}

final class TimingMetricsEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  @override
  String get id => EvaluationStageIds.timing;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    final alignment = input.alignment;
    if (alignment == null) return input;
    return _appendMetrics(
      input,
      buildTargetTimingMetrics(
        alignment: alignment,
        tolerance: const TolerancePolicy().forBeatDuration(
          _beatDuration(input.beatGrid),
        ),
      ),
    );
  });
}

/// Executes the reviewed hotspot builder while retaining no hotspot output in
/// this work state: hotspot ranking and document assembly are GOV-30c-3.
final class TimingHotspotsEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  @override
  String get id => EvaluationStageIds.timingHotspots;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    final alignment = input.alignment;
    if (alignment == null) return input;
    buildTimingHotspots(
      alignment: alignment,
      tolerance: const TolerancePolicy().forBeatDuration(
        _beatDuration(input.beatGrid),
      ),
      ids: TimingMetricSuiteIds.target,
    );
    return input;
  });
}

final class RhythmMetricsEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  @override
  String get id => EvaluationStageIds.rhythm;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    final grid = input.beatGrid;
    if (grid == null) return input;
    return _appendMetrics(
      input,
      buildRhythmMetrics(events: _metricEvents(input), beatGrid: grid).metrics,
    );
  });
}

/// The V2 target contract intentionally has no note timing spans, so this
/// stage preserves the reviewed pitch gate's not-applicable result rather
/// than inventing monophonic target evidence from an unordered note list.
final class PitchMetricsEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  @override
  String get id => EvaluationStageIds.pitch;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    final quality = input.signalQuality?.report;
    if (quality == null) return input;
    return _appendMetrics(
      input,
      buildGatedPitchMetrics(
        analysisPitchEnabled: true,
        target: null,
        frames: input.pitchFrames,
        segments: input.pitchSegments,
        signalQuality: quality,
      ).metrics,
    );
  });
}

final class DynamicsMetricsEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  @override
  String get id => EvaluationStageIds.dynamics;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    final audio = input.preprocessedAudio;
    final quality = input.signalQuality?.report;
    if (audio == null || quality == null) return input;
    return _appendMetrics(
      input,
      buildDynamicsMetrics(
        audio: audio,
        events: _strumEvents(input),
        signalQuality: quality,
      ).metrics,
    );
  });
}

final class AccentEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  @override
  String get id => EvaluationStageIds.accent;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    final events = _strumEvents(input);
    if (events.isNotEmpty) detectLocalAccents(events: events);
    return input;
  });
}

final class SubdivisionEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  @override
  String get id => EvaluationStageIds.subdivision;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    final grid = input.beatGrid;
    if (grid != null) {
      const SubdivisionAnalyzer().analyze(
        events: _metricEvents(input),
        beatGrid: grid,
      );
    }
    return input;
  });
}

final class TransitionEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  @override
  String get id => EvaluationStageIds.transitions;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    buildChordTransitions(input.chordSegments);
    return input;
  });
}

/// Technique proxies remain disabled and non-persisted until their existing
/// Lab/flag boundary is explicitly opened by a later round.
final class TechniqueEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  @override
  String get id => EvaluationStageIds.technique;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    buildTechniqueProxyReport(
      analysisTechniqueProxiesEnabled: false,
      labModeActive: false,
      hasKnownTarget: _hasReferenceTarget(input),
      inputClipped: false,
      backingTrackDominant: false,
      chordSegments: input.chordSegments,
      onsets: <OnsetEvent>[
        for (final event in input.events)
          if (event is OnsetEvent) event,
      ],
    );
    return input;
  });
}

final class CapabilityConfidenceEvaluationStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  CapabilityConfidenceEvaluationStage({CapabilityResolver? resolver})
    : _resolver = resolver ?? CapabilityResolver();

  final CapabilityResolver _resolver;

  @override
  String get id => EvaluationStageIds.capability;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) => _runSafely(input, context, () {
    final quality = input.signalQuality?.report;
    if (quality == null) {
      throw StateError(
        'Capability resolution requires measured signal quality.',
      );
    }
    final confidenceFactors = <double>[
      for (final event in _metricEvents(input)) event.confidence,
    ];
    final modelConfidence = confidenceFactors.isEmpty
        ? 0.0
        : confidenceFactors.reduce((left, right) => left + right) /
              confidenceFactors.length;
    final resolution = _resolver.resolve(
      CapabilityResolverInput(
        signalQuality: quality,
        eventCount: _metricEvents(input).length,
        modelConfidence: modelConfidence,
        alignmentQuality: input.alignment?.confidence ?? 0,
        mode: input.mode,
        hasReferenceTarget: _hasReferenceTarget(input),
        modelAvailable: true,
      ),
    );
    return input.copyWith(
      capabilityReports: resolution.reports,
      unavailableCapabilities: <AnalysisCapability>{
        ...input.unavailableCapabilities,
        for (final report in resolution.reports.values)
          if (report.status == CapabilityStatus.unavailable) report.capability,
      },
      overallConfidence: resolution.overallConfidence,
    );
  });
}

/// The production composition remains a list only; concrete pipeline wiring
/// belongs to GOV-30c-3, after the progress-phase cap is resolved.
List<AnalysisStage<AnalysisWorkState, AnalysisWorkState>>
buildEvaluationStages() =>
    <AnalysisStage<AnalysisWorkState, AnalysisWorkState>>[
      AlignmentEvaluationStage(),
      TimingMetricsEvaluationStage(),
      TimingHotspotsEvaluationStage(),
      RhythmMetricsEvaluationStage(),
      PitchMetricsEvaluationStage(),
      DynamicsMetricsEvaluationStage(),
      AccentEvaluationStage(),
      SubdivisionEvaluationStage(),
      TransitionEvaluationStage(),
      TechniqueEvaluationStage(),
      CapabilityConfidenceEvaluationStage(),
    ];

Future<AppResult<AnalysisWorkState>> _runSafely(
  AnalysisWorkState input,
  AnalysisStageContext context,
  AnalysisWorkState Function() evaluate,
) async {
  try {
    context.cancellationToken.throwIfCancelled();
    final output = evaluate();
    context.cancellationToken.throwIfCancelled();
    return Success<AnalysisWorkState>(output);
  } catch (error, stackTrace) {
    return Failure<AnalysisWorkState>(
      UnknownFailure(cause: error, stackTrace: stackTrace),
    );
  }
}

AnalysisWorkState _appendMetrics(
  AnalysisWorkState input,
  List<AnalysisMetricResult> metrics,
) => input.copyWith(
  metrics: <AnalysisMetricResult>[...input.metrics, ...metrics],
);

bool _hasReferenceTarget(AnalysisWorkState input) =>
    input.target?.expectedEvents.isNotEmpty ?? false;

List<StrumEvent> _strumEvents(AnalysisWorkState input) => <StrumEvent>[
  for (final event in input.events)
    if (event is StrumEvent) event,
];

/// Timeline evidence contains onset/strum pairs at the same instant. Metric
/// modules require strictly increasing timestamps, so their shared adapter
/// view uses the strum event when present and otherwise the original event.
List<AnalysisEvent> _metricEvents(AnalysisWorkState input) {
  final strums = _strumEvents(input);
  if (strums.isNotEmpty) return strums;
  return input.events;
}

Duration _beatDuration(BeatGrid? grid) {
  final beats = grid?.beats;
  if (beats == null || beats.length < 2) {
    return const Duration(milliseconds: 500);
  }
  final duration = beats[1].time - beats[0].time;
  return duration > Duration.zero
      ? duration
      : const Duration(milliseconds: 500);
}
