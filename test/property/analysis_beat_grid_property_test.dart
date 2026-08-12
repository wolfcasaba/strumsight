import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/rhythm/beat_grid.dart';
import 'package:strumsight/features/audio_analysis/domain/rhythm/beat_point.dart';
import 'package:strumsight/features/audio_analysis/engine/rhythm/beat_grid_estimator.dart';
import 'package:strumsight/features/audio_analysis/engine/rhythm/tempo_curve_builder.dart';

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  final random = Random(seed);
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  const estimator = BeatGridEstimator();
  const builder = TempoCurveBuilder();

  test(
    'property: free-play beat grid and tempo curve stay ordered and finite',
    () {
      for (var trial = 0; trial < 100; trial++) {
        final eventCount = 2 + random.nextInt(40);
        final events = <Duration>[];
        var micros = 0;
        for (var i = 0; i < eventCount; i++) {
          events.add(Duration(microseconds: micros));
          micros += 20000 + random.nextInt(980000);
        }
        final clipDuration = Duration(microseconds: micros + 500000);

        final grid = estimator.estimate(
          eventTimes: events,
          clipDuration: clipDuration,
        );
        final curve = builder.build(
          eventTimes: events,
          clipDuration: clipDuration,
        );

        Duration? previousBeat;
        for (final beat in grid.beats) {
          expect(
            beat.time,
            greaterThanOrEqualTo(Duration.zero),
            reason: 'seed=$seed trial=$trial',
          );
          if (previousBeat != null) {
            expect(
              beat.time,
              greaterThan(previousBeat),
              reason: 'seed=$seed trial=$trial',
            );
          }
          previousBeat = beat.time;
          expect(
            beat.confidence,
            inInclusiveRange(0, 1),
            reason: 'seed=$seed trial=$trial',
          );
          expect(
            beat.confidence.isFinite,
            isTrue,
            reason: 'seed=$seed trial=$trial',
          );
        }

        Duration? previousBar;
        for (final bar in grid.bars) {
          if (previousBar != null) {
            expect(
              bar.time,
              greaterThan(previousBar),
              reason: 'seed=$seed trial=$trial',
            );
          }
          previousBar = bar.time;
        }

        Duration? previousPoint;
        for (final point in curve.points) {
          if (previousPoint != null) {
            expect(
              point.time,
              greaterThan(previousPoint),
              reason: 'seed=$seed trial=$trial',
            );
          }
          previousPoint = point.time;
          expect(point.bpm.isFinite, isTrue, reason: 'seed=$seed trial=$trial');
          expect(
            point.bpm,
            inInclusiveRange(0.0000001, 400),
            reason: 'seed=$seed trial=$trial',
          );
          expect(
            point.confidence,
            inInclusiveRange(0, 1),
            reason: 'seed=$seed trial=$trial',
          );
        }

        expect(
          curve.legacyBpm.isFinite,
          isTrue,
          reason: 'seed=$seed trial=$trial',
        );
        expect(
          curve.legacyBpm,
          inInclusiveRange(0, 300),
          reason: 'seed=$seed trial=$trial',
        );
        if (curve.medianBpm != null) {
          expect(
            curve.medianBpm!.isFinite,
            isTrue,
            reason: 'seed=$seed trial=$trial',
          );
          expect(
            curve.medianBpm!,
            inInclusiveRange(0.0000001, 400),
            reason: 'seed=$seed trial=$trial',
          );
        }
        for (final hypothesis in curve.hypotheses) {
          expect(
            hypothesis.confidence,
            inInclusiveRange(0, 1),
            reason: 'seed=$seed trial=$trial',
          );
        }
      }
    },
  );

  test('property: a supplied target timebase is always authoritative', () {
    for (var trial = 0; trial < 50; trial++) {
      final beatCount = 2 + random.nextInt(20);
      final beatTimes = <Duration>[];
      var micros = 0;
      for (var i = 0; i < beatCount; i++) {
        beatTimes.add(Duration(microseconds: micros));
        micros += 100000 + random.nextInt(500000);
      }
      final beatsPerBar = 2 + random.nextInt(6);
      final target = BeatGridTargetInput(
        beatTimes: beatTimes,
        beatsPerBar: beatsPerBar,
      );
      final counting = _CountingFreePlayBeatInference();
      final grid = BeatGridEstimator(freePlayInference: counting).estimate(
        eventTimes: const <Duration>[],
        clipDuration: Duration(microseconds: micros + 500000),
        target: target,
      );

      expect(
        grid.beats.every((b) => b.source == BeatSource.target),
        isTrue,
        reason: 'seed=$seed trial=$trial',
      );
      expect(counting.estimateCallCount, 0, reason: 'seed=$seed trial=$trial');
    }
  });
}

final class _CountingFreePlayBeatInference implements FreePlayBeatInference {
  int estimateCallCount = 0;

  @override
  List<BeatPoint> infer({
    required List<Duration> eventTimes,
    required Duration clipDuration,
  }) {
    estimateCallCount++;
    return const <BeatPoint>[];
  }
}
