import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

void main() {
  final map = SongTimeMap.fromTempoMap(
    TempoMap([
      TempoChange(at: BeatPosition.zero, bpm: Tempo(120)),
      TempoChange(at: BeatPosition.fromBeats(4), bpm: Tempo(60)),
    ]),
  );

  test('constant 120 BPM maps beats to seconds', () {
    final constant = SongTimeMap.fromTempoMap(TempoMap.constant(Tempo(120)));
    expect(constant.timeAt(BeatPosition.zero), Duration.zero);
    expect(
      constant.timeAt(BeatPosition.fromBeats(1)),
      const Duration(milliseconds: 500),
    );
    expect(
      constant.timeAt(BeatPosition.fromBeats(4)),
      const Duration(seconds: 2),
    );
  });

  test('tempo boundary is continuous and invertible', () {
    expect(map.timeAt(BeatPosition.fromBeats(4)), const Duration(seconds: 2));
    expect(map.timeAt(BeatPosition.fromBeats(5)), const Duration(seconds: 3));
    expect(
      map.positionAt(const Duration(seconds: 2)),
      BeatPosition.fromBeats(4),
    );
    expect(
      map.positionAt(const Duration(milliseconds: 1999)),
      lessThan(BeatPosition.fromBeats(4)),
    );
  });

  test('uses the new tempo from the exact tick boundary', () {
    final boundary = BeatPosition.fromTicks(4 * BeatPosition.ticksPerBeat);
    expect(
      map.timeAt(boundary - const BeatPosition.fromTicks(1)),
      const Duration(microseconds: 1998958),
    );
    expect(map.timeAt(boundary), const Duration(seconds: 2));
    expect(
      map.timeAt(boundary + const BeatPosition.fromTicks(1)),
      const Duration(microseconds: 2002083),
    );
    expect(
      map.durationBetween(boundary, boundary + const BeatPosition.fromTicks(1)),
      const Duration(microseconds: 2083),
    );
  });

  test('speed scales duration without mutating source map', () {
    final source = TempoMap.constant(Tempo(120));
    final half = SongTimeMap.fromTempoMap(source, speed: 0.5);
    final normal = SongTimeMap.fromTempoMap(source);
    final doubleSpeed = SongTimeMap.fromTempoMap(source, speed: 2);
    expect(half.timeAt(BeatPosition.fromBeats(2)), const Duration(seconds: 2));
    expect(
      normal.timeAt(BeatPosition.fromBeats(2)),
      const Duration(seconds: 1),
    );
    expect(
      doubleSpeed.timeAt(BeatPosition.fromBeats(2)),
      const Duration(milliseconds: 500),
    );
    expect(source.changes.single.bpm, Tempo(120));
  });

  test('durationBetween rejects reversed ranges', () {
    final constant = SongTimeMap.fromTempoMap(TempoMap.constant(Tempo(120)));
    expect(
      () => constant.durationBetween(
        BeatPosition.fromBeats(2),
        BeatPosition.zero,
      ),
      throwsA(isA<SongStructureValidationException>()),
    );
  });
}
