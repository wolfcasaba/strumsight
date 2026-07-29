// ignore_for_file: deprecated_export_use

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/codec/wav_codec.dart';
import 'package:strumsight/features/analyze/engine/wav_decoder.dart'
    as legacy_decoder;
import 'package:strumsight/features/learn/audio/wav.dart' as legacy_encoder;

void main() {
  group('pcmToWav', () {
    test('preserves the exact minimal mono PCM16 RIFF layout', () {
      final wav = pcmToWav(Int16List.fromList([0, 32767, -32768, -1]), 8000);

      expect(
        wav,
        Uint8List.fromList([
          0x52, 0x49, 0x46, 0x46, // RIFF
          0x2c, 0x00, 0x00, 0x00, // RIFF payload size
          0x57, 0x41, 0x56, 0x45, // WAVE
          0x66, 0x6d, 0x74, 0x20, // fmt
          0x10, 0x00, 0x00, 0x00, // fmt chunk size
          0x01, 0x00, // PCM
          0x01, 0x00, // mono
          0x40, 0x1f, 0x00, 0x00, // 8000 Hz
          0x80, 0x3e, 0x00, 0x00, // 16000 bytes/sec
          0x02, 0x00, // block alignment
          0x10, 0x00, // 16 bits/sample
          0x64, 0x61, 0x74, 0x61, // data
          0x08, 0x00, 0x00, 0x00, // data length
          0x00, 0x00, // 0
          0xff, 0x7f, // 32767
          0x00, 0x80, // -32768
          0xff, 0xff, // -1
        ]),
      );
    });
  });

  test('PCM16 encode/decode round-trip preserves samples and sample rate', () {
    const sampleRate = 22050;
    final samples = Int16List.fromList([
      -32768,
      -16384,
      -1,
      0,
      1,
      16384,
      32767,
    ]);

    final decoded = WavDecoder.decode(pcmToWav(samples, sampleRate));

    expect(decoded, isNotNull);
    final (pcm, decodedSampleRate) = decoded!;
    expect(decodedSampleRate, sampleRate);
    expect(pcm, hasLength(samples.length));
    for (var i = 0; i < samples.length; i++) {
      expect(pcm[i], closeTo(samples[i] / 32768.0, 1 / 32768));
    }
  });

  test('legacy feature imports re-export the shared codec contracts', () {
    final wav = legacy_encoder.pcmToWav(Int16List.fromList([0, 1, -1]), 8000);

    final decoded = legacy_decoder.WavDecoder.decode(wav);

    expect(decoded, isNotNull);
    expect(decoded!.$2, 8000);
  });
}
