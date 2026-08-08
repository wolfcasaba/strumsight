// E05-R19 — Picking-hand metric engine (SDD §20).
//
// Pure-Dart calculator for the seven picking metrics (SDD §20.1 + §20.2,
// brief §3/§4). The engine reads a chronological `PickingFrame` series and
// a parallel list of audio-onset events, and produces both per-event
// trajectory observations and session-aggregate observations.
//
// **Sync gate (brief §5/2 — KÖTÖTT).** Event-level metrics
// (`strokeDirection` / `strokeAmplitude` / `strokeSpeed` / `strokeLinearity`
// / `pickingZone`) emit `notObservable` unless the injected
// `PickingSyncQuality` is `good` or `excellent`. The session aggregates
// (`downUpAsymmetry` / `beatToBeatConsistency`) are unaffected — they
// are slow enough that they can survive the same sync quality that
// poisons an event-level call. A test explicitly removes the gate to
// confirm the `poor` cell goes red (§10 valódi-sértés próba).
//
// **Direction convention (brief §5/4).** `Δv > 0 → down`,
// `Δv < 0 → up`. The guitar-space `(u, v)` is mirror-free (R15), so the
// convention does NOT need to branch on the camera-flip or
// `HandTrack.handedness`. The mirror-parity acceptance cell verifies this.
//
// **Stroke window (brief §5/3).** The pre / post constants live in
// `StrokeWindow.defaultPre` / `defaultPost`. Overlap with the next onset
// truncates the window — the engine reads the truncated window as-is.

library;

import 'dart:math' as math;

import 'package:strumsight/core/geometry/guitar_space.dart';
import 'package:strumsight/features/vision/domain/geometry/guitar_landmark_mapper.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_track.dart';

import 'metric_observation.dart';
import 'picking_metrics.dart';
import 'stroke_window.dart';

/// One timestamped picking-track sample.
final class PickingFrame implements PickingFrameLike {
  PickingFrame({
    required this.timestamp,
    required this.track,
    this.guitarLandmarks = const {},
  });

  @override
  final Duration timestamp;

  /// The smoothed picking-role hand track for this frame.
  final HandTrack track;

  /// Per-landmark guitar-space mappings. Absent IDs match the upstream
  /// `HandTrack.smoothedLandmarks` absent-IDs rule (no zero-fill).
  final Map<HandLandmarkId, MappedHandLandmark> guitarLandmarks;
}

/// Pure, confidence-aware calculations for the seven picking metrics.
final class PickingMetricEngine {
  const PickingMetricEngine();

  // -- Public API -------------------------------------------------------------

  /// Compute everything: per-event metrics + session aggregates + zone
  /// distribution. This is the single entry point most callers use; the
  /// individual metric methods below exist for unit tests that want to
  /// exercise a single calculation without spinning up the full pipeline.
  PickingSessionResult compute({
    required List<PickingFrame> frames,
    required List<PickingOnsetEvent> onsets,
    required PickingSyncQuality sync,
    StrokeWindow window = const StrokeWindow(),
  }) {
    final cuts = window.cut(frames: frames, onsets: onsets);
    final events = <PickingEventResult>[];
    final amplitudes = <double>[];
    final aggregateEvents = <PickingEventResult>[];
    for (final cut in cuts) {
      final samples = <PickingFrame>[
        for (final s in cut.samples) s as PickingFrame,
      ];
      events.add(
        _eventResult(
          samples: samples,
          onset: cut.window.onset,
          truncated: cut.window.truncated,
          sync: sync,
        ),
      );
      // Session aggregates (brief §5/2 — "csak a lassabb, aggregát
      // metrikák maradnak érvényesek" under poor / acceptable sync) are
      // computed from the RAW amplitude and direction — the per-event
      // gate is a *display* policy, not a data policy. The aggregate
      // methods themselves (`beatToBeatConsistencyFromAmplitudes`,
      // `downUpAsymmetryFromEvents`) skip gate-blocked events only when
      // the underlying values are non-finite, never on the basis of
      // `isObservable`.
      final amp = _rawAmplitude(samples);
      if (amp.isFinite && amp > 0) amplitudes.add(amp);
      aggregateEvents.add(
        _rawEventResult(samples: samples, onset: cut.window.onset),
      );
    }
    return PickingSessionResult(
      perEvent: events,
      consistency: beatToBeatConsistencyFromAmplitudes(amplitudes),
      asymmetry: downUpAsymmetryFromEvents(aggregateEvents),
      zoneDistribution: _zoneDistributionFromEvents(events),
    );
  }

  /// Internal: per-event amplitude without sync gate. Used by session
  /// aggregates, which are immune to the brief §5/2 sync gate.
  double _rawAmplitude(List<PickingFrame> samples) {
    final usable = _usableFrames(samples, PickingMetricId.strokeAmplitude);
    if (usable.length < 2) return double.nan;
    final values = _pathSegments(usable);
    if (values.isEmpty) return double.nan;
    final path = values.reduce((a, b) => a + b);
    return path.isFinite ? path : double.nan;
  }

  /// Internal: per-event observation bundle for session-aggregate use
  /// (no sync gate, no zone classification).
  PickingEventResult _rawEventResult({
    required List<PickingFrame> samples,
    required Duration onset,
  }) {
    final amp = _rawAmplitude(samples);
    final dir = _rawDirection(samples);
    final speed = _rawSpeed(samples);
    final lin = _rawLinearity(samples);
    final ampObs = amp.isFinite
        ? MetricObservation.observable(value: amp, confidence: 1.0)
        : MetricObservation.notObservable();
    final speedObs = speed.isFinite
        ? MetricObservation.observable(value: speed, confidence: 1.0)
        : MetricObservation.notObservable();
    final linObs = lin.isFinite
        ? MetricObservation.observable(value: lin, confidence: 1.0)
        : MetricObservation.notObservable();
    final dirObs = dir.isFinite
        ? MetricObservation.observable(value: dir, confidence: 1.0)
        : MetricObservation.notObservable();
    return PickingEventResult(
      direction: dirObs,
      amplitude: ampObs,
      speed: speedObs,
      linearity: linObs,
      zone: PickingZone.outsideCalibratedZone,
      truncated: false,
    );
  }

  double _rawDirection(List<PickingFrame> samples) {
    final usable = _usableFrames(samples, PickingMetricId.strokeDirection);
    if (usable.length < 2) return double.nan;
    final first = _wristUv(usable.first);
    final last = _wristUv(usable.last);
    if (first == null || last == null) return double.nan;
    final deltaV = last.v - first.v;
    if (!deltaV.isFinite) return double.nan;
    return deltaV == 0 ? 0.0 : (deltaV > 0 ? 1.0 : -1.0);
  }

  double _rawSpeed(List<PickingFrame> samples) {
    final usable = _usableFrames(samples, PickingMetricId.strokeSpeed);
    if (usable.length < 2) return double.nan;
    final first = usable.first;
    final last = usable.last;
    final durationUs =
        last.timestamp.inMicroseconds - first.timestamp.inMicroseconds;
    if (durationUs <= 0) return double.nan;
    final values = _pathSegments(usable);
    if (values.isEmpty) return double.nan;
    final path = values.reduce((a, b) => a + b);
    if (!path.isFinite) return double.nan;
    return path / (durationUs / 1e6);
  }

  double _rawLinearity(List<PickingFrame> samples) {
    final usable = _usableFrames(samples, PickingMetricId.strokeLinearity);
    if (usable.length < 2) return double.nan;
    final first = _wristUv(usable.first);
    final last = _wristUv(usable.last);
    if (first == null || last == null) return double.nan;
    final chord = _chord(first, last);
    final path = _pathSegments(usable).fold<double>(0.0, (a, b) => a + b);
    if (path <= 0 || !chord.isFinite || !path.isFinite) return double.nan;
    final linearity = chord / path;
    return linearity.clamp(0.0, 1.0).toDouble();
  }

  /// Per-event direction. `good`/`excellent` sync → observable; otherwise
  /// `notObservable`. Even with good sync, degenerate windows (single
  /// sample, coincident start/end) emit `notObservable`.
  MetricObservation strokeDirection(
    List<PickingFrame> window, {
    required PickingSyncQuality sync,
  }) {
    if (!_eventLevelAllowed(sync)) return MetricObservation.notObservable();
    final usable = _usableFrames(window, PickingMetricId.strokeDirection);
    if (usable.length < 2) return MetricObservation.notObservable();
    final first = _wristUv(usable.first);
    final last = _wristUv(usable.last);
    if (first == null || last == null) return MetricObservation.notObservable();
    final deltaV = last.v - first.v;
    if (!deltaV.isFinite) return MetricObservation.notObservable();
    // The direction value itself is a sign-coded ±1 (down = +1, up = -1).
    // Returning a numeric ±1 lets downstream code threshold / aggregate
    // without parsing the StrumDirection enum.
    final sign = deltaV == 0 ? 0.0 : (deltaV > 0 ? 1.0 : -1.0);
    return _valueWithConfidence(
      sign,
      _confidence(usable, PickingMetricId.strokeDirection),
    );
  }

  /// Per-event amplitude = total path length over the window (sum of
  /// consecutive segment distances in guitar-space). `notObservable` under
  /// `poor` / `acceptable` sync OR for degenerate windows (< 2 samples).
  MetricObservation strokeAmplitude(
    List<PickingFrame> window, {
    required PickingSyncQuality sync,
  }) {
    if (!_eventLevelAllowed(sync)) return MetricObservation.notObservable();
    final usable = _usableFrames(window, PickingMetricId.strokeAmplitude);
    if (usable.length < 2) return MetricObservation.notObservable();
    final values = _pathSegments(usable);
    if (values.isEmpty) return MetricObservation.notObservable();
    final path = values.reduce((a, b) => a + b);
    if (!path.isFinite) return MetricObservation.notObservable();
    return _valueWithConfidence(
      path,
      _confidence(usable, PickingMetricId.strokeAmplitude),
    );
  }

  /// Per-event speed = amplitude / window duration (units per second).
  MetricObservation strokeSpeed(
    List<PickingFrame> window, {
    required PickingSyncQuality sync,
  }) {
    if (!_eventLevelAllowed(sync)) return MetricObservation.notObservable();
    final usable = _usableFrames(window, PickingMetricId.strokeSpeed);
    if (usable.length < 2) return MetricObservation.notObservable();
    final first = usable.first;
    final last = usable.last;
    final durationUs =
        last.timestamp.inMicroseconds - first.timestamp.inMicroseconds;
    if (durationUs <= 0) return MetricObservation.notObservable();
    final values = _pathSegments(usable);
    if (values.isEmpty) return MetricObservation.notObservable();
    final path = values.reduce((a, b) => a + b);
    if (!path.isFinite) return MetricObservation.notObservable();
    final speed = path / (durationUs / 1e6);
    return _valueWithConfidence(
      speed,
      _confidence(usable, PickingMetricId.strokeSpeed),
    );
  }

  /// Per-event linearity = chord_length / path_length. Bounded in (0, 1].
  MetricObservation strokeLinearity(
    List<PickingFrame> window, {
    required PickingSyncQuality sync,
  }) {
    if (!_eventLevelAllowed(sync)) return MetricObservation.notObservable();
    final usable = _usableFrames(window, PickingMetricId.strokeLinearity);
    if (usable.length < 2) return MetricObservation.notObservable();
    final first = _wristUv(usable.first);
    final last = _wristUv(usable.last);
    if (first == null || last == null) return MetricObservation.notObservable();
    final chord = _chord(first, last);
    final path = _pathSegments(usable).fold<double>(0.0, (a, b) => a + b);
    if (path <= 0 || !chord.isFinite || !path.isFinite) {
      return MetricObservation.notObservable();
    }
    final linearity = chord / path;
    if (linearity > 1.0 + 1e-9) {
      // Numerical noise — path is shorter than the chord (impossible by
      // construction but the math can drift). Clamp.
      return _valueWithConfidence(
        1.0,
        _confidence(usable, PickingMetricId.strokeLinearity),
      );
    }
    return _valueWithConfidence(
      linearity.clamp(0.0, 1.0).toDouble(),
      _confidence(usable, PickingMetricId.strokeLinearity),
    );
  }

  /// Session-level aggregate: |mean(down amplitude) - mean(up amplitude)|
  /// divided by max. Range [0, 1]. Requires at least one down AND one up
  /// stroke (a one-sided session emits `notObservable`).
  MetricObservation downUpAsymmetryFromEvents(List<PickingEventResult> events) {
    final downAmps = <double>[];
    final upAmps = <double>[];
    for (final e in events) {
      final amp = e.amplitude;
      if (!amp.isObservable || amp.value == null) continue;
      final dir = e.direction;
      if (!dir.isObservable || dir.value == null) continue;
      if (dir.value! > 0) {
        downAmps.add(amp.value!);
      } else if (dir.value! < 0) {
        upAmps.add(amp.value!);
      }
    }
    if (downAmps.isEmpty || upAmps.isEmpty) {
      return MetricObservation.notObservable();
    }
    final downMean = downAmps.reduce((a, b) => a + b) / downAmps.length;
    final upMean = upAmps.reduce((a, b) => a + b) / upAmps.length;
    final maxAmp = math.max(downMean, upMean);
    if (maxAmp <= 0) return MetricObservation.notObservable();
    final asym = (downMean - upMean).abs() / maxAmp;
    if (!asym.isFinite) return MetricObservation.notObservable();
    // Confidence is the average of the two clusters' confidences.
    final conf = _aggregateConfidence(events);
    return _valueWithConfidence(asym.clamp(0.0, 1.0).toDouble(), conf);
  }

  /// Session-level aggregate: `1 - min(1, stddev/mean)`. Range [0, 1].
  /// Requires `>= pickingConsistencyMinimumEvents` strokes.
  MetricObservation beatToBeatConsistencyFromAmplitudes(
    List<double> amplitudes,
  ) {
    if (amplitudes.length < pickingConsistencyMinimumEvents) {
      return MetricObservation.notObservable();
    }
    final mean = amplitudes.reduce((a, b) => a + b) / amplitudes.length;
    if (mean <= 0) return MetricObservation.notObservable();
    final variance =
        amplitudes.map((a) => math.pow(a - mean, 2)).reduce((a, b) => a + b) /
        amplitudes.length;
    final stddev = math.sqrt(variance);
    if (!stddev.isFinite) return MetricObservation.notObservable();
    final cv = stddev / mean;
    if (!cv.isFinite) return MetricObservation.notObservable();
    final consistency = (1 - cv.clamp(0.0, 1.0)).toDouble();
    return _valueWithConfidence(consistency, 1.0);
  }

  /// Classify a single `(u, v)` into a [PickingZone].
  ///
  /// The four SDD §20.2 categories:
  ///   - `nearBridge`          — u ≥ nearBridgeLowerU
  ///   - `nearNeck`            — u <  nearNeckUpperU
  ///   - `middleBody`          — nearNeckUpperU ≤ u < nearBridgeLowerU
  ///   - `outsideCalibratedZone` — u ∉ [0, 1] OR |v| > 1 OR any non-finite
  ///
  /// The classifier is **total** — every point returns a value. Out-of-plane
  /// points fall into `outsideCalibratedZone` so downstream code never has
  /// to deal with `null`.
  static PickingZone classifyZone(
    GuitarSpacePoint point, {
    PickingZoneThresholds thresholds = const PickingZoneThresholds(),
  }) {
    if (!point.u.isFinite ||
        !point.v.isFinite ||
        point.u < 0 ||
        point.u > 1 ||
        point.v < -1 ||
        point.v > 1) {
      return PickingZone.outsideCalibratedZone;
    }
    if (point.u >= thresholds.nearBridgeLowerU) {
      return PickingZone.nearBridge;
    }
    if (point.u < thresholds.nearNeckUpperU) {
      return PickingZone.nearNeck;
    }
    return PickingZone.middleBody;
  }

  /// Look up the catalog definition for a metric. Mirrors the R18 accessor.
  static PickingMetricDefinition definitionFor(PickingMetricId id) =>
      pickingMetricDefinitions.firstWhere((definition) => definition.id == id);

  // -- Internal helpers -------------------------------------------------------

  PickingEventResult _eventResult({
    required List<PickingFrame> samples,
    required Duration onset,
    required bool truncated,
    required PickingSyncQuality sync,
  }) {
    final dir = strokeDirection(samples, sync: sync);
    final amp = strokeAmplitude(samples, sync: sync);
    final speed = strokeSpeed(samples, sync: sync);
    final lin = strokeLinearity(samples, sync: sync);
    PickingZone zone = PickingZone.outsideCalibratedZone;
    if (_eventLevelAllowed(sync) && samples.isNotEmpty) {
      // Anchor the zone to the sample closest to the onset — the
      // wrist position there is what the §20.2 classifier is asked
      // about.
      final anchor = samples.reduce(
        (a, b) =>
            (a.timestamp - onset).inMicroseconds.abs() <
                (b.timestamp - onset).inMicroseconds.abs()
            ? a
            : b,
      );
      final uv = _wristUv(anchor);
      if (uv != null) zone = classifyZone(uv);
    }
    return PickingEventResult(
      direction: dir,
      amplitude: amp,
      speed: speed,
      linearity: lin,
      zone: zone,
      truncated: truncated,
    );
  }

  Map<PickingZone, double> _zoneDistributionFromEvents(
    List<PickingEventResult> events,
  ) {
    if (events.isEmpty) {
      return const <PickingZone, double>{};
    }
    final counts = <PickingZone, int>{for (final z in PickingZone.values) z: 0};
    for (final e in events) {
      counts[e.zone] = (counts[e.zone] ?? 0) + 1;
    }
    return {
      for (final entry in counts.entries)
        entry.key: entry.value / events.length,
    };
  }

  bool _eventLevelAllowed(PickingSyncQuality sync) =>
      sync == PickingSyncQuality.good || sync == PickingSyncQuality.excellent;

  List<PickingFrame> _usableFrames(
    List<PickingFrame> input,
    PickingMetricId id,
  ) {
    final minVis = definitionFor(id).minimumVisibility;
    return input
        .where((s) => s.track.role == HandRole.picking)
        .where((s) => _visibility(s, id) >= minVis)
        .toList(growable: false);
  }

  double _visibility(PickingFrame sample, PickingMetricId id) {
    final wristVisibility =
        sample.guitarLandmarks[HandLandmarkId.wrist]?.confidence ??
        sample.track.smoothedLandmarks[HandLandmarkId.wrist]?.visibility ??
        0.0;
    if (!wristVisibility.isFinite) return 0.0;
    return wristVisibility;
  }

  double _confidence(List<PickingFrame> usable, PickingMetricId id) {
    if (usable.isEmpty) return 0.0;
    final vis =
        usable.map((s) => _visibility(s, id)).reduce((a, b) => a + b) /
        usable.length;
    return vis.clamp(0.0, 1.0).toDouble();
  }

  double _aggregateConfidence(List<PickingEventResult> events) {
    final amps = events
        .where((e) => e.amplitude.isObservable)
        .map((e) => e.amplitude.confidence)
        .toList();
    if (amps.isEmpty) return 0.0;
    return amps.reduce((a, b) => a + b) / amps.length;
  }

  GuitarSpacePoint? _wristUv(PickingFrame sample) =>
      sample.guitarLandmarks[HandLandmarkId.wrist]?.uv;

  double _chord(GuitarSpacePoint a, GuitarSpacePoint b) {
    final du = a.u - b.u;
    final dv = a.v - b.v;
    return math.sqrt(du * du + dv * dv);
  }

  List<double> _pathSegments(List<PickingFrame> usable) {
    final segments = <double>[];
    GuitarSpacePoint? prev;
    for (final s in usable) {
      final cur = _wristUv(s);
      if (cur == null) continue;
      if (prev != null) {
        final d = _chord(prev, cur);
        if (d.isFinite) segments.add(d);
      }
      prev = cur;
    }
    return segments;
  }

  MetricObservation _valueWithConfidence(double value, double confidence) =>
      MetricObservation.observable(value: value, confidence: confidence);
}

/// All values the [PickingMetricEngine.compute] entry point produces for a
/// single session.
final class PickingSessionResult {
  const PickingSessionResult({
    required this.perEvent,
    required this.consistency,
    required this.asymmetry,
    required this.zoneDistribution,
  });

  /// One entry per onset, in onset order.
  final List<PickingEventResult> perEvent;

  /// 1 - CV across all observable event amplitudes. `notObservable`
  /// below `pickingConsistencyMinimumEvents` strokes.
  final MetricObservation consistency;

  /// |mean(down) - mean(up)| / max, per the brief §20.1.
  final MetricObservation asymmetry;

  /// Fraction of events in each [PickingZone], summing to 1.
  final Map<PickingZone, double> zoneDistribution;
}

/// Per-onset metric bundle.
final class PickingEventResult {
  const PickingEventResult({
    required this.direction,
    required this.amplitude,
    required this.speed,
    required this.linearity,
    required this.zone,
    required this.truncated,
  });

  /// ±1 numeric (`+1` = down / `Δv > 0`, `-1` = up / `Δv < 0`,
  /// `0` = zero displacement). The caller maps ±1 to `StrumDirection`
  /// at its own layer (brief §0.0/4).
  final MetricObservation direction;

  /// Total path length in guitar-space units.
  final MetricObservation amplitude;

  /// Path length per second.
  final MetricObservation speed;

  /// Chord / path, clamped to [0, 1].
  final MetricObservation linearity;

  /// Picking zone at the onset (SDD §20.2).
  final PickingZone zone;

  /// True if the window was truncated to the next onset (brief §5/3).
  final bool truncated;
}
