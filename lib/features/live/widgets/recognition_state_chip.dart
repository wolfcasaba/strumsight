import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/recognition/recognition_decision.dart';

/// The Live stage's single, always-honest statement of WHICH decision state
/// the chord recognizer is in (E14-R37, ADR 0550 D1).
///
/// Every one of the six [RecognitionDecision] states of ADR 0505 D3 renders
/// **distinctly** — its own icon, its own colour role and its own localized
/// sentence — through one exhaustive `switch` expression with no `default`
/// arm, so adding a seventh state is a compile error here rather than a
/// silently generic chip (the [UncertaintyReasonBanner] contract, applied to
/// the decision axis instead of the reject-reason axis).
///
/// The chip states the recognizer's CONFIDENCE STATE; it never states a
/// chord as recognised. Only [RecognitionDecision.confirmed] lets the stage's
/// hero present a chord at all — see `LiveFrame`-side gating in
/// `live_screen.dart` — and [RecognitionDecision.provisional] names the
/// chord only inside an explicitly hedged sentence ("Settling on C…"), never
/// as a verdict (ADR 0271 §1: UNKNOWN > CONFIDENTLY WRONG).
class RecognitionStateChip extends StatelessWidget {
  const RecognitionStateChip({
    super.key,
    required this.decision,
    this.chordLabel,
  });

  /// The frame's typed chord verdict. Callers skip this widget entirely when
  /// the producer supplies no decision at all (`null`) — an absent decision
  /// is not a state, and inventing one for it would be a claim.
  final RecognitionDecision decision;

  /// The chord the recognizer is working on, when one is known. Used ONLY by
  /// the hedged [RecognitionDecision.provisional] sentence.
  final String? chordLabel;

  /// The localized sentence for [decision]. Exhaustive by construction.
  static String textFor(
    AppLocalizations l10n,
    RecognitionDecision decision,
    String? chordLabel,
  ) => switch (decision) {
    RecognitionDecision.candidate => l10n.liveDecisionCandidate,
    RecognitionDecision.provisional =>
      chordLabel == null || chordLabel.isEmpty
          ? l10n.liveDecisionProvisional
          : l10n.liveDecisionProvisionalNamed(chordLabel),
    RecognitionDecision.confirmed => l10n.liveDecisionConfirmed,
    RecognitionDecision.uncertain => l10n.liveDecisionUncertain,
    RecognitionDecision.rejected => l10n.liveDecisionRejected,
    RecognitionDecision.expired => l10n.liveDecisionExpired,
  };

  /// A shape cue that survives full colour loss (E14-R39 lelet: the
  /// confidence tokens are one grey in greyscale) — every state has its own
  /// glyph, not just its own hue.
  static IconData iconFor(RecognitionDecision decision) => switch (decision) {
    RecognitionDecision.candidate => Icons.hearing,
    RecognitionDecision.provisional => Icons.more_horiz,
    RecognitionDecision.confirmed => Icons.check_circle_outline,
    RecognitionDecision.uncertain => Icons.help_outline,
    RecognitionDecision.rejected => Icons.block,
    RecognitionDecision.expired => Icons.history_toggle_off,
  };

  Color _colorFor(BuildContext context) => switch (decision) {
    RecognitionDecision.confirmed => AppColors.success,
    RecognitionDecision.candidate ||
    RecognitionDecision.provisional => AppColors.primary,
    RecognitionDecision.uncertain ||
    RecognitionDecision.rejected => AppColors.danger,
    RecognitionDecision.expired => context.palette.muted,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final text = textFor(l10n, decision, chordLabel);
    final color = _colorFor(context);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Container(
        key: ValueKey('live-decision-${decision.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(iconFor(decision), size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: palette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
