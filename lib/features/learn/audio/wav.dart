import 'dart:typed_data';

/// Wrap 16-bit mono PCM [samples] in a minimal RIFF/WAVE container so it can be
/// played by `audioplayers` `BytesSource`. Pure & deterministic — the synth
/// helpers (metronome click, chord pad) build the PCM and call this.
Uint8List pcmToWav(Int16List samples, int sampleRate) {
  final n = samples.length;
  const headerLen = 44;
  final dataLen = n * 2;
  final out = ByteData(headerLen + dataLen);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + dataLen, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, 1, Endian.little); // mono
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < n; i++) {
    out.setInt16(headerLen + i * 2, samples[i], Endian.little);
  }
  return out.buffer.asUint8List();
}
