import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import '../actions/ss_button.dart';
import 'ss_overlay_host.dart';

/// The size-adaptive confirmation sheet for a risky-but-not-tool action
/// (session deletion, publishing a post, downloading a model — §3): a
/// bottom sheet on compact/medium widths, a side sheet on expanded ones
/// (ADR 0279 §5.6). [confirmLabel] names the action itself and
/// [consequence] states what is lost and that it is irreversible (§5.1) —
/// both caller-supplied, same as every other button label in this design
/// system (`SsButton.label`); the design system does not resolve copy from
/// `AppLocalizations` itself (a feature screen's own l10n owns this string).
final class SsConfirmationSheet extends StatefulWidget {
  const SsConfirmationSheet({
    super.key,
    required this.title,
    required this.consequence,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    this.destructive = true,
  });

  final String title;

  /// What is lost — subject-specific, supplied by the caller (§5.1).
  final String consequence;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;

  /// When true (the default), the confirm button renders in the destructive
  /// variant. Set false for a consequential-but-reversible action (e.g.
  /// publishing a post that can later be deleted).
  final bool destructive;

  /// Presents an [SsConfirmationSheet] adaptively sized to [context]'s
  /// current width (§5.6).
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String consequence,
    required String confirmLabel,
    required String cancelLabel,
    required VoidCallback onConfirm,
    bool destructive = true,
  }) {
    return SsOverlayHost.showSheetSurface<void>(
      context: context,
      barrierLabel: cancelLabel,
      builder: (context) => SsConfirmationSheet(
        title: title,
        consequence: consequence,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        onConfirm: onConfirm,
        destructive: destructive,
      ),
    );
  }

  @override
  State<SsConfirmationSheet> createState() => _SsConfirmationSheetState();
}

class _SsConfirmationSheetState extends State<SsConfirmationSheet> {
  var _confirmed = false;

  void _handleConfirm() {
    // Exactly-once guard (§5.5/A6): a second tap that lands before the pop
    // animation removes the button is a no-op, not a second callback run.
    if (_confirmed) return;
    setState(() => _confirmed = true);
    widget.onConfirm();
    Navigator.of(context).maybePop();
  }

  void _handleCancel() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;

    return Padding(
      padding: const EdgeInsets.all(SsSpacing.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: typography.titleLarge.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space4),
          Text(
            widget.consequence,
            key: const ValueKey('ss-confirmation-consequence-detail'),
            style: typography.bodyMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SsButton(
                key: const ValueKey('ss-confirmation-cancel'),
                label: widget.cancelLabel,
                variant: SsButtonVariant.tertiary,
                onPressed: _confirmed ? null : _handleCancel,
              ),
              const SizedBox(width: SsSpacing.space2),
              SsButton(
                key: const ValueKey('ss-confirmation-confirm'),
                label: widget.confirmLabel,
                variant: widget.destructive
                    ? SsButtonVariant.destructive
                    : SsButtonVariant.primary,
                destructiveSemanticHint: widget.destructive
                    ? widget.consequence
                    : null,
                onPressed: _confirmed ? null : _handleConfirm,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
