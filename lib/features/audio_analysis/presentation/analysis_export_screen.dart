import 'package:flutter/material.dart';

import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../application/export_analysis_use_case.dart';
import '../domain/analysis_document.dart';
import 'widgets/export_preview.dart';

/// Export/share entry point (ADR 0247, brief §5 Döntés 4 "Előnézet
/// kötelező"). The preview always renders first; [ExportAnalysisUseCase.
/// share] only ever runs from the explicit confirm action below — there is
/// no code path that shares before the user has seen [ExportPreview].
class AnalysisExportScreen extends StatefulWidget {
  const AnalysisExportScreen({
    required this.document,
    required this.exportUseCase,
    super.key,
  });

  final AnalysisDocument document;
  final ExportAnalysisUseCase exportUseCase;

  @override
  State<AnalysisExportScreen> createState() => _AnalysisExportScreenState();
}

class _AnalysisExportScreenState extends State<AnalysisExportScreen> {
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final export = widget.exportUseCase.preview(widget.document);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisExportTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(child: ExportPreview(export: export)),
            Padding(
              padding: const EdgeInsets.all(SsSpacing.space4),
              child: SizedBox(
                width: double.infinity,
                child: SsButton(
                  key: const Key('analysis-export-confirm'),
                  label: l10n.analysisExportConfirmShare,
                  loading: _sharing,
                  onPressed: _handleConfirm,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleConfirm() async {
    final caption = AppLocalizations.of(context).analysisExportCaption;
    setState(() => _sharing = true);
    try {
      await widget.exportUseCase.share(
        document: widget.document,
        caption: caption,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
