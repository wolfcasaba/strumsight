import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

void main() {
  test('random beat round trips are monotonic within one tick', () {
    final map = SongTimeMap.fromTempoMap(
      TempoMap([
        TempoChange(at: BeatPosition.zero, bpm: Tempo(120)),
        TempoChange(at: BeatPosition.fromBeats(8), bpm: Tempo(90)),
        TempoChange(at: BeatPosition.fromBeats(16), bpm: Tempo(150)),
      ]),
    );
    final random = Random(9303);
    var previousTime = Duration.zero;
    final beats = List<BeatPosition>.generate(
      500,
      (_) => BeatPosition.fromTicks(
        random.nextInt(24 * BeatPosition.ticksPerBeat),
      ),
    )..sort();
    for (final beat in beats) {
      final time = map.timeAt(beat);
      final roundTrip = map.positionAt(time);
      expect((roundTrip - beat).abs().ticks, lessThanOrEqualTo(1));
      expect(time >= previousTime, isTrue);
      previousTime = time;
    }
  });
}
