/// Immutable native-rate PCM context for later Audio Analysis V2 stages.
///
/// [originalSamples] is reserved for dynamics measurements. [canonicalSamples]
/// is for feature extraction; with the default policy both fields reference the
/// same immutable snapshot, so the context never creates an unnecessary second
/// PCM buffer. Sample timestamps are always rounded down to microseconds.
final class PreprocessedAudio {
  PreprocessedAudio({
    required List<double> originalSamples,
    required List<double> canonicalSamples,
    required this.sampleRate,
    required this.originalChannelCount,
    required this.normalizationGain,
    required this.preprocessingVersion,
  }) {
    _originalSamples = List<double>.unmodifiable(originalSamples);
    _canonicalSamples = identical(originalSamples, canonicalSamples)
        ? _originalSamples
        : List<double>.unmodifiable(canonicalSamples);
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate');
    }
    if (originalChannelCount <= 0) {
      throw ArgumentError.value(originalChannelCount, 'originalChannelCount');
    }
    if (!normalizationGain.isFinite || normalizationGain <= 0) {
      throw ArgumentError.value(normalizationGain, 'normalizationGain');
    }
    if (_originalSamples.length != _canonicalSamples.length) {
      throw ArgumentError(
        'Original and canonical samples must have equal length.',
      );
    }
  }

  static const int _microsPerSecond = Duration.microsecondsPerSecond;

  late final List<double> _originalSamples;
  late final List<double> _canonicalSamples;

  final int sampleRate;
  final int originalChannelCount;

  /// Multiplicative peak-normalization factor applied to canonical samples.
  final double normalizationGain;
  final String preprocessingVersion;

  List<double> get originalSamples => _originalSamples;
  List<double> get canonicalSamples => _canonicalSamples;

  /// Converts a native sample index to a floor-rounded timestamp.
  Duration sampleIndexToDuration(int sampleIndex) {
    if (sampleIndex < 0) {
      throw ArgumentError.value(sampleIndex, 'sampleIndex');
    }
    return Duration(microseconds: sampleIndex * _microsPerSecond ~/ sampleRate);
  }

  /// Returns the last native sample whose floor-rounded timestamp is at most
  /// [duration]. This makes every timestamp created by
  /// [sampleIndexToDuration] round-trip exactly despite microsecond precision.
  int durationToSampleIndex(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration');
    }
    return ((duration.inMicroseconds + 1) * sampleRate - 1) ~/ _microsPerSecond;
  }
}
