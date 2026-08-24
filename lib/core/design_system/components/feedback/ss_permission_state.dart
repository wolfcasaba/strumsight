import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import 'failure_presentation.dart';

/// The runtime permissions the design system knows how to present (§3).
enum SsPermissionKind { microphone, camera, notification, storage }

const _iconByKind = {
  SsPermissionKind.microphone: Icons.mic_none_outlined,
  SsPermissionKind.camera: Icons.camera_alt_outlined,
  SsPermissionKind.notification: Icons.notifications_none_outlined,
  SsPermissionKind.storage: Icons.folder_open_outlined,
};

/// A permission state that says both **why** it is needed and **what
/// happens** if it stays denied (§5.4), then offers exactly the action
/// [presentation] decided — request-again for a plain denial, settings for a
/// permanent one (§6.1).
///
/// [rationale] and [consequence] are supplied by the caller: only the screen
/// asking for the permission knows why it needs it.
///
/// Accepts the same full set of [SsFailureActionKind] callbacks as
/// [SsFailureState]. A callback left null for an action [presentation]
/// produced means no button is built for that action at all — a dead
/// (permanently disabled) control is never rendered.
final class SsPermissionState extends StatelessWidget {
  const SsPermissionState({
    super.key,
    required this.kind,
    required this.rationale,
    required this.consequence,
    required this.presentation,
    this.onRetry,
    this.onOpenSettings,
    this.onContinueOffline,
    this.onContactSupport,
  });

  final SsPermissionKind kind;
  final String rationale;
  final String consequence;
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
            Icon(_iconByKind[kind], color: colors.textSecondary, size: 40),
            const SizedBox(height: SsSpacing.space4),
            Text(
              presentation.title,
              style: typography.titleMedium.copyWith(color: colors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SsSpacing.space2),
            Text(
              rationale,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SsSpacing.space1),
            Text(
              consequence,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SsSpacing.space4),
            for (final action in presentation.actions)
              if (_callbackFor(action.kind) case final onPressed?)
                Padding(
                  padding: const EdgeInsets.only(top: SsSpacing.space2),
                  child: FilledButton(
                    key: ValueKey('ss-permission-state-${action.kind.name}'),
                    onPressed: onPressed,
                    child: Text(action.label),
                  ),
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
