import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import 'failure_presentation.dart';

/// Renders an [SsFailurePresentation] — title, message and exactly the
/// actions the mapping decided (§5.1, §5.3). No [SsFailureActionKind.retry]
/// entry means no retry button is built at all — and the same holds the
/// other way round: if the mapping DID produce an action but the caller left
/// its callback null, that button is skipped too. A rendered button's
/// `onPressed` is never null; there is no permanently disabled control.
final class SsFailureState extends StatelessWidget {
  const SsFailureState({
    super.key,
    required this.presentation,
    this.onRetry,
    this.onOpenSettings,
    this.onContinueOffline,
    this.onContactSupport,
  });

  final SsFailurePresentation presentation;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onContinueOffline;
  final VoidCallback? onContactSupport;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SsSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.danger, size: 40),
            const SizedBox(height: SsSpacing.space4),
            Text(
              presentation.title,
              style: typography.titleMedium.copyWith(color: colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SsSpacing.space2),
            Text(
              presentation.message,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SsSpacing.space4),
            Wrap(
              spacing: SsSpacing.space2,
              runSpacing: SsSpacing.space2,
              alignment: WrapAlignment.center,
              children: [
                for (final action in presentation.actions)
                  if (_callbackFor(action.kind) case final onPressed?)
                    FilledButton(
                      key: ValueKey('ss-failure-state-${action.kind.name}'),
                      onPressed: onPressed,
                      child: Text(action.label),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  VoidCallback? _callbackFor(SsFailureActionKind kind) => switch (kind) {
    SsFailureActionKind.retry => onRetry,
    SsFailureActionKind.openSettings => onOpenSettings,
    SsFailureActionKind.continueOffline => onContinueOffline,
    SsFailureActionKind.contactSupport => onContactSupport,
  };
}
