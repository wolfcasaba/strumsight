import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/domain/model/chord_pair_stats.dart';

void main() {
  test('ChordPair is immutable and value equal', () {
    expect(
      const ChordPair(from: 'G', to: 'D'),
      const ChordPair(from: 'G', to: 'D'),
    );
    expect(
      const ChordPair(from: 'G', to: 'D'),
      isNot(const ChordPair(from: 'D', to: 'G')),
    );
  });

  test('stats expose immutable counts and measured delays', () {
    final stats = ChordPairStats(
      pair: ChordPair(from: 'G', to: 'D'),
      attempts: 3,
      correctChanges: 2,
      wrongChordCount: 1,
      noDetectionCount: 0,
      unstableCount: 0,
      insufficientSignalCount: 0,
      recognizedChangeDelays: [
        Duration(milliseconds: 100),
        Duration(milliseconds: 300),
        Duration(milliseconds: 200),
      ],
    );

    expect(
      stats.medianRecognizedChangeDelay,
      const Duration(milliseconds: 200),
    );
    expect(stats.measuredChanges, 3);
    expect(stats.outcomeCount, 3);
    expect(
      () => stats.recognizedChangeDelays.add(Duration.zero),
      throwsUnsupportedError,
    );
  });

  test('invalid stats report validation failures', () {
    final stats = ChordPairStats(
      pair: ChordPair(from: 'G', to: 'D'),
      attempts: 1,
      correctChanges: 1,
      wrongChordCount: 1,
      noDetectionCount: 0,
      unstableCount: 0,
      insufficientSignalCount: 0,
      recognizedChangeDelays: const [],
    );

    expect(stats.validate(), isNotEmpty);
  });
}
