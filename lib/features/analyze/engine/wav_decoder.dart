import 'dart:typed_data';

/// Decoded audio: mono PCM in [-1, 1] plus its sample rate (Hz).
typedef DecodedAudio = (List<double> pcm, int sampleRate);

/// A tiny, dependency-free WAV decoder for the "import your own audio" path
/// (round 179). Turns a `.wav` file's bytes into the mono-PCM + sample-rate
/// pair `ClipAnalyzer.analyze` expects — so an imported clip runs through the
/// identical DSP a mic recording does.
///
/// Supports the two encodings phones and exporters actually emit: **16-bit PCM**
/// (format 1) and **32-bit IEEE float** (format 3), mono or stereo (channels
/// are averaged to mono). Anything else (24-bit, 8-bit, compressed, ADPCM)
/// returns null so the caller can show an honest "convert to WAV" message
/// instead of decoding garbage. Compressed formats (MP3/M4A/OGG) are NOT WAV
/// and need a platform decoder — deliberately out of scope here.
abstract final class WavDecoder {
  /// Decode [bytes] or return null if they are not a supported WAV.
  static DecodedAudio? decode(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final bd = ByteData.sublistView(bytes);
    // RIFF / WAVE header.
    if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') return null;

    var off = 12;
    int? format;
    int channels = 1;
    int sampleRate = 0;
    int bitsPerSample = 0;
    List<double>? pcm;

    while (off + 8 <= bytes.length) {
      final id = _tag(bytes, off);
      final size = bd.getUint32(off + 4, Endian.little);
      final body = off + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = bd.getUint16(body, Endian.little);
        channels = bd.getUint16(body + 2, Endian.little);
        sampleRate = bd.getUint32(body + 4, Endian.little);
        bitsPerSample = bd.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        final dataEnd =
            (body + size <= bytes.length) ? body + size : bytes.length;
        pcm = _readSamples(
            bd, body, dataEnd, format ?? 1, channels, bitsPerSample);
      }
      // Chunks are word-aligned: an odd size carries a pad byte.
      off = body + size + (size & 1);
    }

    if (pcm == null || sampleRate <= 0 || pcm.isEmpty) return null;
    return (pcm, sampleRate);
  }

  static List<double>? _readSamples(ByteData bd, int start, int end, int format,
      int channels, int bitsPerSample) {
    if (channels < 1) return null;
    if (format == 1 && bitsPerSample == 16) {
      final frameBytes = 2 * channels;
      final n = (end - start) ~/ frameBytes;
      final out = Float64List(n);
      for (var i = 0; i < n; i++) {
        var acc = 0.0;
        final base = start + i * frameBytes;
        for (var c = 0; c < channels; c++) {
          acc += bd.getInt16(base + 2 * c, Endian.little);
        }
        out[i] = acc / channels / 32768.0;
      }
      return out;
    }
    if (format == 3 && bitsPerSample == 32) {
      final frameBytes = 4 * channels;
      final n = (end - start) ~/ frameBytes;
      final out = Float64List(n);
      for (var i = 0; i < n; i++) {
        var acc = 0.0;
        final base = start + i * frameBytes;
        for (var c = 0; c < channels; c++) {
          acc += bd.getFloat32(base + 4 * c, Endian.little);
        }
        out[i] = (acc / channels).clamp(-1.0, 1.0);
      }
      return out;
    }
    return null; // unsupported bit depth / encoding
  }

  static String _tag(Uint8List b, int off) =>
      String.fromCharCodes(b.sublist(off, off + 4));
}
