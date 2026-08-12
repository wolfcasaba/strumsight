import 'package:meta/meta.dart';

/// One stable, voiced span emitted by the gated monophonic pitch capability.
///
/// This intentionally differs from the older timeline [PitchSegment] stub;
/// see ADR 0235 for the boundary and naming decision.
@immutable
final class MonophonicPitchSegment {
  MonophonicPitchSegment({
    required this.start,
    required this.end,
    required this.medianHz,
    required this.medianMidi,
    required this.centsOffset,
    required this.stabilityCents,
    required this.confidence,
  }) {
    if (start.isNegative || end < start) {
      throw ArgumentError(
        'Pitch segment range must be non-negative and ordered.',
      );
    }
    if (!medianHz.isFinite || medianHz <= 0 || medianHz > 5000) {
      throw ArgumentError.value(medianHz, 'medianHz');
    }
    if (medianMidi < 0 || medianMidi > 127) {
      throw ArgumentError.value(medianMidi, 'medianMidi');
    }
    if (!centsOffset.isFinite ||
        !stabilityCents.isFinite ||
        stabilityCents < 0) {
      throw ArgumentError('Pitch segment cents values must be finite.');
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence');
    }
  }

  final Duration start;
  final Duration end;
  final double medianHz;
  final int medianMidi;
  final double centsOffset;
  final double stabilityCents;
  final double confidence;

  Duration get duration => end - start;
}
