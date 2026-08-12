import 'dart:math' as math;

import '../../domain/analysis_capability.dart';
import '../../domain/analysis_event.dart';
import '../../domain/rhythm/beat_grid.dart';
import '../../domain/rhythm/beat_point.dart';

/// Candidate beat subdivisions supported by the first rhythm-proxy release.
abstract final class SubdivisionCandidates {
  static const Set<int> supported = <int>{1, 2, 3, 4};
  static const double ambiguityRatio = 1.05;
}

/// Result of fitting onset phases to the supported beat subdivisions.
final class SubdivisionAnalysis {
  SubdivisionAnalysis._({
    required this.status,
    required this.subdivision,
    required this.phaseDeviation,
    required List<BeatPoint> usedBeats,
  }) : usedBeats = List<BeatPoint>.unmodifiable(usedBeats);

  /// Resolves already-calculated candidate deviations. This is public because
  /// adapters that calculate phases off-isolate must use the same inclusive
  /// ambiguity policy as [SubdivisionAnalyzer], rather than recreate it.
  factory SubdivisionAnalysis.forCandidateDeviations({
    required Map<int, double> candidateDeviations,
    List<BeatPoint> usedBeats = const <BeatPoint>[],
  }) {
    if (candidateDeviations.keys.any(
          (candidate) => !SubdivisionCandidates.supported.contains(candidate),
        ) ||
        candidateDeviations.values.any(
          (value) => !value.isFinite || value < 0,
        )) {
      throw ArgumentError.value(candidateDeviations, 'candidateDeviations');
    }
    if (candidateDeviations.isEmpty) {
      return SubdivisionAnalysis._(
        status: CapabilityStatus.unavailable,
        subdivision: null,
        phaseDeviation: 0,
        usedBeats: usedBeats,
      );
    }
    final ordered = candidateDeviations.entries.toList()
      ..sort((left, right) {
        final byDeviation = left.value.compareTo(right.value);
        return byDeviation != 0 ? byDeviation : left.key.compareTo(right.key);
      });
    final winner = ordered.first;
    final runnerUp = ordered.cast<MapEntry<int, double>?>().firstWhere(
      (entry) =>
          entry != null &&
          entry.key != winner.key &&
          !_isEquivalentMultiple(winner.key, entry.key),
      orElse: () => null,
    );
    final ambiguous =
        runnerUp != null &&
        _withinAmbiguityThreshold(winner.value, runnerUp.value);
    return SubdivisionAnalysis._(
      status: ambiguous
          ? CapabilityStatus.degraded
          : CapabilityStatus.available,
      subdivision: ambiguous ? null : winner.key,
      phaseDeviation: winner.value,
      usedBeats: usedBeats,
    );
  }

  final CapabilityStatus status;
  final int? subdivision;

  /// Population standard deviation of the selected candidate's signed phase
  /// offsets, expressed as a fraction of one beat.
  final double phaseDeviation;
  final List<BeatPoint> usedBeats;
}

/// Fits observed onset phases to {1, 2, 3, 4} subdivisions per beat.
final class SubdivisionAnalyzer {
  const SubdivisionAnalyzer();

  SubdivisionAnalysis analyze({
    required List<AnalysisEvent> events,
    required BeatGrid beatGrid,
  }) {
    final phases = <_BeatPhase>[];
    for (final event in events) {
      final phase = _phaseFor(event.time, beatGrid.beats);
      if (phase != null) phases.add(phase);
    }
    if (phases.isEmpty) {
      return SubdivisionAnalysis.forCandidateDeviations(
        candidateDeviations: const <int, double>{},
      );
    }
    final deviations = <int, double>{
      for (final candidate in SubdivisionCandidates.supported)
        candidate: _standardDeviation(<double>[
          for (final phase in phases)
            _nearestSubdivisionOffset(phase.value, candidate),
        ]),
    };
    return SubdivisionAnalysis.forCandidateDeviations(
      candidateDeviations: deviations,
      usedBeats: <BeatPoint>{for (final phase in phases) phase.beat}.toList(),
    );
  }
}

final class _BeatPhase {
  const _BeatPhase(this.value, this.beat);
  final double value;
  final BeatPoint beat;
}

_BeatPhase? _phaseFor(Duration time, List<BeatPoint> beats) {
  for (var index = 0; index + 1 < beats.length; index++) {
    final start = beats[index].time;
    final end = beats[index + 1].time;
    if (time >= start && time < end) {
      final duration = end.inMicroseconds - start.inMicroseconds;
      if (duration <= 0) return null;
      return _BeatPhase(
        (time.inMicroseconds - start.inMicroseconds) / duration,
        beats[index],
      );
    }
  }
  return null;
}

double _nearestSubdivisionOffset(double phase, int subdivision) {
  final nearestIndex = (phase * subdivision).round();
  return phase - nearestIndex / subdivision;
}

double _standardDeviation(List<double> values) {
  if (values.isEmpty) return 0;
  final mean = values.reduce((left, right) => left + right) / values.length;
  final variance =
      values
          .map((value) => (value - mean) * (value - mean))
          .reduce((left, right) => left + right) /
      values.length;
  return math.sqrt(variance);
}

bool _isEquivalentMultiple(int winner, int candidate) =>
    candidate > winner && candidate % winner == 0;

bool _withinAmbiguityThreshold(double best, double challenger) {
  if (best == 0) return challenger == 0;
  return challenger / best <= SubdivisionCandidates.ambiguityRatio;
}
