// Analyze entry point (SDD Ch13 Kör 26, UI-34).
//
// Route-free by design (brief §0.0/B3): this screen is reached and its
// callbacks are wired by whichever later round activates the route. It
// offers the two input modes (microphone recording, file import) and a
// preview of recent analyses; it never touches the analysis repository or
// input validator directly — the host supplies both the recent list and the
// mode callbacks.

import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/input/input_limits.dart';
import '../../domain/analysis_summary.dart';

/// The Analyze feature's landing screen.
final class AnalysisHomeScreen extends StatelessWidget {
  const AnalysisHomeScreen({
    required this.recentAnalyses,
    required this.onStartRecording,
    required this.onImportFile,
    this.onOpenAnalysis,
    super.key,
  });

  /// Most-recent-first list the host has already loaded. This screen never
  /// reads the analysis repository itself.
  final List<AnalysisSummary> recentAnalyses;

  final VoidCallback onStartRecording;
  final VoidCallback onImportFile;
  final void Function(AnalysisSummary summary)? onOpenAnalysis;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisHomeTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _InputModeCard(
              key: const Key('analysis-home-record'),
              icon: Icons.mic,
              title: l10n.analysisHomeRecordCta,
              description: l10n.analysisHomeRecordDescription,
              onTap: onStartRecording,
            ),
            const SizedBox(height: 12),
            _InputModeCard(
              key: const Key('analysis-home-import'),
              icon: Icons.file_upload_outlined,
              title: l10n.analysisHomeImportCta,
              description: l10n.analysisHomeImportDescription(
                InputLimits.maxFileBytes ~/ InputLimits.bytesPerMebibyte,
              ),
              onTap: onImportFile,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.analysisHomeRecentSectionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (recentAnalyses.isEmpty)
              Text(
                l10n.analysisHomeRecentEmpty,
                key: const Key('analysis-home-recent-empty'),
              )
            else
              for (final summary in recentAnalyses)
                _RecentAnalysisTile(
                  summary: summary,
                  onTap: onOpenAnalysis == null
                      ? null
                      : () => onOpenAnalysis!(summary),
                ),
          ],
        ),
      ),
    );
  }
}

final class _InputModeCard extends StatelessWidget {
  const _InputModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(description),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _RecentAnalysisTile extends StatelessWidget {
  const _RecentAnalysisTile({required this.summary, required this.onTap});

  final AnalysisSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = summary.title.isEmpty ? summary.documentId : summary.title;
    return Semantics(
      label: l10n.analysisHomeOpenAnalysisSemantics(title),
      button: onTap != null,
      child: ListTile(
        key: Key('analysis-home-recent-${summary.documentId}'),
        title: Text(title),
        subtitle: Text(_formatDate(summary.createdAt)),
        onTap: onTap,
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}
