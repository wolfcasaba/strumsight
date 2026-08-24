import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import '../actions/ss_button.dart';
import 'ss_overlay_host.dart';

/// One consequence dimension for [SsToolConfirmationSheet] — a caller-owned
/// (label, detail) pair, same as every other button/field label in this
/// design system (the design system does not resolve copy from
/// `AppLocalizations` itself). [label] names the dimension itself ("Reads",
/// "Writes", "Leaves this device", "Starts recording"); [detail] states
/// this specific action's answer, including an explicit negative (e.g.
/// "Nothing") when the dimension does not apply — the row always renders
/// (§5.2).
@immutable
final class SsToolDimension {
  const SsToolDimension({required this.label, required this.detail})
    : assert(
        detail != '',
        'SsToolDimension.detail must not be empty — pass an explicit '
        'negative such as "Nothing" or "None" when the dimension does not '
        'apply (§5.2), never a blank row',
      );

  final String label;
  final String detail;
}

/// The confirmation surface for an AI-tool action — the operation-side
/// counterpart of the R12 provenance badge (ADR 0278): that badge says
/// where content CAME from, this sheet says what the tool is ABOUT to DO
/// (ADR 0279 §5.2).
///
/// This is the design system's OWN presentation model (§0.0/D2) — it does
/// NOT mirror `TutorToolPermission` (`readLocal`/`computeLocal`, the only
/// tool-permission enum in the app today), because that enum cannot express
/// "writes", "leaves this device", or "starts recording" at all. A later
/// feature-layer round maps its concrete tool actions onto these four
/// dimensions; this component only guarantees each one is independently
/// expressible and independently rendered.
final class SsToolConfirmationSheet extends StatefulWidget {
  const SsToolConfirmationSheet({
    super.key,
    required this.actionLabel,
    required this.summary,
    required this.reads,
    required this.writes,
    required this.leavesDevice,
    required this.recording,
    required this.cancelLabel,
    required this.onConfirm,
    this.destructive = true,
  });

  /// Names the action AND is the confirm button's label (§5.1) — e.g.
  /// "Update practice plan".
  final String actionLabel;

  /// One-line summary of what the AI wants to do.
  final String summary;

  final SsToolDimension reads;
  final SsToolDimension writes;
  final SsToolDimension leavesDevice;
  final SsToolDimension recording;
  final String cancelLabel;
  final VoidCallback onConfirm;

  /// When true (the default), the confirm button renders in the destructive
  /// variant with a semantics hint — an AI-initiated tool action is
  /// consequential by construction (§5.2), same treatment as
  /// [SsConfirmationSheet] and [SsDialog].
  final bool destructive;

  /// Presents an [SsToolConfirmationSheet] adaptively sized to [context]'s
  /// current width (§5.6).
  static Future<void> show(
    BuildContext context, {
    required String actionLabel,
    required String summary,
    required SsToolDimension reads,
    required SsToolDimension writes,
    required SsToolDimension leavesDevice,
    required SsToolDimension recording,
    required String cancelLabel,
    required VoidCallback onConfirm,
    bool destructive = true,
  }) {
    // The exactly-once guard lives here, OUTSIDE any State (§5.5, MAJOR-3) —
    // see the identical comment on SsConfirmationSheet.show for why.
    var confirmed = false;
    void guardedOnConfirm() {
      if (confirmed) return;
      confirmed = true;
      onConfirm();
    }

    return SsOverlayHost.showSheetSurface<void>(
      context: context,
      barrierLabel: cancelLabel,
      builder: (context) => SsToolConfirmationSheet(
        actionLabel: actionLabel,
        summary: summary,
        reads: reads,
        writes: writes,
        leavesDevice: leavesDevice,
        recording: recording,
        cancelLabel: cancelLabel,
        onConfirm: guardedOnConfirm,
        destructive: destructive,
      ),
    );
  }

  @override
  State<SsToolConfirmationSheet> createState() =>
      _SsToolConfirmationSheetState();
}

class _SsToolConfirmationSheetState extends State<SsToolConfirmationSheet> {
  var _confirmed = false;

  void _handleConfirm() {
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The body scrolls independently of the action row below
        // (BLOCKER-1) — on a short/landscape viewport or at
        // maximumTextScale, the four consequence dimensions (the most
        // privacy-critical content on this sheet) must never be pushed
        // off-screen ahead of the buttons.
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
                  widget.actionLabel,
                  style: typography.titleLarge.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: SsSpacing.space2),
                Text(
                  widget.summary,
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: SsSpacing.space4),
                _DimensionRow(
                  key: const ValueKey('ss-tool-confirmation-reads'),
                  dimension: widget.reads,
                  colors: colors,
                  typography: typography,
                ),
                _DimensionRow(
                  key: const ValueKey('ss-tool-confirmation-writes'),
                  dimension: widget.writes,
                  colors: colors,
                  typography: typography,
                ),
                _DimensionRow(
                  key: const ValueKey('ss-tool-confirmation-leaves-device'),
                  dimension: widget.leavesDevice,
                  colors: colors,
                  typography: typography,
                ),
                _DimensionRow(
                  key: const ValueKey('ss-tool-confirmation-recording'),
                  dimension: widget.recording,
                  colors: colors,
                  typography: typography,
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
                key: const ValueKey('ss-tool-confirmation-cancel'),
                label: widget.cancelLabel,
                variant: SsButtonVariant.tertiary,
                onPressed: _confirmed ? null : _handleCancel,
              ),
              SsButton(
                key: const ValueKey('ss-tool-confirmation-confirm'),
                label: widget.actionLabel,
                variant: widget.destructive
                    ? SsButtonVariant.destructive
                    : SsButtonVariant.primary,
                destructiveSemanticHint: widget.destructive
                    ? widget.summary
                    : null,
                onPressed: _confirmed ? null : _handleConfirm,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One independently-rendered consequence dimension — reads, writes, leaves
/// this device, or starts recording (§5.2, §0.0/D7: four separate cells,
/// each measured against the built tree). [SsToolDimension.label] and
/// [SsToolDimension.detail] render as two distinct [Text] widgets rather
/// than one interpolated string, so a test can assert on either half
/// without a substring match.
final class _DimensionRow extends StatelessWidget {
  const _DimensionRow({
    required super.key,
    required this.dimension,
    required this.colors,
    required this.typography,
  });

  final SsToolDimension dimension;
  final SsColorScheme colors;
  final SsTypography typography;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SsSpacing.space1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              dimension.label,
              style: typography.labelLarge.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              dimension.detail,
              style: typography.bodyMedium.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
