/// Backing-audio container extensions the on-device player accepts.
///
/// The set mirrors `PlatformFilePickerAdapter.supportedAudioExtensions`:
/// what the editor can attach is exactly what the trainer can play. The
/// Android backend (MediaPlayer) decodes all seven.
///
/// iOS caveat — AVFoundation has no built-in Ogg Vorbis or FLAC-in-Ogg
/// decoder, so an `ogg` (and, on older versions, a `flac`) asset can still
/// fail when the platform loads it. That is deliberately NOT special-cased
/// here: the player surfaces the real platform failure
/// (`backingAudioPlayer.prepare`, retryable) instead of pretending the
/// user's file was never a valid choice.
const Set<String> supportedBackingAudioFormats = <String>{
  'mp3',
  'm4a',
  'mp4',
  'aac',
  'ogg',
  'flac',
  'wav',
};

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
