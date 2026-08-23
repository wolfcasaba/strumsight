/// Analysis → Community share-artifact mapper (E09-R10, ADR 0404 §D1).
///
/// Builds an [AnalysisImprovementArtifact] from an
/// [AnalysisComparison] (the "two sessions, before/after" surface
/// from `audio_analysis/domain/comparison/analysis_comparison.dart`).
///
/// The mapper imports only the audio_analysis `public.dart` barrel
/// — never the engine internals, never the waveform/landmark/sample
/// buffer types. The artifact only carries the per-metric verdicts
/// (metricId + directionCode + the three numeric deltas). The
/// §6.1 measure-matrix "raw audio / waveform / landmark" row is
/// enforced by ABSENCE.
library;

import 'package:strumsight/features/audio_analysis/public.dart';

import '../../domain/entities/share_artifact.dart';

/// Wire codes mirroring [MetricComparisonDirection]. The Community
/// domain does NOT import the audio_analysis enum directly — the
/// mapper translates at the seam (ADR 0404 §D2, brief §A1).
const String _directionImproved = 'improved';
const String _directionRegressed = 'regressed';
const String _directionUnchanged = 'unchanged';
const String _directionInconclusive = 'inconclusive';

String _encodeDirection(MetricComparisonDirection direction) {
  return switch (direction) {
    MetricComparisonDirection.improved => _directionImproved,
    MetricComparisonDirection.regressed => _directionRegressed,
    MetricComparisonDirection.unchanged => _directionUnchanged,
    MetricComparisonDirection.inconclusive => _directionInconclusive,
  };
}

/// Builds an [AnalysisImprovementArtifact] from an [AnalysisComparison].
///
/// The `sourceId` is the COMPARISON id (a stable id the
/// audio_analysis feature assigns to the comparison record, not
/// the internal `beforeAnalysisId`/`afterAnalysisId` pair —
/// those are private to the feature).
AnalysisImprovementArtifact analysisImprovementFromComparison(
  AnalysisComparison comparison, {
  required DateTime createdAt,
  required String sourceId,
  int schemaVersion = shareArtifactSchemaVersion,
}) {
  return AnalysisImprovementArtifact(
    schemaVersion: schemaVersion,
    sourceId: sourceId,
    createdAt: createdAt,
    metrics: comparison.metrics
        .map(
          (m) => MetricImprovement(
            metricId: m.metricId,
            directionCode: _encodeDirection(m.direction),
            beforeValue: m.beforeValue,
            afterValue: m.afterValue,
            relativeDelta: m.relativeDelta,
          ),
        )
        .toList(growable: false),
  );
}