import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/harmony/chord_frame_evidence.dart';
import 'package:strumsight/features/audio_analysis/engine/harmony/chord_label_normalizer.dart';
import 'package:strumsight/features/audio_analysis/engine/harmony/chord_segment_assembler.dart';
import 'package:strumsight/features/audio_analysis/engine/harmony/decoder_source.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final random = Random(seed);
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test(
    'property: assembled chord spans are monotonic, non-overlapping, and bounded',
    () {
      const assembler = ChordSegmentAssembler();
      const labels = <String?>['C', 'G', 'Am', 'F', null];

      for (var trial = 0; trial < 100; trial++) {
        final duration = Duration(microseconds: 1 + random.nextInt(1000000));
        final frames = <ChordFrameEvidence>[];
        var time = 0;
        while (time < duration.inMicroseconds) {
          frames.add(
            ChordFrameEvidence.complete(
              time: Duration(microseconds: time),
              topLabel: labels[random.nextInt(labels.length)],
              topConfidence: 0.2 + random.nextDouble() * 0.8,
              noChordProbability: 0,
              tonalness: 1,
              source: DecoderSource.dsp,
            ),
          );
          time += 1 + random.nextInt(200000);
        }

        final segments = assembler.assemble(
          frames: frames,
          clipDuration: duration,
        );
        var accountedMicroseconds = 0;
        var cursor = Duration.zero;
        for (var index = 0; index < segments.length; index++) {
          final segment = segments[index];
          expect(
            segment.start,
            greaterThanOrEqualTo(Duration.zero),
            reason: 'seed=$seed trial=$trial',
          );
          expect(
            segment.end,
            lessThanOrEqualTo(duration),
            reason: 'seed=$seed trial=$trial',
          );
          expect(
            segment.end,
            greaterThanOrEqualTo(segment.start),
            reason: 'seed=$seed trial=$trial',
          );
          if (index > 0) {
            expect(
              segment.start,
              greaterThanOrEqualTo(segments[index - 1].end),
              reason: 'seed=$seed trial=$trial',
            );
          }
          accountedMicroseconds += (segment.start - cursor).inMicroseconds;
          accountedMicroseconds += (segment.end - segment.start).inMicroseconds;
          cursor = segment.end;
        }
        accountedMicroseconds += (duration - cursor).inMicroseconds;
        expect(
          accountedMicroseconds,
          duration.inMicroseconds,
          reason: 'seed=$seed trial=$trial',
        );
        if (segments.isNotEmpty) {
          expect(
            segments.last.end,
            duration,
            reason: 'seed=$seed trial=$trial',
          );
        }
      }
    },
  );

  test('property: label normalization is idempotent', () {
    const normalizer = ChordLabelNormalizer();
    const labels = <String>['Cmaj', 'CM', 'Cmin', 'Cm', 'C#', 'Db', 'Bbmin7'];

    for (final label in labels) {
      final normalized = normalizer.normalize(label);
      expect(normalizer.normalize(normalized), normalized, reason: label);
    }
  });
}
