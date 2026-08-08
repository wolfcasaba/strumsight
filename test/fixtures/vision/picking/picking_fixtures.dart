// E05-R19 — Picking-hand stroke fixture generators.
//
// Deterministic synthetic stroke trajectories for the picking metric engine
// tests. The four canonical patterns required by brief §3 / §6:
//
//   1. downstrokeIdeal       — clean downward pick, perfectly linear,
//   2. upstrokeIdeal         — clean upward pick, perfectly linear,
//   3. downstrokeNoisy       — same shape with back-and-forth wobble,
//   4. mixedAlternating      — 2 down + 2 up strokes, varying amplitudes,
//   5. fastToggle            — 6 onsets in 1 s, triggers window truncation,
//   6. zoneAtBridge / zoneAtMiddleBody / zoneAtNeck / zoneOutside
//                            — single-frame fixtures exercising the
//                              picking-zone classifier (§0.0/5, §20.2).
//
// All generators are pure functions on plain Dart primitives. The trajectories
// are expressed in guitar-space `(u, v)` (R15, mirror-free) — the engine
// reads them via the existing `MappedHandLandmark` contract.
//
// The numeric values are computed in the implementation handoff
// (`docs/rounds/e05-r19-picking-hand-stroke-metrics.md` §10) with `python3 -c`
// and reproduced here byte-for-byte. The noisy trajectory's reduced linearity
// (0.75) is the central proof that the metric is not a `1.0`-trick — the path
// length grows because of the jitter while the chord stays at the geometric
// displacement.

library;

import 'package:strumsight/core/geometry/guitar_space.dart';
import 'package:strumsight/features/vision/domain/geometry/guitar_landmark_mapper.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_track.dart';
import 'package:strumsight/features/vision/domain/metrics/picking_metric_engine.dart';
import 'package:strumsight/features/vision/domain/metrics/stroke_window.dart';

/// Builds a `[PickingFrame]` with the given timestamp and guitar-space
/// `(u, v)` mapped wrist landmark. Defaults: full visibility, picking role,
/// right-handed, track id `0`. Tests override what they need.
PickingFrame _pickingFrame({
  required int timestampMs,
  required double u,
  required double v,
  double visibility = 0.95,
  HandRole role = HandRole.picking,
  Handedness handedness = Handedness.right,
  int id = 0,
}) {
  final raw = <HandLandmarkId, HandLandmarkPoint>{
    HandLandmarkId.wrist: HandLandmarkPoint(
      x: u,
      y: v,
      z: 0,
      visibility: visibility,
    ),
  };
  return PickingFrame(
    timestamp: Duration(milliseconds: timestampMs),
    track: HandTrack(
      id: id,
      handedness: handedness,
      role: role,
      status: TrackStatus.active,
      smoothedLandmarks: raw,
      firstFrameIndex: timestampMs,
      lastSeenFrameIndex: timestampMs,
    ),
    guitarLandmarks: {
      HandLandmarkId.wrist: MappedHandLandmark(
        uv: GuitarSpacePoint(u, v),
        confidence: visibility,
      ),
    },
  );
}

/// Six-sample idealizált downstroke centred on the onset.
///
/// Timestamps (ms, relative to onset): -100, -50, 0, +50, +100, +150.
/// `v` trajectory: -0.30, -0.18, -0.06, +0.06, +0.18, +0.30 (perfectly
/// linear in v).
/// `u` constant at 0.85 (picking zone, near bridge).
///
/// Engine-derived values (computed in §10 via `python3 -c`):
///   path       = 0.60
///   chord      = 0.60
///   linearity  = 1.0
///   speed      = 2.40 / s
///   Δv         = +0.60 → direction = down
List<PickingFrame> downstrokeIdeal({
  int onsetMs = 0,
  double visibility = 0.95,
}) {
  final offsets = <int>[-100, -50, 0, 50, 100, 150];
  final vs = <double>[-0.30, -0.18, -0.06, 0.06, 0.18, 0.30];
  return [
    for (var i = 0; i < offsets.length; i++)
      _pickingFrame(
        timestampMs: onsetMs + offsets[i],
        u: 0.85,
        v: vs[i],
        visibility: visibility,
      ),
  ];
}

/// Six-sample idealizált upstroke — the mirror image of [downstrokeIdeal]
/// (Δv = -0.60, otherwise identical).
List<PickingFrame> upstrokeIdeal({int onsetMs = 0, double visibility = 0.95}) {
  final offsets = <int>[-100, -50, 0, 50, 100, 150];
  final vs = <double>[0.30, 0.18, 0.06, -0.06, -0.18, -0.30];
  return [
    for (var i = 0; i < offsets.length; i++)
      _pickingFrame(
        timestampMs: onsetMs + offsets[i],
        u: 0.85,
        v: vs[i],
        visibility: visibility,
      ),
  ];
}

/// Noisy downstroke — same start/end as the ideal but the trajectory wobbles
/// so the path length exceeds the chord. Engine values (§10):
///   path       = 0.80
///   chord      = 0.60
///   linearity  = 0.75
///   speed      = 3.20 / s
///   Δv         = +0.60 → direction still down
///
/// This is the fixture that proves the linearity metric is not a
/// constant — a back-and-forth wobble INCREASES the path length and
/// therefore DECREASES the linearity score (chord / path).
List<PickingFrame> downstrokeNoisy({
  int onsetMs = 0,
  double visibility = 0.95,
}) {
  final offsets = <int>[-100, -50, 0, 50, 100, 150];
  final vs = <double>[-0.30, -0.20, -0.25, -0.10, -0.15, 0.30];
  return [
    for (var i = 0; i < offsets.length; i++)
      _pickingFrame(
        timestampMs: onsetMs + offsets[i],
        u: 0.85,
        v: vs[i],
        visibility: visibility,
      ),
  ];
}

/// Four alternating strokes (down, up, down, up) with non-uniform amplitudes
/// for the asymmetry / consistency aggregates. Engine values (§10):
///   down mean amplitude = 0.575, up mean amplitude = 0.475
///   asymmetry = |0.575 - 0.475| / max = 0.173913
///   amplitude stddev across all four = 0.055902, mean = 0.525, cv = 0.106479
///   consistency = 1 - cv = 0.893521
class AlternatingStrokes {
  AlternatingStrokes._({required this.frames, required this.onsets});

  final List<PickingFrame> frames;
  final List<PickingOnsetEvent> onsets;

  /// Constructs the canonical 4-stroke fixture.
  factory AlternatingStrokes.standard() {
    final frames = <PickingFrame>[];
    final onsets = <PickingOnsetEvent>[];

    // Stroke 1: downstroke, amplitude 0.60 (v: -0.30 → +0.30)
    onsets.add(PickingOnsetEvent(timestamp: const Duration(milliseconds: 500)));
    frames.addAll([
      _pickingFrame(timestampMs: 400, u: 0.85, v: -0.30),
      _pickingFrame(timestampMs: 450, u: 0.85, v: -0.10),
      _pickingFrame(timestampMs: 500, u: 0.85, v: 0.10),
      _pickingFrame(timestampMs: 550, u: 0.85, v: 0.30),
    ]);

    // Stroke 2: upstroke, amplitude 0.50 (v: +0.25 → -0.25)
    onsets.add(
      PickingOnsetEvent(timestamp: const Duration(milliseconds: 1500)),
    );
    frames.addAll([
      _pickingFrame(timestampMs: 1400, u: 0.85, v: 0.25),
      _pickingFrame(timestampMs: 1450, u: 0.85, v: 0.083),
      _pickingFrame(timestampMs: 1500, u: 0.85, v: -0.083),
      _pickingFrame(timestampMs: 1550, u: 0.85, v: -0.25),
    ]);

    // Stroke 3: downstroke, amplitude 0.55
    onsets.add(
      PickingOnsetEvent(timestamp: const Duration(milliseconds: 2500)),
    );
    frames.addAll([
      _pickingFrame(timestampMs: 2400, u: 0.85, v: -0.275),
      _pickingFrame(timestampMs: 2450, u: 0.85, v: -0.092),
      _pickingFrame(timestampMs: 2500, u: 0.85, v: 0.092),
      _pickingFrame(timestampMs: 2550, u: 0.85, v: 0.275),
    ]);

    // Stroke 4: upstroke, amplitude 0.45
    onsets.add(
      PickingOnsetEvent(timestamp: const Duration(milliseconds: 3500)),
    );
    frames.addAll([
      _pickingFrame(timestampMs: 3400, u: 0.85, v: 0.225),
      _pickingFrame(timestampMs: 3450, u: 0.85, v: 0.075),
      _pickingFrame(timestampMs: 3500, u: 0.85, v: -0.075),
      _pickingFrame(timestampMs: 3550, u: 0.85, v: -0.225),
    ]);

    return AlternatingStrokes._(frames: frames, onsets: onsets);
  }

  /// A "tight" 4-stroke fixture where amplitudes cluster around 0.60, so the
  /// consistency metric returns ~0.975 (computed in §10).
  factory AlternatingStrokes.tight() {
    final frames = <PickingFrame>[];
    final onsets = <PickingOnsetEvent>[];

    final amps = <double>[0.60, 0.62, 0.58, 0.61];
    for (var i = 0; i < amps.length; i++) {
      final onset = 500 + i * 1000;
      final a = amps[i];
      onsets.add(PickingOnsetEvent(timestamp: Duration(milliseconds: onset)));
      final sign = i.isEven ? 1.0 : -1.0;
      frames.addAll([
        _pickingFrame(timestampMs: onset - 100, u: 0.85, v: -sign * a / 2),
        _pickingFrame(timestampMs: onset - 50, u: 0.85, v: -sign * a / 4),
        _pickingFrame(timestampMs: onset + 0, u: 0.85, v: sign * a / 4),
        _pickingFrame(timestampMs: onset + 50, u: 0.85, v: sign * a / 2),
      ]);
    }

    return AlternatingStrokes._(frames: frames, onsets: onsets);
  }

  /// 3-stroke fixture exactly at the consistency-minimum boundary.
  factory AlternatingStrokes.exactlyAtMinimum() {
    final frames = <PickingFrame>[];
    final onsets = <PickingOnsetEvent>[];

    final amps = <double>[0.60, 0.55, 0.65];
    for (var i = 0; i < amps.length; i++) {
      final onset = 500 + i * 1000;
      final a = amps[i];
      onsets.add(PickingOnsetEvent(timestamp: Duration(milliseconds: onset)));
      frames.addAll([
        _pickingFrame(timestampMs: onset - 100, u: 0.85, v: -a / 2),
        _pickingFrame(timestampMs: onset + 0, u: 0.85, v: 0),
        _pickingFrame(timestampMs: onset + 100, u: 0.85, v: a / 2),
      ]);
    }

    return AlternatingStrokes._(frames: frames, onsets: onsets);
  }

  /// 2-stroke fixture — strictly below the consistency-minimum boundary.
  factory AlternatingStrokes.belowMinimum() {
    final frames = <PickingFrame>[];
    final onsets = <PickingOnsetEvent>[];

    onsets.add(PickingOnsetEvent(timestamp: const Duration(milliseconds: 500)));
    frames.addAll([
      _pickingFrame(timestampMs: 400, u: 0.85, v: -0.30),
      _pickingFrame(timestampMs: 550, u: 0.85, v: 0.30),
    ]);
    onsets.add(
      PickingOnsetEvent(timestamp: const Duration(milliseconds: 1500)),
    );
    frames.addAll([
      _pickingFrame(timestampMs: 1400, u: 0.85, v: 0.25),
      _pickingFrame(timestampMs: 1550, u: 0.85, v: -0.25),
    ]);

    return AlternatingStrokes._(frames: frames, onsets: onsets);
  }
}

/// Six onsets 130 ms apart — exercises the truncation rule (the next onset
/// always falls inside the current window's `[onset-pre, onset+post)` =
/// `[onset-100, onset+150)`, so the post side is cut short each time).
/// The fast-toggle threshold is determined by the gap to the next onset vs.
/// the post window (150 ms); any rhythm below 150 ms triggers truncation,
/// this fixture pins that contract.
class FastToggleStrokes {
  FastToggleStrokes._({required this.frames, required this.onsets});

  final List<PickingFrame> frames;
  final List<PickingOnsetEvent> onsets;

  factory FastToggleStrokes.sixAt130ms() {
    const onsets = <PickingOnsetEvent>[
      PickingOnsetEvent(timestamp: Duration(milliseconds: 0)),
      PickingOnsetEvent(timestamp: Duration(milliseconds: 130)),
      PickingOnsetEvent(timestamp: Duration(milliseconds: 260)),
      PickingOnsetEvent(timestamp: Duration(milliseconds: 390)),
      PickingOnsetEvent(timestamp: Duration(milliseconds: 520)),
      PickingOnsetEvent(timestamp: Duration(milliseconds: 650)),
    ];
    final frames = <PickingFrame>[];
    // Build frames every 33 ms spanning the whole 750 ms window.
    for (var t = -100; t <= 800; t += 33) {
      // Linear oscillation between -0.3 and +0.3 with a 130 ms period so
      // each onset sits at the midpoint of a downstroke.
      final phase = (t / 130.0) * 2 * 3.141592653589793;
      frames.add(
        _pickingFrame(timestampMs: t, u: 0.85, v: 0.30 * _sinApprox(phase)),
      );
    }
    return FastToggleStrokes._(frames: frames, onsets: onsets);
  }
}

double _sinApprox(double x) {
  // Reduce to [-pi, pi] then use a cheap Taylor series good enough for
  // |x| < pi; the fixtures only need a smooth-ish curve for the truncation
  // test to PASS — the exact shape does not enter any assertion.
  final pi = 3.141592653589793;
  var r = x % (2 * pi);
  if (r > pi) r -= 2 * pi;
  if (r < -pi) r += 2 * pi;
  final r2 = r * r;
  return r -
      (r * r2) / 6.0 +
      (r * r2 * r2) / 120.0 -
      (r * r2 * r2 * r2) / 5040.0;
}

/// Returns a single frame anchored on the picking zone boundary given by
/// `u` (v = 0). Used by the §0.0/5 four-category picking-zone acceptance
/// cells.
PickingFrame pickingZoneFrame({
  required double u,
  required double v,
  double visibility = 0.95,
}) {
  return _pickingFrame(timestampMs: 0, u: u, v: v, visibility: visibility);
}
