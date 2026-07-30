import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/beat_time_converter.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

void main() {
  group('BeatTimeConverter forward conversion', () {
    const converter = BeatTimeConverter(
      tempo: Tempo(120),
      meter: Meter(beatsPerBar: 4),
    );

    test('uses one final microsecond rounding step', () {
      expect(
        converter.timeOf(BeatPosition.quarters(1)),
        const Duration(milliseconds: 500),
      );
      expect(
        converter.timeOf(BeatPosition.eighths(1)),
        const Duration(milliseconds: 250),
      );
      expect(
        converter.timeOf(const BeatPosition(1)),
        const Duration(microseconds: 1042),
      );
      expect(converter.timeOfTicks(481), const Duration(microseconds: 501042));
    });

    test('exposes exact quarter-beat and meter-aware bar durations', () {
      expect(converter.beatDuration, const Duration(milliseconds: 500));
      expect(converter.barDuration, const Duration(seconds: 2));

      const threeFour = BeatTimeConverter(
        tempo: Tempo(120),
        meter: Meter(beatsPerBar: 3),
      );
      expect(threeFour.barDuration, const Duration(milliseconds: 1500));

      const threeEight = BeatTimeConverter(
        tempo: Tempo(120),
        meter: Meter(beatsPerBar: 3, beatUnit: 8),
      );
      expect(threeEight.barDuration, const Duration(milliseconds: 750));
    });
  });

  group('BeatTimeConverter inverse conversion', () {
    test('round-trips every 32-tick grid point over 64 quarter beats', () {
      for (final bpm in const [60.0, 90.0, 120.0, 137.5]) {
        final converter = BeatTimeConverter(
          tempo: Tempo(bpm),
          meter: const Meter(beatsPerBar: 4),
        );
        for (
          var ticks = 0;
          ticks <= BeatPosition.ticksPerBeat * 64;
          ticks += 32
        ) {
          final position = BeatPosition.fromTicks(ticks);
          expect(
            converter.positionAt(converter.timeOf(position)),
            position,
            reason: 'round-trip at $bpm BPM and $ticks ticks',
          );
        }
      }
    });

    test('rejects negative elapsed time', () {
      const converter = BeatTimeConverter(
        tempo: Tempo(120),
        meter: Meter(beatsPerBar: 4),
      );

      expect(
        () => converter.positionAt(const Duration(microseconds: -1)),
        throwsArgumentError,
      );
    });
  });

  group('BeatTimeConverter validation guards', () {
    test('every conversion member rejects an invalid tempo', () {
      const converter = BeatTimeConverter(
        tempo: Tempo(0),
        meter: Meter(beatsPerBar: 4),
      );

      expect(() => converter.timeOf(const BeatPosition(1)), throwsStateError);
      expect(() => converter.timeOfTicks(1), throwsStateError);
      expect(
        () => converter.positionAt(const Duration(microseconds: 1)),
        throwsStateError,
      );
      expect(() => converter.beatDuration, throwsStateError);
      expect(() => converter.barDuration, throwsStateError);
    });

    test('every conversion member rejects an invalid meter', () {
      const converter = BeatTimeConverter(
        tempo: Tempo(120),
        meter: Meter(beatsPerBar: 0),
      );

      expect(() => converter.timeOf(const BeatPosition(1)), throwsStateError);
      expect(() => converter.timeOfTicks(1), throwsStateError);
      expect(
        () => converter.positionAt(const Duration(microseconds: 1)),
        throwsStateError,
      );
      expect(() => converter.beatDuration, throwsStateError);
      expect(() => converter.barDuration, throwsStateError);
    });
  });
}
