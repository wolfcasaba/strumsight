import 'beat_position.dart';
import 'meter.dart';
import 'tempo.dart';

/// Converts exact musical ticks to session time at one fixed tempo and meter.
final class BeatTimeConverter {
  const BeatTimeConverter({required this.tempo, required this.meter});

  static const int _microsecondsPerMinute = 60000000;

  final Tempo tempo;
  final Meter meter;

  /// Converts [position] from the musical origin to elapsed session time.
  Duration timeOf(BeatPosition position) => timeOfTicks(position.ticks);

  /// Converts non-negative raw 480-PPQ [ticks] to elapsed session time.
  Duration timeOfTicks(int ticks) {
    _ensureValid();
    if (ticks < 0) {
      throw ArgumentError.value(ticks, 'ticks', 'Ticks cannot be negative.');
    }
    final microseconds =
        (ticks *
                _microsecondsPerMinute /
                (tempo.bpm * BeatPosition.ticksPerBeat))
            .round();
    return Duration(microseconds: microseconds);
  }

  /// Converts elapsed session [time] to the nearest musical tick.
  BeatPosition positionAt(Duration time) {
    _ensureValid();
    if (time < Duration.zero) {
      throw ArgumentError.value(
        time,
        'time',
        'Elapsed time cannot be negative.',
      );
    }
    final ticks =
        (time.inMicroseconds *
                tempo.bpm *
                BeatPosition.ticksPerBeat /
                _microsecondsPerMinute)
            .round();
    return BeatPosition.fromTicks(ticks);
  }

  /// Duration of one quarter-note beat.
  Duration get beatDuration => timeOfTicks(BeatPosition.ticksPerBeat);

  /// Duration of one complete bar in [meter].
  Duration get barDuration {
    _ensureValid();
    return timeOfTicks(meter.ticksPerBar);
  }

  void _ensureValid() {
    if (tempo.validate().isNotEmpty || meter.validate().isNotEmpty) {
      throw StateError('Cannot convert beat time with invalid tempo or meter.');
    }
  }
}
