/// Privacy-preserving, deterministic fingerprinting for normalized PCM input.
library;

import 'dart:convert';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart' as crypto;

/// Builds the input component of an analysis cache key.
///
/// The input is intentionally limited to audio format metadata, preprocessing
/// version, and quantized PCM. It excludes filename, path, device identity,
/// and unquantized floating-point representation.
abstract final class AudioFingerprint {
  /// Returns a lowercase SHA-256 digest of the canonical 16-bit PCM payload.
  static String compute({
    required List<double> samples,
    required int sampleRate,
    required int channelCount,
    required String preprocessingVersion,
  }) {
    if (sampleRate <= 0) throw ArgumentError.value(sampleRate, 'sampleRate');
    if (channelCount <= 0) {
      throw ArgumentError.value(channelCount, 'channelCount');
    }
    if (preprocessingVersion.trim().isEmpty) {
      throw ArgumentError.value(preprocessingVersion, 'preprocessingVersion');
    }

    final versionBytes = utf8.encode(preprocessingVersion);
    final header = ByteData(20)
      ..setUint64(0, samples.length, Endian.little)
      ..setUint32(8, sampleRate, Endian.little)
      ..setUint32(12, channelCount, Endian.little)
      ..setUint32(16, versionBytes.length, Endian.little);
    final pcm = ByteData(samples.length * 2);
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      if (!sample.isFinite) {
        throw ArgumentError.value(sample, 'samples', 'must be finite');
      }
      pcm.setInt16(index * 2, _quantize(sample), Endian.little);
    }
    return crypto.sha256.convert(<int>[
      ...header.buffer.asUint8List(),
      ...versionBytes,
      ...pcm.buffer.asUint8List(),
    ]).toString();
  }

  static int _quantize(double sample) {
    final clipped = sample.clamp(-1.0, 1.0);
    return (clipped * 32767).round();
  }
}
