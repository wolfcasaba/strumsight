import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('rhythm proxies stay finite and ranges remain valid', () {
    for (var trial = 0; trial < 200; trial++) {
      final random = math.Random(seed + trial * 1777);
      final report = buildRhythmMetrics(
        events: _events(random),
        beatGrid: _grid(random),
      );
      for (final result in report.metrics) {
        expect(
          result.confidence,
          inInclusiveRange(0, 1),
          reason: 'seed=$seed trial=$trial ${result.id}',
        );
        switch (result.value) {
          case PercentageMetricValue(:final value):
            expect(
              value,
              inInclusiveRange(0, 1),
              reason: 'seed=$seed trial=$trial ${result.id}',
            );
          case ScalarMetricValue(:final value):
            expect(
              value.isFinite,
              isTrue,
              reason: 'seed=$seed trial=$trial ${result.id}',
            );
          case null:
            expect(
              result.status,
              CapabilityStatus.unavailable,
              reason: 'seed=$seed trial=$trial ${result.id}',
            );
          default:
            fail('unexpected metric value for ${result.id}');
        }
      }
      if (report.subdivision.subdivision != null) {
        expect(report.subdivision.subdivision, anyOf(1, 2, 3, 4));
      }
    }
  });
}

List<AnalysisEvent> _events(math.Random random) {
  var milliseconds = 0;
  final count = random.nextInt(25);
  return <AnalysisEvent>[
    for (var index = 0; index < count; index++)
      OnsetEvent(
        id: 'event-$index',
        time: Duration(milliseconds: milliseconds += 1 + random.nextInt(750)),
        confidence: random.nextDouble(),
      ),
  ];
}

BeatGrid _grid(math.Random random) {
  final source = random.nextBool() ? BeatSource.target : BeatSource.estimated;
  return BeatGrid(
    beats: <BeatPoint>[
      for (var index = 0; index < 10; index++)
        BeatPoint(
          index: index,
          time: Duration(milliseconds: index * 1000),
          confidence: random.nextDouble(),
          source: source,
        ),
    ],
    bars: const <BarPoint>[],
    beatsPerBar: 4,
    beatsPerBarSource: source == BeatSource.target
        ? BeatsPerBarSource.target
        : BeatsPerBarSource.legacyDefault,
    status: CapabilityStatus.available,
    meterStatus: source == BeatSource.target
        ? CapabilityStatus.available
        : CapabilityStatus.notApplicable,
  );
}
