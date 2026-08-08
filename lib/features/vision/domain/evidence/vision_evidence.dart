import 'dart:convert';

import 'evidence_provenance.dart';
import 'vision_observation.dart';

/// The state of the input evidence, never a technical-playing judgement.
enum ObservationState { observed, inferred, notObservable, experimental }

/// Immutable, reproducible output of a fusion window.
final class VisionEvidence {
  VisionEvidence({
    required this.id,
    required this.metric,
    required this.value,
    required this.confidence,
    required this.observationState,
    required this.provenance,
  }) {
    if (id.trim().isEmpty ||
        !(confidence.isFinite && confidence >= 0 && confidence <= 1)) {
      throw ArgumentError(
        'Evidence id and finite [0, 1] confidence are required.',
      );
    }
    if (observationState == ObservationState.notObservable && value != null) {
      throw ArgumentError(
        'Not-observable evidence cannot contain a metric value.',
      );
    }
  }

  final String id;
  final EvidenceMetric metric;
  final double? value;
  final double confidence;
  final ObservationState observationState;
  final EvidenceProvenance provenance;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'metric': metric.key,
    'value': value,
    'confidence': confidence,
    'observationState': _stateName(observationState),
    'provenance': provenance.toJson(),
  };

  /// Stable FNV-1a ID derived only from the metric and the window key.
  static String deterministicId({
    required EvidenceMetric metric,
    required EvidenceWindow window,
  }) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    for (final byte in utf8.encode(
      '${metric.key}:${window.startUs}:${window.endUs}',
    )) {
      hash = (hash ^ BigInt.from(byte)) * prime & mask;
    }
    return 'vision-evidence-${hash.toRadixString(16).padLeft(16, '0')}';
  }

  static String _stateName(ObservationState state) => switch (state) {
    ObservationState.observed => 'observed',
    ObservationState.inferred => 'inferred',
    ObservationState.notObservable => 'notObservable',
    ObservationState.experimental => 'experimental',
  };
}
