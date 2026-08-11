import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';

void main() {
  group('PreprocessedAudio timebase', () {
    test(
      'maps the native-rate sample matrix with floor-rounded timestamps',
      () {
        final cases =
            <({int sampleRate, List<({int index, int micros})> cells})>[
              (
                sampleRate: 44100,
                cells: <({int index, int micros})>[
                  (index: 0, micros: 0),
                  (index: 1, micros: 22),
                  (index: 44099, micros: 999977),
                  (index: 44100, micros: 1000000),
                  (index: 44101, micros: 1000022),
                  (index: 44117, micros: 1000385),
                ],
              ),
              (
                sampleRate: 48000,
                cells: <({int index, int micros})>[
                  (index: 0, micros: 0),
                  (index: 1, micros: 20),
                  (index: 47999, micros: 999979),
                  (index: 48000, micros: 1000000),
                  (index: 48001, micros: 1000020),
                  (index: 48017, micros: 1000354),
                ],
              ),
            ];

        for (final testCase in cases) {
          final audio = _audio(
            sampleRate: testCase.sampleRate,
            length: testCase.cells.last.index + 1,
          );

          for (final cell in testCase.cells) {
            final duration = audio.sampleIndexToDuration(cell.index);
            expect(
              duration,
              Duration(microseconds: cell.micros),
              reason: '${testCase.sampleRate} Hz at sample ${cell.index}',
            );
            expect(
              audio.durationToSampleIndex(duration),
              cell.index,
              reason: 'round trip ${testCase.sampleRate} Hz at ${cell.index}',
            );
          }
        }
      },
    );

    test('retains immutable input samples and default canonical identity', () {
      final samples = <double>[0.25, -0.5, 0.75];
      final audio = _audio(samples: samples);
      samples[0] = 99;

      expect(audio.originalSamples, <double>[0.25, -0.5, 0.75]);
      expect(identical(audio.originalSamples, audio.canonicalSamples), isTrue);
      expect(() => audio.originalSamples[0] = 1, throwsUnsupportedError);
      expect(() => audio.canonicalSamples[0] = 1, throwsUnsupportedError);
    });

    test(
      'rejects invalid native sample-rate and normalization gain values',
      () {
        expect(() => _audio(sampleRate: 0), throwsArgumentError);
        expect(
          () => PreprocessedAudio(
            originalSamples: const <double>[0],
            canonicalSamples: const <double>[0],
            sampleRate: 44100,
            originalChannelCount: 1,
            normalizationGain: 0,
            preprocessingVersion: 'v1',
          ),
          throwsArgumentError,
        );
      },
    );
  });
}

PreprocessedAudio _audio({
  int sampleRate = 44100,
  int length = 3,
  List<double>? samples,
}) {
  final source = samples ?? List<double>.filled(length, 0.25);
  return PreprocessedAudio(
    originalSamples: source,
    canonicalSamples: source,
    sampleRate: sampleRate,
    originalChannelCount: 1,
    normalizationGain: 1,
    preprocessingVersion: 'v1',
  );
}
