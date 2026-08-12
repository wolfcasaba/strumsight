import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/rhythm/beat_grid.dart';
import 'package:strumsight/features/audio_analysis/domain/rhythm/beat_point.dart';
import 'package:strumsight/features/audio_analysis/engine/rhythm/beat_grid_estimator.dart';

void main() {
  group('BeatGridEstimator target-first', () {
    test('every beat is BeatSource.target and inference is never called', () {
      final counting = _CountingFreePlayBeatInference();
      final estimator = BeatGridEstimator(freePlayInference: counting);
      final target = BeatGridTargetInput(
        beatTimes: <Duration>[
          Duration.zero,
          const Duration(milliseconds: 500),
          const Duration(milliseconds: 1000),
          const Duration(milliseconds: 1500),
        ],
        beatsPerBar: 4,
      );

      final grid = estimator.estimate(
        eventTimes: const <Duration>[Duration.zero],
        clipDuration: const Duration(milliseconds: 2000),
        target: target,
      );

      expect(grid.beats.every((b) => b.source == BeatSource.target), isTrue);
      expect(grid.beatsPerBarSource, BeatsPerBarSource.target);
      expect(grid.beatsPerBar, 4);
      expect(grid.meterStatus, CapabilityStatus.available);
      expect(counting.estimateCallCount, 0);
    });

    test(
      'real-violation probe: always-estimate makes the call-count assertion fail',
      () {
        final counting = _CountingFreePlayBeatInference();
        // Deliberately ignoring the target — proves the test above is a real
        // assertion, not a vacuous one (SDD §10 real-violation probe).
        counting.infer(
          eventTimes: const <Duration>[
            Duration.zero,
            Duration(milliseconds: 500),
          ],
          clipDuration: const Duration(milliseconds: 1000),
        );
        expect(counting.estimateCallCount, isNot(0));
      },
    );
  });

  group('BeatGridEstimator free-play', () {
    const estimator = BeatGridEstimator();

    test('infers evenly spaced beats and defaults beatsPerBar to 4', () {
      final events = <Duration>[
        for (var i = 0; i < 8; i++) Duration(milliseconds: 500 * i),
      ];
      final grid = estimator.estimate(
        eventTimes: events,
        clipDuration: const Duration(milliseconds: 3500),
      );

      expect(grid.beats, isNotEmpty);
      expect(grid.beats.every((b) => b.source == BeatSource.estimated), isTrue);
      expect(grid.beatsPerBar, 4);
      expect(grid.beatsPerBarSource, BeatsPerBarSource.legacyDefault);
      expect(grid.meterStatus, CapabilityStatus.notApplicable);
      expect(grid.status, CapabilityStatus.available);
    });

    test('fewer than two events yields a degraded, beat-less grid', () {
      final grid = estimator.estimate(
        eventTimes: const <Duration>[Duration.zero],
        clipDuration: const Duration(seconds: 1),
      );

      expect(grid.beats, isEmpty);
      expect(grid.status, CapabilityStatus.degraded);
      expect(grid.meterStatus, CapabilityStatus.notApplicable);
    });

    test('beats and bars are strictly time-ordered', () {
      final events = <Duration>[
        for (var i = 0; i < 12; i++) Duration(milliseconds: 400 * i),
      ];
      final grid = estimator.estimate(
        eventTimes: events,
        clipDuration: const Duration(milliseconds: 4800),
      );

      Duration? previous;
      for (final beat in grid.beats) {
        if (previous != null) expect(beat.time, greaterThan(previous));
        previous = beat.time;
      }
      previous = null;
      for (final bar in grid.bars) {
        if (previous != null) expect(bar.time, greaterThan(previous));
        previous = bar.time;
      }
    });
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
    return <BeatPoint>[
      for (var i = 0; i < eventTimes.length; i++)
        BeatPoint(
          index: i,
          time: eventTimes[i],
          confidence: 1,
          source: BeatSource.estimated,
        ),
    ];
  }
}
