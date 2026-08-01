import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_history_entry.dart';

/// Renders a simple visual bias for the timing of the session's last
/// [practiceHistoryDetailLimit] attempts.
///
/// The chart is intentionally tiny — the screen reader summary carries
/// the meaning (A11). Empty when the session kept no detail attempts.
///
/// The bias label is derived from the **session-level** signed
/// [timingBias] (negative = early, positive = late); the previous build
/// always emitted "balanced" regardless of input (M3), which made the
/// chart a colour-only signal even when the session was clearly late or
/// early.
class TimingBiasChart extends StatelessWidget {
  const TimingBiasChart({
    required this.detailAttempts,
    required this.timingBias,
    super.key,
  });

  final List<PracticeAttemptDetail> detailAttempts;

  /// Signed average timing error of the session. Negative ⇒ early,
  /// positive ⇒ late, |bias| ≤ [_balancedThresholdMicros] ⇒ balanced.
  final Duration timingBias;

  /// Below ±15 ms the human ear cannot reliably detect a directional bias.
  /// Anything under this is rendered as "on the beat".
  static const int _balancedThresholdMicros = 15000;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (detailAttempts.isEmpty) {
      return const SizedBox.shrink();
    }
    final biasDirection = _biasDirectionLabel(l10n, timingBias);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ExcludeSemantics blocks the `practiceResultTimingTitle`
            // Text from being merged into the inner semantics summary
            // (A1.4 — the chart must announce one sentence, not
            // "Timing: On the beat" plus "On the beat").
            ExcludeSemantics(
              child: Text(
                l10n.practiceResultTimingTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            Semantics(
              container: true,
              label: l10n.practiceResultTimingSemantic(biasDirection),
              child: ExcludeSemantics(child: Text(biasDirection)),
            ),
          ],
        ),
      ),
    );
  }

  String _biasDirectionLabel(AppLocalizations l10n, Duration bias) {
    final micros = bias.inMicroseconds;
    if (micros <= _balancedThresholdMicros &&
        micros >= -_balancedThresholdMicros) {
      return l10n.practiceResultTimingBalanced;
    }
    if (micros < 0) {
      return l10n.practiceResultTimingEarly;
    }
    return l10n.practiceResultTimingLate;
  }
}
