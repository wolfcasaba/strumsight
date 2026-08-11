import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';

import 'analysis_context.dart';

/// One asynchronous, cancellable unit in the analysis pipeline (SDD Ch7 §8.5).
abstract interface class AnalysisStage<I, O> {
  String get id;
  int get version;

  Future<AppResult<O>> run(I input, AnalysisStageContext context);
}

/// Classifies an expected [AppFailure] at the pipeline boundary without
/// widening the sealed core [AppFailure] hierarchy.
final class StageFailure {
  const StageFailure.degradable(
    this.failure, {
    this.unavailableCapabilities = const <AnalysisCapability>{},
  }) : isDegradable = true;

  const StageFailure.fatal(this.failure)
    : isDegradable = false,
      unavailableCapabilities = const <AnalysisCapability>{};

  final AppFailure failure;
  final bool isDegradable;
  final Set<AnalysisCapability> unavailableCapabilities;
}

/// Composition-owned policy: a stage returns a regular [AppResult], then the
/// pipeline decides whether that expected failure can degrade the whole run.
typedef AnalysisStageFailureClassifier =
    StageFailure Function(String stageId, AppFailure failure);
