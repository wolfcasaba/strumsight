import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';
import 'package:strumsight/features/audio_analysis/domain/target/expected_event.dart';
import 'package:strumsight/features/audio_analysis/engine/alignment/event_aligner.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test(
    'matched indices are strictly monotonic for randomized ordered inputs',
    () {
      const aligner = EventAligner();
      for (var trial = 0; trial < 200; trial++) {
        final rng = math.Random(seed + trial * 997);
        final observed = _events(rng, 'o');
        final expected = _expectedEvents(rng, 'e');
        final result = aligner.align(
          observed: observed,
          expected: expected,
          beatDuration: const Duration(milliseconds: 500),
        );

        var observedIndex = -1;
        var expectedIndex = -1;
        for (final match in result.matches) {
          expect(
            match.observedIndex,
            greaterThan(observedIndex),
            reason: 'seed=$seed trial=$trial observed',
          );
          expect(
            match.expectedIndex,
            greaterThan(expectedIndex),
            reason: 'seed=$seed trial=$trial expected',
          );
          observedIndex = match.observedIndex;
          expectedIndex = match.expectedIndex;
        }
        expect(
          result.totalCost.isFinite,
          isTrue,
          reason: 'seed=$seed trial=$trial',
        );
        expect(
          result.confidence,
          inInclusiveRange(0, 1),
          reason: 'seed=$seed trial=$trial',
        );
      }
    },
  );
}

List<AnalysisEvent> _events(math.Random rng, String prefix) {
  var milliseconds = 0;
  final count = rng.nextInt(30);
  return <AnalysisEvent>[
    for (var index = 0; index < count; index++)
      OnsetEvent(
        id: '$prefix$index',
        time: Duration(milliseconds: milliseconds += rng.nextInt(180)),
        confidence: rng.nextDouble(),
      ),
  ];
}

List<ExpectedEvent> _expectedEvents(math.Random rng, String prefix) {
  var milliseconds = 0;
  final count = rng.nextInt(30);
  return <ExpectedEvent>[
    for (var index = 0; index < count; index++)
      ExpectedEvent(
        id: '$prefix$index',
        time: Duration(milliseconds: milliseconds += rng.nextInt(180)),
        type: ExpectedEventType.onset,
      ),
  ];
}
