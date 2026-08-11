import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final random = math.Random(seed);
  const gateway = AudioDecoderGateway();

  test('property: 500 bounded random inputs never escape as exceptions', () {
    for (var index = 0; index < 500; index++) {
      final length = random.nextInt(64 * 1024);
      final bytes = Uint8List.fromList(
        List<int>.generate(length, (_) => random.nextInt(256)),
      );
      if (index.isEven && bytes.length >= 12) {
        bytes.setRange(0, 4, 'RIFF'.codeUnits);
        bytes.setRange(8, 12, 'WAVE'.codeUnits);
      }

      final result = gateway.decode(FileAnalysisInput(bytes: bytes));
      expect(
        result,
        isA<AppResult<DecodedAudio>>(),
        reason: 'seed=$seed index=$index',
      );
      if (result case Success<DecodedAudio>(:final value)) {
        expect(value.samples.every((sample) => sample.isFinite), isTrue);
      }
    }
  });
}
