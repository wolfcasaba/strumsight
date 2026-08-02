import 'song_section.dart';

const int _microsPerMinute = 60000000;

final class BeatPosition implements Comparable<BeatPosition> {
  static const int ticksPerBeat = 480;
  const BeatPosition.fromTicks(this.ticks);
  const BeatPosition(this.ticks);
  static const zero = BeatPosition.fromTicks(0);
  final int ticks;
  factory BeatPosition.fromBeats(int beats) =>
      BeatPosition.fromTicks(beats * ticksPerBeat);
  factory BeatPosition.fromFraction(int numerator, [int denominator = 1]) {
    if (denominator <= 0) {
      throw SongStructureValidationException('beat.denominator.invalid');
    }
    final scaled = numerator * ticksPerBeat;
    if (scaled % denominator != 0) {
      throw SongStructureValidationException('beat.notRepresentable');
    }
    return BeatPosition.fromTicks(scaled ~/ denominator);
  }
  BeatPosition operator +(BeatPosition other) =>
      BeatPosition.fromTicks(ticks + other.ticks);
  BeatPosition operator -(BeatPosition other) =>
      BeatPosition.fromTicks(ticks - other.ticks);
  BeatPosition operator -() => BeatPosition.fromTicks(-ticks);
  BeatPosition abs() => BeatPosition.fromTicks(ticks.abs());
  bool operator <(BeatPosition other) => ticks < other.ticks;
  bool operator <=(BeatPosition other) => ticks <= other.ticks;
  bool operator >(BeatPosition other) => ticks > other.ticks;
  bool operator >=(BeatPosition other) => ticks >= other.ticks;
  @override
  int compareTo(BeatPosition other) => ticks.compareTo(other.ticks);
  @override
  bool operator ==(Object other) =>
      other is BeatPosition && other.ticks == ticks;
  @override
  int get hashCode => ticks.hashCode;
  @override
  String toString() => 'BeatPosition($ticks ticks)';
}

final class Tempo {
  Tempo(this.bpm) {
    if (bpm <= 0) {
      throw SongStructureValidationException('tempo.bpm.invalid');
    }
  }
  final int bpm;
  @override
  bool operator ==(Object other) => other is Tempo && other.bpm == bpm;
  @override
  int get hashCode => bpm.hashCode;
}

final class TempoChange {
  const TempoChange({required this.at, required this.bpm});
  final BeatPosition at;
  final Tempo bpm;

  @override
  bool operator ==(Object other) =>
      other is TempoChange && other.at == at && other.bpm == bpm;

  @override
  int get hashCode => Object.hash(at, bpm);
}

final class TempoMap {
  TempoMap(Iterable<TempoChange> changes)
    : changes = List.unmodifiable(changes) {
    if (this.changes.isEmpty || this.changes.first.at != BeatPosition.zero) {
      throw SongStructureValidationException('tempoMap.firstBoundary.invalid');
    }
    if (this.changes.any((change) => change.bpm.bpm <= 0)) {
      throw SongStructureValidationException('tempo.bpm.invalid');
    }
    for (var i = 1; i < this.changes.length; i++) {
      if (this.changes[i].at <= this.changes[i - 1].at) {
        throw SongStructureValidationException('tempoMap.boundaries.invalid');
      }
    }
  }
  factory TempoMap.constant(Tempo tempo) =>
      TempoMap([TempoChange(at: BeatPosition.zero, bpm: tempo)]);
  final List<TempoChange> changes;

  @override
  bool operator ==(Object other) =>
      other is TempoMap && _listEquals(other.changes, changes);

  @override
  int get hashCode => Object.hashAll(changes);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

int microsecondsForTicks(int ticks, Tempo tempo, int speedMicros) {
  final numerator = ticks * _microsPerMinute * 1000000;
  final denominator = BeatPosition.ticksPerBeat * tempo.bpm * speedMicros;
  if (numerator >= 0) return (numerator + denominator ~/ 2) ~/ denominator;
  return -((-numerator + denominator ~/ 2) ~/ denominator);
}
