import 'dart:math' as math;

import 'package:strumsight/core/geometry/guitar_space.dart';
import '../geometry/guitar_landmark_mapper.dart';
import '../landmarks/hand_landmarks.dart';
import '../landmarks/hand_track.dart';
import 'metric_definition.dart';
import 'metric_observation.dart';

/// One timestamped fretting-track sample. The role is read from [track], never
/// inferred from physical handedness.
final class FrettingFrame {
  FrettingFrame({
    required this.timestamp,
    required this.track,
    this.guitarLandmarks = const {},
  });

  final Duration timestamp;
  final HandTrack track;
  final Map<HandLandmarkId, MappedHandLandmark> guitarLandmarks;
}

/// Generic target marker used by the practice adapter in a later round.
final class FrettingTarget {
  const FrettingTarget({required this.timestamp, required this.position});
  final Duration timestamp;
  final GuitarSpacePoint position;
}

/// Pure, confidence-aware calculations for the six production proxy metrics.
final class FrettingMetricEngine {
  const FrettingMetricEngine();

  static const _requiredRaw = <FrettingMetricId, List<HandLandmarkId>>{
    FrettingMetricId.wristDeviationProxy: [
      HandLandmarkId.wrist,
      HandLandmarkId.middleMcp,
      HandLandmarkId.indexMcp,
    ],
    FrettingMetricId.fingerSpreadProxy: [
      HandLandmarkId.indexTip,
      HandLandmarkId.pinkyTip,
    ],
  };

  static const _requiredGuitar = <FrettingMetricId, List<HandLandmarkId>>{
    FrettingMetricId.handToNeckDistance: [HandLandmarkId.wrist],
    FrettingMetricId.chordChangeTravel: [HandLandmarkId.wrist],
    FrettingMetricId.readyPositionTime: [HandLandmarkId.wrist],
    FrettingMetricId.positionStability: [HandLandmarkId.wrist],
  };

  MetricObservation wristDeviationProxy(
    Iterable<FrettingFrame> samples, {
    bool geometryLost = false,
  }) => _rawAngle(samples, FrettingMetricId.wristDeviationProxy);

  MetricObservation handToNeckDistance(
    Iterable<FrettingFrame> samples, {
    bool geometryLost = false,
  }) => _guitarSingle(
    samples,
    FrettingMetricId.handToNeckDistance,
    geometryLost,
    (p) => p.v.abs(),
  );

  MetricObservation chordChangeTravel(
    Iterable<FrettingFrame> samples, {
    bool geometryLost = false,
  }) {
    if (geometryLost) return MetricObservation.notObservable();
    final points = _points(samples, FrettingMetricId.chordChangeTravel);
    if (points.length < 2) return MetricObservation.notObservable();
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += points[i - 1].distanceTo(points[i]);
    }
    return _valueWithConfidence(
      total,
      _confidence(samples, FrettingMetricId.chordChangeTravel),
    );
  }

  MetricObservation readyPositionTime(
    Iterable<FrettingFrame> samples,
    FrettingTarget target, {
    double radius = 0.15,
    bool geometryLost = false,
  }) {
    if (geometryLost || !radius.isFinite || radius <= 0) {
      return MetricObservation.notObservable();
    }
    final before = samples
        .where((s) => s.timestamp <= target.timestamp)
        .toList();
    if (before.isEmpty) return MetricObservation.notObservable();
    for (final sample in before.reversed) {
      final point = sample.guitarLandmarks[HandLandmarkId.wrist]?.uv;
      if (point != null && point.distanceTo(target.position) <= radius) {
        return _valueWithConfidence(
          (target.timestamp.inMicroseconds - sample.timestamp.inMicroseconds)
              .toDouble(),
          _confidence(before, FrettingMetricId.readyPositionTime),
        );
      }
    }
    return MetricObservation.notObservable();
  }

  MetricObservation positionStability(
    Iterable<FrettingFrame> samples, {
    bool geometryLost = false,
  }) {
    if (geometryLost) return MetricObservation.notObservable();
    final points = _points(samples, FrettingMetricId.positionStability);
    if (points.length < 2) return MetricObservation.notObservable();
    final meanU =
        points.map((p) => p.u).reduce((a, b) => a + b) / points.length;
    final meanV =
        points.map((p) => p.v).reduce((a, b) => a + b) / points.length;
    final variance =
        points
            .map((p) => math.pow(p.u - meanU, 2) + math.pow(p.v - meanV, 2))
            .reduce((a, b) => a + b) /
        points.length;
    return _valueWithConfidence(
      math.sqrt(variance),
      _confidence(samples, FrettingMetricId.positionStability),
    );
  }

  MetricObservation fingerSpreadProxy(
    Iterable<FrettingFrame> samples, {
    bool geometryLost = false,
  }) => _rawDistance(
    samples,
    FrettingMetricId.fingerSpreadProxy,
    HandLandmarkId.indexTip,
    HandLandmarkId.pinkyTip,
  );

  MetricObservation _rawAngle(
    Iterable<FrettingFrame> input,
    FrettingMetricId id,
  ) {
    final samples = _usable(input, id);
    if (samples.isEmpty) return MetricObservation.notObservable();
    final values = <double>[];
    for (final s in samples) {
      final w = s.track.smoothedLandmarks[HandLandmarkId.wrist];
      final m = s.track.smoothedLandmarks[HandLandmarkId.middleMcp];
      final i = s.track.smoothedLandmarks[HandLandmarkId.indexMcp];
      if (w == null || m == null || i == null) continue;
      final ax = m.x - w.x, ay = m.y - w.y;
      final bx = i.x - w.x, by = i.y - w.y;
      final denominator =
          math.sqrt(ax * ax + ay * ay) * math.sqrt(bx * bx + by * by);
      if (denominator > 0 && denominator.isFinite) {
        values.add(
          math.acos((ax * bx + ay * by) / denominator).clamp(0.0, math.pi),
        );
      }
    }
    if (values.isEmpty) return MetricObservation.notObservable();
    return _valueWithConfidence(
      values.reduce((a, b) => a + b) / values.length,
      _confidence(samples, id),
    );
  }

  MetricObservation _rawDistance(
    Iterable<FrettingFrame> input,
    FrettingMetricId id,
    HandLandmarkId a,
    HandLandmarkId b,
  ) {
    final samples = _usable(input, id);
    final values = <double>[];
    for (final s in samples) {
      final p = s.track.smoothedLandmarks[a], q = s.track.smoothedLandmarks[b];
      if (p != null && q != null)
        values.add(math.sqrt(math.pow(p.x - q.x, 2) + math.pow(p.y - q.y, 2)));
    }
    if (values.isEmpty) return MetricObservation.notObservable();
    return _valueWithConfidence(
      values.reduce((a, b) => a + b) / values.length,
      _confidence(samples, id),
    );
  }

  MetricObservation _guitarSingle(
    Iterable<FrettingFrame> input,
    FrettingMetricId id,
    bool lost,
    double Function(GuitarSpacePoint) read,
  ) {
    if (lost) return MetricObservation.notObservable();
    final points = _points(input, id);
    if (points.isEmpty) return MetricObservation.notObservable();
    return _valueWithConfidence(
      points.map(read).reduce((a, b) => a + b) / points.length,
      _confidence(input, id),
    );
  }

  List<GuitarSpacePoint> _points(
    Iterable<FrettingFrame> input,
    FrettingMetricId id,
  ) => _usable(input, id)
      .map((s) => s.guitarLandmarks[HandLandmarkId.wrist]?.uv)
      .whereType<GuitarSpacePoint>()
      .toList();

  List<FrettingFrame> _usable(
    Iterable<FrettingFrame> input,
    FrettingMetricId id,
  ) => input
      .where((s) => s.track.role == HandRole.fretting)
      .where((s) => _visibility(s, id) >= definitionFor(id).minimumVisibility)
      .toList();

  double _visibility(FrettingFrame sample, FrettingMetricId id) {
    final ids = _requiredRaw[id] ?? _requiredGuitar[id]!;
    final values = ids.map(
      (landmark) =>
          sample.guitarLandmarks[landmark]?.confidence ??
          sample.track.smoothedLandmarks[landmark]?.visibility ??
          0.0,
    );
    return values.reduce(math.min);
  }

  double _confidence(Iterable<FrettingFrame> samples, FrettingMetricId id) {
    final usable = samples
        .where((s) => s.track.role == HandRole.fretting)
        .toList();
    if (usable.isEmpty) return 0;
    return usable.map((s) => _visibility(s, id)).reduce((a, b) => a + b) /
        usable.length;
  }

  MetricObservation _valueWithConfidence(double value, double confidence) =>
      MetricObservation.observable(value: value, confidence: confidence);

  static MetricDefinition definitionFor(FrettingMetricId id) =>
      frettingMetricDefinitions.firstWhere((definition) => definition.id == id);
}

final List<MetricDefinition> frettingMetricDefinitions = List.unmodifiable(
  <MetricDefinition>[
    for (final entry in <FrettingMetricId, double>{
      FrettingMetricId.wristDeviationProxy: 0.60,
      FrettingMetricId.handToNeckDistance: 0.60,
      FrettingMetricId.chordChangeTravel: 0.65,
      FrettingMetricId.readyPositionTime: 0.65,
      FrettingMetricId.positionStability: 0.65,
      FrettingMetricId.fingerSpreadProxy: 0.70,
    }.entries)
      MetricDefinition(
        id: entry.key,
        minimumVisibility: entry.value,
        window: const Duration(milliseconds: 500),
        confidenceFormula: 'mean(minimum landmark confidence)',
        requiredCapability:
            entry.key == FrettingMetricId.wristDeviationProxy ||
                entry.key == FrettingMetricId.fingerSpreadProxy
            ? FrettingCapability.handTracking
            : FrettingCapability.guitarRelativeTracking,
      ),
  ],
);
