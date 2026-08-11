import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

const _floor = QualityThresholds.silenceFloorDbfs;
const _ceiling = QualityThresholds.maxDbfs;

void main() {
  group('SignalQualityMath.linearToDbfs', () {
    test('full-scale amplitude is 0 dBFS', () {
      expect(
        SignalQualityMath.linearToDbfs(
          1.0,
          floorDbfs: _floor,
          ceilingDbfs: _ceiling,
        ),
        closeTo(0.0, 1e-9),
      );
    });

    test('zero amplitude clamps to the documented silence floor', () {
      expect(
        SignalQualityMath.linearToDbfs(
          0.0,
          floorDbfs: _floor,
          ceilingDbfs: _ceiling,
        ),
        _floor,
      );
      expect(
        SignalQualityMath.linearToDbfs(
          0.0,
          floorDbfs: _floor,
          ceilingDbfs: _ceiling,
        ).isFinite,
        isTrue,
      );
    });

    test('amplitude above full scale clamps to the ceiling, never above', () {
      expect(
        SignalQualityMath.linearToDbfs(
          100.0,
          floorDbfs: _floor,
          ceilingDbfs: _ceiling,
        ),
        _ceiling,
      );
    });

    test('a known amplitude matches the textbook formula', () {
      final amplitude = math.pow(10, -60.0 / 20).toDouble();
      expect(
        SignalQualityMath.linearToDbfs(
          amplitude,
          floorDbfs: _floor,
          ceilingDbfs: _ceiling,
        ),
        closeTo(-60.0, 1e-6),
      );
    });
  });

  group('SignalQualityMath.clippedSampleRatio — inclusive threshold', () {
    // python3 -c "print(0.99889, 0.999, 0.99911)"
    const belowThreshold = 0.99889;
    const onThreshold = 0.999;
    const aboveThreshold = 0.99911;

    test('a sample strictly below the threshold is not clipped', () {
      final ratio = SignalQualityMath.clippedSampleRatio(<double>[
        belowThreshold,
      ], threshold: QualityThresholds.clippedSampleThreshold);
      expect(ratio, 0.0);
    });

    test('a sample exactly on the threshold counts as clipped (inclusive)', () {
      final ratio = SignalQualityMath.clippedSampleRatio(<double>[
        onThreshold,
      ], threshold: QualityThresholds.clippedSampleThreshold);
      expect(ratio, 1.0);
    });

    test('a sample above the threshold counts as clipped', () {
      final ratio = SignalQualityMath.clippedSampleRatio(<double>[
        aboveThreshold,
      ], threshold: QualityThresholds.clippedSampleThreshold);
      expect(ratio, 1.0);
    });

    test('negative amplitudes are compared by absolute value', () {
      final ratio = SignalQualityMath.clippedSampleRatio(<double>[
        -onThreshold,
      ], threshold: QualityThresholds.clippedSampleThreshold);
      expect(ratio, 1.0);
    });

    // python3 -c "print(999/1000000, 1000/1000000, 1001/1000000)"
    for (final ratioCase
        in <({String name, int clipped, bool expectWarningRatio})>[
          (name: 'below', clipped: 999, expectWarningRatio: false),
          (name: 'on', clipped: 1000, expectWarningRatio: true),
          (name: 'above', clipped: 1001, expectWarningRatio: true),
        ]) {
      test(
        'ratio ${ratioCase.name} the warning threshold (${ratioCase.clipped}/1e6)',
        () {
          final samples = List<double>.generate(
            1000000,
            (i) => i < ratioCase.clipped ? onThreshold : 0.0,
          );
          final ratio = SignalQualityMath.clippedSampleRatio(
            samples,
            threshold: QualityThresholds.clippedSampleThreshold,
          );
          expect(
            ratio >= QualityThresholds.clippedRatioWarning,
            ratioCase.expectWarningRatio,
            reason: 'ratio=$ratio',
          );
        },
      );
    }
  });

  group('SignalQualityMath.silentFrameRatio — inclusive threshold', () {
    // python3 -c "for db in (-60.01, -60.0, -59.99): print(10**(db/20))"
    const belowThresholdAmplitude = 0.0009988493699365057; // -60.01 dBFS
    const onThresholdAmplitude = 0.001; // -60.0 dBFS
    const aboveThresholdAmplitude = 0.0010011519555381682; // -59.99 dBFS

    double frameDbfs(double amplitude) => SignalQualityMath.rmsDbfs(
      List<double>.filled(2048, amplitude),
      floorDbfs: _floor,
      ceilingDbfs: _ceiling,
    );

    test('a quieter-than-threshold frame counts as silent (inclusive)', () {
      final ratio = SignalQualityMath.silentFrameRatio(<double>[
        frameDbfs(belowThresholdAmplitude),
      ], silentThresholdDbfs: QualityThresholds.silentFrameDbfs);
      expect(ratio, 1.0);
    });

    test('a frame exactly on the threshold counts as silent (inclusive)', () {
      final ratio = SignalQualityMath.silentFrameRatio(<double>[
        frameDbfs(onThresholdAmplitude),
      ], silentThresholdDbfs: QualityThresholds.silentFrameDbfs);
      expect(ratio, 1.0);
    });

    test('a louder-than-threshold frame does not count as silent', () {
      final ratio = SignalQualityMath.silentFrameRatio(<double>[
        frameDbfs(aboveThresholdAmplitude),
      ], silentThresholdDbfs: QualityThresholds.silentFrameDbfs);
      expect(ratio, 0.0);
    });
  });

  group('SignalQualityMath.percentile', () {
    test(
      '10th percentile of a known distribution matches linear interpolation',
      () {
        final values = <double>[for (var i = 1; i <= 10; i++) i.toDouble()];
        // rank = 0.10 * 9 = 0.9 -> between index 0 (1.0) and index 1 (2.0)
        expect(SignalQualityMath.percentile(values, 0.10), closeTo(1.9, 1e-9));
      },
    );

    test('percentile of a single value is that value', () {
      expect(SignalQualityMath.percentile(<double>[-42.0], 0.5), -42.0);
    });

    test(
      'percentile 0 and 1 return the extremes regardless of input order',
      () {
        final values = <double>[5.0, 1.0, 3.0, 2.0, 4.0];
        expect(SignalQualityMath.percentile(values, 0.0), 1.0);
        expect(SignalQualityMath.percentile(values, 1.0), 5.0);
      },
    );

    test(
      'a bimodal distribution — percentile tracks the quiet floor, not the mean',
      () {
        // 90 quiet frames at -100 dBFS, 10 loud frames at -10 dBFS.
        final values = <double>[
          ...List<double>.filled(90, -100.0),
          ...List<double>.filled(10, -10.0),
        ];
        final mean = values.reduce((a, b) => a + b) / values.length;
        final p10 = SignalQualityMath.percentile(values, 0.10);
        expect(p10, closeTo(-100.0, 1e-9));
        expect(p10, isNot(closeTo(mean, 5.0)));
      },
    );
  });

  group('SignalQualityMath.weightedTonalness', () {
    test('all-silent frames (zero weight) produce 0.0, never NaN', () {
      final result = SignalQualityMath.weightedTonalness(
        <double>[1.0, 1.0, 1.0],
        <double>[0.0, 0.0, 0.0],
      );
      expect(result, 0.0);
    });

    test('empty input produces 0.0', () {
      expect(SignalQualityMath.weightedTonalness(<double>[], <double>[]), 0.0);
    });

    test('a single tonal frame with flatness 0 yields tonalness 1', () {
      final result = SignalQualityMath.weightedTonalness(
        <double>[0.0],
        <double>[1.0],
      );
      expect(result, 1.0);
    });

    test('a loud tonal frame outweighs many silent frames', () {
      final result = SignalQualityMath.weightedTonalness(
        <double>[0.0, ...List<double>.filled(50, 1.0)],
        <double>[1.0, ...List<double>.filled(50, 1e-9)],
      );
      expect(result, greaterThan(0.99));
    });

    test('throws on mismatched array lengths', () {
      expect(
        () => SignalQualityMath.weightedTonalness(<double>[1.0], <double>[]),
        throwsArgumentError,
      );
    });
  });

  group('SignalQualityMath.frameMetrics — spectral flatness proxy', () {
    test(
      'a pure tone is more tonal (lower flatness) than a noise-like frame',
      () {
        const frameSize = QualityThresholds.frameSize;
        final tone = List<double>.generate(
          frameSize,
          (i) => math.sin(2 * math.pi * 440 * i / 44100),
        );
        // Deterministic pseudo-noise: no dart:math Random, a fixed LCG so the
        // test stays reproducible without relying on a seeded generator API.
        var state = 12345;
        final noise = List<double>.generate(frameSize, (_) {
          state = (state * 1103515245 + 12345) & 0x7fffffff;
          return (state / 0x7fffffff) * 2 - 1;
        });

        final toneFrames = SignalQualityMath.frameMetrics(
          tone,
          frameSize: frameSize,
          hopSize: frameSize,
          floorDbfs: _floor,
          ceilingDbfs: _ceiling,
        );
        final noiseFrames = SignalQualityMath.frameMetrics(
          noise,
          frameSize: frameSize,
          hopSize: frameSize,
          floorDbfs: _floor,
          ceilingDbfs: _ceiling,
        );

        expect(
          toneFrames.single.spectralFlatness,
          lessThan(noiseFrames.single.spectralFlatness),
        );
        expect(toneFrames.single.spectralFlatness.isFinite, isTrue);
        expect(noiseFrames.single.spectralFlatness.isFinite, isTrue);
      },
    );

    test('a fully silent frame has finite, bounded flatness', () {
      const frameSize = QualityThresholds.frameSize;
      final silence = List<double>.filled(frameSize, 0.0);
      final frames = SignalQualityMath.frameMetrics(
        silence,
        frameSize: frameSize,
        hopSize: frameSize,
        floorDbfs: _floor,
        ceilingDbfs: _ceiling,
      );
      expect(frames.single.spectralFlatness.isFinite, isTrue);
      expect(frames.single.spectralFlatness, inInclusiveRange(0.0, 1.0));
    });

    test(
      'the last partial frame is measured, not dropped or zero-padded away',
      () {
        const frameSize = QualityThresholds.frameSize;
        final samples = List<double>.filled(frameSize + 10, 0.5);
        final frames = SignalQualityMath.frameMetrics(
          samples,
          frameSize: frameSize,
          hopSize: frameSize,
          floorDbfs: _floor,
          ceilingDbfs: _ceiling,
        );
        expect(frames, hasLength(2));
        expect(frames[1].rmsDbfs.isFinite, isTrue);
      },
    );
  });
}
