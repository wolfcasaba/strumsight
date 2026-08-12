import 'package:flutter/material.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';

import '../../../l10n/app_localizations.dart';

/// Small, host-agnostic progress surface for a cancellable V2 analysis.
///
/// Unit counts are optional pipeline evidence. No estimate is rendered when a
/// stage did not supply both values, avoiding a misleading synthetic percent.
final class AnalysisProgressView extends StatelessWidget {
  const AnalysisProgressView({
    required this.phase,
    required this.onCancel,
    this.completedUnits,
    this.totalUnits,
    super.key,
  });

  final AnalysisProgressPhase phase;
  final VoidCallback onCancel;
  final int? completedUnits;
  final int? totalUnits;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unitsAvailable = completedUnits != null && totalUnits != null;
    final progress = unitsAvailable ? completedUnits! / totalUnits! : null;
    return Semantics(
      container: true,
      label: l10n.analysisProgressSemantics(_phaseTitle(l10n)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            _phaseTitle(l10n),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(_phaseDescription(l10n)),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: l10n.analysisProgressCancel,
            child: OutlinedButton(
              onPressed: onCancel,
              child: Text(l10n.analysisProgressCancel),
            ),
          ),
        ],
      ),
    );
  }

  String _phaseTitle(AppLocalizations l10n) => switch (phase) {
    AnalysisProgressPhase.preparing => l10n.analysisProgressPreparing,
    AnalysisProgressPhase.validatingInput => l10n.analysisProgressValidating,
    AnalysisProgressPhase.preprocessing => l10n.analysisProgressPreprocessing,
    AnalysisProgressPhase.extractingEvents => l10n.analysisProgressExtracting,
    AnalysisProgressPhase.estimatingHarmony => l10n.analysisProgressHarmony,
    AnalysisProgressPhase.estimatingBeatGrid => l10n.analysisProgressBeatGrid,
    AnalysisProgressPhase.computingMetrics => l10n.analysisProgressMetrics,
    AnalysisProgressPhase.buildingInsights => l10n.analysisProgressInsights,
    AnalysisProgressPhase.finalizing => l10n.analysisProgressFinalizing,
  };

  String _phaseDescription(AppLocalizations l10n) => switch (phase) {
    AnalysisProgressPhase.preparing =>
      l10n.analysisProgressPreparingDescription,
    AnalysisProgressPhase.validatingInput =>
      l10n.analysisProgressValidatingDescription,
    AnalysisProgressPhase.preprocessing =>
      l10n.analysisProgressPreprocessingDescription,
    AnalysisProgressPhase.extractingEvents =>
      l10n.analysisProgressExtractingDescription,
    AnalysisProgressPhase.estimatingHarmony =>
      l10n.analysisProgressHarmonyDescription,
    AnalysisProgressPhase.estimatingBeatGrid =>
      l10n.analysisProgressBeatGridDescription,
    AnalysisProgressPhase.computingMetrics =>
      l10n.analysisProgressMetricsDescription,
    AnalysisProgressPhase.buildingInsights =>
      l10n.analysisProgressInsightsDescription,
    AnalysisProgressPhase.finalizing =>
      l10n.analysisProgressFinalizingDescription,
  };
}
