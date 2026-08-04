import 'package:meta/meta.dart';

/// One confidence-gated pitch estimate produced from an audio frame.
@immutable
final class PitchObservation {
  const PitchObservation({
    required this.observedAt,
    required this.frequencyHz,
    required this.midiPitch,
    required this.centsFromNearest,
    required this.clarity,
    required this.rms,
    required this.stable,
  });

  final DateTime observedAt;
  final double frequencyHz;
  final int midiPitch;
  final double centsFromNearest;
  final double clarity;
  final double rms;
  final bool stable;
}
