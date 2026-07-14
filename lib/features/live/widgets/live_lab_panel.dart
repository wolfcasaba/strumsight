import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../diagnostics/widgets/diagnostics_panel.dart';
import '../providers/live_lab_provider.dart';

/// Lab-mode Live panel (r199): a button that captures the last ~30 s of mic
/// audio (external guitar played into the phone) and runs the ML+DSP chord
/// comparison, then shows the reused [DiagnosticsPanel] with the ML-vs-DSP
/// result + upload status. Only mounted while Lab mode is on (the Live screen
/// gates it). Theme tokens + ARB only; never blocks the mic.
class LiveLabPanel extends ConsumerWidget {
  const LiveLabPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final labState = ref.watch(liveLabProvider);
    final analyzing = labState.phase == LiveLabPhase.analyzing;
    final result = labState.result;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.labDiagnosticsTitle,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: palette.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: analyzing
                    ? null
                    : () =>
                        ref.read(liveLabProvider.notifier).captureAndAnalyze(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: palette.onAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                child: analyzing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        l10n.labCaptureUpload,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
              ),
            ],
          ),
          if (labState.phase == LiveLabPhase.empty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.labCaptureEmpty,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: palette.muted,
                ),
              ),
            ),
          if (result != null && result.diagnostics != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: DiagnosticsPanel(result: result),
              ),
            ),
        ],
      ),
    );
  }
}
