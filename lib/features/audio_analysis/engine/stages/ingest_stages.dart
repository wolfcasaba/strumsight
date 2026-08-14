import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import '../../domain/analysis_capability.dart';
import '../../domain/analysis_input.dart';
import '../../domain/analysis_warning.dart';
import '../../domain/harmony/chord_frame_evidence.dart';
import '../../domain/preprocessed_audio.dart';
import '../analysis_context.dart';
import '../analysis_stage.dart';
import '../analysis_work_state.dart';
import '../events/event_timeline_builder.dart';
import '../harmony/chord_segment_assembler.dart';
import '../harmony/decoder_source.dart';
import '../pitch/monophonic_pitch_segment_builder.dart';
import '../pitch/pitch_frame_extractor.dart';
import '../preprocessing/preprocessing_stage.dart';
import '../quality/signal_quality_stage.dart';
import '../rhythm/beat_grid_estimator.dart';
import '../rhythm/tempo_curve_builder.dart';

/// Stage IDs used both by the adapters below and by
/// [classifyIngestStageFailure] — the single source of truth for the
/// degradation policy in ADR 0250 §3.
abstract final class IngestStageIds {
  static const String preprocessing = 'preprocessing';
  static const String signalQuality = 'signal-quality';
  static const String pitch = 'pitch';
  static const String harmony = 'harmony';
  static const String rhythm = 'rhythm';
  static const String events = 'events';
}

/// Composition-owned degradation policy (ADR 0250 §3): preprocessing, signal
/// quality and events are fatal; pitch, harmony and rhythm are degradable and
/// record the capabilities their failure makes unavailable.
///
/// NOTE for the §6.1 real-violation test: temporarily changing the
/// `preprocessing` case below to `StageFailure.degradable(...)` must turn the
/// corresponding composition-test cell red.
StageFailure classifyIngestStageFailure(String stageId, AppFailure failure) {
  switch (stageId) {
    case IngestStageIds.preprocessing:
    case IngestStageIds.signalQuality:
    case IngestStageIds.events:
      return StageFailure.fatal(failure);
    case IngestStageIds.pitch:
      return StageFailure.degradable(
        failure,
        unavailableCapabilities: const <AnalysisCapability>{
          AnalysisCapability.monophonicPitch,
          AnalysisCapability.intonation,
          AnalysisCapability.noteStability,
          AnalysisCapability.transitionSmoothness,
        },
      );
    case IngestStageIds.harmony:
      return StageFailure.degradable(
        failure,
        unavailableCapabilities: const <AnalysisCapability>{
          AnalysisCapability.chordTimeline,
        },
      );
    case IngestStageIds.rhythm:
      return StageFailure.degradable(
        failure,
        unavailableCapabilities: const <AnalysisCapability>{
          AnalysisCapability.beatGrid,
          AnalysisCapability.tempoCurve,
          AnalysisCapability.timingAccuracy,
        },
      );
    default:
      return StageFailure.fatal(failure);
  }
}

/// Wraps the already-reviewed [PreprocessingStage] into the ingest chain's
/// uniform work-state contract. Calls the injected stage; never recomputes.
final class PreprocessingIngestStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  const PreprocessingIngestStage({this.stage = const PreprocessingStage()});

  final AnalysisStage<ValidatedPcmAnalysisInput, PreprocessedAudio> stage;

  @override
  String get id => IngestStageIds.preprocessing;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) async {
    final result = await stage.run(input.input, context);
    return result.map((audio) => input.copyWith(preprocessedAudio: audio));
  }
}

/// Wraps the already-reviewed [SignalQualityStage]; folds its report
/// warnings into the work state's accumulated warning list.
final class SignalQualityIngestStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  SignalQualityIngestStage({
    AnalysisStage<ValidatedPcmAnalysisInput, SignalQualityStageResult>? stage,
  }) : stage = stage ?? SignalQualityStage();

  final AnalysisStage<ValidatedPcmAnalysisInput, SignalQualityStageResult>
  stage;

  @override
  String get id => IngestStageIds.signalQuality;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) async {
    final result = await stage.run(input.input, context);
    return result.map(
      (quality) => input.copyWith(
        signalQuality: quality,
        warnings: <AnalysisWarning>[
          ...input.warnings,
          ...quality.report.warnings,
        ],
      ),
    );
  }
}

/// Extracts YIN pitch frames and groups them into monophonic segments.
/// Requires [AnalysisWorkState.preprocessedAudio] — its absence is this
/// stage's only failure path, since the wrapped modules never fail on
/// well-formed audio.
final class PitchIngestStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  PitchIngestStage({PitchFrameExtractor? frameExtractor, this.segmentBuilder})
    : frameExtractor = frameExtractor ?? PitchFrameExtractor();

  final PitchFrameExtractor frameExtractor;
  final MonophonicPitchSegmentBuilder? segmentBuilder;

  @override
  String get id => IngestStageIds.pitch;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) async {
    final audio = input.preprocessedAudio;
    if (audio == null) {
      return const Failure<AnalysisWorkState>(
        ValidationFailure(cause: 'pitch stage requires preprocessed audio'),
      );
    }
    context.cancellationToken.throwIfCancelled();
    final frames = frameExtractor.extract(
      samples: audio.canonicalSamples,
      sampleRate: audio.sampleRate,
    );
    final builder = segmentBuilder ?? MonophonicPitchSegmentBuilder();
    final segments = builder.build(frames);
    return Success<AnalysisWorkState>(
      input.copyWith(pitchFrames: frames, pitchSegments: segments),
    );
  }
}

/// Derives V1 chord spans into `ChordFrameEvidence.derived` (V1 carries no
/// ranked probabilities, per that factory's contract) and assembles them
/// with the reviewed [ChordSegmentAssembler]. Requires
/// [AnalysisWorkState.legacyEvidence]; its absence is this stage's failure
/// path.
final class HarmonyIngestStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  HarmonyIngestStage({
    ChordSegmentAssembler? assembler,
    this.policy = const ChordSegmentationPolicy(),
  }) : assembler = assembler ?? const ChordSegmentAssembler();

  final ChordSegmentAssembler assembler;
  final ChordSegmentationPolicy policy;

  @override
  String get id => IngestStageIds.harmony;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) async {
    final evidence = input.legacyEvidence;
    if (evidence == null) {
      return const Failure<AnalysisWorkState>(
        ValidationFailure(cause: 'harmony stage requires legacy evidence'),
      );
    }
    context.cancellationToken.throwIfCancelled();
    final frames = <ChordFrameEvidence>[
      for (final chord in evidence.chords)
        ChordFrameEvidence.derived(
          time: chord.start,
          topLabel: chord.label,
          source: DecoderSource.dsp,
        ),
    ];
    final segments = assembler.assemble(
      frames: frames,
      clipDuration: evidence.duration,
      policy: policy,
    );
    return Success<AnalysisWorkState>(input.copyWith(chordSegments: segments));
  }
}

/// Reads V1 strum times as onset evidence for the reviewed
/// [BeatGridEstimator] and [TempoCurveBuilder]. Requires
/// [AnalysisWorkState.legacyEvidence]; its absence is this stage's failure
/// path.
final class RhythmIngestStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  RhythmIngestStage({
    BeatGridEstimator? beatGridEstimator,
    TempoCurveBuilder? tempoCurveBuilder,
  }) : beatGridEstimator = beatGridEstimator ?? const BeatGridEstimator(),
       tempoCurveBuilder = tempoCurveBuilder ?? const TempoCurveBuilder();

  final BeatGridEstimator beatGridEstimator;
  final TempoCurveBuilder tempoCurveBuilder;

  @override
  String get id => IngestStageIds.rhythm;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) async {
    final evidence = input.legacyEvidence;
    if (evidence == null) {
      return const Failure<AnalysisWorkState>(
        ValidationFailure(cause: 'rhythm stage requires legacy evidence'),
      );
    }
    context.cancellationToken.throwIfCancelled();
    final eventTimes = <Duration>[
      for (final strum in evidence.strums) strum.time,
    ]..sort();
    final beatGrid = beatGridEstimator.estimate(
      eventTimes: eventTimes,
      clipDuration: evidence.duration,
    );
    final tempoCurve = tempoCurveBuilder.build(
      eventTimes: eventTimes,
      clipDuration: evidence.duration,
    );
    return Success<AnalysisWorkState>(
      input.copyWith(beatGrid: beatGrid, tempoCurve: tempoCurve),
    );
  }
}

/// Wraps the reviewed [EventTimelineBuilder]; the events track is the basis
/// of the eventual `AnalysisTimeline`, so a fatal outcome here matches ADR
/// 0250 §3. Requires both [AnalysisWorkState.legacyEvidence] and
/// [AnalysisWorkState.preprocessedAudio].
final class EventsIngestStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  const EventsIngestStage({this.builder = const EventTimelineBuilder()});

  final EventTimelineBuilder builder;

  @override
  String get id => IngestStageIds.events;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) async {
    final evidence = input.legacyEvidence;
    final audio = input.preprocessedAudio;
    if (evidence == null || audio == null) {
      return const Failure<AnalysisWorkState>(
        ValidationFailure(
          cause:
              'events stage requires legacy evidence and preprocessed '
              'audio',
        ),
      );
    }
    context.cancellationToken.throwIfCancelled();
    final result = builder.build(
      runId: context.runId,
      evidence: evidence,
      audio: audio,
    );
    return Success<AnalysisWorkState>(
      input.copyWith(
        events: result.events,
        suppressedEvents: result.suppressedEvents,
      ),
    );
  }
}

/// The full ingest chain in ADR 0250's fixed order: preprocessing → signal
/// quality → pitch → harmony → rhythm → events. Pairs with
/// [classifyIngestStageFailure] when composed into an `AnalysisPipeline`.
/// Not wired into any provider in this round (ADR 0250 §4).
List<AnalysisStage<AnalysisWorkState, AnalysisWorkState>> buildIngestStages() =>
    <AnalysisStage<AnalysisWorkState, AnalysisWorkState>>[
      const PreprocessingIngestStage(),
      SignalQualityIngestStage(),
      PitchIngestStage(),
      HarmonyIngestStage(),
      RhythmIngestStage(),
      const EventsIngestStage(),
    ];
