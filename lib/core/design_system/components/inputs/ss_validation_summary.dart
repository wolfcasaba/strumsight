import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';

/// One field-level validation failure: [fieldLabel] identifies which field
/// it belongs to in the summary list, [message] is the localized reason.
/// Both are hívó-oldali (caller-supplied) — only the screen owning the form
/// knows its own fields and validation rules (same string-ownership rule as
/// [SsEmptyState]); [SsValidationSummary] itself only owns the generic
/// heading and the screen-reader announcement copy, sourced from
/// `design_system_{en,hu}.arb`.
final class SsValidationIssue {
  const SsValidationIssue({required this.fieldLabel, required this.message});

  final String fieldLabel;
  final String message;
}

/// The common validation summary shown at the top of a form (§3). Renders
/// nothing when [issues] is empty — a summary with no problems is visual
/// noise, and its `liveRegion` would announce "no issues" on every keypress.
final class SsValidationSummary extends StatelessWidget {
  const SsValidationSummary({
    super.key,
    required this.l10n,
    required this.issues,
  });

  final AppLocalizations l10n;
  final List<SsValidationIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;

    return Semantics(
      container: true,
      liveRegion: true,
      label: l10n.dsValidationSummarySemanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: colors.danger, size: 20),
              const SizedBox(width: SsSpacing.space2),
              Expanded(
                child: Text(
                  l10n.dsValidationSummaryTitle,
                  style: typography.titleMedium.copyWith(color: colors.danger),
                ),
              ),
            ],
          ),
          const SizedBox(height: SsSpacing.space2),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: SsSpacing.space1),
              child: SsFieldError(l10n: l10n, message: issue.message),
            ),
        ],
      ),
    );
  }
}

/// The mező-szintű (field-level) inline error shown directly under a field.
/// [message] is hívó-oldali (the caller's validation rule already localized
/// it); [SsFieldError] itself only owns the "Error" prefix a screen reader
/// announces before it, from `design_system_{en,hu}.arb`.
final class SsFieldError extends StatelessWidget {
  const SsFieldError({super.key, required this.l10n, required this.message});

  final AppLocalizations l10n;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;

    return Semantics(
      label: '${l10n.dsFieldErrorSemanticPrefix}: $message',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colors.danger, size: 16),
          const SizedBox(width: SsSpacing.space1),
          Expanded(
            child: Text(
              message,
              style: typography.bodyMedium.copyWith(color: colors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
