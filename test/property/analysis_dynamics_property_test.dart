import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('dynamics metrics stay finite and in range across random sessions', () {
    for (var trial = 0; trial < 200; trial++) {
      final random = math.Random(seed + trial * 2029);
      final eventCount = 3 + random.nextInt(30);
      final events = _events(random, eventCount);
      final audio = _audio(random, events);
      final report = buildDynamicsMetrics(
        audio: audio,
        events: events,
        signalQuality: _report(random),
        expectedAccentEventIds: random.nextBool()
            ? <String>{
                for (final event in events)
                  if (random.nextBool()) event.id,
              }
            : null,
      );

      expect(
        report.metrics.map((metric) => metric.id).toSet(),
        DynamicsMetricIds.all,
        reason: 'seed=$seed trial=$trial',
      );
      for (final metric in report.metrics) {
        expect(
          metric.confidence,
          inInclusiveRange(0, 1),
          reason: 'seed=$seed trial=$trial ${metric.id}',
        );
        switch (metric.value) {
          case PercentageMetricValue(:final value):
            expect(
              value,
              inInclusiveRange(0, 1),
              reason: 'seed=$seed trial=$trial ${metric.id}',
            );
          case ScalarMetricValue(:final value):
            expect(
              value.isFinite,
              isTrue,
              reason: 'seed=$seed trial=$trial ${metric.id}',
            );
          case null:
            expect(
              metric.status,
              anyOf(
                CapabilityStatus.unavailable,
                CapabilityStatus.notApplicable,
              ),
              reason: 'seed=$seed trial=$trial ${metric.id}',
            );
          default:
            fail('unexpected metric value for ${metric.id}');
        }
      }
    }
  });
}

List<StrumEvent> _events(math.Random random, int count) {
  var milliseconds = 0;
  return <StrumEvent>[
    for (var index = 0; index < count; index++)
      StrumEvent(
        id: 'strum-$index',
        time: Duration(milliseconds: milliseconds += 50 + random.nextInt(400)),
        confidence: random.nextDouble(),
        direction: switch (random.nextInt(3)) {
          0 => StrumDirection.down,
          1 => StrumDirection.up,
          _ => StrumDirection.unknown,
        },
        sampleIndex: milliseconds,
        attackStrength: random.nextDouble() * 0.9,
        localRms: random.nextDouble() * 0.5,
      ),
  ];
}

PreprocessedAudio _audio(math.Random random, List<StrumEvent> events) {
  final length = events.isEmpty ? 1000 : events.last.sampleIndex! + 50;
  final samples = List<double>.generate(
    length,
    (_) => (random.nextDouble() - 0.5) * 0.1,
  );
  return PreprocessedAudio(
    originalSamples: samples,
    canonicalSamples: samples,
    sampleRate: 1000,
    originalChannelCount: 1,
    normalizationGain: 1.0,
    preprocessingVersion: 'property-test',
  );
}

SignalQualityReport _report(math.Random random) => SignalQualityReport(
  overall: random.nextDouble(),
  peakDbfs: -random.nextDouble() * 20,
  rmsDbfs: -10 - random.nextDouble() * 20,
  noiseFloorDbfs: -60 + random.nextDouble() * 40,
  clippedSampleRatio: random.nextDouble() * 0.1,
  silentRatio: random.nextDouble() * 0.3,
  tonalness: random.nextDouble(),
  measured: true,
);
