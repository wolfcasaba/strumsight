import 'analysis_mode.dart';

/// Privacy-safe input metadata retained with an analysis document, never PCM.
final class AnalysisInputSummary {
  AnalysisInputSummary({
    required this.source,
    required this.duration,
    required this.sampleRate,
    required this.channelCount,
    required this.fingerprint,
    this.sourceName,
    this.originalAudioRetained = false,
  }) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration');
    }
    if (sampleRate <= 0 || channelCount <= 0) {
      throw ArgumentError('Sample rate and channel count must be positive.');
    }
    if (fingerprint.trim().isEmpty) {
      throw ArgumentError.value(fingerprint, 'fingerprint');
    }
  }
  final AnalysisInputSource source;
  final Duration duration;
  final int sampleRate;
  final int channelCount;
  final String fingerprint;
  final String? sourceName;
  final bool originalAudioRetained;
}
