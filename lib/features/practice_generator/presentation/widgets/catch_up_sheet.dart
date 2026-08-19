import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// Non-shaming, fact-based explanation of how the practice plan handles
/// missed days, rest days and a longer break (ADR 0269, SDD Ch8 Kör 27).
///
/// Every line on the sheet comes from the ARB templates so the wording
/// is identical in English and Hungarian. The sheet never invents free
/// text — each row maps to a deterministic acceptance criterion:
///
///   * "No catch-up pressure" — A1, ADR 0258 §3.
///   * "Rest days stay rest" — A2.
///   * "Today's focus moves forward" — A6.
///   * "Travel doesn't count as a miss" — A7.
///   * "Coming back after a break" — A5, ADR 0269 §5.4.
///
/// The sheet never offers a "do more today" CTA and never references
/// the user's missed count or streak — keeping the tone neutral is a
/// hard acceptance criterion, not a style choice (ADR 0269 §5.5).
class CatchUpSheet extends StatelessWidget {
  const CatchUpSheet({super.key});

  /// Convenience helper for callers — mirrors the static `show` style
  /// used elsewhere in this feature (e.g. [PlanReasonSheet.show]).
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => const CatchUpSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.practicePlanCatchUpSheetTitle,
              key: const Key('catch-up-title'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.practicePlanCatchUpSheetBody,
              key: const Key('catch-up-body'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _CatchUpRow(
              keyId: 'catch-up-row-no-backlog',
              title: l10n.practicePlanCatchUpSheetNoBacklogTitle,
              body: l10n.practicePlanCatchUpSheetNoBacklogBody,
            ),
            _CatchUpRow(
              keyId: 'catch-up-row-rest-day',
              title: l10n.practicePlanCatchUpSheetRestDayTitle,
              body: l10n.practicePlanCatchUpSheetRestDayBody,
            ),
            _CatchUpRow(
              keyId: 'catch-up-row-primary',
              title: l10n.practicePlanCatchUpSheetPrimaryMovesTitle,
              body: l10n.practicePlanCatchUpSheetPrimaryMovesBody,
            ),
            _CatchUpRow(
              keyId: 'catch-up-row-travel',
              title: l10n.practicePlanCatchUpSheetTravelTitle,
              body: l10n.practicePlanCatchUpSheetTravelBody,
            ),
            _CatchUpRow(
              keyId: 'catch-up-row-return',
              title: l10n.practicePlanCatchUpSheetReturnTitle,
              body: l10n.practicePlanCatchUpSheetReturnBody,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                key: const Key('catch-up-dismiss'),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.practicePlanCatchUpSheetDismiss),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the catch-up sheet — a short, factual headline plus its
/// supporting body copy. Both lines come from the ARB.
class _CatchUpRow extends StatelessWidget {
  const _CatchUpRow({
    required this.keyId,
    required this.title,
    required this.body,
  });

  final String keyId;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            key: Key('$keyId-title'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            body,
            key: Key('$keyId-body'),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
