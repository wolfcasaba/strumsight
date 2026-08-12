import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('target timing metrics are always finite and ratios stay in [0, 1]', () {
    const aligner = EventAligner();
    const beat = Duration(milliseconds: 500);
    for (var trial = 0; trial < 200; trial++) {
      final rng = math.Random(seed + trial * 1009);
      final observed = _events(rng, 'o');
      final expected = _expectedEvents(rng, 'e');
      final alignment = aligner.align(
        observed: observed,
        expected: expected,
        beatDuration: beat,
      );
      final tolerance = const TolerancePolicy().forBeatDuration(beat);
      final results = buildTargetTimingMetrics(
        alignment: alignment,
        tolerance: tolerance,
      );
      _assertHealthy(results, seed: seed, trial: trial);
    }
  });

  test(
    'freeplay timing metrics are always finite, ratios in [0,1], confidence bounded',
    () {
      for (var trial = 0; trial < 200; trial++) {
        final rng = math.Random(seed + trial * 7919);
        final beatGrid = _beatGrid(rng);
        final observed = _events(rng, 'o');
        final results = buildFreePlayTimingMetrics(
          observed: observed,
          beatGrid: beatGrid,
        );
        _assertHealthy(results, seed: seed, trial: trial);
        for (final result in results) {
          expect(
            result.confidence,
            inInclusiveRange(0, 1),
            reason: 'seed=$seed trial=$trial ${result.id}',
          );
        }
      }
    },
  );
}

void _assertHealthy(
  List<AnalysisMetricResult> results, {
  required int seed,
  required int trial,
}) {
  expect(results, hasLength(10), reason: 'seed=$seed trial=$trial');
  for (final result in results) {
    final value = result.value;
    if (value == null) {
      expect(
        result.status,
        CapabilityStatus.unavailable,
        reason: 'seed=$seed trial=$trial ${result.id}',
      );
      continue;
    }
    switch (value) {
      case ScalarMetricValue(:final value):
        expect(
          value.isFinite,
          isTrue,
          reason: 'seed=$seed trial=$trial ${result.id}',
        );
      case PercentageMetricValue(:final value):
        expect(
          value,
          inInclusiveRange(0, 1),
          reason: 'seed=$seed trial=$trial ${result.id}',
        );
      default:
        fail('unexpected metric value type for ${result.id}');
    }
  }
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

BeatGrid _beatGrid(math.Random rng) {
  final count = 2 + rng.nextInt(30);
  var milliseconds = 0;
  return BeatGrid(
    beats: <BeatPoint>[
      for (var index = 0; index < count; index++)
        BeatPoint(
          index: index,
          time: Duration(milliseconds: milliseconds += 400 + rng.nextInt(200)),
          confidence: rng.nextDouble(),
          source: BeatSource.estimated,
        ),
    ],
    bars: const <BarPoint>[],
    beatsPerBar: 4,
    beatsPerBarSource: BeatsPerBarSource.legacyDefault,
    status: CapabilityStatus.available,
    meterStatus: CapabilityStatus.notApplicable,
  );
}
