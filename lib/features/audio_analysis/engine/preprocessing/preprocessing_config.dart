/// Versioned, immutable preprocessing policy for the Audio Analysis V2 input.
///
/// Transformations require the composition-owned experimental flag as well as
/// their individual setting. The default preserves native PCM unchanged.
final class PreprocessingConfig {
  const PreprocessingConfig.v1({
    this.removeDcOffset = false,
    this.normalizePeak = false,
  });

  static const String v1Version = 'v1';
  static const Duration onsetParityTolerance = Duration(milliseconds: 5);

  /// Removes the arithmetic-mean DC component before feature extraction.
  final bool removeDcOffset;

  /// Scales the canonical peak to one after any DC removal.
  final bool normalizePeak;

  String get version => v1Version;

  bool get hasTransformations => removeDcOffset || normalizePeak;

  /// The frozen V1 inclusive parity gate for a later onset evaluation.
  bool isOnsetParityWithinTolerance(Duration difference) =>
      difference.abs() <= onsetParityTolerance;
}
