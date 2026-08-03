import '../../domain/models/tempo_map.dart';
import 'midi_parser_adapter.dart';

final class MidiTimelineMapper {
  const MidiTimelineMapper();
  Duration atTick(int tick, int ppq, List<MidiEventData> events) {
    final tempos =
        events
            .where((event) => event.kind == 0x151 && event.data.length == 3)
            .toList()
          ..sort((a, b) => a.tick.compareTo(b.tick));
    var micros = 0, previous = 0, tempo = 500000;
    for (final event in tempos) {
      if (event.tick > tick) break;
      micros += ((event.tick - previous) * tempo ~/ ppq);
      previous = event.tick;
      tempo = (event.data[0] << 16) | (event.data[1] << 8) | event.data[2];
    }
    micros += ((tick - previous) * tempo ~/ ppq);
    return Duration(microseconds: micros);
  }

  BeatPosition beatAt(int tick, int ppq) =>
      BeatPosition.fromTicks((tick * BeatPosition.ticksPerBeat / ppq).round());
}
