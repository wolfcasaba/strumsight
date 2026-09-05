import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../first_win_providers.dart';

/// The first-win mini Stage (ADR 0281 §2, A3/A5): a single scored attempt on
/// the round's own fake motor (P2). A weak or uncertain reading is stated
/// plainly and offers a retry — it is never presented as success (A3, the
/// round's real-violation probe is in `docs/rounds/e13-r16-…md` §10). A
/// confidence-SOURCE failure (denied permission, busy mic, motor error) is a
/// separate, honest state (ADR 0534 D5) — it never collapses into the
/// "Listening…" state, and "Not now" stays reachable either way.
class FirstWinStageScreen extends ConsumerWidget {
  const FirstWinStageScreen({super.key, this.onContinue, this.onSkip});

  /// Fires when the user continues past a genuine (>= threshold) success.
  final VoidCallback? onContinue;

  /// "Not now" — leaves the Stage without a completed attempt.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>();
    final typography = Theme.of(context).extension<SsTypography>();
    // Riverpod 3.3.2: AsyncValue exposes `.value` (nullable), not
    // `.valueOrNull`.
    final asyncConfidence = ref.watch(onboardingFirstWinConfidenceProvider);
    final confidence = asyncConfidence.value;
    final hasAttempt = confidence != null;
    final success = hasAttempt && isFirstWinSuccess(confidence);
    final hasError = asyncConfidence.hasError;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(SsSpacing.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasError
                      ? Icons.mic_off_outlined
                      : !hasAttempt
                      ? Icons.mic_outlined
                      : success
                      ? Icons.celebration_outlined
                      : Icons.graphic_eq,
                  size: 48,
                  color: success ? colors?.success : colors?.textSecondary,
                ),
                const SizedBox(height: SsSpacing.space4),
                Text(
                  hasError
                      ? l10n.micPermissionBody
                      : !hasAttempt
                      ? l10n.onboardFirstWinListening
                      : success
                      ? l10n.onboardFirstWinSuccessTitle
                      : l10n.onboardFirstWinWeakTitle,
                  key: const ValueKey('onboard-first-win-title'),
                  style: typography?.titleLarge.copyWith(
                    color: colors?.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!hasError && hasAttempt) ...[
                  const SizedBox(height: SsSpacing.space2),
                  Text(
                    success
                        ? l10n.onboardFirstWinSuccessBody
                        : l10n.onboardFirstWinWeakBody,
                    key: const ValueKey('onboard-first-win-body'),
                    style: typography?.bodyMedium.copyWith(
                      color: colors?.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: SsSpacing.space6),
                if (hasError)
                  FilledButton(
                    key: const ValueKey('onboard-first-win-open-settings'),
                    onPressed: openAppSettings,
                    child: Text(l10n.micPermissionAction),
                  )
                else if (success)
                  FilledButton(
                    key: const ValueKey('onboard-first-win-continue'),
                    onPressed: onContinue,
                    child: Text(l10n.onboardFirstWinContinueAction),
                  )
                else if (hasAttempt)
                  FilledButton(
                    key: const ValueKey('onboard-first-win-retry'),
                    onPressed: () =>
                        ref.invalidate(onboardingFirstWinEngineProvider),
                    child: Text(l10n.onboardFirstWinRetryAction),
                  ),
                TextButton(
                  key: const ValueKey('onboard-first-win-skip'),
                  onPressed: onSkip,
                  child: Text(l10n.onboardFirstWinSkipAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
