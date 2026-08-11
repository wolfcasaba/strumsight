import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/quality/quality_thresholds.dart';
import 'package:strumsight/features/audio_analysis/engine/quality/signal_quality_stage.dart';
import '../../../support/synth.dart';

void main() {
  const thresholds = QualityThresholds.standard;
  final stage = SignalQualityStage();

  test(
    'produces a deterministic complete report for every fixture cell',
    () async {
      final fixtures = <({String name, List<double> samples})>[
        (name: 'silence', samples: List<double>.filled(_sampleRate, 0)),
        (name: 'minus 40 dBFS sine', samples: _sine(amplitude: 0.01)),
        (name: 'full-scale sine', samples: _sine(amplitude: 1)),
        (name: 'impulse clipping', samples: _impulseClip()),
        (name: 'white noise proxy', samples: _noise()),
        (name: 'clean chord', samples: chordSignal(cMajorFreqs).toList()),
        (name: 'short clip', samples: _sine(seconds: 0.2)),
        (name: 'quiet then active', samples: _quietThenActive()),
      ];

      for (final fixture in fixtures) {
        final first = await _run(stage, fixture.samples);
        final second = await _run(stage, fixture.samples);
        _expectCompleteReport(first);
        _expectBitIdentical(first, second);
      }
    },
  );

  test(
    'records each expected recording condition without evaluating playing',
    () async {
      final silence = await _run(stage, List<double>.filled(_sampleRate, 0));
      final clipped = await _run(stage, _sine(amplitude: 1));
      final short = await _run(stage, _sine(seconds: 0.2));

      expect(silence.report.silentRatio, 1);
      expect(
        silence.report.warnings.map((warning) => warning.messageKey),
        contains('quality.recording_silent'),
      );
      expect(
        clipped.report.clippedSampleRatio,
        greaterThan(thresholds.clippedRatioWarning),
      );
      expect(
        clipped.report.warnings.map((warning) => warning.messageKey),
        contains('quality.recording_clipped'),
      );
      expect(
        short.degradedMetrics,
        containsAll(<String>['noiseFloorDbfs', 'tonalness']),
      );

      final playingJudgement = RegExp(
        r'(bad|poor|wrong|sloppy|rossz|gyenge)_?play',
        caseSensitive: false,
      );
      for (final report in <SignalQualityStageResult>[
        silence,
        clipped,
        short,
      ]) {
        for (final warning in report.report.warnings) {
          expect(playingJudgement.hasMatch(warning.messageKey), isFalse);
        }
      }
    },
  );

  test('keeps peak, RMS, and clipping available for a short clip', () async {
    final result = await _run(stage, _sine(amplitude: 0.5, seconds: 0.2));

    expect(result.report.peakDbfs, closeTo(-6.0206, 0.01));
    expect(result.report.rmsDbfs, closeTo(-9.0309, 0.01));
    expect(result.report.clippedSampleRatio, 0);
    expect(result.activeRegionRatio, greaterThan(0));
  });

  test(
    'raises the clipped-recording warning at the inclusive ratio boundary',
    () async {
      for (final count in <int>[999, 1000, 1001]) {
        final samples = List<double>.filled(1000000, 0);
        for (var index = 0; index < count; index++) {
          samples[index] = 1;
        }
        final result = await _run(stage, samples);
        final keys = result.report.warnings.map(
          (warning) => warning.messageKey,
        );
        expect(
          keys.contains('quality.recording_clipped'),
          count >= 1000,
          reason: 'clipped count=$count',
        );
      }
    },
  );
}

const _sampleRate = 44100;
const _thresholds = QualityThresholds.standard;

Future<SignalQualityStageResult> _run(
  SignalQualityStage stage,
  List<double> samples,
) async {
  final result = await stage.run(
    ValidatedPcmAnalysisInput(
      input: PcmAnalysisInput(
        samples: samples,
        sampleRate: _sampleRate,
        channelCount: 1,
        source: AnalysisInputSource.microphone,
      ),
    ),
    AnalysisStageContext(
      runId: 'quality-test',
      phase: AnalysisProgressPhase.computingMetrics,
      cancellationToken: AnalysisCancellationSource(),
      eventSink: (_) {},
    ),
  );
  return switch (result) {
    Success<SignalQualityStageResult>(:final value) => value,
    Failure<SignalQualityStageResult>(:final error) => throw StateError(
      error.code,
    ),
  };
}

void _expectCompleteReport(SignalQualityStageResult result) {
  final report = result.report;
  expect(report.overall, inInclusiveRange(0, 1));
  for (final dbfs in <double>[
    report.peakDbfs,
    report.rmsDbfs,
    report.noiseFloorDbfs,
  ]) {
    expect(dbfs, inInclusiveRange(-120, 6));
  }
  expect(report.clippedSampleRatio, inInclusiveRange(0, 1));
  expect(report.silentRatio, inInclusiveRange(0, 1));
  expect(report.tonalness, inInclusiveRange(0, 1));
  expect(result.activeRegionRatio, inInclusiveRange(0, 1));
  expect(result.thresholdsVersion, _thresholds.version);
}

void _expectBitIdentical(
  SignalQualityStageResult left,
  SignalQualityStageResult right,
) {
  expect(left.report.overall, right.report.overall);
  expect(left.report.peakDbfs, right.report.peakDbfs);
  expect(left.report.rmsDbfs, right.report.rmsDbfs);
  expect(left.report.noiseFloorDbfs, right.report.noiseFloorDbfs);
  expect(left.report.clippedSampleRatio, right.report.clippedSampleRatio);
  expect(left.report.silentRatio, right.report.silentRatio);
  expect(left.report.tonalness, right.report.tonalness);
  expect(left.activeRegionRatio, right.activeRegionRatio);
  expect(left.degradedMetrics, right.degradedMetrics);
  expect(left.thresholdsVersion, right.thresholdsVersion);
}

List<double> _sine({double amplitude = 1, double seconds = 1}) =>
    List<double>.generate(
      (_sampleRate * seconds).round(),
      (index) => amplitude * math.sin(2 * math.pi * 440 * index / _sampleRate),
    );

List<double> _impulseClip() {
  final samples = List<double>.filled(_sampleRate, 0);
  for (var index = 0; index < samples.length; index += 100) {
    samples[index] = 1;
  }
  return samples;
}

List<double> _noise() {
  var state = 0x13579;
  return List<double>.generate(_sampleRate, (_) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return (state / 0x7fffffff) * 2 - 1;
  });
}

List<double> _quietThenActive() => <double>[
  ...List<double>.filled(_sampleRate ~/ 2, 0),
  ..._sine(seconds: 0.5),
];
