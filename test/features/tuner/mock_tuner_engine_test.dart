import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/engine/mock_tuner_engine.dart';

void main() {
  final engine = MockTunerEngine();

  test('readingAt yields a valid open-string note and in-range cents', () {
    for (var ms = 0; ms < 20000; ms += 50) {
      final r = engine.readingAt(Duration(milliseconds: ms));
      expect(const ['E', 'A', 'D', 'G', 'B'], contains(r.note));
      expect(r.cents, inInclusiveRange(-50.0, 50.0));
      expect(r.frequencyHz, greaterThan(0));
    }
  });

  test('the note becomes in tune at some point', () {
    var reached = false;
    for (var ms = 0; ms < 6000; ms += 10) {
      if (engine.readingAt(Duration(milliseconds: ms)).inTune) {
        reached = true;
        break;
      }
    }
    expect(reached, isTrue);
  });
}
