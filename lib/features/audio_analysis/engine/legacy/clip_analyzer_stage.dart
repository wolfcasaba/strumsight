import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_provenance_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_stage.dart';

import 'legacy_evidence.dart';

/// V2 stage adapter for the unchanged, public V1 clip-analysis entrypoint.
final class ClipAnalyzerStage
    implements AnalysisStage<LegacyClipAnalyzerInput, LegacyEvidence> {
  const ClipAnalyzerStage({
    this.provenanceBuilder = const AnalysisProvenanceBuilder(),
  });

  final AnalysisProvenanceBuilder provenanceBuilder;

  @override
  String get id => 'clip-analyzer-legacy';

  @override
  int get version => 1;

  @override
  Future<AppResult<LegacyEvidence>> run(
    LegacyClipAnalyzerInput input,
    AnalysisStageContext context,
  ) async {
    context.cancellationToken.throwIfCancelled();
    final weights = input.strumRefinerWeights;
    final candidate = runClipAnalysis((
      input.samples,
      input.sampleRate,
      weights,
      false,
      null,
    ));
    final outcome = _refinerOutcome(input, candidate.strums, weights);
    context.cancellationToken.throwIfCancelled();

    final provenance = provenanceBuilder.build(
      strumRefinerSource: outcome.source,
      fallbackReason: outcome.fallbackReason,
    );
    return Success<LegacyEvidence>(
      LegacyEvidence.fromAnalyzeResult(
        candidate,
        call: LegacyClipAnalyzerCall(
          sampleRate: input.sampleRate,
          sampleCount: input.samples.length,
          labMode: false,
          hasCandidateStrumRefiner: weights != null,
          modelManifestIds: provenance.modelManifestIds,
        ),
        provenance: provenance,
      ),
    );
  }

  _RefinerOutcome _refinerOutcome(
    LegacyClipAnalyzerInput input,
    List<TimelineStrum> candidateStrums,
    Object? weights,
  ) {
    if (weights == null) return const _RefinerOutcome.none();

    final baseline = runClipAnalysis((
      input.samples,
      input.sampleRate,
      null,
      false,
      null,
    ));
    if (_sameStrumLabelsAndConfidence(candidateStrums, baseline.strums)) {
      return const _RefinerOutcome.heuristic(
        AnalysisProvenanceBuilder.candidateMatchesHeuristicFallback,
      );
    }
    return const _RefinerOutcome.crnn();
  }

  bool _sameStrumLabelsAndConfidence(
    List<TimelineStrum> candidate,
    List<TimelineStrum> baseline,
  ) {
    if (candidate.length != baseline.length) return false;
    for (var index = 0; index < candidate.length; index++) {
      if (candidate[index].direction != baseline[index].direction ||
          candidate[index].confidence != baseline[index].confidence) {
        return false;
      }
    }
    return true;
  }
}

final class _RefinerOutcome {
  const _RefinerOutcome.none()
    : source = StrumRefinerSource.none,
      fallbackReason = null;

  const _RefinerOutcome.heuristic(this.fallbackReason)
    : source = StrumRefinerSource.heuristic;

  const _RefinerOutcome.crnn()
    : source = StrumRefinerSource.crnn,
      fallbackReason = null;

  final StrumRefinerSource source;
  final String? fallbackReason;
}
