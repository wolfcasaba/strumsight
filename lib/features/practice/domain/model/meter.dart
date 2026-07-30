import 'beat_position.dart';
import 'practice_validation.dart';

/// A musical meter expressed as beats per bar and the beat-note denominator.
final class Meter {
  const Meter({required this.beatsPerBar, this.beatUnit = 4});

  static const int minimumBeatsPerBar = 1;
  static const int maximumBeatsPerBar = 16;
  static const Set<int> supportedBeatUnits = {2, 4, 8};

  final int beatsPerBar;
  final int beatUnit;

  /// Returns every independent validation problem for this meter.
  List<PracticeValidationFailure> validate() {
    final failures = <PracticeValidationFailure>[];
    if (beatsPerBar < minimumBeatsPerBar || beatsPerBar > maximumBeatsPerBar) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.meterBeatsPerBarOutOfRange,
          message: 'Beats per bar must be between 1 and 16.',
        ),
      );
    }
    if (!supportedBeatUnits.contains(beatUnit)) {
      failures.add(
        const PracticeValidationFailure(
          code: PracticeValidationCode.meterBeatUnitUnsupported,
          message: 'Beat unit must be 2, 4, or 8.',
        ),
      );
    }
    return List.unmodifiable(failures);
  }

  /// Exact 480-PPQ duration of one bar.
  ///
  /// Validate the meter before reading this getter. An out-of-range
  /// [beatsPerBar] or unsupported [beatUnit] throws [StateError].
  int get ticksPerBar {
    if (beatsPerBar < minimumBeatsPerBar || beatsPerBar > maximumBeatsPerBar) {
      throw StateError(
        'Cannot calculate ticksPerBar for invalid beats per bar $beatsPerBar.',
      );
    }
    final ticksPerMeterBeat = switch (beatUnit) {
      2 => BeatPosition.ticksPerBeat * 2,
      4 => BeatPosition.ticksPerBeat,
      8 => BeatPosition.ticksPerBeat ~/ 2,
      _ => throw StateError(
        'Cannot calculate ticksPerBar for unsupported beat unit $beatUnit.',
      ),
    };
    return beatsPerBar * ticksPerMeterBeat;
  }

  @override
  bool operator ==(Object other) =>
      other is Meter &&
      other.beatsPerBar == beatsPerBar &&
      other.beatUnit == beatUnit;

  @override
  int get hashCode => Object.hash(beatsPerBar, beatUnit);

  @override
  String toString() => 'Meter($beatsPerBar/$beatUnit)';
}
