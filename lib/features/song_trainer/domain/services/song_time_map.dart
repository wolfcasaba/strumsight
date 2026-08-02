import '../models/tempo_map.dart';
import '../models/song_section.dart';

final class SongTimeMap {
  SongTimeMap.fromTempoMap(this.tempoMap, {double speed = 1.0})
    : speedMicros = _speedMicros(speed) {
    if (speed <= 0) {
      throw SongStructureValidationException('songTimeMap.speed.invalid');
    }
  }
  final TempoMap tempoMap;
  final int speedMicros;

  static int _speedMicros(double speed) {
    if (!speed.isFinite || speed <= 0) {
      throw SongStructureValidationException('songTimeMap.speed.invalid');
    }
    return (speed * 1000000).round();
  }

  Duration timeAt(BeatPosition position) =>
      durationBetween(BeatPosition.zero, position);

  Duration durationBetween(BeatPosition start, BeatPosition end) {
    if (start.ticks < 0 || end < start) {
      throw SongStructureValidationException('songTimeMap.range.invalid');
    }
    var cursor = start;
    var total = 0;
    for (
      var i = _tempoIndex(start);
      cursor < end && i < tempoMap.changes.length;
      i++
    ) {
      final next = i + 1 < tempoMap.changes.length
          ? tempoMap.changes[i + 1].at
          : end;
      final segmentEnd = next < end ? next : end;
      total += microsecondsForTicks(
        segmentEnd.ticks - cursor.ticks,
        tempoMap.changes[i].bpm,
        speedMicros,
      );
      cursor = segmentEnd;
    }
    return Duration(microseconds: total);
  }

  BeatPosition positionAt(Duration time) {
    if (time.isNegative) {
      throw SongStructureValidationException('songTimeMap.time.invalid');
    }
    var remaining = time.inMicroseconds;
    for (var i = 0; i < tempoMap.changes.length; i++) {
      final next = i + 1 < tempoMap.changes.length
          ? tempoMap.changes[i + 1].at
          : null;
      if (next == null) {
        return tempoMap.changes[i].at +
            _ticksForMicroseconds(remaining, tempoMap.changes[i].bpm);
      }
      final segment = durationBetween(
        tempoMap.changes[i].at,
        next,
      ).inMicroseconds;
      if (remaining <= segment) {
        return tempoMap.changes[i].at +
            _ticksForMicroseconds(remaining, tempoMap.changes[i].bpm);
      }
      remaining -= segment;
    }
    return BeatPosition.zero;
  }

  BeatPosition _ticksForMicroseconds(int micros, Tempo tempo) {
    final numerator =
        micros * BeatPosition.ticksPerBeat * tempo.bpm * speedMicros;
    final denominator = 60000000 * 1000000;
    return BeatPosition.fromTicks(
      (numerator + denominator ~/ 2) ~/ denominator,
    );
  }

  int _tempoIndex(BeatPosition position) {
    var index = 0;
    for (
      var i = 1;
      i < tempoMap.changes.length && tempoMap.changes[i].at <= position;
      i++
    ) {
      index = i;
    }
    return index;
  }
}
