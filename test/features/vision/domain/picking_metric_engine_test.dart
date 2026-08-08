// E05-R19 — Picking metric engine tests (brief §6 acceptance matrix).
//
// The §6 acceptance criteria are exhaustive across the seven metrics:
//
//   1. Stroke-fixture matrix (down / up / noisy) — direction, amplitude,
//      speed, linearity with values computed in §10 via `python3 -c`.
//   2. Sync matrix (poor / acceptable / good / excellent) — event-level
//      metrics `notObservable` under `poor` / `acceptable`, observable
//      under `good` / `excellent`.
//   3. Nincs-esemény — empty event list → no per-event output, aggregate
//      `notObservable` (not 0).
//   4. Átfedő ablak — the fast-toggle fixture drives the truncation rule
//      (cut + signal).
//   5. Mirror / balkezes paritás — 2-cell (handedness left/right), every
//      other field bit-identical, proves direction invariance.
//   6. Aggregát-minimum — n = pickingConsistencyMinimumEvents → value,
//      n < that → `notObservable`.
//   7. Picking-zóna — all four SDD §20.2 categories reachable.
//   8. Catalog validation — every definition `isValid`.
//
// Plus the brief §6 acceptance #4 (valódi-sértés próba): removing the
// sync gate turns the `poor` sync-mátrix cell red.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/geometry/guitar_space.dart';
import 'package:strumsight/features/vision/domain/geometry/guitar_landmark_mapper.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_landmarks.dart';
import 'package:strumsight/features/vision/domain/landmarks/hand_track.dart';
import 'package:strumsight/features/vision/domain/metrics/metric_observation.dart';
import 'package:strumsight/features/vision/domain/metrics/picking_metric_engine.dart';
import 'package:strumsight/features/vision/domain/metrics/picking_metrics.dart';
import 'package:strumsight/features/vision/domain/metrics/stroke_window.dart';

import '../../../fixtures/vision/picking/picking_fixtures.dart';

void main() {
  const engine = PickingMetricEngine();

  // ---------------------------------------------------------------------------
  // (1) Stroke-fixture matrix — direction / amplitude / speed / linearity.
  // ---------------------------------------------------------------------------

  group('stroke fixture matrix — direction', () {
    test('ideal downstroke → direction = +1', () {
      final obs = engine.strokeDirection(
        downstrokeIdeal(),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, 1.0);
    });

    test('ideal upstroke → direction = -1', () {
      final obs = engine.strokeDirection(
        upstrokeIdeal(),
        sync: PickingSyncQuality.excellent,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, -1.0);
    });

    test('noisy downstroke → direction still +1 (Δv unchanged by jitter)', () {
      final obs = engine.strokeDirection(
        downstrokeNoisy(),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, 1.0);
    });

    test('degenerate single-sample window is not observable', () {
      final obs = engine.strokeDirection(
        downstrokeIdeal().sublist(0, 1),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.notObservable);
    });
  });

  group('stroke fixture matrix — amplitude', () {
    test('ideal downstroke → amplitude = 0.60 (§10)', () {
      final obs = engine.strokeAmplitude(
        downstrokeIdeal(),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, closeTo(0.60, 1e-9));
    });

    test('ideal upstroke → amplitude = 0.60', () {
      final obs = engine.strokeAmplitude(
        upstrokeIdeal(),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, closeTo(0.60, 1e-9));
    });

    test('noisy downstroke → amplitude = 0.80 (wobble increases path)', () {
      // §10 falsification: path = 0.80 ≠ 0.60 — proves the amplitude
      // metric is not a constant. The chord is still 0.60 (start/end
      // unchanged) but the path is longer because of the back-and-forth
      // wobble.
      final obs = engine.strokeAmplitude(
        downstrokeNoisy(),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, closeTo(0.80, 1e-9));
    });
  });

  group('stroke fixture matrix — speed', () {
    test('ideal downstroke → speed = 2.40 / s (§10)', () {
      final obs = engine.strokeSpeed(
        downstrokeIdeal(),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, closeTo(2.40, 1e-9));
    });

    test('noisy downstroke → speed = 3.20 / s (longer path over same '
        'window)', () {
      final obs = engine.strokeSpeed(
        downstrokeNoisy(),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, closeTo(3.20, 1e-9));
    });
  });

  group('stroke fixture matrix — linearity', () {
    test('ideal downstroke → linearity = 1.0 (perfectly linear)', () {
      final obs = engine.strokeLinearity(
        downstrokeIdeal(),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, closeTo(1.0, 1e-9));
    });

    test('noisy downstroke → linearity = 0.75 (wobble reduces linearity)', () {
      // §10 falsification: 0.75 ≠ 1.0 — proves the linearity metric
      // is NOT a constant. The chord stays at 0.60 while the path
      // grows to 0.80, so chord / path = 0.75.
      final obs = engine.strokeLinearity(
        downstrokeNoisy(),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, closeTo(0.75, 1e-9));
    });
  });

  // The "nagyon gyors váltogatás" cell (brief §6 first row) — the
  // FastToggleStrokes.sixAt130ms() fixture drives the truncation rule.
  // Numeric values were computed via `python3 -c` mirroring the exact
  // Taylor series approximation `_sinApprox()` and the new cut boundary
  // (at next onset's pre-window start, post F1 BLOCKER fix). See §10.
  group('stroke fixture matrix — fast toggle (six onsets @ 130 ms)', () {
    test('direction = -1.0 for every truncated window (Δv < 0 across the '
        'sinusoidal stroke)', () {
      final fixture = FastToggleStrokes.sixAt130ms();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      expect(result.perEvent.length, 6);
      for (var i = 0; i < result.perEvent.length; i++) {
        expect(
          result.perEvent[i].direction.observability,
          MetricObservability.observable,
          reason: 'window $i direction must be observable under good sync',
        );
        expect(
          result.perEvent[i].direction.value,
          -1.0,
          reason: 'window $i Δv < 0 → direction = -1.0',
        );
      }
    });

    test('amplitude = path length, increases across the truncated windows '
        'as the sine wave bends', () {
      final fixture = FastToggleStrokes.sixAt130ms();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      // Values computed via `python3 -c` (§10) — path is the sum of
      // |Δv| segment lengths (u is constant at 0.85). The increasing
      // path is a real signal: the truncated windows capture the
      // steepest part of the sinusoid where consecutive samples are
      // far apart.
      const expected = <double>[
        0.881578560, // window 0 — 4 samples
        0.914108325, // window 1 — 4 samples
        0.938067528, // window 2 — 4 samples
        0.953234834, // window 3 — 4 samples
        0.959465515, // window 4 — 4 samples
        2.043662081, // window 5 — 8 samples (full un-truncated window)
      ];
      for (var i = 0; i < result.perEvent.length; i++) {
        expect(
          result.perEvent[i].amplitude.observability,
          MetricObservability.observable,
          reason: 'window $i amplitude must be observable under good sync',
        );
        expect(
          result.perEvent[i].amplitude.value,
          closeTo(expected[i], 1e-6),
          reason: 'window $i path length',
        );
      }
    });

    test('speed ≈ 9.0 / s for truncated windows (4 samples over 99 ms)', () {
      final fixture = FastToggleStrokes.sixAt130ms();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      // Windows 0..4 are truncated to 99 ms with 4 samples covering the
      // steepest part of the sine wave; window 5 is the un-truncated
      // 250 ms window (8 samples).
      const expectedSpeed = <double>[
        8.904833942, // window 0
        9.233417428, // window 1
        9.475429580, // window 2
        9.628634691, // window 3
        9.691570857, // window 4
        8.847021997, // window 5 (full window)
      ];
      for (var i = 0; i < result.perEvent.length; i++) {
        expect(
          result.perEvent[i].speed.value,
          closeTo(expectedSpeed[i], 1e-6),
          reason: 'window $i speed',
        );
      }
    });

    test('linearity decreases across truncated windows (chord shrinks '
        'faster than path)', () {
      final fixture = FastToggleStrokes.sixAt130ms();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      // Linearitiy = chord / path. The truncated windows capture the
      // peak → trough portion of the sine wave where consecutive samples
      // cross zero, so the chord is much shorter than the path —
      // proof that the metric is NOT a constant.
      const expected = <double>[
        0.354232410, // window 0
        0.312192128, // window 1
        0.272682640, // window 2
        0.234785322, // window 3
        0.197713860, // window 4
        0.062689111, // window 5 (full window — sinusoidal path far exceeds
        // the chord)
      ];
      for (var i = 0; i < result.perEvent.length; i++) {
        expect(
          result.perEvent[i].linearity.value,
          closeTo(expected[i], 1e-6),
          reason: 'window $i linearity',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // (2) Sync matrix (brief §6) — event-level metrics gate on sync quality.
  // ---------------------------------------------------------------------------

  group('sync matrix — event-level gate', () {
    for (final cell in PickingSyncQuality.values) {
      test(
        'direction under sync=$cell → '
        '${cell == PickingSyncQuality.poor || cell == PickingSyncQuality.acceptable ? "notObservable" : "observable"}',
        () {
          final obs = engine.strokeDirection(downstrokeIdeal(), sync: cell);
          final expected =
              (cell == PickingSyncQuality.poor ||
                  cell == PickingSyncQuality.acceptable)
              ? MetricObservability.notObservable
              : MetricObservability.observable;
          expect(obs.observability, expected, reason: 'sync=$cell');
        },
      );
    }

    test('amplitude under poor sync → notObservable', () {
      final obs = engine.strokeAmplitude(
        downstrokeIdeal(),
        sync: PickingSyncQuality.poor,
      );
      expect(obs.observability, MetricObservability.notObservable);
      expect(obs.value, isNull);
    });

    test('amplitude under acceptable sync → notObservable', () {
      final obs = engine.strokeAmplitude(
        downstrokeIdeal(),
        sync: PickingSyncQuality.acceptable,
      );
      expect(obs.observability, MetricObservability.notObservable);
    });

    test('amplitude under excellent sync → observable with documented '
        'value 0.60', () {
      final obs = engine.strokeAmplitude(
        downstrokeIdeal(),
        sync: PickingSyncQuality.excellent,
      );
      expect(obs.observability, MetricObservability.observable);
      expect(obs.value, closeTo(0.60, 1e-9));
    });

    test('speed / linearity gate the same way (poor → notObservable)', () {
      for (final m
          in <
            MetricObservation Function(List<PickingFrame>, PickingSyncQuality)
          >[
            (s, q) => engine.strokeSpeed(s, sync: q),
            (s, q) => engine.strokeLinearity(s, sync: q),
          ]) {
        final obs = m(downstrokeIdeal(), PickingSyncQuality.poor);
        expect(obs.observability, MetricObservability.notObservable);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // (3) Nincs-esemény — empty event list (brief §6).
  // ---------------------------------------------------------------------------

  group('empty event list', () {
    test('engine.compute with no onsets → empty perEvent + notObservable '
        'aggregates', () {
      final result = engine.compute(
        frames: downstrokeIdeal(),
        onsets: const <PickingOnsetEvent>[],
        sync: PickingSyncQuality.good,
      );
      expect(result.perEvent, isEmpty);
      expect(
        result.consistency.observability,
        MetricObservability.notObservable,
      );
      expect(result.asymmetry.observability, MetricObservability.notObservable);
    });

    test('engine.compute with empty frames list and a single onset → '
        'no per-event output, aggregate notObservable', () {
      final result = engine.compute(
        frames: const <PickingFrame>[],
        onsets: const [
          PickingOnsetEvent(timestamp: Duration(milliseconds: 100)),
        ],
        sync: PickingSyncQuality.good,
      );
      expect(result.perEvent.length, 1);
      expect(
        result.perEvent[0].amplitude.observability,
        MetricObservability.notObservable,
      );
      expect(
        result.consistency.observability,
        MetricObservability.notObservable,
      );
      expect(result.asymmetry.observability, MetricObservability.notObservable);
    });
  });

  // ---------------------------------------------------------------------------
  // (4) Átfedő ablak — fast-toggle truncation (brief §6).
  // ---------------------------------------------------------------------------

  group('overlapping windows — truncation', () {
    test(
      'fast-toggle fixture truncates windows 0..4 and preserves window 5',
      () {
        final fixture = FastToggleStrokes.sixAt130ms();
        final result = engine.compute(
          frames: fixture.frames,
          onsets: fixture.onsets,
          sync: PickingSyncQuality.good,
        );
        expect(result.perEvent.length, 6);
        for (var i = 0; i < 5; i++) {
          expect(
            result.perEvent[i].truncated,
            isTrue,
            reason: 'window $i should be truncated',
          );
        }
        expect(result.perEvent[5].truncated, isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // (5) Aggregát — asymmetry / consistency (brief §6).
  // ---------------------------------------------------------------------------

  group('down-up asymmetry — standard 4-stroke fixture', () {
    test('asymmetry = 0.173913 (§10)', () {
      final fixture = AlternatingStrokes.standard();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      expect(result.asymmetry.observability, MetricObservability.observable);
      expect(result.asymmetry.value, closeTo(0.173913, 1e-6));
    });

    test(
      'asymmetry is observable even under poor sync (session aggregate)',
      () {
        // Brief §5/2: "lassú aggregát metrikák maradnak érvényesek"
        // under poor sync — session aggregates are immune to the gate.
        final fixture = AlternatingStrokes.standard();
        final result = engine.compute(
          frames: fixture.frames,
          onsets: fixture.onsets,
          sync: PickingSyncQuality.poor,
        );
        expect(result.asymmetry.observability, MetricObservability.observable);
      },
    );

    test('one-sided session (down only) → notObservable asymmetry', () {
      // Build a session with only downstrokes.
      final frames = <PickingFrame>[];
      final onsets = <PickingOnsetEvent>[];
      for (var i = 0; i < 3; i++) {
        final onsetMs = 500 + i * 1000;
        onsets.add(
          PickingOnsetEvent(timestamp: Duration(milliseconds: onsetMs)),
        );
        frames.addAll([
          _build(
            timestampMs: onsetMs - 100,
            u: 0.85,
            v: -0.3,
            role: HandRole.picking,
          ),
          _build(
            timestampMs: onsetMs + 100,
            u: 0.85,
            v: 0.3,
            role: HandRole.picking,
          ),
        ]);
      }
      final result = engine.compute(
        frames: frames,
        onsets: onsets,
        sync: PickingSyncQuality.good,
      );
      expect(result.asymmetry.observability, MetricObservability.notObservable);
    });
  });

  group('beat-to-beat consistency — boundary cells (brief §6)', () {
    test('n = 3 (= minimum) → value = 0.931959 (§10)', () {
      final fixture = AlternatingStrokes.exactlyAtMinimum();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      expect(result.consistency.observability, MetricObservability.observable);
      expect(result.consistency.value, closeTo(0.931959, 1e-6));
    });

    test('n = 2 (< minimum) → notObservable', () {
      final fixture = AlternatingStrokes.belowMinimum();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      expect(
        result.consistency.observability,
        MetricObservability.notObservable,
      );
    });

    test('tight 4-stroke fixture → consistency ≈ 0.975452 (§10)', () {
      final fixture = AlternatingStrokes.tight();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      expect(result.consistency.observability, MetricObservability.observable);
      expect(result.consistency.value, closeTo(0.975452, 1e-6));
    });

    test('standard 4-stroke fixture → consistency = 0.893521 (§10)', () {
      final fixture = AlternatingStrokes.standard();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      expect(result.consistency.observability, MetricObservability.observable);
      expect(result.consistency.value, closeTo(0.893521, 1e-6));
    });

    test('consistency is observable under poor sync (session aggregate)', () {
      final fixture = AlternatingStrokes.standard();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.poor,
      );
      expect(result.consistency.observability, MetricObservability.observable);
    });
  });

  // ---------------------------------------------------------------------------
  // (6) Picking-zone classifier — SDD §20.2 four-category coverage (§0.0/5).
  // ---------------------------------------------------------------------------

  group('picking-zone classifier — all four SDD §20.2 categories', () {
    test('nearBridge — u >= 0.70', () {
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.95, 0.5)),
        PickingZone.nearBridge,
      );
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.70, -0.5)),
        PickingZone.nearBridge,
      );
    });

    test('middleBody — 0.40 <= u < 0.70', () {
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.55, 0.0)),
        PickingZone.middleBody,
      );
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.40, 0.3)),
        PickingZone.middleBody,
      );
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.69, 0.0)),
        PickingZone.middleBody,
      );
    });

    test('nearNeck — u < 0.40', () {
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.20, 0.0)),
        PickingZone.nearNeck,
      );
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.0, 0.5)),
        PickingZone.nearNeck,
      );
    });

    test('outsideCalibratedZone — u < 0 OR u > 1 OR |v| > 1', () {
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(-0.10, 0.0)),
        PickingZone.outsideCalibratedZone,
      );
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(1.05, 0.0)),
        PickingZone.outsideCalibratedZone,
      );
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.50, 1.10)),
        PickingZone.outsideCalibratedZone,
      );
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.50, -1.05)),
        PickingZone.outsideCalibratedZone,
      );
    });

    test('boundary — u exactly at 0.40 → middleBody (>= cut)', () {
      // The cut-point semantics: u < 0.40 → nearNeck, u >= 0.40 →
      // middleBody. The right-open boundary at 0.40 means a fixture at
      // exactly u = 0.40 returns middleBody.
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.40, 0.0)),
        PickingZone.middleBody,
      );
    });

    test('boundary — u exactly at 0.70 → nearBridge (>= cut)', () {
      expect(
        PickingMetricEngine.classifyZone(GuitarSpacePoint(0.70, 0.0)),
        PickingZone.nearBridge,
      );
    });

    test('non-finite inputs are guarded by GuitarSpacePoint itself '
        '(defensive)', () {
      // The `GuitarSpacePoint` constructor throws ArgumentError on
      // non-finite coordinates, so the classifier never sees NaN /
      // Infinity. We verify the defensive invariant here:
      expect(() => GuitarSpacePoint(double.nan, 0.0), throwsArgumentError);
      expect(() => GuitarSpacePoint(0.5, double.infinity), throwsArgumentError);
    });

    test('per-event engine result records the onset-anchored zone', () {
      // Standard fixture sits at u=0.85 → nearBridge.
      final fixture = AlternatingStrokes.standard();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      for (final e in result.perEvent) {
        expect(e.zone, PickingZone.nearBridge);
      }
    });

    test('zoneDistribution sums to 1 over a 4-stroke session', () {
      final fixture = AlternatingStrokes.standard();
      final result = engine.compute(
        frames: fixture.frames,
        onsets: fixture.onsets,
        sync: PickingSyncQuality.good,
      );
      final sum = result.zoneDistribution.values.fold<double>(
        0.0,
        (a, b) => a + b,
      );
      expect(sum, closeTo(1.0, 1e-9));
    });
  });

  // ---------------------------------------------------------------------------
  // (7) Mirror / balkezes paritás — 2-cell handedness axis (brief §6 + §0.0/2).
  //
  // WHAT THIS GROUP PROVES: the engine does not branch on
  // `HandTrack.handedness` — it may only read `role` and the
  // mirror-free `(u, v)` mapping (R15). Two sample sequences with
  // byte-identical `role`, raw landmarks and guitar-space `(u, v)`,
  // differing ONLY in `handedness` (`left` vs `right`), must yield the
  // same direction classification and observable amplitudes.
  //
  // WHAT THIS GROUP DOES NOT PROVE: camera-mirroring / `leftHanded`
  // setting path. That normalization is the CALLER's responsibility
  // (R13 `HandTrackAssigner` already supplies the resolved `role`, and
  // R15 supplies mirror-free guitar-space `(u, v)`). The four-axis
  // matrix (leftHanded × front/back) cannot be constructed at this
  // layer because there is no `leftHanded` or camera-facing axis on
  // the input — a "4 cell" version here would be two duplicated pairs,
  // not four independent configurations (L176).
  // ---------------------------------------------------------------------------

  group('mirror / left-handed parity (handedness axis, 2 cells)', () {
    List<PickingFrame> trajectory(Handedness handedness) =>
        downstrokeIdeal().map((f) {
          final newTrack = HandTrack(
            id: f.track.id,
            handedness: handedness,
            role: f.track.role,
            status: f.track.status,
            smoothedLandmarks: f.track.smoothedLandmarks,
            firstFrameIndex: f.track.firstFrameIndex,
            lastSeenFrameIndex: f.track.lastSeenFrameIndex,
          );
          return PickingFrame(
            timestamp: f.timestamp,
            track: newTrack,
            guitarLandmarks: f.guitarLandmarks,
          );
        }).toList();

    test('direction / amplitude / speed / linearity are invariant to '
        'HandTrack.handedness for identical role / geometry', () {
      const tolerance = 1e-9;
      final left = trajectory(Handedness.left);
      final right = trajectory(Handedness.right);

      final metrics = <String, MetricObservation Function(List<PickingFrame>)>{
        'strokeDirection': (s) =>
            engine.strokeDirection(s, sync: PickingSyncQuality.good),
        'strokeAmplitude': (s) =>
            engine.strokeAmplitude(s, sync: PickingSyncQuality.good),
        'strokeSpeed': (s) =>
            engine.strokeSpeed(s, sync: PickingSyncQuality.good),
        'strokeLinearity': (s) =>
            engine.strokeLinearity(s, sync: PickingSyncQuality.good),
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

  // ---------------------------------------------------------------------------
  // (8) Visibility / role gates — the role and visibility filters.
  // ---------------------------------------------------------------------------

  group('visibility + role gates', () {
    test('picking-role track is required (fretting-role frame is filtered '
        'out)', () {
      final asFretting = downstrokeIdeal().map((f) {
        final newTrack = HandTrack(
          id: f.track.id,
          handedness: f.track.handedness,
          role: HandRole.fretting,
          status: f.track.status,
          smoothedLandmarks: f.track.smoothedLandmarks,
          firstFrameIndex: f.track.firstFrameIndex,
          lastSeenFrameIndex: f.track.lastSeenFrameIndex,
        );
        return PickingFrame(
          timestamp: f.timestamp,
          track: newTrack,
          guitarLandmarks: f.guitarLandmarks,
        );
      }).toList();
      final obs = engine.strokeAmplitude(
        asFretting,
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.notObservable);
    });

    test('sub-threshold visibility (0.10 < minimum 0.55) is filtered out', () {
      final obs = engine.strokeAmplitude(
        downstrokeIdeal(visibility: 0.10),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.notObservable);
    });

    test('exactly-at-threshold visibility (0.55) is observable', () {
      final obs = engine.strokeAmplitude(
        downstrokeIdeal(visibility: 0.55),
        sync: PickingSyncQuality.good,
      );
      expect(obs.observability, MetricObservability.observable);
    });
  });

  // ---------------------------------------------------------------------------
  // (9) Catalog validation — every definition is `isValid`.
  // ---------------------------------------------------------------------------

  group('catalog validation', () {
    test('all pickingMetricDefinitions are isValid', () {
      for (final d in pickingMetricDefinitions) {
        expect(d.isValid, isTrue, reason: 'definition ${d.id} isValid');
      }
    });

    test('catalog covers exactly one definition per PickingMetricId', () {
      final ids = pickingMetricDefinitions.map((d) => d.id).toSet();
      expect(ids.length, PickingMetricId.values.length);
      expect(ids, PickingMetricId.values.toSet());
    });

    test('definitionFor(id) round-trips every PickingMetricId', () {
      for (final id in PickingMetricId.values) {
        final def = PickingMetricEngine.definitionFor(id);
        expect(def.id, id);
        expect(def.minimumVisibility, 0.55);
        expect(
          def.requiredCapability,
          PickingCapability.guitarRelativeTracking,
        );
      }
    });

    test('PickingMetricDefinition rejects non-finite visibility', () {
      expect(
        () => PickingMetricDefinition(
          id: PickingMetricId.strokeAmplitude,
          minimumVisibility: double.nan,
          window: const Duration(milliseconds: 250),
          confidenceFormula: 'x',
          requiredCapability: PickingCapability.guitarRelativeTracking,
        ),
        throwsArgumentError,
      );
    });

    test('PickingMetricDefinition rejects zero-duration window', () {
      expect(
        () => PickingMetricDefinition(
          id: PickingMetricId.strokeAmplitude,
          minimumVisibility: 0.55,
          window: Duration.zero,
          confidenceFormula: 'x',
          requiredCapability: PickingCapability.guitarRelativeTracking,
        ),
        throwsArgumentError,
      );
    });

    test('PickingMetricDefinition rejects empty confidence formula', () {
      expect(
        () => PickingMetricDefinition(
          id: PickingMetricId.strokeAmplitude,
          minimumVisibility: 0.55,
          window: const Duration(milliseconds: 250),
          confidenceFormula: '   ',
          requiredCapability: PickingCapability.guitarRelativeTracking,
        ),
        throwsArgumentError,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // (10) Valódi-sértés próba — sync-kapu eltávolítása (brief §6).
  //
  // Briefly commenting out `_eventLevelAllowed` in `picking_metric_engine.dart`
  // (line ~339) turns the four `poor` / `acceptable` cells of the
  // sync-mátrix RED — this is the documented falsification that the
  // gate is load-bearing. The mutation is NOT applied automatically;
  // the §10 implementation handoff records the manual run + revert.
  // ---------------------------------------------------------------------------

  group('valódi-sértés próba — sync gate is load-bearing (brief §6)', () {
    test('under poor sync, event-level metrics are notObservable', () {
      // The same fixture that produces 0.60 amplitude under `good` sync
      // is notObservable under `poor` sync — the gate IS the contract.
      final obs = engine.strokeAmplitude(
        downstrokeIdeal(),
        sync: PickingSyncQuality.poor,
      );
      expect(obs.observability, MetricObservability.notObservable);
      expect(obs.value, isNull);
    });
  });
}

PickingFrame _build({
  required int timestampMs,
  required double u,
  required double v,
  required HandRole role,
  double visibility = 0.95,
}) {
  // Helper used by the one-sided asymmetry test.
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
      id: 0,
      handedness: Handedness.right,
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
