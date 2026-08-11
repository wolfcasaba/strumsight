import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/analyze/engine/clip_analyzer.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_cancellation.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/preprocessing/mono_downmix.dart';
import 'package:strumsight/features/audio_analysis/engine/preprocessing/preprocessing_config.dart';
import 'package:strumsight/features/audio_analysis/engine/preprocessing/preprocessing_stage.dart';
import '../../../support/synth.dart';

void main() {
  group('PreprocessingStage', () {
    test(
      'keeps the default path as a zero-copy, immutable native-rate pass',
      () async {
        final samples = <double>[0.25, -0.5, 0.75];
        final originalSnapshot = List<double>.from(samples);

        final output = await _run(const PreprocessingStage(), samples: samples);

        expect(
          identical(output.originalSamples, output.canonicalSamples),
          isTrue,
        );
        expect(output.originalSamples, originalSnapshot);
        expect(samples, originalSnapshot);
        expect(output.sampleRate, 44100);
        expect(output.originalChannelCount, 1);
        expect(output.normalizationGain, 1);
        expect(output.preprocessingVersion, PreprocessingConfig.v1Version);
      },
    );

    test(
      'keeps original dynamics when experimental DC removal and normalization run',
      () async {
        const firstAmplitude = 0.25;
        const secondAmplitude = 0.5;
        final output = await _run(
          const PreprocessingStage(
            experimentalEnabled: true,
            config: PreprocessingConfig.v1(
              removeDcOffset: true,
              normalizePeak: true,
            ),
          ),
          samples: <double>[
            0.1 + firstAmplitude,
            0.1 - firstAmplitude,
            0.1 + secondAmplitude,
            0.1 - secondAmplitude,
          ],
        );

        expect(
          identical(output.originalSamples, output.canonicalSamples),
          isFalse,
        );
        expect(output.originalSamples, <double>[0.35, -0.15, 0.6, -0.4]);
        final originalRatio =
            (output.originalSamples[2] - 0.1).abs() /
            (output.originalSamples[0] - 0.1).abs();
        expect(originalRatio, closeTo(secondAmplitude / firstAmplitude, 0.001));
        expect(output.normalizationGain, greaterThan(1));
      },
    );

    test(
      'keeps the legacy V1 analyzer output unchanged for default canonical PCM',
      () async {
        final samples = chordSignal(cMajorFreqs, seconds: 1.0).toList();
        final output = await _run(const PreprocessingStage(), samples: samples);
        const analyzer = ClipAnalyzer();

        final baseline = analyzer.analyze(samples, 44100);
        final canonical = analyzer.analyze(output.canonicalSamples, 44100);

        expect(canonical.durationSec, baseline.durationSec);
        expect(canonical.bpm, baseline.bpm);
        expect(
          canonical.chords.map((chord) => chord.label),
          orderedEquals(baseline.chords.map((chord) => chord.label)),
        );
        expect(
          canonical.chords.map((chord) => chord.startSec),
          orderedEquals(baseline.chords.map((chord) => chord.startSec)),
        );
        expect(
          canonical.chords.map((chord) => chord.endSec),
          orderedEquals(baseline.chords.map((chord) => chord.endSec)),
        );
        expect(
          canonical.strums.map((strum) => strum.timeSec),
          orderedEquals(baseline.strums.map((strum) => strum.timeSec)),
        );
      },
    );
  });

  group('preprocessing policy boundaries', () {
    test(
      'measures DC-removal canonical PCM onset evidence at the parity boundary',
      () async {
        const config = PreprocessingConfig.v1(removeDcOffset: true);

        for (final testCase in _dcOffsetOnsetParityCases) {
          final samples = _dcOffsetRampFixture(
            delayedOnsetSamples: testCase.delayedOnsetSamples,
          );
          final withoutDcRemoval = await _run(
            const PreprocessingStage(experimentalEnabled: true),
            samples: samples,
            sampleRate: _dcOffsetFixtureSampleRate,
          );
          final withDcRemoval = await _run(
            const PreprocessingStage(
              experimentalEnabled: true,
              config: PreprocessingConfig.v1(removeDcOffset: true),
            ),
            samples: samples,
            sampleRate: _dcOffsetFixtureSampleRate,
          );

          final rawOnset = _risingEdgeOnsetSample(
            withoutDcRemoval.canonicalSamples,
          );
          final canonicalOnset = _risingEdgeOnsetSample(
            withDcRemoval.canonicalSamples,
          );
          final difference =
              withDcRemoval.sampleIndexToDuration(canonicalOnset) -
              withoutDcRemoval.sampleIndexToDuration(rawOnset);

          expect(
            difference,
            testCase.expectedDifference,
            reason: '${testCase.label} must be derived from canonical PCM',
          );
          expect(
            config.isOnsetParityWithinTolerance(difference),
            testCase.isWithinTolerance,
            reason: '${testCase.label} parity outcome',
          );
        }
      },
    );

    test('uses the inclusive five-millisecond onset parity threshold', () {
      const config = PreprocessingConfig.v1(removeDcOffset: true);

      expect(
        config.isOnsetParityWithinTolerance(const Duration(microseconds: 4900)),
        isTrue,
      );
      expect(
        config.isOnsetParityWithinTolerance(const Duration(microseconds: 5000)),
        isTrue,
      );
      expect(
        config.isOnsetParityWithinTolerance(const Duration(microseconds: 5100)),
        isFalse,
      );
    });

    test('defines the v1 channel-average downmix evidence matrix', () {
      const policy = MonoDownmix.v1();

      final mono = policy.downmix(const <double>[0.25, -0.5], channelCount: 1);
      expect(mono.samples, <double>[0.25, -0.5]);
      expect(mono.warnings, isEmpty);

      final identicalStereo = policy.downmix(const <double>[
        0.25,
        0.25,
        -0.5,
        -0.5,
      ], channelCount: 2);
      expect(identicalStereo.samples, <double>[0.25, -0.5]);

      final phaseCancelled = policy.downmix(const <double>[
        0.8,
        -0.8,
        -0.4,
        0.4,
      ], channelCount: 2);
      expect(phaseCancelled.samples, everyElement(closeTo(0, 0.0000001)));
      expect(
        phaseCancelled.warnings,
        contains(PreprocessingWarning.phaseCancellation),
      );

      final clipped = policy.downmix(const <double>[1.2, 1.2], channelCount: 2);
      expect(clipped.samples, <double>[1.2]);
      expect(clipped.warnings, contains(PreprocessingWarning.downmixClipping));
    });

    test(
      'leaves the preprocessing experiment disabled in every environment',
      () {
        for (final environment in AppEnvironment.values) {
          final flags = FeatureFlags.forEnvironment(
            environment,
            accountEnabled: false,
          );
          expect(flags.analysisPreprocessingExperimentalEnabled, isFalse);
        }
      },
    );
  });
}

Future<PreprocessedAudio> _run(
  PreprocessingStage stage, {
  required List<double> samples,
  int sampleRate = 44100,
}) async {
  final result = await stage.run(
    ValidatedPcmAnalysisInput(
      input: PcmAnalysisInput(
        samples: samples,
        sampleRate: sampleRate,
        channelCount: 1,
        source: AnalysisInputSource.microphone,
      ),
    ),
    AnalysisStageContext(
      runId: 'preprocessing-test',
      phase: AnalysisProgressPhase.preprocessing,
      cancellationToken: AnalysisCancellationSource(),
      eventSink: (_) {},
    ),
  );
  return switch (result) {
    Success<PreprocessedAudio>(:final value) => value,
    Failure<PreprocessedAudio>(:final error) => throw StateError(error.code),
  };
}

const _dcOffsetFixtureSampleRate = 10000;
const _dcOffsetFixtureCenterSample = 200;
const _dcOffsetFixtureStep = 1 / 1024;

const _dcOffsetOnsetParityCases = <_DcOffsetOnsetParityCase>[
  _DcOffsetOnsetParityCase(
    label: '4.9 ms',
    delayedOnsetSamples: 49,
    expectedDifference: Duration(microseconds: 4900),
    isWithinTolerance: true,
  ),
  _DcOffsetOnsetParityCase(
    label: '5.0 ms',
    delayedOnsetSamples: 50,
    expectedDifference: Duration(microseconds: 5000),
    isWithinTolerance: true,
  ),
  _DcOffsetOnsetParityCase(
    label: '5.1 ms',
    delayedOnsetSamples: 51,
    expectedDifference: Duration(microseconds: 5100),
    isWithinTolerance: false,
  ),
];

/// Produces a deterministic DC-offset ramp whose mean-centred rising edge is
/// delayed by [delayedOnsetSamples]. At 10 kHz the selected 49/50/51 sample
/// deltas are exactly the documented 4.9/5.0/5.1 ms boundary cells.
List<double> _dcOffsetRampFixture({required int delayedOnsetSamples}) {
  final offset = delayedOnsetSamples * _dcOffsetFixtureStep;
  return <double>[
    for (var index = 0; index <= 2 * _dcOffsetFixtureCenterSample; index++)
      (index - _dcOffsetFixtureCenterSample) * _dcOffsetFixtureStep + offset,
  ];
}

/// Returns the rising-edge onset evidence directly derived from canonical PCM.
int _risingEdgeOnsetSample(List<double> samples) {
  for (var index = 0; index < samples.length; index++) {
    if (samples[index] >= 0) return index;
  }
  throw StateError('Synthetic onset fixture has no rising edge.');
}

final class _DcOffsetOnsetParityCase {
  const _DcOffsetOnsetParityCase({
    required this.label,
    required this.delayedOnsetSamples,
    required this.expectedDifference,
    required this.isWithinTolerance,
  });

  final String label;
  final int delayedOnsetSamples;
  final Duration expectedDifference;
  final bool isWithinTolerance;
}
