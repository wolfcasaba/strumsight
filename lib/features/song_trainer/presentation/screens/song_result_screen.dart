// Song Trainer result screen.
//
// Brief §6 acceptance: "Chord/direction/note verdict, accessible measure
// heatmap, problem range retry és next section működik."

import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/progress/song_progress_aggregator.dart';
import '../../application/trainer/song_trainer_result.dart';
import '../../domain/models/setlist_result.dart';
import '../widgets/measure_heatmap.dart';

/// Post-session result screen for the Song Trainer coach.
final class SongResultScreen extends StatelessWidget {
  const SongResultScreen({
    super.key,
    required this.result,
    this.progress,
    this.setlistResult,
    this.onRetry,
    this.onNextSection,
  });

  final SongTrainerResult result;
  final SongProgressAggregate? progress;
  final SetlistResult? setlistResult;
  final VoidCallback? onRetry;
  final VoidCallback? onNextSection;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.songTrainerResultTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SsSpacing.space4),
          children: <Widget>[
            if (progress case final current?) ...<Widget>[
              _ProgressSummary(progress: current),
              const SizedBox(height: SsSpacing.space4),
            ],
            if (setlistResult case final setlist?) ...<Widget>[
              _SetlistSummary(result: setlist),
              const SizedBox(height: SsSpacing.space4),
            ],
            MeasureHeatmap(
              measureResults: result.measureResults,
              sectionResults: result.sectionResults,
            ),
            const SizedBox(height: SsSpacing.space4),
            SsButton(
              key: const Key('song-result-retry'),
              onPressed: onRetry,
              label: l10n.songTrainerRetryProblemRange,
            ),
            const SizedBox(height: SsSpacing.space2),
            SsButton(
              key: const Key('song-result-next-section'),
              onPressed: onNextSection,
              variant: SsButtonVariant.secondary,
              label: l10n.songTrainerNextSection,
            ),
          ],
        ),
      ),
    );
  }
}

final class _ProgressSummary extends StatelessWidget {
  const _ProgressSummary({required this.progress});

  final SongProgressAggregate progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final measures = progress.measures;
    final bestScore = measures.isEmpty
        ? null
        : measures.map((measure) => measure.bestScore).reduce(_maxScore);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Semantics(
      key: const Key('song-result-progress'),
      container: true,
      child: SsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.songTrainerProgressTitle,
              style: typography.titleMedium.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: SsSpacing.space2),
            Text(
              measures.isEmpty
                  ? l10n.songTrainerProgressEmpty
                  : l10n.songTrainerProgressSummary(
                      measures.length,
                      (bestScore! * 100).round(),
                    ),
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SetlistSummary extends StatelessWidget {
  const _SetlistSummary({required this.result});

  final SetlistResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final completed = result.itemResults
        .where((item) => item.status == SetlistItemResultStatus.completed)
        .length;
    final skipped = result.itemResults
        .where((item) => item.status == SetlistItemResultStatus.skipped)
        .length;
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Semantics(
      key: const Key('song-result-setlist'),
      container: true,
      child: SsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              l10n.songTrainerSetlistResultTitle,
              style: typography.titleMedium.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: SsSpacing.space2),
            Text(
              l10n.songTrainerSetlistResultSummary(completed, skipped),
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _maxScore(double left, double right) => left > right ? left : right;
