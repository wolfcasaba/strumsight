// E05-R14 §6 — Posture baseline mátrix + nyers drift-megfigyelés.
//
// A §6 mátrix mindkét tengelye KÜLÖN cellákkal, a határ mindkét oldalával:
//   setup-quality a küszöb ALATT / RAJTA / FÖLÖTT
//     × látható időtartam a minimum ALATT / RAJTA / FÖLÖTT.
// Baseline KIZÁRÓLAG a „rajta vagy fölötte × rajta vagy fölötte" cellákban
// jön létre; minden más cellában nincs baseline, és a posture-megfigyelés
// `notObservable` (kör-brief §5.5 — részleges ablakból nincs baseline).

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/landmarks/pose_landmarks.dart';
import 'package:strumsight/features/vision/domain/landmarks/posture_baseline.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';

const _config = PostureBaselineConfig(
  minimumVisibleDuration: Duration(seconds: 3),
  minimumSampleCount: 2,
  minimumQualityScore: 0.7,
);

PoseLandmarks _poseAt(
  int timestampUs, {
  double offsetY = 0,
  double visibility = 0.9,
}) => mapRawPoseLandmarks(
  timestampUs: timestampUs,
  raw: <RawPoseLandmark>[
    RawPoseLandmark(
      name: 'left_shoulder',
      x: 0.40,
      y: 0.30 + offsetY,
      z: 0,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'right_shoulder',
      x: 0.60,
      y: 0.30 + offsetY,
      z: 0,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'left_hip',
      x: 0.44,
      y: 0.70 + offsetY,
      z: 0,
      visibility: visibility,
    ),
    RawPoseLandmark(
      name: 'right_hip',
      x: 0.56,
      y: 0.70 + offsetY,
      z: 0,
      visibility: visibility,
    ),
  ],
);

/// Feeds a two-sample window covering [durationUs] at [qualityScore].
PostureBaselineCollector _feedWindow({
  required int durationUs,
  required double qualityScore,
  VisionMetricState overallQuality = VisionMetricState.good,
}) {
  final collector = PostureBaselineCollector(config: _config);
  collector.add(
    pose: _poseAt(0),
    overallQuality: overallQuality,
    qualityScore: qualityScore,
  );
  collector.add(
    pose: _poseAt(durationUs),
    overallQuality: overallQuality,
    qualityScore: qualityScore,
  );
  return collector;
}

void main() {
  group('baseline matrix — quality × visible duration', () {
    const belowDuration = 2000000; // 2 s — under the 3 s minimum
    const atDuration = 3000000; // exactly at the minimum
    const aboveDuration = 4000000; // above the minimum

    const qualityCells = <String, double>{
      'below threshold': 0.6,
      'at threshold': 0.7,
      'above threshold': 0.8,
    };
    const durationCells = <String, int>{
      'below minimum': belowDuration,
      'at minimum': atDuration,
      'above minimum': aboveDuration,
    };

    for (final quality in qualityCells.entries) {
      for (final duration in durationCells.entries) {
        final expectBaseline =
            quality.value >= _config.minimumQualityScore &&
            duration.value >= _config.minimumVisibleDuration.inMicroseconds;
        test('quality ${quality.key} × duration ${duration.key} → '
            '${expectBaseline ? 'baseline' : 'no baseline'}', () {
          final collector = _feedWindow(
            durationUs: duration.value,
            qualityScore: quality.value,
          );
          if (expectBaseline) {
            expect(collector.baseline, isNotNull);
            expect(collector.baseline!.sampleCount, 2);
            expect(collector.baseline!.durationUs, duration.value);
            expect(
              collector.observe(_poseAt(duration.value)).state,
              VisionMetricState.good,
            );
          } else {
            expect(collector.baseline, isNull);
            expect(
              collector.observe(_poseAt(duration.value)).state,
              VisionMetricState.notObservable,
              reason: 'without a baseline, posture must be notObservable',
            );
          }
        });
      }
    }
  });

  test('a non-good categorical quality state blocks the baseline', () {
    final collector = _feedWindow(
      durationUs: 4000000,
      qualityScore: 0.95,
      overallQuality: VisionMetricState.needsImprovement,
    );
    expect(collector.baseline, isNull);
  });

  test('notObservable quality state blocks the baseline', () {
    final collector = _feedWindow(
      durationUs: 4000000,
      qualityScore: 0.95,
      overallQuality: VisionMetricState.notObservable,
    );
    expect(collector.baseline, isNull);
  });

  test('an interrupted window is discarded, not partially reused', () {
    final collector = PostureBaselineCollector(config: _config);
    collector.add(
      pose: _poseAt(0),
      overallQuality: VisionMetricState.good,
      qualityScore: 0.9,
    );
    // A bad frame in the middle resets the window.
    collector.add(
      pose: _poseAt(1000000),
      overallQuality: VisionMetricState.needsImprovement,
      qualityScore: 0.9,
    );
    expect(collector.windowSampleCount, 0);
    collector.add(
      pose: _poseAt(2000000),
      overallQuality: VisionMetricState.good,
      qualityScore: 0.9,
    );
    // Only 2 s of clean window since the reset → still no baseline.
    collector.add(
      pose: _poseAt(4000000),
      overallQuality: VisionMetricState.good,
      qualityScore: 0.9,
    );
    expect(
      collector.baseline,
      isNull,
      reason: 'the reset restarts the clock; 2 s < 3 s minimum',
    );
  });

  test('a pose without the required landmarks never feeds the baseline', () {
    final collector = PostureBaselineCollector(config: _config);
    final headOnly = mapRawPoseLandmarks(
      timestampUs: 0,
      raw: const <RawPoseLandmark>[
        RawPoseLandmark(name: 'neck', x: 0.5, y: 0.26, z: 0, visibility: 0.9),
      ],
    );
    collector.add(
      pose: headOnly,
      overallQuality: VisionMetricState.good,
      qualityScore: 0.9,
    );
    collector.add(
      pose: headOnly,
      overallQuality: VisionMetricState.good,
      qualityScore: 0.9,
    );
    expect(collector.baseline, isNull);
    expect(collector.windowSampleCount, 0);
  });

  test('low-visibility landmarks are treated as absent', () {
    final collector = PostureBaselineCollector(config: _config);
    collector.add(
      pose: _poseAt(0, visibility: 0.1),
      overallQuality: VisionMetricState.good,
      qualityScore: 0.9,
    );
    collector.add(
      pose: _poseAt(4000000, visibility: 0.1),
      overallQuality: VisionMetricState.good,
      qualityScore: 0.9,
    );
    expect(collector.baseline, isNull);
  });

  group('raw posture observation', () {
    PostureBaselineCollector goodCollector() =>
        _feedWindow(durationUs: 4000000, qualityScore: 0.9);

    test('baseline averages the accepted window and records its span', () {
      final collector = goodCollector();
      final baseline = collector.baseline!;
      expect(baseline.presentIds, hasLength(4));
      expect(
        baseline.byId(PoseLandmarkId.leftShoulder)!.x,
        closeTo(0.40, 1e-9),
      );
      expect(baseline.shoulderSpan, closeTo(0.20, 1e-9));
    });

    test('an unchanged pose drifts by zero', () {
      final observation = goodCollector().observe(_poseAt(5000000));
      expect(observation.state, VisionMetricState.good);
      expect(observation.comparedLandmarkCount, 4);
      expect(observation.maxDrift, closeTo(0, 1e-9));
      expect(observation.meanDrift, closeTo(0, 1e-9));
    });

    test('a shifted pose drifts by the span-normalized offset', () {
      // 0.04 normalized-frame shift over a 0.20 shoulder span → 0.2.
      final observation = goodCollector().observe(
        _poseAt(5000000, offsetY: 0.04),
      );
      expect(observation.maxDrift, closeTo(0.2, 1e-9));
      expect(observation.meanDrift, closeTo(0.2, 1e-9));
      expect(
        observation.driftFor(PoseLandmarkId.leftShoulder),
        closeTo(0.2, 1e-9),
      );
      expect(
        observation.driftFor(PoseLandmarkId.neckReference),
        isNull,
        reason: 'a landmark absent from the baseline has no drift value',
      );
    });

    test('a notObservable pose yields a notObservable observation', () {
      final observation = goodCollector().observe(
        PoseLandmarks.notObservable(timestampUs: 6000000),
      );
      expect(observation.state, VisionMetricState.notObservable);
      expect(observation.comparedLandmarkCount, 0);
    });

    test('reset removes the baseline', () {
      final collector = goodCollector()..reset();
      expect(collector.baseline, isNull);
      expect(
        collector.observe(_poseAt(7000000)).state,
        VisionMetricState.notObservable,
      );
    });
  });
}
