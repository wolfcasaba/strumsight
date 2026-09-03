// Analyze entry point (SDD Ch13 Kör 26, UI-34).
//
// Route-free by design (brief §0.0/B3): this screen is reached and its
// callbacks are wired by whichever later round activates the route. It
// offers the two input modes (microphone recording, file import) and a
// preview of recent analyses; it never touches the analysis repository or
// input validator directly — the host supplies both the recent list and the
// mode callbacks.

import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisHomeTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SsSpacing.space4),
          children: <Widget>[
            _InputModeCard(
              key: const Key('analysis-home-record'),
              icon: Icons.mic,
              title: l10n.analysisHomeRecordCta,
              description: l10n.analysisHomeRecordDescription,
              onTap: onStartRecording,
            ),
            const SizedBox(height: SsSpacing.space3),
            _InputModeCard(
              key: const Key('analysis-home-import'),
              icon: Icons.file_upload_outlined,
              title: l10n.analysisHomeImportCta,
              description: l10n.analysisHomeImportDescription(
                InputLimits.maxFileBytes ~/ InputLimits.bytesPerMebibyte,
              ),
              onTap: onImportFile,
            ),
            const SizedBox(height: SsSpacing.space6),
            if (recentAnalyses.isEmpty)
              SsEmptyState(
                key: const Key('analysis-home-recent-empty'),
                icon: Icons.history,
                title: l10n.analysisHomeRecentSectionTitle,
                message: l10n.analysisHomeRecentEmpty,
                actionLabel: l10n.analysisHomeRecordCta,
                onAction: onStartRecording,
              )
            else ...<Widget>[
              Text(
                l10n.analysisHomeRecentSectionTitle,
                style: typography.titleMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: SsSpacing.space2),
              for (final summary in recentAnalyses)
                _RecentAnalysisTile(
                  summary: summary,
                  onTap: onOpenAnalysis == null
                      ? null
                      : () => onOpenAnalysis!(summary),
                ),
            ],
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
    return SsContentCard(
      icon: icon,
      title: title,
      message: description,
      actions: [SsCardAction(label: title, onPressed: onTap)],
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
    final onTapCallback = onTap;
    return Padding(
      padding: const EdgeInsets.only(bottom: SsSpacing.space2),
      child: Semantics(
        label: l10n.analysisHomeOpenAnalysisSemantics(title),
        button: onTapCallback != null,
        child: SsContentCard(
          key: Key('analysis-home-recent-${summary.documentId}'),
          title: title,
          message: _formatDate(summary.createdAt),
          actions: onTapCallback == null
              ? const []
              : [SsCardAction(label: title, onPressed: onTapCallback)],
        ),
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
