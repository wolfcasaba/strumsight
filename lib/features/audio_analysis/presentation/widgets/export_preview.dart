import 'package:flutter/material.dart';

import 'package:strumsight/l10n/app_localizations.dart';

import '../../domain/export/analysis_export.dart';

/// Lists the *categories* the redacted export contains — never the raw
/// JSON — so the user can see what leaves the device before confirming a
/// share (brief §6 "Előnézet-kapu" / "UI" acceptance cells).
class ExportPreview extends StatelessWidget {
  const ExportPreview({required this.export, super.key});

  final AnalysisExport export;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sections = <_ExportSectionRow>[
      _ExportSectionRow(l10n.analysisExportSectionInput, 1),
      _ExportSectionRow(l10n.analysisExportSectionSignalQuality, 1),
      _ExportSectionRow(
        l10n.analysisExportSectionCapabilities,
        export.capabilities.length,
      ),
      _ExportSectionRow(
        l10n.analysisExportSectionMetrics,
        export.metrics.length,
      ),
      _ExportSectionRow(
        l10n.analysisExportSectionHotspots,
        export.hotspots.length,
      ),
      _ExportSectionRow(
        l10n.analysisExportSectionInsights,
        export.insights.length,
      ),
      _ExportSectionRow(
        l10n.analysisExportSectionWarnings,
        export.warnings.length,
      ),
      _ExportSectionRow(l10n.analysisExportSectionCompletion, 1),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          l10n.analysisExportIntro,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        for (final section in sections) ...<Widget>[
          Card(
            child: ListTile(
              title: Text(section.label),
              trailing: Text(l10n.analysisExportSectionCount(section.count)),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

class _ExportSectionRow {
  const _ExportSectionRow(this.label, this.count);
  final String label;
  final int count;
}
