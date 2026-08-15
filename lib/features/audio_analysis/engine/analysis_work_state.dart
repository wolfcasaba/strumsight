import 'package:meta/meta.dart';

import '../domain/analysis_capability.dart';
import '../domain/analysis_document.dart';
import '../domain/analysis_event.dart';
import '../domain/analysis_input.dart';
import '../domain/analysis_metric.dart';
import '../domain/analysis_mode.dart';
import '../domain/analysis_segment.dart';
import '../domain/analysis_warning.dart';
import '../domain/pitch/monophonic_pitch_segment.dart';
import '../domain/pitch/pitch_frame.dart';
import '../domain/preprocessed_audio.dart';
import '../domain/rhythm/beat_grid.dart';
import '../domain/target/alignment_result.dart';
import '../domain/target/analysis_target.dart';
import 'events/event_timeline_builder.dart' show SuppressedEvent;
import 'legacy/legacy_evidence.dart' show LegacyEvidence;
import 'quality/signal_quality_stage.dart' show SignalQualityStageResult;
import 'rhythm/tempo_curve_builder.dart' show TempoCurve;

/// Single, immutable work-state type carried by every V2 ingest stage (ADR
/// 0250 §1). Each stage reads what it needs and returns a [copyWith] of the
/// artifacts it produced — the previous instance is never mutated.
///
/// Only artifacts a later ingest stage or the eventual `AnalysisDocument`
/// assembly actually reads are kept here (ADR 0250 §"Következmények");
/// intermediate stage-local values stay inside the wrapped module.
@immutable
final class AnalysisWorkState {
  AnalysisWorkState({
    required this.input,
    this.mode = AnalysisMode.freePlay,
    this.target,
    this.legacyEvidence,
    this.preprocessedAudio,
    this.signalQuality,
    List<PitchFrame> pitchFrames = const <PitchFrame>[],
    List<MonophonicPitchSegment> pitchSegments =
        const <MonophonicPitchSegment>[],
    List<ChordSegment> chordSegments = const <ChordSegment>[],
    this.beatGrid,
    this.tempoCurve,
    List<AnalysisEvent> events = const <AnalysisEvent>[],
    List<SuppressedEvent> suppressedEvents = const <SuppressedEvent>[],
    List<AnalysisWarning> warnings = const <AnalysisWarning>[],
    Set<AnalysisCapability> unavailableCapabilities =
        const <AnalysisCapability>{},
    this.alignment,
    List<AnalysisMetricResult> metrics = const <AnalysisMetricResult>[],
    Map<AnalysisCapability, CapabilityReport> capabilityReports =
        const <AnalysisCapability, CapabilityReport>{},
    this.overallConfidence,
    this.document,
  }) : pitchFrames = List<PitchFrame>.unmodifiable(pitchFrames),
       pitchSegments = List<MonophonicPitchSegment>.unmodifiable(pitchSegments),
       chordSegments = List<ChordSegment>.unmodifiable(chordSegments),
       events = List<AnalysisEvent>.unmodifiable(events),
       suppressedEvents = List<SuppressedEvent>.unmodifiable(suppressedEvents),
       warnings = List<AnalysisWarning>.unmodifiable(warnings),
       unavailableCapabilities = Set<AnalysisCapability>.unmodifiable(
         unavailableCapabilities,
       ),
       metrics = List<AnalysisMetricResult>.unmodifiable(metrics),
       capabilityReports =
           Map<AnalysisCapability, CapabilityReport>.unmodifiable(
             capabilityReports,
           );

  /// The boundary input plus any input-quality warnings it already carries.
  final ValidatedPcmAnalysisInput input;

  /// The caller's run intent. It stays explicit because a practice-mode run
  /// can still lack a usable target (ADR 0251 §3).
  final AnalysisMode mode;

  /// Optional caller-supplied snapshot of the performance reference. Stages
  /// consume it but never infer or construct one from observed audio.
  final AnalysisTarget? target;

  /// V1 evidence the ingest chain adapts (ADR 0250 problem table, row 3):
  /// harmony derives `ChordFrameEvidence` from `legacyEvidence.chords`
  /// (`EvidenceCompleteness.derived`), rhythm reads `legacyEvidence.strums`
  /// as onset times, and events wraps `EventTimelineBuilder` directly with
  /// it. Produced mid-chain by the `legacy-evidence` ingest stage (which
  /// wraps the reviewed `ClipAnalyzerStage` over the preprocessed audio) —
  /// never supplied by the caller.
  final LegacyEvidence? legacyEvidence;

  final PreprocessedAudio? preprocessedAudio;
  final SignalQualityStageResult? signalQuality;
  final List<PitchFrame> pitchFrames;
  final List<MonophonicPitchSegment> pitchSegments;
  final List<ChordSegment> chordSegments;
  final BeatGrid? beatGrid;
  final TempoCurve? tempoCurve;
  final List<AnalysisEvent> events;
  final List<SuppressedEvent> suppressedEvents;

  /// Domain-level warnings gathered along the chain (e.g. signal-quality
  /// findings). Distinct from the pipeline's own `stage_unavailable`
  /// warnings, which [AnalysisPipeline] tracks separately per run.
  final List<AnalysisWarning> warnings;

  /// Capabilities an ingest adapter itself determined unavailable, as
  /// opposed to the ones [AnalysisPipeline] records from a degraded stage
  /// failure. Empty in this round — no adapter resolves capability
  /// availability yet (GOV-30c-2).
  final Set<AnalysisCapability> unavailableCapabilities;

  /// Target alignment is absent, rather than fabricated, when [target] is
  /// null or has no expected events (ADR 0251 §2).
  final AlignmentResult? alignment;

  /// Published metric artifacts accumulated by the evaluation stages.
  final List<AnalysisMetricResult> metrics;

  /// The resolver's per-capability evidence, kept separately from the
  /// pipeline-level degradation set.
  final Map<AnalysisCapability, CapabilityReport> capabilityReports;

  /// Resolver-combined confidence, unavailable until its fatal stage runs.
  final double? overallConfidence;

  /// The publishable V2 document assembled after the evidence and evaluation
  /// stages complete. It remains absent until document assembly succeeds.
  final AnalysisDocument? document;

  /// The initial state for one ingest run: only the boundary PCM input,
  /// seeded with its own warnings. `legacyEvidence` is not a seed input —
  /// the `legacy-evidence` ingest stage derives it from the preprocessed
  /// audio partway through the chain.
  factory AnalysisWorkState.seed({
    required ValidatedPcmAnalysisInput input,
    AnalysisMode mode = AnalysisMode.freePlay,
    AnalysisTarget? target,
  }) => AnalysisWorkState(
    input: input,
    mode: mode,
    target: target,
    warnings: input.warnings,
  );

  AnalysisWorkState copyWith({
    ValidatedPcmAnalysisInput? input,
    AnalysisMode? mode,
    AnalysisTarget? target,
    LegacyEvidence? legacyEvidence,
    PreprocessedAudio? preprocessedAudio,
    SignalQualityStageResult? signalQuality,
    List<PitchFrame>? pitchFrames,
    List<MonophonicPitchSegment>? pitchSegments,
    List<ChordSegment>? chordSegments,
    BeatGrid? beatGrid,
    TempoCurve? tempoCurve,
    List<AnalysisEvent>? events,
    List<SuppressedEvent>? suppressedEvents,
    List<AnalysisWarning>? warnings,
    Set<AnalysisCapability>? unavailableCapabilities,
    AlignmentResult? alignment,
    List<AnalysisMetricResult>? metrics,
    Map<AnalysisCapability, CapabilityReport>? capabilityReports,
    double? overallConfidence,
    AnalysisDocument? document,
  }) => AnalysisWorkState(
    input: input ?? this.input,
    mode: mode ?? this.mode,
    target: target ?? this.target,
    legacyEvidence: legacyEvidence ?? this.legacyEvidence,
    preprocessedAudio: preprocessedAudio ?? this.preprocessedAudio,
    signalQuality: signalQuality ?? this.signalQuality,
    pitchFrames: pitchFrames ?? this.pitchFrames,
    pitchSegments: pitchSegments ?? this.pitchSegments,
    chordSegments: chordSegments ?? this.chordSegments,
    beatGrid: beatGrid ?? this.beatGrid,
    tempoCurve: tempoCurve ?? this.tempoCurve,
    events: events ?? this.events,
    suppressedEvents: suppressedEvents ?? this.suppressedEvents,
    warnings: warnings ?? this.warnings,
    unavailableCapabilities:
        unavailableCapabilities ?? this.unavailableCapabilities,
    alignment: alignment ?? this.alignment,
    metrics: metrics ?? this.metrics,
    capabilityReports: capabilityReports ?? this.capabilityReports,
    overallConfidence: overallConfidence ?? this.overallConfidence,
    document: document ?? this.document,
  );
}
