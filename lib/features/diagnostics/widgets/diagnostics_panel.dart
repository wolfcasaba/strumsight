import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../analyze/engine/ml_chord_decoder.dart';
import '../../analyze/model/analyze_result.dart';
import '../data/diagnostics_uploader.dart';
import '../providers/diagnostics_providers.dart';

/// Lab-mode ML-vs-DSP diagnostics panel (r198). Shown ONLY when Lab mode is on
/// and the Analyze result carries [MlChordDiagnostics]: the ML↔DSP agreement %,
/// a compact per-segment ML-vs-DSP comparison, and the upload status. Theme
/// tokens + ARB only.
class DiagnosticsPanel extends ConsumerWidget {
  const DiagnosticsPanel({super.key, required this.result});

  final AnalyzeResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diag = result.diagnostics;
    if (diag == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final uploadStatus = ref.watch(diagnosticsUploadProvider);
    final agreementPct = (diag.agreement.clamp(0.0, 1.0) * 100).round();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                l10n.labDiagnosticsTitle,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: palette.ink,
                ),
              ),
              const Spacer(),
              Text(
                '${l10n.labModeAgreement}  $agreementPct%',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Legend(l10n: l10n, palette: palette),
          const SizedBox(height: 8),
          ..._rows(context, palette, diag.mlChords),
          const SizedBox(height: 10),
          _UploadStatusLine(status: uploadStatus, l10n: l10n, palette: palette),
        ],
      ),
    );
  }

  List<Widget> _rows(
      BuildContext context, AppPalette palette, List<TimelineChord> mlChords) {
    return [
      for (final seg in mlChords)
        Builder(builder: (_) {
          final mid = (seg.startSec + seg.endSec) / 2;
          final dspLabel = _labelAt(result.chords, mid);
          final agree = MlChordDecoder.majminReduce(seg.label) ==
              MlChordDecoder.majminReduce(dspLabel);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    '${seg.startSec.toStringAsFixed(1)}s',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      color: palette.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    seg.label,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: palette.ink,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    dspLabel ?? '—',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: palette.muted,
                    ),
                  ),
                ),
                Icon(
                  agree ? Icons.check_circle : Icons.remove_circle_outline,
                  size: 16,
                  color: agree ? AppColors.primary : palette.muted,
                ),
              ],
            ),
          );
        }),
    ];
  }

  static String? _labelAt(List<TimelineChord> chords, double t) {
    for (final c in chords) {
      if (t >= c.startSec && t < c.endSec) return c.label;
    }
    return null;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.l10n, required this.palette});

  final AppLocalizations l10n;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    TextStyle head() => TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0.8,
          color: palette.muted,
        );
    return Row(
      children: [
        const SizedBox(width: 44),
        Expanded(child: Text(l10n.labMlChord, style: head())),
        Expanded(child: Text(l10n.labDspChord, style: head())),
        const SizedBox(width: 16),
      ],
    );
  }
}

class _UploadStatusLine extends StatelessWidget {
  const _UploadStatusLine({
    required this.status,
    required this.l10n,
    required this.palette,
  });

  final DiagnosticsUploadStatus status;
  final AppLocalizations l10n;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (status) {
      DiagnosticsUploadStatus.uploading => (
          null,
          l10n.labUploading,
          palette.muted,
        ),
      DiagnosticsUploadStatus.uploaded => (
          Icons.cloud_done_outlined,
          l10n.labUploaded,
          AppColors.primary,
        ),
      DiagnosticsUploadStatus.failed => (
          Icons.cloud_off_outlined,
          l10n.labUploadFailed,
          palette.muted,
        ),
      DiagnosticsUploadStatus.idle => (null, null, palette.muted),
    };
    if (label == null) return const SizedBox.shrink();
    return Row(
      children: [
        if (status == DiagnosticsUploadStatus.uploading)
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (icon != null)
          Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }
}
