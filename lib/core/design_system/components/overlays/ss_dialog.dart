import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_elevation.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import '../actions/ss_button.dart';
import '../surfaces/ss_surface.dart';
import 'ss_overlay_host.dart';

/// A consequence-first alert dialog (ADR 0279 §5.1) — the confirm button
/// names the action itself (e.g. "Delete session"), never a bare "Yes"/"OK",
/// and [message] states what is lost and that it is irreversible. Cancel is
/// always present (§5.3); [cancelLabel] is a required caller-supplied
/// string, same as every other button label in this design system
/// (`SsButton.label`) — the design system does not resolve copy from
/// `AppLocalizations` itself (ADR 0274, design system does not import
/// `lib/features/**`, and `lib/l10n/app_{en,hu}.arb` is a generated
/// aggregate, ADR 0307 — a feature screen's own l10n owns this string).
///
/// Callable on its own — from a `VoidCallback` such as
/// `SsStageScaffold.onUnsavedSessionBackAttempt` — via [show], independent
/// of any particular screen's widget tree (§0.0/D3).
final class SsDialog extends StatefulWidget {
  const SsDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    this.destructive = true,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final bool destructive;

  /// Presents an [SsDialog] centered over [context]. Resolves once the
  /// dialog closes, by any of: the confirm button, the cancel button, the
  /// barrier, Android back, or Escape (§5.4/A7).
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required String cancelLabel,
    required VoidCallback onConfirm,
    bool destructive = true,
  }) {
    return SsOverlayHost.showDialogSurface<void>(
      context: context,
      barrierLabel: cancelLabel,
      builder: (context) => SsDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        onConfirm: onConfirm,
        destructive: destructive,
      ),
    );
  }

  @override
  State<SsDialog> createState() => _SsDialogState();
}

class _SsDialogState extends State<SsDialog> {
  var _confirmed = false;

  void _handleConfirm() {
    // Guards against a double tap firing the destructive callback twice
    // (§5.5/A6) — the confirm button is disabled the instant the first tap
    // lands, before the pop animation even starts.
    if (_confirmed) return;
    setState(() => _confirmed = true);
    try {
      widget.onConfirm();
    } catch (_) {
      // A failed onConfirm must not leave two permanently dead buttons
      // (MINOR-1) — re-enable so the caller can retry or cancel.
      if (mounted) setState(() => _confirmed = false);
      rethrow;
    }
    Navigator.of(context).maybePop();
  }

  void _handleCancel() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;

    return SsSurface(
      elevation: SsElevation.modal,
      radius: SsSurfaceRadius.lg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The body scrolls independently of the action row below (BLOCKER-1)
          // — on a short/landscape viewport or at maximumTextScale, the title
          // and message must never push the buttons off-screen.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                SsSpacing.space6,
                SsSpacing.space6,
                SsSpacing.space6,
                0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: typography.titleLarge.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: SsSpacing.space2),
                  Text(
                    widget.message,
                    style: typography.bodyMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(SsSpacing.space6),
            child: OverflowBar(
              spacing: SsSpacing.space2,
              overflowSpacing: SsSpacing.space2,
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                SsButton(
                  key: const ValueKey('ss-dialog-cancel'),
                  label: widget.cancelLabel,
                  variant: SsButtonVariant.tertiary,
                  onPressed: _confirmed ? null : _handleCancel,
                ),
                SsButton(
                  key: const ValueKey('ss-dialog-confirm'),
                  label: widget.confirmLabel,
                  variant: widget.destructive
                      ? SsButtonVariant.destructive
                      : SsButtonVariant.primary,
                  destructiveSemanticHint: widget.destructive
                      ? widget.message
                      : null,
                  onPressed: _confirmed ? null : _handleConfirm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
