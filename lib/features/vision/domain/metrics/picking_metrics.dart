// E05-R19 — Picking-hand metric catalog (SDD §20).
//
// The catalog mirrors `metric_definition.dart` (R18, fretting-hand) BY
// SHAPE, not by import: that file hardcodes `FrettingMetricId` /
// `FrettingCapability` and is NOT in this round's `allowed_paths`. So the
// picking-side lives here, with the same throw-`ArgumentError` constructor
// invariant, the same `isValid` getter, and the same `definitionFor(id)`
// accessor — only the ID enum, capability enum, thresholds and metric list
// are picking-specific.
//
// The catalog exposes:
//   - `PickingMetricId` — the seven observable picking metrics (brief §20.1
//     + §20.2 + §0.0/5).
//   - `PickingCapability` — capability required before a metric can be
//     interpreted. All seven need `guitarRelativeTracking` because the
//     metrics operate in guitar-space `(u, v)` (R15) — the picking-zone
//     classifier obviously needs the bridge↔neck axis, but the trajectory
//     metrics also need it to be camera-independent.
//   - `PickingSyncQuality` — the four-level injected audio–vision sync
//     quality (poor / acceptable / good / excellent). Grep over the
//     codebase returns zero hits for this name; the type lives here and
//     nowhere else.
//   - `PickingZone` — the four-category SDD §20.2 enum
//     (nearBridge / middleBody / nearNeck / outsideCalibratedZone).
//     This is a DIFFERENT enum from `GuitarRegion` (R15): R15's `pickingZone`
//     value is a coarse body-third cut for the FRETING hand; §20.2's four
//     values are a relative bridge↔neck zone for the PICKING hand.
//   - `PickingZoneThresholds` — the configurable `u`-axis cut points, same
//     shape as `GuitarRegionThresholds`. Defaults: `nearBridge` ≥ 0.70,
//     `nearNeck` < 0.40, `middleBody` covers the 0.40..0.70 span.
//   - `PickingMetricDefinition` — the per-metric catalog record.
//   - `pickingMetricDefinitions` — the validated, unmodifiable list.

library;

import 'package:meta/meta.dart';

/// Capability required before a picking metric can be interpreted.
enum PickingCapability { guitarRelativeTracking }

/// Picking-hand metric IDs (SDD §20.1 + §20.2).
enum PickingMetricId {
  /// Net trajectory direction (down vs up). SDD §20.1.
  strokeDirection,

  /// Total path length of the trajectory over the window. SDD §20.1.
  strokeAmplitude,

  /// Average speed = amplitude / window duration. SDD §20.1.
  strokeSpeed,

  /// Path linearity = chord_length / path_length ∈ (0, 1]. SDD §20.1.
  strokeLinearity,

  /// Downstroke amplitude vs upstroke amplitude asymmetry. SDD §20.1.
  downUpAsymmetry,

  /// Beat-to-beat amplitude consistency (1 - CV). SDD §20.1.
  beatToBeatConsistency,

  /// Picking-zone classification at the onset. SDD §20.2.
  pickingZone,
}

/// Audio–vision sync quality (E05-R19 brief §5/2).
///
/// Injected — the real audio–vision alignment is wired in R21. The four
/// values form the brief's gate:
///   - [poor] / [acceptable] — event-level metrics return `notObservable`,
///     only the slower, session-aggregate metrics may still emit a value.
///   - [good] / [excellent] — event-level metrics emit normally.
///
/// Grep over the repository for `PickingSyncQuality` confirms zero hits
/// outside this file (the brief §0.0/5 invariant).
enum PickingSyncQuality { poor, acceptable, good, excellent }

/// Picking-zone category (SDD §20.2).
///
/// A NEUTRAL observation of the picking hand's bridge↔neck position. The
/// brief §20.2 and §5/1 require this to carry NO quality judgement: an
/// `outsideCalibratedZone` observation does NOT mean the player is wrong,
/// it just means the hand has drifted outside the calibrated envelope.
enum PickingZone { nearBridge, middleBody, nearNeck, outsideCalibratedZone }

/// Configurable cut points for [PickingZoneClassifier].
///
/// Defaults match a standard electric/acoustic layout: the bridge-side third
/// (`u ≥ 0.70`) is the typical picking zone, the neck-side third
/// (`u < 0.40`) is the "near the neck" position used for fingerstyle or
/// softer attack, and `middleBody` covers the 0.40..0.70 span.
@immutable
final class PickingZoneThresholds {
  const PickingZoneThresholds({
    this.nearNeckUpperU = 0.40,
    this.nearBridgeLowerU = 0.70,
  }) : assert(nearNeckUpperU > 0 && nearNeckUpperU < 1),
       assert(nearBridgeLowerU > 0 && nearBridgeLowerU < 1),
       assert(nearNeckUpperU < nearBridgeLowerU);

  /// The `u` value where `nearNeck` ends and `middleBody` begins.
  final double nearNeckUpperU;

  /// The `u` value where `middleBody` ends and `nearBridge` begins.
  final double nearBridgeLowerU;
}

/// Per-metric definition record. Mirrors R18 `MetricDefinition` exactly:
/// throw-`ArgumentError` constructor + `isValid` getter.
@immutable
final class PickingMetricDefinition {
  PickingMetricDefinition({
    required this.id,
    required this.minimumVisibility,
    required this.window,
    required this.confidenceFormula,
    required this.requiredCapability,
  }) {
    if (!(minimumVisibility.isFinite &&
        minimumVisibility >= 0 &&
        minimumVisibility <= 1)) {
      throw ArgumentError.value(
        minimumVisibility,
        'minimumVisibility',
        'Must be finite and in [0, 1].',
      );
    }
    if (window <= Duration.zero) {
      throw ArgumentError.value(
        window,
        'window',
        'Must be a positive Duration.',
      );
    }
    if (confidenceFormula.trim().isEmpty) {
      throw ArgumentError.value(
        confidenceFormula,
        'confidenceFormula',
        'Must be a non-empty string.',
      );
    }
  }

  final PickingMetricId id;
  final double minimumVisibility;
  final Duration window;
  final String confidenceFormula;
  final PickingCapability requiredCapability;

  bool get isValid =>
      minimumVisibility.isFinite &&
      minimumVisibility >= 0 &&
      minimumVisibility <= 1 &&
      window > Duration.zero &&
      confidenceFormula.trim().isNotEmpty;
}

/// The complete, validated picking-metric catalog.
///
/// All seven metrics require `guitarRelativeTracking` — the trajectory
/// metrics need mirror-free `(u, v)` to be comparable across camera angles,
/// and the picking-zone classifier is meaningless without the
/// bridge↔neck axis.
final List<PickingMetricDefinition> pickingMetricDefinitions =
    List.unmodifiable(<PickingMetricDefinition>[
      for (final entry in <PickingMetricId, double>{
        PickingMetricId.strokeDirection: 0.55,
        PickingMetricId.strokeAmplitude: 0.55,
        PickingMetricId.strokeSpeed: 0.55,
        PickingMetricId.strokeLinearity: 0.55,
        PickingMetricId.downUpAsymmetry: 0.55,
        PickingMetricId.beatToBeatConsistency: 0.55,
        PickingMetricId.pickingZone: 0.55,
      }.entries)
        PickingMetricDefinition(
          id: entry.key,
          minimumVisibility: entry.value,
          window: const Duration(milliseconds: 250),
          confidenceFormula: 'mean(minimum landmark confidence)',
          requiredCapability: PickingCapability.guitarRelativeTracking,
        ),
    ]);

/// The minimum number of strokes (events) the engine needs before the
/// beat-to-beat consistency aggregate can emit a value. Below this, the
/// aggregate is `notObservable` (brief §6 — "aggregát-minimum").
///
/// The two cells around this boundary are tested: `n = 3 → value` and
/// `n = 2 → notObservable`.
const int pickingConsistencyMinimumEvents = 3;
