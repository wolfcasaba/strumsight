import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import 'failure_presentation.dart';

/// Renders an [SsFailurePresentation] — title, message and exactly the
/// actions the mapping decided (§5.1, §5.3). A callback left null for an
/// action the presentation never produced is simply never invoked: no
/// [SsFailureActionKind.retry] entry means no retry button is built at all.
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
                  FilledButton(
                    key: ValueKey('ss-failure-state-${action.kind.name}'),
                    onPressed: _callbackFor(action.kind),
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
