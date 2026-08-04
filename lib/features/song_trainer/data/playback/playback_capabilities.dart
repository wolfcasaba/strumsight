final class PlaybackCapabilities {
  const PlaybackCapabilities({
    required this.canSeek,
    required this.canChangeRate,
    required this.preservesPitchWhenRateChanges,
    required this.positionPrecision,
    required this.supportedFormats,
    this.minimumRate,
    this.maximumRate,
  }) : assert(
         !canChangeRate || (minimumRate != null && maximumRate != null),
         'Rate-capable playback must declare its supported range.',
       );

  final bool canSeek;
  final bool canChangeRate;
  final bool preservesPitchWhenRateChanges;
  final Duration positionPrecision;
  final Set<String> supportedFormats;
  final double? minimumRate;
  final double? maximumRate;

  bool supportsFormat(String extension) =>
      supportedFormats.contains(extension.toLowerCase());

  bool supportsRate(double rate) {
    final minimum = minimumRate;
    final maximum = maximumRate;
    return canChangeRate &&
        rate.isFinite &&
        minimum != null &&
        maximum != null &&
        rate >= minimum &&
        rate <= maximum;
  }
}
