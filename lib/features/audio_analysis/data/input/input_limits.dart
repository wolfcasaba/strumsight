/// Versioned input limits for Audio Analysis V2.
///
/// The duration values are provisional until the E06-R28 device benchmark;
/// callers record [provenanceVersion] with the analysis provenance they create.
abstract final class InputLimits {
  static const int version = 1;
  static const String provenanceVersion = 'analysis-input-limits-v1';

  static const int bytesPerMebibyte = 1024 * 1024;
  static const int maxFileBytes = 64 * bytesPerMebibyte;
  static const Duration minDuration = Duration(milliseconds: 250);
  static const Duration maxDuration = Duration(minutes: 10);
  static const int minSampleRate = 8000;
  static const int maxSampleRate = 192000;
  static const int maxChannels = 2;
}
