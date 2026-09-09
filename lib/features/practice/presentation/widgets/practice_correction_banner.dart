import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../live/public.dart';
import '../../domain/model/practice_correction.dart';

/// The session feedback slot's "next fix" line (E14-R38, ADR 0551 D6).
///
/// It states ONE concrete correction and nothing else. Two kinds of sentence
/// can appear, and which one appears is the whole point of the round:
///
/// * the app abstained → the recognizer's own reject reason, in the SAME
///   words the Live uncertainty banner uses ("Too quiet — move closer to the
///   mic or play louder"). The player is told what to change about the
///   listening conditions, never that they played wrongly;
/// * the app was confident and the target was missed or wrong → the expected
///   chord ("Play C on the next target"), or the bare target when the
///   exercise has no chord.
///
/// The widget renders from the [PracticeCorrection] value alone, so it is
/// directly testable without a running session.
class PracticeCorrectionBanner extends StatelessWidget {
  const PracticeCorrectionBanner({super.key, required this.correction});

  final PracticeCorrection correction;

  /// The localized correction sentence. Exhaustive over
  /// [PracticeCorrectionKind]; a new kind is a compile error here.
  static String textFor(
    AppLocalizations l10n,
    PracticeCorrection correction,
  ) => switch (correction.kind) {
    PracticeCorrectionKind.recognitionUnclear => _rejectReasonText(
      l10n,
      correction.rejectReasonCode,
    ),
    PracticeCorrectionKind.playExpectedChord => l10n
        .practiceCorrectionPlayChord(correction.expectedChord ?? ''),
    PracticeCorrectionKind.hitTheTarget => l10n.practiceCorrectionHitTarget,
  };

  /// Decodes the stable reject-reason code the practice domain carries (a
  /// plain `String`, so that domain stays feature-independent) back into the
  /// typed Live reason, and states it in the SAME words the Live stage uses.
  ///
  /// An unknown or absent code yields the generic "could not tell" sentence
  /// rather than a guess — a correction the app cannot justify is not a
  /// correction (ADR 0271 §1). The exhaustive `switch` below and
  /// `UncertaintyReasonBanner.textFor` are pinned to the same strings by
  /// `practice_correction_banner_test.dart` (11 cells, one per reason).
  static String _rejectReasonText(AppLocalizations l10n, String? code) {
    final reason = _tryParseRejectReason(code);
    if (reason == null) return l10n.practiceCorrectionUnclear;
    return switch (reason) {
      RecognitionRejectReason.lowConfidence => l10n.liveRejectLowConfidence,
      RecognitionRejectReason.unstable => l10n.liveRejectUnstable,
      RecognitionRejectReason.signalTooQuiet => l10n.liveRejectSignalTooQuiet,
      RecognitionRejectReason.signalTooLoud => l10n.liveRejectSignalTooLoud,
      RecognitionRejectReason.signalClipping => l10n.liveRejectSignalClipping,
      RecognitionRejectReason.signalTooNoisy => l10n.liveRejectSignalTooNoisy,
      RecognitionRejectReason.signalSpeechLike =>
        l10n.liveRejectSignalSpeechLike,
      RecognitionRejectReason.signalUnstable => l10n.liveRejectSignalUnstable,
      RecognitionRejectReason.noChord => l10n.liveRejectNoChord,
      RecognitionRejectReason.modelUnavailable =>
        l10n.liveRejectModelUnavailable,
      RecognitionRejectReason.timeout => l10n.liveRejectTimeout,
    };
  }

  /// Tolerant lookup: `RecognitionRejectReason.fromJson` throws on an
  /// unknown name, which is right for a persisted contract but wrong here —
  /// a code this build does not know must degrade to the generic sentence,
  /// not crash the practice screen.
  static RecognitionRejectReason? _tryParseRejectReason(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final reason in RecognitionRejectReason.values) {
      if (reason.name == code) return reason;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('practice-correction'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.practiceCorrectionTitle,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    textFor(l10n, correction),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
