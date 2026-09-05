import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/recognition/recognition_decision.dart';

/// The Stage `feedback` slot's single source of "why didn't this register a
/// chord" (ADR 0520 D1/D4): maps the MERGED, closed [RecognitionRejectReason]
/// (ADR 0505 D3) to localized text with an exhaustive `switch` expression —
/// no `default`/`_` arm, so a future enum member is a compile error here, not
/// a silently-generic message (D2).
///
/// Shown only when `LiveFrame.chordRejectReason != null`; when it is `null`
/// (no decision yet, or a confirmed chord) the caller keeps using the
/// pre-existing heuristic feedback instead (ADR 0520 D5) — this widget makes
/// no such decision itself (D6).
class UncertaintyReasonBanner extends StatelessWidget {
  const UncertaintyReasonBanner({super.key, required this.reason});

  final RecognitionRejectReason reason;

  /// The localized text for [reason]. Exhaustive by construction: adding a
  /// [RecognitionRejectReason] value without adding a matching case here is a
  /// compile error, never a silent fallback.
  static String textFor(
    AppLocalizations l10n,
    RecognitionRejectReason reason,
  ) => switch (reason) {
    RecognitionRejectReason.lowConfidence => l10n.liveRejectLowConfidence,
    RecognitionRejectReason.unstable => l10n.liveRejectUnstable,
    RecognitionRejectReason.signalQuality => l10n.liveRejectSignalQuality,
    RecognitionRejectReason.noChord => l10n.liveRejectNoChord,
    RecognitionRejectReason.modelUnavailable => l10n.liveRejectModelUnavailable,
    RecognitionRejectReason.timeout => l10n.liveRejectTimeout,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 14, color: AppColors.danger),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              textFor(l10n, reason),
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
    );
  }
}
