import 'practice_validation.dart';

/// An exact musical position measured in integer ticks at 480 PPQ.
///
/// The canonical persisted representation is the raw integer [ticks] value.
/// Use [fromTicks] for runtime or data-driven input so invalid negative values
/// are rejected in every build mode.
final class BeatPosition implements Comparable<BeatPosition> {
  const BeatPosition(this.ticks) : assert(ticks >= 0);

  /// Pulses per quarter-note beat.
  static const int ticksPerBeat = 480;

  static const int _ticksPerEighth = ticksPerBeat ~/ 2;
  static const int _ticksPerSixteenth = ticksPerBeat ~/ 4;
  static const int _ticksPerEighthTriplet = ticksPerBeat ~/ 3;

  /// The exact non-negative position in 480-PPQ ticks.
  final int ticks;

  /// Creates a position from runtime tick data.
  factory BeatPosition.fromTicks(int ticks) {
    if (ticks < 0) {
      _throwNegative(ticks, 'ticks');
    }
    return BeatPosition(ticks);
  }

  /// Creates a position containing [count] quarter notes.
  factory BeatPosition.quarters(int count) =>
      BeatPosition.fromTicks(count * ticksPerBeat);

  /// Creates a position containing [count] eighth notes.
  factory BeatPosition.eighths(int count) =>
      BeatPosition.fromTicks(count * _ticksPerEighth);

  /// Creates a position containing [count] sixteenth notes.
  factory BeatPosition.sixteenths(int count) =>
      BeatPosition.fromTicks(count * _ticksPerSixteenth);

  /// Creates a position containing [count] eighth-note triplets.
  factory BeatPosition.eighthTriplets(int count) =>
      BeatPosition.fromTicks(count * _ticksPerEighthTriplet);

  /// Converts the legacy `double beat` representation to integer ticks.
  ///
  /// The conversion is `(beats * 480).round()`, so its maximum rounding error
  /// is ≤ `1/960 beat` (half a tick). Today's `x.0`/`x.5` grid and every
  /// supported subdivision whose tick size divides 480 round-trip with zero
  /// deviation.
  factory BeatPosition.fromLegacyBeats(double beats) {
    if (!beats.isFinite) {
      throw ArgumentError.value(
        beats,
        'beats',
        'Legacy beat positions must be finite.',
      );
    }
    if (beats < 0) {
      _throwNegative(beats, 'beats');
    }
    return BeatPosition.fromTicks((beats * ticksPerBeat).round());
  }

  /// Converts this position back to the legacy `double beat` representation.
  ///
  /// This and [fromLegacyBeats] are the Practice domain's only `double`
  /// musical-position boundary.
  double toLegacyBeats() => ticks / ticksPerBeat;

  /// Returns the exact sum of two musical positions.
  BeatPosition operator +(BeatPosition other) =>
      BeatPosition.fromTicks(ticks + other.ticks);

  /// Returns the exact difference, rejecting a result before timeline zero.
  BeatPosition operator -(BeatPosition other) =>
      BeatPosition.fromTicks(ticks - other.ticks);

  @override
  int compareTo(BeatPosition other) => ticks.compareTo(other.ticks);

  @override
  bool operator ==(Object other) =>
      other is BeatPosition && other.ticks == ticks;

  @override
  int get hashCode => ticks.hashCode;

  @override
  String toString() => 'BeatPosition($ticks ticks)';

  static Never _throwNegative(num value, String name) {
    throw ArgumentError.value(
      value,
      name,
      '${PracticeValidationCode.beatPositionNegative}: '
      'Musical positions cannot be negative.',
    );
  }
}
