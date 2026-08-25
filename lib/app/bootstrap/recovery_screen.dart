import 'package:flutter/material.dart';

import '../../core/design_system/foundations/ss_colors.dart';
import '../../core/design_system/foundations/ss_spacing.dart';
import '../../core/design_system/foundations/ss_typography.dart';
import '../../l10n/app_localizations.dart';

/// The in-app "safe mode" surface (ADR 0281 §3/§6, SDD Ch13 Kör 16).
///
/// Distinct from [BootstrapFailureApp] in `lib/app/strumsight_app.dart`
/// (the pre-first-frame, provider-free fallback `main` uses when bootstrap
/// itself cannot run): this screen is reachable from inside the running app
/// (see [AppRoutes.recovery]) for a controlled, in-app degraded state.
///
/// [problems] must already be redacted, code-based strings — this widget
/// renders them verbatim and never interpolates a raw exception itself. It
/// offers no data-deleting action: safe mode is a recovery surface, not a
/// factory reset (§5.3). The only action is a non-destructive [onRetry].
class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({required this.problems, this.onRetry, super.key});

  /// One entry per redacted problem. Never a raw exception's `toString()`.
  final List<String> problems;

  /// Re-attempts whatever operation failed. Null hides the retry button —
  /// some failures (e.g. a corrupt config) have nothing to retry.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>();
    final typography = Theme.of(context).extension<SsTypography>();
    final titleStyle = typography?.titleLarge.copyWith(
      color: colors?.textPrimary,
    );
    final bodyStyle = typography?.bodyMedium.copyWith(
      color: colors?.textSecondary,
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SsSpacing.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 56,
                  color: colors?.textSecondary,
                ),
                const SizedBox(height: SsSpacing.space4),
                Text(
                  l10n.recoveryTitle,
                  style: titleStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SsSpacing.space2),
                Text(
                  l10n.recoveryBody,
                  style: bodyStyle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SsSpacing.space4),
                for (final problem in problems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SsSpacing.space2),
                    child: Text(
                      '• $problem',
                      style: bodyStyle,
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: SsSpacing.space4),
                Text(
                  l10n.recoveryDataSafeNotice,
                  style: bodyStyle,
                  textAlign: TextAlign.center,
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: SsSpacing.space6),
                  FilledButton(
                    onPressed: onRetry,
                    child: Text(l10n.recoveryRetryAction),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
