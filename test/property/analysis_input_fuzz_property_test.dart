import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_decoder.dart' show DecodedAudio;
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/input/wav_decoder_adapter.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';

void main() {
  test(
    'seeded random WAV-like byte arrays never escape the decoder boundary',
    () {
      final seed =
          int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
      // Always visible in logs so any failure is reproducible.
      // ignore: avoid_print
      print('PROPERTY_SEED=$seed');
      final random = Random(seed);
      const decoder = WavDecoderAdapter();

      for (var index = 0; index < 500; index++) {
        final length = random.nextInt(64 * 1024 + 1);
        final bytes = Uint8List.fromList(
          List<int>.generate(length, (_) => random.nextInt(256)),
        );
        if (index.isEven && length >= 12) {
          bytes.setRange(0, 4, 'RIFF'.codeUnits);
          bytes.setRange(8, 12, 'WAVE'.codeUnits);
        }

        final result = decoder.decode(
          FileAnalysisInput(
            bytes: bytes,
            source: AnalysisInputSource.importedFile,
          ),
        );

        expect(
          result,
          isA<AppResult<DecodedAudio>>(),
          reason: 'seed=$seed case=$index',
        );
        if (result case Success<DecodedAudio>(:final value)) {
          expect(value.$1.every((sample) => sample.isFinite), isTrue);
        }
      }
    },
  );
}
