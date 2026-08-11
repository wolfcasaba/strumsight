/// Versioned, temporary limits for analysis input at the trust boundary.
///
/// The 10-minute duration is intentionally provisional until the E06-R28
/// device benchmark establishes a measured policy (SDD Ch7 §22.5).
abstract final class InputLimits {
  static const int version = 1;
  static const int maxFileBytes = 64 * 1024 * 1024;
  static const Duration minDuration = Duration(milliseconds: 250);
  static const Duration maxDuration = Duration(minutes: 10);
  static const int minSampleRate = 8000;
  static const int maxSampleRate = 192000;
  static const int maxChannels = 2;
}
