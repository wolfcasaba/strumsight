// Song Trainer result screen.
//
// Brief §6 acceptance: "Chord/direction/note verdict, accessible measure
// heatmap, problem range retry és next section működik."

import 'package:flutter/material.dart';

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
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (progress case final current?) ...<Widget>[
              _ProgressSummary(progress: current),
              const SizedBox(height: 16),
            ],
            if (setlistResult case final setlist?) ...<Widget>[
              _SetlistSummary(result: setlist),
              const SizedBox(height: 16),
            ],
            MeasureHeatmap(
              measureResults: result.measureResults,
              sectionResults: result.sectionResults,
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('song-result-retry'),
              onPressed: onRetry,
              child: Text(l10n.songTrainerRetryProblemRange),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('song-result-next-section'),
              onPressed: onNextSection,
              child: Text(l10n.songTrainerNextSection),
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
    return Semantics(
      key: const Key('song-result-progress'),
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.songTrainerProgressTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                measures.isEmpty
                    ? l10n.songTrainerProgressEmpty
                    : l10n.songTrainerProgressSummary(
                        measures.length,
                        (bestScore! * 100).round(),
                      ),
              ),
            ],
          ),
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
    return Semantics(
      key: const Key('song-result-setlist'),
      container: true,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.songTrainerSetlistResultTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(l10n.songTrainerSetlistResultSummary(completed, skipped)),
            ],
          ),
        ),
      ),
    );
  }
}

double _maxScore(double left, double right) => left > right ? left : right;
