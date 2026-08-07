// E05-R14 — Posture baseline collector + raw posture observation models
// (ADR 0186 §Döntés 5, kör-brief §5.5).
//
// A baseline KIZÁRÓLAG jó setup-quality (E05-R09 `VisionMetricState.good` +
// numerikus küszöb) és elegendő látható időtartam mellett jöhet létre.
// Részleges ablakból NINCS baseline „hogy legyen valami" — ilyenkor a
// későbbi posture-megfigyelés `notObservable`.
//
// A drift/quality modellek NYERS mértékek (baseline-hoz viszonyított,
// vállszélességgel normalizált delta) — NEM posture safety policy és NEM
// „jó/rossz testtartás" ítélet; az az E05-R20 dolga.

library;

import 'dart:math' as math;

import '../quality/vision_frame_quality.dart';
import 'pose_landmarks.dart';

/// Tunable gate for [PostureBaselineCollector].
///
/// Every limit is explicit: a caller changing a threshold must say so at the
/// call site (the `QualityThresholds` convention).
final class PostureBaselineConfig {
  const PostureBaselineConfig({
    this.minimumVisibleDuration = const Duration(seconds: 3),
    this.minimumSampleCount = 3,
    this.minimumQualityScore = 0.7,
    this.minimumLandmarkVisibility = 0.5,
    this.requiredIds = const <PoseLandmarkId>{
      PoseLandmarkId.leftShoulder,
      PoseLandmarkId.rightShoulder,
    },
  }) : assert(minimumSampleCount >= 1),
       assert(minimumQualityScore >= 0 && minimumQualityScore <= 1),
       assert(minimumLandmarkVisibility >= 0 && minimumLandmarkVisibility <= 1);

  /// How long an uninterrupted, gate-passing window must last.
  final Duration minimumVisibleDuration;

  /// How many gate-passing samples the window must contain.
  final int minimumSampleCount;

  /// Numeric setup-quality floor, on top of the categorical
  /// `VisionMetricState.good` requirement.
  final double minimumQualityScore;

  /// Per-landmark visibility floor — a point below it is treated as absent.
  final double minimumLandmarkVisibility;

  /// Landmarks that MUST be present in every accepted sample.
  final Set<PoseLandmarkId> requiredIds;
}

/// A completed personal posture baseline: the per-landmark mean position of
/// an accepted window, plus the raw window statistics it was built from.
final class PostureBaseline {
  PostureBaseline({
    required Map<PoseLandmarkId, PoseLandmarkPoint> reference,
    required this.sampleCount,
    required this.durationUs,
    required this.shoulderSpan,
  }) : _reference = Map<PoseLandmarkId, PoseLandmarkPoint>.unmodifiable(
         reference,
       );

  final Map<PoseLandmarkId, PoseLandmarkPoint> _reference;

  /// Number of gate-passing samples averaged into this baseline.
  final int sampleCount;

  /// Wall time covered by the accepted window, in microseconds.
  final int durationUs;

  /// Mean shoulder distance in normalized frame units — the scale the drift
  /// model normalizes by. `0` when both shoulders were never present.
  final double shoulderSpan;

  PoseLandmarkPoint? byId(PoseLandmarkId id) => _reference[id];

  List<PoseLandmarkId> get presentIds => PoseLandmarkId.values
      .where(_reference.containsKey)
      .toList(growable: false);
}

/// Raw, judgement-free posture observation against a [PostureBaseline].
///
/// `driftById` holds the shoulder-span-normalized euclidean distance between
/// the current landmark and its baseline reference. No threshold, cue or
/// verdict is attached — interpretation is E05-R20's job.
final class PostureObservation {
  PostureObservation._({
    required this.state,
    required Map<PoseLandmarkId, double> driftById,
    required this.maxDrift,
    required this.meanDrift,
  }) : _driftById = Map<PoseLandmarkId, double>.unmodifiable(driftById);

  /// The explicit "we cannot tell" observation — no baseline, no observable
  /// pose, or no landmark shared with the baseline.
  factory PostureObservation.notObservable() => PostureObservation._(
    state: VisionMetricState.notObservable,
    driftById: const <PoseLandmarkId, double>{},
    maxDrift: 0,
    meanDrift: 0,
  );

  final VisionMetricState state;
  final Map<PoseLandmarkId, double> _driftById;

  /// Largest per-landmark normalized drift in this observation.
  final double maxDrift;

  /// Mean per-landmark normalized drift in this observation.
  final double meanDrift;

  double? driftFor(PoseLandmarkId id) => _driftById[id];

  int get comparedLandmarkCount => _driftById.length;
}

/// Collects gate-passing pose samples into a personal [PostureBaseline].
///
/// Any sample failing the gate RESETS the window: a baseline is never built
/// from a partial or interrupted observation (kör-brief §5.5).
final class PostureBaselineCollector {
  PostureBaselineCollector({this.config = const PostureBaselineConfig()});

  final PostureBaselineConfig config;

  final List<PoseLandmarks> _window = <PoseLandmarks>[];
  PostureBaseline? _baseline;

  /// The completed baseline, or `null` while no accepted window exists.
  PostureBaseline? get baseline => _baseline;

  /// Number of samples currently held in the open window.
  int get windowSampleCount => _window.length;

  /// Feeds one frame. Returns the baseline if this call completed one,
  /// otherwise `null`.
  ///
  /// [overallQuality] is the E05-R09 categorical setup state and
  /// [qualityScore] its numeric companion in `[0, 1]`; both must clear the
  /// gate or the window resets.
  PostureBaseline? add({
    required PoseLandmarks pose,
    required VisionMetricState overallQuality,
    required double qualityScore,
  }) {
    if (!_accepts(
      pose: pose,
      overallQuality: overallQuality,
      qualityScore: qualityScore,
    )) {
      _window.clear();
      return null;
    }
    _window.add(pose);
    final durationUs = _window.last.timestampUs - _window.first.timestampUs;
    if (_window.length < config.minimumSampleCount ||
        durationUs < config.minimumVisibleDuration.inMicroseconds) {
      return null;
    }
    final completed = _average(_window, durationUs);
    _baseline = completed;
    return completed;
  }

  /// Discards the open window and any completed baseline.
  void reset() {
    _window.clear();
    _baseline = null;
  }

  /// Raw drift of [pose] against the completed baseline.
  ///
  /// Returns [PostureObservation.notObservable] when there is no baseline,
  /// the pose is not observable, or no landmark is shared.
  PostureObservation observe(PoseLandmarks pose) {
    final reference = _baseline;
    if (reference == null ||
        pose.observability == PoseObservability.notObservable) {
      return PostureObservation.notObservable();
    }
    final scale = reference.shoulderSpan > 0 ? reference.shoulderSpan : 1.0;
    final drifts = <PoseLandmarkId, double>{};
    for (final id in reference.presentIds) {
      final current = pose.byId(id);
      final anchor = reference.byId(id);
      if (current == null || anchor == null) continue;
      if (current.visibility < config.minimumLandmarkVisibility) continue;
      final dx = current.x - anchor.x;
      final dy = current.y - anchor.y;
      drifts[id] = math.sqrt(dx * dx + dy * dy) / scale;
    }
    if (drifts.isEmpty) return PostureObservation.notObservable();
    final values = drifts.values.toList(growable: false);
    return PostureObservation._(
      state: VisionMetricState.good,
      driftById: drifts,
      maxDrift: values.reduce(math.max),
      meanDrift: values.reduce((a, b) => a + b) / values.length,
    );
  }

  bool _accepts({
    required PoseLandmarks pose,
    required VisionMetricState overallQuality,
    required double qualityScore,
  }) {
    if (overallQuality != VisionMetricState.good) return false;
    if (!qualityScore.isFinite || qualityScore < config.minimumQualityScore) {
      return false;
    }
    if (pose.observability == PoseObservability.notObservable) return false;
    for (final id in config.requiredIds) {
      final point = pose.byId(id);
      if (point == null ||
          point.visibility < config.minimumLandmarkVisibility) {
        return false;
      }
    }
    if (_window.isNotEmpty && pose.timestampUs < _window.last.timestampUs) {
      return false;
    }
    return true;
  }

  PostureBaseline _average(List<PoseLandmarks> window, int durationUs) {
    final sums = <PoseLandmarkId, List<double>>{};
    final counts = <PoseLandmarkId, int>{};
    for (final sample in window) {
      for (final id in sample.presentIds) {
        final point = sample.byId(id)!;
        if (point.visibility < config.minimumLandmarkVisibility) continue;
        final accumulator = sums.putIfAbsent(id, () => <double>[0, 0, 0, 0]);
        accumulator[0] += point.x;
        accumulator[1] += point.y;
        accumulator[2] += point.z;
        accumulator[3] += point.visibility;
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    final reference = <PoseLandmarkId, PoseLandmarkPoint>{};
    for (final entry in sums.entries) {
      final count = counts[entry.key]!;
      reference[entry.key] = PoseLandmarkPoint(
        x: entry.value[0] / count,
        y: entry.value[1] / count,
        z: entry.value[2] / count,
        visibility: entry.value[3] / count,
      );
    }
    final left = reference[PoseLandmarkId.leftShoulder];
    final right = reference[PoseLandmarkId.rightShoulder];
    final span = (left == null || right == null)
        ? 0.0
        : math.sqrt(
            math.pow(left.x - right.x, 2) + math.pow(left.y - right.y, 2),
          );
    return PostureBaseline(
      reference: reference,
      sampleCount: window.length,
      durationUs: durationUs,
      shoulderSpan: span,
    );
  }
}
