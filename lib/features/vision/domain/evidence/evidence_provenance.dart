import '../sync/sync_quality.dart';

/// Geometry source recorded with an evidence window.
enum GeometrySource { tracked, manual }

/// A half-open interval on the shared session microsecond timeline.
final class EvidenceWindow {
  EvidenceWindow({required this.startUs, required this.endUs}) {
    if (endUs <= startUs) {
      throw ArgumentError.value(endUs, 'endUs', 'Must be after startUs.');
    }
  }

  final int startUs;
  final int endUs;

  Duration get duration => Duration(microseconds: endUs - startUs);

  bool contains(int timestampUs) =>
      timestampUs >= startUs && timestampUs < endUs;

  Map<String, Object> toJson() => <String, Object>{
    'startUs': startUs,
    'endUs': endUs,
  };
}

/// Versioned inputs needed to reproduce an evidence calculation.
final class EvidenceProvenance {
  EvidenceProvenance({
    required this.metricId,
    required this.window,
    required this.modelVersion,
    required this.geometrySource,
    required this.syncQuality,
    required this.thresholdsVersion,
    required this.qualityThresholdsVersion,
  }) {
    if (metricId.trim().isEmpty ||
        modelVersion.trim().isEmpty ||
        thresholdsVersion.trim().isEmpty ||
        qualityThresholdsVersion.trim().isEmpty) {
      throw ArgumentError(
        'Evidence provenance version and metric fields are required.',
      );
    }
  }

  final String metricId;
  final EvidenceWindow window;
  final String modelVersion;
  final GeometrySource geometrySource;
  final SyncQuality syncQuality;
  final String thresholdsVersion;
  final String qualityThresholdsVersion;

  Map<String, Object> toJson() => <String, Object>{
    'metricId': metricId,
    'window': window.toJson(),
    'modelVersion': modelVersion,
    'geometrySource': geometrySource.name,
    'syncQuality': syncQuality.name,
    'thresholdsVersion': thresholdsVersion,
    'qualityThresholdsVersion': qualityThresholdsVersion,
  };
}
