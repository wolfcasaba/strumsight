// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart' as legacy_core;
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_pipeline.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_provenance_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_stage.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_work_state.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/legacy_evidence.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/ingest_stages.dart';

const _sampleRate = 44100;

void main() {
  group('ingest pipeline composition (ADR 0250)', () {
    test(
      // A4: the full six-stage chain runs on valid input and reaches a
      // timeline base — pitch, chord, beat/tempo and event artifacts.
      'A4 — the full chain runs on valid input and produces a timeline base',
      () async {
        final pipeline = AnalysisPipeline<AnalysisWorkState>(
          stages: buildIngestStages(),
          failureClassifier: classifyIngestStageFailure,
        );
        final initial = AnalysisWorkState.seed(
          input: _input(samples: _sine(220, seconds: 0.4)),
          legacyEvidence: _legacyEvidence(
            chords: const <LegacyChordEvidence>[
              LegacyChordEvidence(
                label: 'Am',
                start: Duration.zero,
                end: Duration(seconds: 1),
              ),
            ],
            strums: <LegacyStrumEvidence>[
              for (var i = 0; i < 10; i++)
                LegacyStrumEvidence(
                  direction: legacy_core.StrumDirection.down,
                  time: Duration(milliseconds: 500 * i),
                  confidence: .8,
                ),
            ],
            duration: const Duration(seconds: 5),
          ),
        );

        final observation = await _run(pipeline, initial);

        expect(observation.completion, AnalysisCompletionStatus.complete);
        final value = observation.value;
        expect(value, isNotNull);
        expect(value!.preprocessedAudio, isNotNull);
        expect(value.signalQuality, isNotNull);
        expect(value.pitchFrames, isNotEmpty);
        expect(value.pitchSegments, isNotEmpty);
        expect(value.chordSegments, isNotEmpty);
        expect(value.beatGrid, isNotNull);
        expect(value.tempoCurve, isNotNull);
        expect(value.events, isNotEmpty);
        expect(observation.unavailableCapabilities, isEmpty);
      },
    );

    test(
      // A6, "fatális alatt": a preprocessing failure halts the chain before
      // any later stage runs, and no partial value is published.
      'A6 — a fatal preprocessing failure stops the chain with no partial value',
      () async {
        final calledStageIds = <String>[];
        final pipeline = AnalysisPipeline<AnalysisWorkState>(
          stages: <AnalysisStage<AnalysisWorkState, AnalysisWorkState>>[
            _RecordingFailingStage(
              id: IngestStageIds.preprocessing,
              log: calledStageIds,
            ),
            SignalQualityIngestStage(),
            PitchIngestStage(),
            HarmonyIngestStage(),
            RhythmIngestStage(),
            const EventsIngestStage(),
          ],
          failureClassifier: classifyIngestStageFailure,
        );

        final observation = await _run(
          pipeline,
          AnalysisWorkState.seed(input: _input()),
        );

        expect(observation.completion, AnalysisCompletionStatus.failed);
        expect(observation.value, isNull);
        expect(calledStageIds, <String>[IngestStageIds.preprocessing]);
        // The provenance timing log records every stage the pipeline
        // actually ran, success or failure — unlike `value`/`completion`,
        // it cannot coincidentally match if a *later* stage happened to
        // also fail fatally. This is what the §6.1 real-violation check
        // exercises: temporarily flipping `preprocessing` to degradable in
        // classifyIngestStageFailure makes this assertion fail, because the
        // chain would then keep running through signal-quality, pitch,
        // harmony and rhythm before events finally stops it.
        expect(
          observation.provenance.stageTimings.map((timing) => timing.id),
          <String>[IngestStageIds.preprocessing],
        );
      },
    );

    test(
      // A5, "fatális fölött": a degradable pitch failure does not stop the
      // chain — harmony/rhythm/events still run and produce a value, while
      // the lost capabilities are recorded.
      'A5 — a degradable pitch failure keeps the chain running',
      () async {
        final pipeline = AnalysisPipeline<AnalysisWorkState>(
          stages: <AnalysisStage<AnalysisWorkState, AnalysisWorkState>>[
            const PreprocessingIngestStage(),
            SignalQualityIngestStage(),
            _RecordingFailingStage(id: IngestStageIds.pitch, log: <String>[]),
            HarmonyIngestStage(),
            RhythmIngestStage(),
            const EventsIngestStage(),
          ],
          failureClassifier: classifyIngestStageFailure,
        );
        final initial = AnalysisWorkState.seed(
          input: _input(samples: _sine(220, seconds: 0.4)),
          legacyEvidence: _legacyEvidence(
            chords: const <LegacyChordEvidence>[
              LegacyChordEvidence(
                label: 'C',
                start: Duration.zero,
                end: Duration(seconds: 1),
              ),
            ],
            strums: <LegacyStrumEvidence>[
              for (var i = 0; i < 10; i++)
                LegacyStrumEvidence(
                  direction: legacy_core.StrumDirection.down,
                  time: Duration(milliseconds: 500 * i),
                  confidence: .8,
                ),
            ],
            duration: const Duration(seconds: 5),
          ),
        );

        final observation = await _run(pipeline, initial);

        expect(observation.completion, AnalysisCompletionStatus.degraded);
        expect(observation.value, isNotNull);
        expect(observation.value!.pitchFrames, isEmpty);
        expect(observation.value!.chordSegments, isNotEmpty);
        expect(observation.value!.events, isNotEmpty);
        expect(
          observation.unavailableCapabilities,
          contains(AnalysisCapability.monophonicPitch),
        );
        expect(
          observation.warnings.map((warning) => warning.messageKey),
          contains('analysis.stage_unavailable'),
        );
      },
    );

    test(
      // A5 + A6 together, "a határon": missing V1 evidence degrades harmony
      // and rhythm (their lost capabilities are still recorded) but then
      // fatally stops the chain at events — the last fatal stage — with no
      // partial value.
      'A5/A6 — harmony and rhythm degrade, then events halts the chain fatally',
      () async {
        final pipeline = AnalysisPipeline<AnalysisWorkState>(
          stages: buildIngestStages(),
          failureClassifier: classifyIngestStageFailure,
        );
        final initial = AnalysisWorkState.seed(
          input: _input(samples: _sine(220, seconds: 0.4)),
        );

        final observation = await _run(pipeline, initial);

        expect(observation.completion, AnalysisCompletionStatus.failed);
        expect(observation.value, isNull);
        expect(
          observation.unavailableCapabilities,
          containsAll(<AnalysisCapability>[
            AnalysisCapability.chordTimeline,
            AnalysisCapability.beatGrid,
            AnalysisCapability.tempoCurve,
          ]),
        );
      },
    );
  });
}

Future<AnalysisPipelineResult<AnalysisWorkState>> _run(
  AnalysisPipeline<AnalysisWorkState> pipeline,
  AnalysisWorkState initial,
) async {
  final run = pipeline.start(
    initial,
    cancellationToken: AnalysisCancellationSource(),
  );
  final done = Completer<void>();
  final subscription = run.progress.listen((_) {}, onDone: done.complete);
  final result = await run.result;
  await done.future;
  await subscription.cancel();
  return result;
}

/// A test double standing in for a real ingest stage id so the composition
/// test can prove the classifier's stage-id decision without needing a real
/// module to fail (several wrapped modules never fail on well-formed input).
final class _RecordingFailingStage
    implements AnalysisStage<AnalysisWorkState, AnalysisWorkState> {
  const _RecordingFailingStage({required this.id, required this.log});

  @override
  final String id;

  final List<String> log;

  @override
  int get version => 1;

  @override
  Future<AppResult<AnalysisWorkState>> run(
    AnalysisWorkState input,
    AnalysisStageContext context,
  ) async {
    log.add(id);
    return const Failure<AnalysisWorkState>(ValidationFailure());
  }
}

ValidatedPcmAnalysisInput _input({
  List<double> samples = const <double>[0.1, -0.1, 0.2, -0.2],
}) => ValidatedPcmAnalysisInput(
  input: PcmAnalysisInput(
    samples: samples,
    sampleRate: _sampleRate,
    channelCount: 1,
    source: AnalysisInputSource.microphone,
  ),
);

LegacyEvidence _legacyEvidence({
  List<LegacyChordEvidence> chords = const <LegacyChordEvidence>[],
  List<LegacyStrumEvidence> strums = const <LegacyStrumEvidence>[],
  Duration duration = const Duration(seconds: 1),
}) => LegacyEvidence(
  duration: duration,
  bpm: 120,
  chords: chords,
  strums: strums,
  call: LegacyClipAnalyzerCall(
    sampleRate: _sampleRate,
    sampleCount: _sampleRate,
    labMode: false,
    hasCandidateStrumRefiner: false,
  ),
  provenance: AnalysisProvenanceBuilder().build(
    strumRefinerSource: StrumRefinerSource.none,
  ),
);

List<double> _sine(double frequency, {required double seconds}) =>
    List<double>.generate(
      (seconds * _sampleRate).round(),
      (index) => 0.4 * math.sin(2 * math.pi * frequency * index / _sampleRate),
    );
