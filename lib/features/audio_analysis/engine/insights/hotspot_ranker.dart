import '../../domain/analysis_hotspot.dart';

/// Deterministic display order for precomputed hotspots (ADR 0238).
final class HotspotRanker {
  const HotspotRanker();

  List<AnalysisHotspot> rank(Iterable<AnalysisHotspot> hotspots) {
    final ordered = hotspots.toList()
      ..sort((left, right) {
        final severity = right.severity.index.compareTo(left.severity.index);
        if (severity != 0) return severity;
        final confidence = right.confidence.compareTo(left.confidence);
        return confidence != 0 ? confidence : left.id.compareTo(right.id);
      });
    return List<AnalysisHotspot>.unmodifiable(ordered);
  }
}
