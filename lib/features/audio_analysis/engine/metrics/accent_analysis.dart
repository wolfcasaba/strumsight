import '../../domain/analysis_event.dart';

/// Local (not session-wide) accent detection (SDD §16.5, brief OD-02).
///
/// A global loudness ramp with no true accent must not read as an accent —
/// so every event is compared to its own moving-median neighbourhood, never
/// to the session median.
final class AccentDetectionResult {
  AccentDetectionResult({
    required Set<String> accentEventIds,
    required Map<String, double> localRatioByEventId,
  }) : accentEventIds = Set<String>.unmodifiable(accentEventIds),
       localRatioByEventId = Map<String, double>.unmodifiable(
         localRatioByEventId,
       );

  /// IDs of events whose attack strength exceeds their local neighbourhood
  /// median by more than [detectLocalAccents]'s `thresholdRatio`.
  final Set<String> accentEventIds;

  /// Each event's `attackStrength / localMedian` ratio, keyed by event id.
  final Map<String, double> localRatioByEventId;
}

/// Detects accents from a centred, edge-truncated moving-median window
/// (OD-02 default: the preceding and following 4 events, 9 wide).
///
/// [events] must be strictly time ordered and every event must carry a
/// non-null `attackStrength` (guaranteed for retained R10 output). Passing
/// `windowRadius: events.length` collapses the moving window into the
/// session-wide median — used only to demonstrate why that is the wrong
/// default (brief §6 accent-locality cell).
AccentDetectionResult detectLocalAccents({
  required List<StrumEvent> events,
  int windowRadius = 4,
  double thresholdRatio = 1.2,
}) {
  if (windowRadius <= 0) {
    throw ArgumentError.value(windowRadius, 'windowRadius', 'must be > 0');
  }
  if (thresholdRatio <= 1) {
    throw ArgumentError.value(thresholdRatio, 'thresholdRatio', 'must be > 1');
  }
  final strengths = <double>[for (final event in events) _requireAttack(event)];
  final accentIds = <String>{};
  final ratios = <String, double>{};
  for (var index = 0; index < events.length; index++) {
    final start = (index - windowRadius).clamp(0, events.length - 1);
    final end = (index + windowRadius).clamp(0, events.length - 1);
    final localMedian = _median(strengths.sublist(start, end + 1));
    final ratio = localMedian > 0 ? strengths[index] / localMedian : 0.0;
    ratios[events[index].id] = ratio;
    if (ratio > thresholdRatio) accentIds.add(events[index].id);
  }
  return AccentDetectionResult(
    accentEventIds: accentIds,
    localRatioByEventId: ratios,
  );
}

double _requireAttack(StrumEvent event) {
  final attack = event.attackStrength;
  if (attack == null) {
    throw ArgumentError('StrumEvent ${event.id} is missing attackStrength.');
  }
  return attack;
}

double _median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}
