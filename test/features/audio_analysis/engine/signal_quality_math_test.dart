import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/engine/quality/quality_thresholds.dart';
import 'package:strumsight/features/audio_analysis/engine/quality/signal_quality_math.dart';

void main() {
  const thresholds = QualityThresholds.standard;

  group('SignalQualityMath', () {
    test('uses the documented dBFS floor and full-scale peak convention', () {
      expect(
        SignalQualityMath.peakDbfs(const <double>[0, 0]),
        thresholds.silenceFloorDbfs,
      );
      expect(SignalQualityMath.peakDbfs(const <double>[1]), 0);
      expect(
        SignalQualityMath.rmsDbfs(const <double>[0, 0]),
        thresholds.silenceFloorDbfs,
      );
      expect(SignalQualityMath.rmsDbfs(const <double>[1, -1]), 0);
    });

    test('counts clipped samples at an inclusive threshold', () {
      for (final entry in <({double sample, double expected})>[
        (sample: 0.99889, expected: 0),
        (sample: 0.999, expected: 1),
        (sample: 0.99911, expected: 1),
      ]) {
        expect(
          SignalQualityMath.clippedSampleRatio(<double>[entry.sample]),
          entry.expected,
          reason: 'sample=${entry.sample}',
        );
      }
    });

    test(
      'uses inclusive clipped-ratio and silent-frame warning boundaries',
      () {
        final oneMillion = List<double>.filled(1000000, 0);
        for (final count in <int>[999, 1000, 1001]) {
          for (var index = 0; index < count; index++) {
            oneMillion[index] = 1;
          }
          final ratio = SignalQualityMath.clippedSampleRatio(oneMillion);
          expect(
            ratio >= thresholds.clippedRatioWarning,
            count >= 1000,
            reason: 'clipped count=$count ratio=$ratio',
          );
          for (var index = 0; index < count; index++) {
            oneMillion[index] = 0;
          }
        }

        for (final dbfs in <double>[-60.01, -60.0, -59.99]) {
          final amplitude = math.pow(10, dbfs / 20).toDouble();
          expect(
            SignalQualityMath.isSilentFrame(
              List<double>.filled(2048, amplitude),
            ),
            dbfs <= thresholds.silentSampleDbfs,
            reason: 'frame dbfs=$dbfs',
          );
        }
      },
    );

    test('uses a tenth-percentile frame RMS noise-floor proxy', () {
      final frames = <List<double>>[
        List<double>.filled(2048, 0.0001),
        List<double>.filled(2048, 0.01),
        List<double>.filled(2048, 0.1),
      ];

      expect(
        SignalQualityMath.noiseFloorDbfsForFrames(frames),
        closeTo(-80, 1e-9),
      );
    });

    test('reports tonalness from a Hann-windowed spectral-flatness proxy', () {
      final sine = List<double>.generate(
        2048,
        (index) => math.sin(2 * math.pi * 32 * index / 2048),
      );
      var state = 0x2468;
      final noise = List<double>.generate(2048, (_) {
        state = (state * 1103515245 + 12345) & 0x7fffffff;
        return state / 0x7fffffff * 2 - 1;
      });

      expect(SignalQualityMath.tonalness(sine), greaterThan(0.7));
      expect(
        SignalQualityMath.tonalness(sine),
        greaterThan(SignalQualityMath.tonalness(noise)),
      );
    });
  });
}
