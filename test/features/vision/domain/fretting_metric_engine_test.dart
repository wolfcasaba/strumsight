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
      id: 1,
      handedness: Handedness.left,
      role: HandRole.fretting,
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
    final result = engine.readyPositionTime(
      [frame(0, u: 0.1), frame(200, u: 0.4)],
      FrettingTarget(
        timestamp: Duration(milliseconds: 500),
        position: GuitarSpacePoint(0.4, 0),
      ),
    );
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
    final picking = frame(0).track;
    final result = engine.wristDeviationProxy([
      FrettingFrame(
        timestamp: Duration.zero,
        track: HandTrack(
          id: picking.id,
          handedness: picking.handedness,
          role: HandRole.picking,
          status: picking.status,
          smoothedLandmarks: picking.smoothedLandmarks,
          firstFrameIndex: 0,
          lastSeenFrameIndex: 0,
        ),
      ),
    ]);
    expect(result.observability, MetricObservability.notObservable);
  });
}
