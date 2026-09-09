import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../diagnostics/public.dart';
import '../data/shadow/recognition_shadow_recorder.dart';
import '../model/recognition_runtime_info.dart';
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
              const Icon(
                Icons.science_outlined,
                size: 18,
                color: AppColors.primary,
              ),
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
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: analyzing
                  ? null
                  : () =>
                        ref.read(liveLabProvider.notifier).captureAndAnalyze(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: palette.onAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
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
          if (labState.shadow case final shadow?)
            _ShadowSection(shadow: shadow),
        ],
      ),
    );
  }
}

/// The E14-R23 / E14-R26 shadow report (Lab only).
///
/// Every line is either a FRACTION or an explicit "nothing comparable":
/// an empty sample has no agreement rate, and rendering `0%` or `100%` for
/// it would be a fabricated number (ADR 0271). The closing line restates the
/// invariant the whole round rests on — a shadow band can never change what
/// Live shows.
class _ShadowSection extends StatelessWidget {
  const _ShadowSection({required this.shadow});

  final RecognitionShadowSnapshot shadow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final lines = <String>[];

    if (!shadow.ranAnything) {
      lines.add(l10n.liveLabShadowOff);
    } else {
      final strum = shadow.strum;
      if (shadow.strumShadowEnabled) {
        lines.add(
          strum.comparedVerdicts == 0
              ? l10n.liveLabShadowStrumNoData
              : l10n.liveLabShadowStrumAgreement(
                  strum.agreed,
                  strum.comparedVerdicts,
                ),
        );
        if (strum.candidateVerdicts > 0) {
          lines.add(
            l10n.liveLabShadowStrumAbstained(
              strum.candidateAbstained + strum.bothAbstained,
              strum.candidateVerdicts,
            ),
          );
        }
      }
      if (shadow.chordShadowEnabled) {
        final reason = shadow.chordFallbackReason;
        if (reason != null) {
          lines.add(_chordFallbackText(l10n, reason));
        } else {
          final chord = shadow.chord;
          lines.add(
            chord.comparedFrames == 0
                ? l10n.liveLabShadowChordNoData
                : l10n.liveLabShadowChordAgreement(
                    chord.exactAgreed,
                    chord.comparedFrames,
                  ),
          );
        }
      }
      lines.add(
        l10n.liveLabShadowWindow(
          shadow.strumSamples.length + shadow.chordSamples.length,
          shadow.droppedStrumSamples + shadow.droppedChordSamples,
        ),
      );
    }
    lines.add(l10n.liveLabShadowNeverShown);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.liveLabShadowTitle,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                line,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: palette.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Maps the closed [FallbackReason] set onto localized copy — the raw enum
  /// name is never shown to a reader (AGENTS.md).
  static String _chordFallbackText(
    AppLocalizations l10n,
    FallbackReason reason,
  ) => switch (reason) {
    FallbackReason.assetMissing => l10n.liveLabShadowChordFallbackAssetMissing,
    FallbackReason.assetUnreadable =>
      l10n.liveLabShadowChordFallbackUnreadable,
    FallbackReason.parseFailed => l10n.liveLabShadowChordFallbackParse,
    FallbackReason.shapeMismatch => l10n.liveLabShadowChordFallbackShape,
    FallbackReason.disabledByFlag => l10n.liveLabShadowChordFallbackDisabled,
  };
}
