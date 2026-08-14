import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart' as legacy_core;
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_provenance_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_stage.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_work_state.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/legacy_evidence.dart';
import 'package:strumsight/features/audio_analysis/engine/preprocessing/preprocessing_config.dart';
import 'package:strumsight/features/audio_analysis/engine/preprocessing/preprocessing_stage.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/ingest_stages.dart';

import '../../../../support/synth.dart';

const _sampleRate = 44100;

void main() {
  group('PreprocessingIngestStage', () {
    test('delegates to the injected stage and stores its output', () async {
      final state = AnalysisWorkState.seed(input: _input());

      final result = await const PreprocessingIngestStage().run(
        state,
        _context(phase: AnalysisProgressPhase.preprocessing),
      );

      final next = _requireSuccess(result);
      expect(next.preprocessedAudio, isNotNull);
      expect(next.preprocessedAudio!.sampleRate, _sampleRate);
      expect(identical(next.input, state.input), isTrue);
    });

    test(
      // A3: swapping the injected PreprocessingStage instance changes the
      // adapter's output — proof the adapter calls the real stage rather
      // than copying its body.
      'A3 — swapping the injected stage changes the output',
      () async {
        final state = AnalysisWorkState.seed(
          input: _input(samples: <double>[0.5, -0.5, 0.5, -0.5]),
        );
        final defaultStage = PreprocessingIngestStage();
        final normalizingStage = PreprocessingIngestStage(
          stage: const PreprocessingStage(
            experimentalEnabled: true,
            config: PreprocessingConfig.v1(normalizePeak: true),
          ),
        );

        final defaultResult = _requireSuccess(
          await defaultStage.run(
            state,
            _context(phase: AnalysisProgressPhase.preprocessing),
          ),
        );
        final normalizingResult = _requireSuccess(
          await normalizingStage.run(
            state,
            _context(phase: AnalysisProgressPhase.preprocessing),
          ),
        );

        expect(defaultResult.preprocessedAudio!.normalizationGain, 1);
        expect(
          normalizingResult.preprocessedAudio!.normalizationGain,
          isNot(1),
        );
      },
    );
  });

  group('SignalQualityIngestStage', () {
    test('folds the quality report warnings into the work state', () async {
      final state = AnalysisWorkState.seed(
        input: _input(samples: List<double>.filled(_sampleRate, 0)),
      );

      final next = _requireSuccess(
        await SignalQualityIngestStage().run(
          state,
          _context(phase: AnalysisProgressPhase.preprocessing),
        ),
      );

      expect(next.signalQuality, isNotNull);
      expect(next.warnings, isNotEmpty);
      expect(
        next.warnings.map((warning) => warning.messageKey),
        contains('quality.recording_silent'),
      );
    });
  });

  group('LegacyEvidenceIngestStage', () {
    test('delegates to the injected stage and stores its output', () async {
      final samples = strumPattern(lowFirstPerStrum: [true, false]);
      final state = AnalysisWorkState.seed(
        input: _input(samples: samples),
      ).copyWith(preprocessedAudio: _preprocessedAudio(samples));

      final next = _requireSuccess(
        await const LegacyEvidenceIngestStage().run(
          state,
          _context(phase: AnalysisProgressPhase.extractingEvents),
        ),
      );

      expect(next.legacyEvidence, isNotNull);
      expect(next.legacyEvidence!.strums, isNotEmpty);
    });

    test(
      // A3-equivalent: swapping the injected ClipAnalyzerStage changes the
      // adapter's output — proof the adapter calls the real stage rather
      // than copying its body.
      'swapping the injected stage changes the output',
      () async {
        final samples = strumPattern(lowFirstPerStrum: [true, false]);
        final state = AnalysisWorkState.seed(
          input: _input(samples: samples),
        ).copyWith(preprocessedAudio: _preprocessedAudio(samples));

        final stubbedResult = _requireSuccess(
          await LegacyEvidenceIngestStage(
            stage: const _StubClipAnalyzerStage(),
          ).run(state, _context(phase: AnalysisProgressPhase.extractingEvents)),
        );

        expect(stubbedResult.legacyEvidence, same(_stubEvidence));
      },
    );

    test('fails without preprocessed audio', () async {
      final state = AnalysisWorkState.seed(input: _input());

      final result = await const LegacyEvidenceIngestStage().run(
        state,
        _context(phase: AnalysisProgressPhase.extractingEvents),
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('PitchIngestStage', () {
    test('extracts voiced frames and segments from real audio', () async {
      final samples = _sine(220, seconds: 0.4);
      final state = AnalysisWorkState.seed(
        input: _input(samples: samples),
      ).copyWith(preprocessedAudio: _preprocessedAudio(samples));

      final next = _requireSuccess(
        await PitchIngestStage().run(
          state,
          _context(phase: AnalysisProgressPhase.extractingEvents),
        ),
      );

      expect(next.pitchFrames, isNotEmpty);
      expect(next.pitchSegments, isNotEmpty);
      expect(next.pitchSegments.first.medianMidi, 57); // A3
    });

    test('fails without preprocessed audio', () async {
      final state = AnalysisWorkState.seed(input: _input());

      final result = await PitchIngestStage().run(
        state,
        _context(phase: AnalysisProgressPhase.extractingEvents),
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('HarmonyIngestStage', () {
    test('assembles chord segments from derived V1 chord evidence', () async {
      final state = AnalysisWorkState.seed(input: _input()).copyWith(
        legacyEvidence: _legacyEvidence(
          chords: const <LegacyChordEvidence>[
            LegacyChordEvidence(
              label: 'C',
              start: Duration.zero,
              end: Duration(milliseconds: 800),
            ),
            LegacyChordEvidence(
              label: 'G',
              start: Duration(milliseconds: 800),
              end: Duration(seconds: 1),
            ),
          ],
        ),
      );

      final next = _requireSuccess(
        await HarmonyIngestStage().run(
          state,
          _context(phase: AnalysisProgressPhase.estimatingHarmony),
        ),
      );

      expect(next.chordSegments, hasLength(2));
      expect(next.chordSegments.map((segment) => segment.label), <String>[
        'C',
        'G',
      ]);
    });

    test('fails without legacy evidence', () async {
      final state = AnalysisWorkState.seed(input: _input());

      final result = await HarmonyIngestStage().run(
        state,
        _context(phase: AnalysisProgressPhase.estimatingHarmony),
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('RhythmIngestStage', () {
    test('estimates a beat grid and tempo curve from legacy strums', () async {
      final strums = <LegacyStrumEvidence>[
        for (var i = 0; i < 10; i++)
          LegacyStrumEvidence(
            direction: legacy_core.StrumDirection.down,
            time: Duration(milliseconds: 500 * i),
            confidence: .8,
          ),
      ];
      final state = AnalysisWorkState.seed(input: _input()).copyWith(
        legacyEvidence: _legacyEvidence(
          strums: strums,
          duration: const Duration(milliseconds: 5000),
        ),
      );

      final next = _requireSuccess(
        await RhythmIngestStage().run(
          state,
          _context(phase: AnalysisProgressPhase.estimatingBeatGrid),
        ),
      );

      expect(next.beatGrid, isNotNull);
      expect(next.beatGrid!.beats, isNotEmpty);
      expect(next.tempoCurve, isNotNull);
    });

    test('fails without legacy evidence', () async {
      final state = AnalysisWorkState.seed(input: _input());

      final result = await RhythmIngestStage().run(
        state,
        _context(phase: AnalysisProgressPhase.estimatingBeatGrid),
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('EventsIngestStage', () {
    test('builds the onset/strum event track from legacy evidence', () async {
      final state = AnalysisWorkState.seed(input: _input()).copyWith(
        legacyEvidence: _legacyEvidence(
          strums: const <LegacyStrumEvidence>[
            LegacyStrumEvidence(
              direction: legacy_core.StrumDirection.down,
              time: Duration(milliseconds: 50),
              confidence: .8,
            ),
          ],
        ),
        preprocessedAudio: _preprocessedAudio(
          List<double>.filled(_sampleRate, .25),
        ),
      );

      final next = _requireSuccess(
        await const EventsIngestStage().run(
          state,
          _context(phase: AnalysisProgressPhase.extractingEvents),
        ),
      );

      expect(next.events, hasLength(2));
      expect(next.events.whereType<OnsetEvent>(), hasLength(1));
      expect(next.events.whereType<StrumEvent>(), hasLength(1));
    });

    test('fails without legacy evidence or preprocessed audio', () async {
      final state = AnalysisWorkState.seed(input: _input());

      final result = await const EventsIngestStage().run(
        state,
        _context(phase: AnalysisProgressPhase.extractingEvents),
      );

      expect(result.isFailure, isTrue);
    });
  });

  group('classifyIngestStageFailure', () {
    const failure = ValidationFailure();

    test('preprocessing, signal-quality, legacy-evidence and events are '
        'fatal', () {
      for (final id in <String>[
        IngestStageIds.preprocessing,
        IngestStageIds.signalQuality,
        IngestStageIds.legacyEvidence,
        IngestStageIds.events,
      ]) {
        final verdict = classifyIngestStageFailure(id, failure);
        expect(verdict.isDegradable, isFalse, reason: id);
        expect(verdict.unavailableCapabilities, isEmpty, reason: id);
      }
    });

    test('pitch, harmony and rhythm are degradable with lost capabilities', () {
      final pitch = classifyIngestStageFailure(IngestStageIds.pitch, failure);
      expect(pitch.isDegradable, isTrue);
      expect(
        pitch.unavailableCapabilities,
        contains(AnalysisCapability.monophonicPitch),
      );

      final harmony = classifyIngestStageFailure(
        IngestStageIds.harmony,
        failure,
      );
      expect(harmony.isDegradable, isTrue);
      expect(
        harmony.unavailableCapabilities,
        contains(AnalysisCapability.chordTimeline),
      );

      final rhythm = classifyIngestStageFailure(IngestStageIds.rhythm, failure);
      expect(rhythm.isDegradable, isTrue);
      expect(
        rhythm.unavailableCapabilities,
        contains(AnalysisCapability.beatGrid),
      );
    });

    test('an unknown stage id defaults to fatal', () {
      final verdict = classifyIngestStageFailure('unknown-stage', failure);
      expect(verdict.isDegradable, isFalse);
    });
  });

  group('buildIngestStages', () {
    test('composes exactly the seven ingest stages in ADR 0250 order', () {
      final stages = buildIngestStages();

      expect(stages.map((stage) => stage.id), <String>[
        IngestStageIds.preprocessing,
        IngestStageIds.signalQuality,
        IngestStageIds.legacyEvidence,
        IngestStageIds.pitch,
        IngestStageIds.harmony,
        IngestStageIds.rhythm,
        IngestStageIds.events,
      ]);
    });
  });
}

final _stubEvidence = LegacyEvidence(
  duration: const Duration(seconds: 1),
  bpm: 120,
  chords: const <LegacyChordEvidence>[],
  strums: const <LegacyStrumEvidence>[],
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

final class _StubClipAnalyzerStage
    implements AnalysisStage<LegacyClipAnalyzerInput, LegacyEvidence> {
  const _StubClipAnalyzerStage();

  @override
  String get id => 'stub-clip-analyzer';

  @override
  int get version => 1;

  @override
  Future<AppResult<LegacyEvidence>> run(
    LegacyClipAnalyzerInput input,
    AnalysisStageContext context,
  ) async => Success<LegacyEvidence>(_stubEvidence);
}

AnalysisWorkState _requireSuccess(AppResult<AnalysisWorkState> result) =>
    switch (result) {
      Success<AnalysisWorkState>(:final value) => value,
      Failure<AnalysisWorkState>(:final error) => throw StateError(error.code),
    };

AnalysisStageContext _context({required AnalysisProgressPhase phase}) =>
    AnalysisStageContext(
      runId: 'ingest-stage-test',
      phase: phase,
      cancellationToken: AnalysisCancellationSource(),
      eventSink: (_) {},
    );

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

PreprocessedAudio _preprocessedAudio(List<double> samples) => PreprocessedAudio(
  originalSamples: samples,
  canonicalSamples: samples,
  sampleRate: _sampleRate,
  originalChannelCount: 1,
  normalizationGain: 1,
  preprocessingVersion: 'test',
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
