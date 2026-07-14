// Round 179 — the pure-Dart WAV decoder behind "import your own audio". Proves
// an imported .wav becomes the exact (List<double> mono -1..1, int Hz) shape
// ClipAnalyzer.analyze expects, and that junk / unsupported files are rejected
// honestly (null) rather than decoded into noise.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/engine/wav_decoder.dart';

/// Build a minimal WAV (format 1 = PCM16, or 3 = float32) from per-channel
/// interleaved samples in [-1, 1].
Uint8List _wav(List<double> mono,
    {int sampleRate = 16000, int channels = 1, int format = 1}) {
  final bitsPerSample = format == 3 ? 32 : 16;
  final bytesPerSample = bitsPerSample ~/ 8;
  final frames = mono.length;
  final dataLen = frames * channels * bytesPerSample;
  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) {
    final d = ByteData(4)..setUint32(0, v, Endian.little);
    b.add(d.buffer.asUint8List());
  }

  void u16(int v) {
    final d = ByteData(2)..setUint16(0, v, Endian.little);
    b.add(d.buffer.asUint8List());
  }

  str('RIFF');
  u32(36 + dataLen);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(format);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * channels * bytesPerSample); // byte rate
  u16(channels * bytesPerSample); // block align
  u16(bitsPerSample);
  str('data');
  u32(dataLen);
  for (final s in mono) {
    for (var c = 0; c < channels; c++) {
      if (format == 3) {
        final d = ByteData(4)..setFloat32(0, s, Endian.little);
        b.add(d.buffer.asUint8List());
      } else {
        final v = (s * 32767).round().clamp(-32768, 32767);
        final d = ByteData(2)..setInt16(0, v, Endian.little);
        b.add(d.buffer.asUint8List());
      }
    }
  }
  return b.toBytes();
}

void main() {
  test('decodes 16-bit mono PCM to [-1,1] doubles at the right rate', () {
    final samples = [0.0, 0.5, -0.5, 1.0, -1.0, 0.25];
    final (pcm, sr) = WavDecoder.decode(_wav(samples, sampleRate: 22050))!;
    expect(sr, 22050);
    expect(pcm.length, samples.length);
    for (var i = 0; i < samples.length; i++) {
      expect(pcm[i], closeTo(samples[i], 1 / 32768 + 1e-9));
    }
  });

  test('averages genuine interleaved stereo down to mono', () {
    // Build a real 2-channel PCM16 WAV with DISTINCT L/R per frame:
    //   frame 0: L=+0.5 R=-0.5 -> 0 ;  frame 1: L=0.4 R=0.4 -> 0.4.
    final lr = [0.5, -0.5, 0.4, 0.4]; // interleaved L,R,L,R
    final b = BytesBuilder();
    void str(String s) => b.add(s.codeUnits);
    void u32(int v) =>
        b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
    void u16(int v) =>
        b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
    final dataLen = lr.length * 2;
    str('RIFF');
    u32(36 + dataLen);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(2); // channels
    u32(16000);
    u32(16000 * 2 * 2);
    u16(4);
    u16(16);
    str('data');
    u32(dataLen);
    for (final s in lr) {
      u16(((s * 32767).round().clamp(-32768, 32767)) & 0xFFFF);
    }
    final (pcm, _) = WavDecoder.decode(b.toBytes())!;
    expect(pcm.length, 2);
    expect(pcm[0], closeTo(0.0, 1e-3));
    expect(pcm[1], closeTo(0.4, 1e-3));
  });

  test('decodes 32-bit IEEE float WAV', () {
    final samples = [0.0, 0.75, -0.75, 0.123];
    final (pcm, sr) = WavDecoder.decode(_wav(samples, format: 3))!;
    expect(sr, 16000);
    for (var i = 0; i < samples.length; i++) {
      expect(pcm[i], closeTo(samples[i], 1e-6));
    }
  });

  test('rejects non-WAV / unsupported bytes with null (no garbage decode)', () {
    expect(WavDecoder.decode(Uint8List(10)), isNull); // too short
    expect(WavDecoder.decode(Uint8List.fromList('NOTAWAVFILE!!'.codeUnits)),
        isNull);
    // A valid RIFF header but 8-bit depth (unsupported) → null.
    final eight = _wav([0.1, 0.2]);
    eight[34] = 8; // bitsPerSample = 8
    expect(WavDecoder.decode(eight), isNull);
  });

  test('an MP3-like blob (not RIFF) is rejected', () {
    final mp3 = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x00, ...List.filled(60, 0)]);
    expect(WavDecoder.decode(mp3), isNull);
  });
}
