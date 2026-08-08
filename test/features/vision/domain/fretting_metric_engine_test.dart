import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/geometry/guitar_space.dart';
import 'package:strumsight/features/vision/domain/geometry/guitar_landmark_mapper.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_track.dart';
import 'package:strumsight/features/vision/domain/metrics/fretting_metric_engine.dart';
import 'package:strumsight/features/vision/domain/metrics/metric_observation.dart';

HandLandmarkPoint point(double x, double y, [double visibility = 1]) =>
    HandLandmarkPoint(x: x, y: y, z: 0, visibility: visibility);

FrettingFrame frame(
  int ms, {
  double visibility = 1,
  double u = 0.4,
  double v = 0,
  HandRole role = HandRole.fretting,
  int id = 1,
  Handedness handedness = Handedness.left,
}) {
  final raw = <HandLandmarkId, HandLandmarkPoint>{
    HandLandmarkId.wrist: point(0.4, 0.4, visibility),
    HandLandmarkId.middleMcp: point(0.5, 0.4, visibility),
    HandLandmarkId.indexMcp: point(0.5, 0.5, visibility),
    HandLandmarkId.indexTip: point(0.55, 0.55, visibility),
    HandLandmarkId.pinkyTip: point(0.35, 0.55, visibility),
  };
  return FrettingFrame(
    timestamp: Duration(milliseconds: ms),
    track: HandTrack(
      id: id,
      handedness: handedness,
      role: role,
      status: TrackStatus.active,
      smoothedLandmarks: raw,
      firstFrameIndex: ms,
      lastSeenFrameIndex: ms,
    ),
    guitarLandmarks: {
      HandLandmarkId.wrist: MappedHandLandmark(
        uv: GuitarSpacePoint(u, v),
        confidence: visibility,
      ),
    },
  );
}

/// A frame whose wrist / middleMcp / indexMcp can be arbitrarily placed —
/// used by degenerate tests where coincident landmarks are the point.
FrettingFrame rawFrame(
  int ms,
  Map<HandLandmarkId, HandLandmarkPoint> raw, {
  HandRole role = HandRole.fretting,
  double u = 0.4,
  double v = 0,
  double visibility = 1,
}) {
  return FrettingFrame(
    timestamp: Duration(milliseconds: ms),
    track: HandTrack(
      id: 1,
      handedness: Handedness.left,
      role: role,
      status: TrackStatus.active,
      smoothedLandmarks: raw,
      firstFrameIndex: ms,
      lastSeenFrameIndex: ms,
    ),
    guitarLandmarks: {
      HandLandmarkId.wrist: MappedHandLandmark(
        uv: GuitarSpacePoint(u, v),
        confidence: visibility,
      ),
    },
  );
}

void main() {
  const engine = FrettingMetricEngine();
  final target = FrettingTarget(
    timestamp: const Duration(milliseconds: 500),
    position: GuitarSpacePoint(0.4, 0),
  );

  // ---------------------------------------------------------------------------
  // Typical-case coverage per metric (brief §6 — at least one typical case
  // per metric; the boundary and degenerate matrices live in the groups
  // below).
  // ---------------------------------------------------------------------------

  test('wrist deviation proxy has a finite observable value', () {
    final result = engine.wristDeviationProxy([frame(0)]);
    expect(result.observability, MetricObservability.observable);
    expect(result.value, closeTo(0.785398, 0.00001));
  });

  test('hand-to-neck distance and finger spread are proxies', () {
    expect(engine.handToNeckDistance([frame(0, v: 0.25)]).value, 0.25);
    expect(engine.fingerSpreadProxy([frame(0)]).value, closeTo(0.2, 0.00001));
  });

  test('travel and stability use guitar-relative path', () {
    final samples = [frame(0, u: 0.1), frame(100, u: 0.4), frame(200, u: 0.7)];
    expect(engine.chordChangeTravel(samples).value, closeTo(0.6, 0.00001));
    expect(engine.positionStability(samples).value, closeTo(0.244949, 0.00001));
  });

  test('ready-position time is measured before a generic target', () {
    // Single in-zone sample at t=200 (u=0.4, target u=0.4 → distance 0).
    // The previous sample at t=0 is out of zone, so the contiguous run
    // starts at t=200.
    final result = engine.readyPositionTime([
      frame(0, u: 0.1),
      frame(200, u: 0.4),
    ], target);
    expect(result.value, 300000);
  });

  test('visibility below the metric threshold is not observable', () {
    final result = engine.fingerSpreadProxy([frame(0, visibility: 0.69)]);
    expect(result.observability, MetricObservability.notObservable);
    expect(result.value, isNull);
  });

  test('lost geometry prevents guitar-relative calculations', () {
    final result = engine.positionStability([
      frame(0),
      frame(100, u: 0.5),
    ], geometryLost: true);
    expect(result.observability, MetricObservability.notObservable);
  });

  test('picking-role track is never treated as fretting evidence', () {
    final result = engine.wristDeviationProxy([
      frame(0, role: HandRole.picking),
    ]);
    expect(result.observability, MetricObservability.notObservable);
  });

  // ---------------------------------------------------------------------------
  // F1 BLOCKER regressions (review E05-R18 F1) — picking-only and
  // sub-threshold-visibility-only inputs to readyPositionTime.
  // ---------------------------------------------------------------------------

  test('readyPositionTime rejects picking-role-only input (F1 regression)', () {
    final result = engine.readyPositionTime([
      frame(0, u: 0.4, role: HandRole.picking),
    ], target);
    expect(result.observability, MetricObservability.notObservable);
    expect(result.value, isNull);
  });

  test('readyPositionTime rejects sub-threshold-visibility-only input '
      '(F1 regression)', () {
    final result = engine.readyPositionTime([
      frame(0, u: 0.4, visibility: 0.10),
    ], target);
    expect(result.observability, MetricObservability.notObservable);
    expect(result.value, isNull);
  });

  // ---------------------------------------------------------------------------
  // F2 MAJOR regressions (review E05-R18 F2) — 4-sample dwell fixture
  // proves the contiguous-run algorithm returns the zone-entry time, not
  // the last-in-zone timestamp.
  // ---------------------------------------------------------------------------

  test('readyPositionTime returns the entry time of a contiguous dwell '
      '(F2 regression)', () {
    // t=0   out of zone (u=0.1 → distance 0.3)
    // t=100 in  zone (entry — distance 0)
    // t=200 in  zone
    // t=300 in  zone
    // target at t=500 → expected ready time 500 - 100 = 400 000 µs.
    final result = engine.readyPositionTime([
      frame(0, u: 0.1),
      frame(100, u: 0.4),
      frame(200, u: 0.4),
      frame(300, u: 0.4),
    ], target);
    expect(result.observability, MetricObservability.observable);
    expect(result.value, 400000);
  });

  test('readyPositionTime with no in-zone samples is not observable', () {
    final result = engine.readyPositionTime([
      frame(0, u: 0.9),
      frame(100, u: 0.9),
    ], target);
    expect(result.observability, MetricObservability.notObservable);
  });

  // ---------------------------------------------------------------------------
  // F3 MAJOR — per-metric boundary (visibility EXACTLY at minimumVisibility)
  // and degenerate (coincident landmarks / 0–1 element) tests.
  // ---------------------------------------------------------------------------

  group('boundary (visibility exactly at threshold)', () {
    test('wristDeviationProxy at 0.60 is observable', () {
      final result = engine.wristDeviationProxy([frame(0, visibility: 0.60)]);
      expect(result.observability, MetricObservability.observable);
    });

    test('handToNeckDistance at 0.60 is observable', () {
      final result = engine.handToNeckDistance([
        frame(0, v: 0.25, visibility: 0.60),
      ]);
      expect(result.observability, MetricObservability.observable);
      expect(result.value, 0.25);
    });

    test('chordChangeTravel at 0.65 is observable', () {
      final result = engine.chordChangeTravel([
        frame(0, u: 0.1, visibility: 0.65),
        frame(100, u: 0.4, visibility: 0.65),
      ]);
      expect(result.observability, MetricObservability.observable);
    });

    test('readyPositionTime at 0.65 is observable', () {
      final result = engine.readyPositionTime([
        frame(0, u: 0.4, visibility: 0.65),
      ], target);
      expect(result.observability, MetricObservability.observable);
    });

    test('positionStability at 0.65 is observable', () {
      final result = engine.positionStability([
        frame(0, u: 0.1, visibility: 0.65),
        frame(100, u: 0.4, visibility: 0.65),
      ]);
      expect(result.observability, MetricObservability.observable);
    });

    test('fingerSpreadProxy at 0.70 is observable', () {
      final result = engine.fingerSpreadProxy([frame(0, visibility: 0.70)]);
      expect(result.observability, MetricObservability.observable);
    });
  });

  group('degenerate (coincident landmarks / 0–1 element)', () {
    test(
      'wristDeviationProxy with coincident wrist/middleMcp is not observable',
      () {
        // wrist == middleMcp ⇒ denominator is 0, angle is undefined.
        final raw = <HandLandmarkId, HandLandmarkPoint>{
          HandLandmarkId.wrist: point(0.4, 0.4, 1),
          HandLandmarkId.middleMcp: point(0.4, 0.4, 1),
          HandLandmarkId.indexMcp: point(0.5, 0.5, 1),
        };
        final result = engine.wristDeviationProxy([rawFrame(0, raw)]);
        expect(result.observability, MetricObservability.notObservable);
      },
    );

    test('handToNeckDistance with empty input is not observable', () {
      final result = engine.handToNeckDistance(const <FrettingFrame>[]);
      expect(result.observability, MetricObservability.notObservable);
    });

    test('chordChangeTravel with a single sample is not observable', () {
      final result = engine.chordChangeTravel([frame(0, u: 0.4)]);
      expect(result.observability, MetricObservability.notObservable);
    });

    test('readyPositionTime with non-positive radius is not observable', () {
      final result = engine.readyPositionTime(
        [frame(0, u: 0.4)],
        target,
        radius: 0,
      );
      expect(result.observability, MetricObservability.notObservable);
    });

    test('positionStability with a single sample is not observable', () {
      final result = engine.positionStability([frame(0, u: 0.4)]);
      expect(result.observability, MetricObservability.notObservable);
    });

    test('fingerSpreadProxy with coincident indexTip/pinkyTip is observable '
        'with documented finite value 0', () {
      // Two tips at the same point ⇒ Euclidean distance exactly 0.
      // Documented finite degenerate result; notObservable would be
      // ambiguous (is the hand clenched? or are we blind?).
      final raw = <HandLandmarkId, HandLandmarkPoint>{
        HandLandmarkId.wrist: point(0.4, 0.4, 1),
        HandLandmarkId.middleMcp: point(0.5, 0.4, 1),
        HandLandmarkId.indexMcp: point(0.5, 0.5, 1),
        HandLandmarkId.indexTip: point(0.5, 0.5, 1),
        HandLandmarkId.pinkyTip: point(0.5, 0.5, 1),
      };
      final result = engine.fingerSpreadProxy([rawFrame(0, raw)]);
      expect(result.observability, MetricObservability.observable);
      expect(result.value, 0.0);
    });
  });

  // ---------------------------------------------------------------------------
  // F4 MAJOR — mirror / left-handed parity.
  //
  // WHAT THIS GROUP PROVES: the engine does not branch on
  // `HandTrack.handedness` — it may only read `role`. Two sample sequences
  // with byte-identical `role`, raw landmarks and guitar-space `(u, v)`,
  // differing ONLY in `handedness` (`left` vs `right`), must yield the same
  // value and observability for all six metrics. A regression in which the
  // engine accidentally consults `handedness` instead of / in addition to
  // `role` turns these assertions red.
  //
  // WHAT THIS GROUP DOES NOT PROVE: it does not cover the camera-mirroring
  // or the `leftHanded` setting path. That normalization is the CALLER's
  // responsibility (R13 `HandTrackAssigner` supplies the already-resolved
  // `role`; R15 supplies mirror-free guitar-space `(u, v)`) and is tested at
  // those layers. There is therefore no front/back-camera axis at this layer
  // to vary — a "4 cell" matrix here would be two duplicated pairs, not four
  // independent configurations. Hence 2 cells: the single axis that this
  // layer can actually observe.
  // ---------------------------------------------------------------------------

  group('mirror / left-handed parity (handedness axis, 2 cells)', () {
    List<FrettingFrame> trajectory(Handedness handedness) => [
      frame(0, u: 0.1, v: 0, handedness: handedness),
      frame(100, u: 0.4, v: 0, handedness: handedness),
      frame(200, u: 0.7, v: 0, handedness: handedness),
    ];

    test('metrics are invariant to HandTrack.handedness for identical '
        'role / geometry', () {
      const tolerance = 1e-5;
      final left = trajectory(Handedness.left);
      final right = trajectory(Handedness.right);
      final cellTarget = FrettingTarget(
        timestamp: const Duration(milliseconds: 500),
        position: GuitarSpacePoint(0.4, 0),
      );

      final metrics = <String, MetricObservation Function(List<FrettingFrame>)>{
        'wristDeviationProxy': engine.wristDeviationProxy,
        'handToNeckDistance': engine.handToNeckDistance,
        'chordChangeTravel': engine.chordChangeTravel,
        'positionStability': engine.positionStability,
        'fingerSpreadProxy': engine.fingerSpreadProxy,
        'readyPositionTime': (samples) =>
            engine.readyPositionTime(samples, cellTarget),
      };

      metrics.forEach((name, compute) {
        final l = compute(left);
        final r = compute(right);
        expect(
          l.observability,
          MetricObservability.observable,
          reason: '$name should be observable for the left-handed cell',
        );
        expect(
          r.observability,
          l.observability,
          reason: '$name observability parity across handedness',
        );
        expect(
          r.value!,
          closeTo(l.value!, tolerance),
          reason: '$name value parity across handedness',
        );
      });
    });
  });
}
