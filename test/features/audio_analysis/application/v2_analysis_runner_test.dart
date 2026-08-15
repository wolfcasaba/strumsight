// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_isolate_runner.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_providers.dart';
import 'package:strumsight/features/audio_analysis/application/v2_analysis_runner.dart';
import 'package:strumsight/features/audio_analysis/data/analysis_document_codec.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_hotspot.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input_summary.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_insight.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_provenance.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_timeline.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/signal_quality_report.dart';
import 'package:strumsight/features/audio_analysis/domain/target/analysis_target.dart';
import 'package:strumsight/features/audio_analysis/domain/target/expected_event.dart';
import 'package:strumsight/features/audio_analysis/engine/stages/analysis_stage_phases.dart';

import '../../../support/synth.dart';

const _sampleRate = 44100;

void main() {
  group('V2AnalysisRunner (ADR 0254)', () {
    test('A1 — analysisV2RunnerProvider resolves a real runner', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final runner = container.read(analysisV2RunnerProvider);

      expect(runner, isA<V2AnalysisRunner>());
    });

    test(
      'F1 — the 20-stage chain runs off the calling isolate, not blocking it '
      '(ADR 0254 §5.4)',
      () async {
        final runner = V2AnalysisRunner();
        final events = <String>[];
        final handle = runner.start(_request(samples: _fullClip()));
        Timer(Duration.zero, () => events.add('timer'));
        await handle.result;
        events.add('result');

        // A same-isolate pipeline schedules its whole 20-stage run as a
        // microtask chain, which the Dart event loop always drains before
        // it services a pending timer — so a same-isolate run would
        // observe 'result' before 'timer'. Spawning a real isolate and
        // round-tripping the message ports takes real wall time, so the
        // zero-duration timer on THIS isolate always fires first while
        // that isolate does the DSP work.
        expect(events, <String>['timer', 'result']);
      },
    );

    test('A2/A3 — PCM in produces an AnalysisDocument out through the full '
        '20-stage chain composed from buildFullAnalysisStages()', () async {
      final runner = V2AnalysisRunner();
      final handle = runner.start(_request(samples: _fullClip()));

      final phases = <AnalysisProgressPhase>[];
      final subscription = handle.progress.listen((event) {
        if (event is AnalysisPhaseProgressEvent) phases.add(event.phase);
      });
      final result = await handle.result;
      await subscription.cancel();

      expect(result.completion, AnalysisCompletionStatus.complete);
      expect(result.document, isNotNull);
      expect(phases, <AnalysisProgressPhase>[
        for (final stage in buildFullAnalysisStages())
          analysisStagePhases[stage.id]!,
      ]);
    });

    test(
      'A4 — the encoded document never contains the analysed samples',
      () async {
        const marker = 0.918273645;
        final samples = <double>[marker, marker, marker, ..._fullClip()];
        final runner = V2AnalysisRunner();
        final result = await runner.start(_request(samples: samples)).result;
        final document = result.document!;

        final encoded = const AnalysisDocumentCodec().encode(document);

        expect(encoded.contains(marker.toString()), isFalse);
      },
    );

    test('A6 — cancel yields no partial document', () async {
      final runner = V2AnalysisRunner();
      final handle = runner.start(_request(samples: _fullClip()));

      await handle.cancel();
      final result = await handle.result;

      expect(result.completion, AnalysisCompletionStatus.cancelled);
      expect(result.document, isNull);
    });

    for (final cell
        in <({String label, AnalysisTarget? target, bool timingPresent})>[
          (label: 'referencia nélkül', target: null, timingPresent: false),
          (
            label: 'a határon — üres expectedEvents nem referencia',
            target: AnalysisTarget(
              id: 'empty-target',
              kind: AnalysisTargetKind.practice,
              timebase: AnalysisTargetTimebase.session,
            ),
            timingPresent: false,
          ),
          (
            label: 'referenciával',
            target: AnalysisTarget(
              id: 'real-target',
              kind: AnalysisTargetKind.practice,
              timebase: AnalysisTargetTimebase.session,
              expectedEvents: <ExpectedEvent>[
                ExpectedEvent(
                  id: 'expected-1',
                  time: Duration.zero,
                  type: ExpectedEventType.onset,
                ),
              ],
            ),
            timingPresent: true,
          ),
        ]) {
      test('A5 — ${cell.label}: document born, timing metrics presence '
          'matches the reference boundary', () async {
        final runner = V2AnalysisRunner();
        final result = await runner
            .start(
              _request(
                samples: _fullClip(),
                mode: AnalysisMode.practiceTarget,
                target: cell.target,
              ),
            )
            .result;

        expect(result.completion, AnalysisCompletionStatus.complete);
        final document = result.document;
        expect(document, isNotNull);
        final hasTimingMetrics = document!.metrics.any(
          (metric) =>
              metric.id == AnalysisMetricId.timingTargetMeanAbsoluteError,
        );
        expect(hasTimingMetrics, cell.timingPresent);
      });
    }
  });
}

AnalysisRunRequest _request({
  required List<double> samples,
  AnalysisMode mode = AnalysisMode.freePlay,
  AnalysisTarget? target,
}) => AnalysisRunRequest(
  seed: _seedDocument(mode: mode),
  audio: ValidatedPcmAnalysisInput(
    input: PcmAnalysisInput(
      samples: samples,
      sampleRate: _sampleRate,
      channelCount: 1,
      source: AnalysisInputSource.practiceSession,
    ),
  ),
  target: target,
);

/// Only the run's identity/mode/provenance mag; never the audio carrier
/// (ADR 0254 §1) — the pipeline reads its actual PCM from the request's
/// [AnalysisRunRequest.audio], not from anything here.
AnalysisDocument _seedDocument({required AnalysisMode mode}) =>
    AnalysisDocument(
      id: 'seed-document',
      schemaVersion: analysisDocumentSchemaVersion,
      createdAt: DateTime.utc(2026, 8, 15),
      mode: mode,
      input: AnalysisInputSummary(
        source: AnalysisInputSource.practiceSession,
        duration: Duration.zero,
        sampleRate: _sampleRate,
        channelCount: 1,
        fingerprint: 'seed',
      ),
      provenance: AnalysisProvenance(
        appVersion: 'test',
        analyzerVersion: 'test',
        pipelineVersion: 'test',
        stageVersions: const <String, String>{},
        dspConfigHash: 'test',
        modelManifestIds: const <String>[],
        inputFingerprint: 'seed',
        platform: 'test',
        featureFlagSnapshot: const <String, bool>{},
      ),
      signalQuality: SignalQualityReport(
        overall: 0,
        peakDbfs: 0,
        rmsDbfs: 0,
        noiseFloorDbfs: 0,
        clippedSampleRatio: 0,
        silentRatio: 0,
        tonalness: 0,
      ),
      capabilities: const <CapabilityReport>[],
      timeline: AnalysisTimeline(duration: Duration.zero),
      metrics: const <AnalysisMetricResult>[],
      hotspots: const <AnalysisHotspot>[],
      insights: const <AnalysisInsight>[],
      warnings: const <AnalysisWarning>[],
      completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
    );

/// A single clip combining a clean monophonic passage with a
/// polyphonic chord-plus-strum passage, mirroring
/// `full_pipeline_composition_test.dart`'s fixture so the full chain
/// reaches a `complete` (never `degraded`) status.
List<double> _fullClip() => <double>[
  ..._sine(220, seconds: 0.4),
  ...chordSignal(cMajorFreqs, seconds: 0.8),
  ...chordSignal(gMajorFreqs, seconds: 0.8),
  ...strumPattern(
    lowFirstPerStrum: <bool>[true, false, true, false],
    gapSeconds: 0.5,
  ),
];

List<double> _sine(double frequency, {required double seconds}) =>
    List<double>.generate(
      (seconds * _sampleRate).round(),
      (index) => 0.4 * math.sin(2 * math.pi * frequency * index / _sampleRate),
    );
