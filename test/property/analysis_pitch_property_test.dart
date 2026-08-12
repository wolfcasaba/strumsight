import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  test('pitch calculations remain finite across randomized valid evidence', () {
    for (var trial = 0; trial < 200; trial += 1) {
      final random = math.Random(seed + trial * 313);
      final baseFrequency = 80 + random.nextDouble() * 900;
      final confidence = 0.6 + random.nextDouble() * 0.4;
      final frames = <PitchFrame>[
        for (var index = 0; index < 20; index += 1)
          _frameOnStableCurve(
            baseFrequency: baseFrequency,
            cents: (random.nextDouble() - 0.5) * 60,
            confidence: confidence,
            index: index,
          ),
      ];
      final segments = MonophonicPitchSegmentBuilder().build(frames);
      expect(segments, hasLength(1));
      final target = MonophonicPitchTarget(<PitchTargetNote>[
        PitchTargetNote(
          start: Duration.zero,
          end: const Duration(milliseconds: 200),
          midiNote: segments.single.medianMidi,
        ),
      ]);
      final report = buildGatedPitchMetrics(
        analysisPitchEnabled: true,
        target: target,
        frames: frames,
        segments: segments,
      );
      expect(report.capability.status, CapabilityStatus.available);
      expect(report.capability.confidence, inInclusiveRange(0, 1));
      for (final segment in segments) {
        expect(segment.medianHz, inInclusiveRange(0.000001, 5000));
        expect(segment.centsOffset.isFinite, isTrue);
        expect(segment.stabilityCents.isFinite, isTrue);
        expect(segment.confidence, inInclusiveRange(0, 1));
      }
      for (final metric in report.metrics) {
        final value = metric.value!;
        switch (value) {
          case ScalarMetricValue(:final value):
            expect(value.isFinite, isTrue, reason: metric.id);
          case PercentageMetricValue(:final value):
            expect(value, inInclusiveRange(0, 1), reason: metric.id);
          case DurationMetricValue(:final value):
            expect(value.isNegative, isFalse, reason: metric.id);
          default:
            fail('Unexpected pitch metric value type: ${value.runtimeType}');
        }
      }
    }
  });
}

PitchFrame _frameOnStableCurve({
  required double baseFrequency,
  required double cents,
  required double confidence,
  required int index,
}) {
  final frequency = baseFrequency * math.pow(2, cents / 1200).toDouble();
  final midi = (69 + 12 * math.log(frequency / 440) / math.ln2).round().clamp(
    0,
    127,
  );
  return PitchFrame(
    time: Duration(milliseconds: index * 10),
    frequencyHz: frequency,
    midiNote: midi,
    confidence: confidence,
  );
}
