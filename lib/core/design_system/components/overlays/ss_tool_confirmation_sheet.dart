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
  const SsToolDimension({required this.label, required this.detail});

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
  }) {
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
        onConfirm: onConfirm,
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
            widget.actionLabel,
            style: typography.titleLarge.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space2),
          Text(
            widget.summary,
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
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
          const SizedBox(height: SsSpacing.space6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SsButton(
                key: const ValueKey('ss-tool-confirmation-cancel'),
                label: widget.cancelLabel,
                variant: SsButtonVariant.tertiary,
                onPressed: _confirmed ? null : _handleCancel,
              ),
              const SizedBox(width: SsSpacing.space2),
              SsButton(
                key: const ValueKey('ss-tool-confirmation-confirm'),
                label: widget.actionLabel,
                onPressed: _confirmed ? null : _handleConfirm,
              ),
            ],
          ),
        ],
      ),
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
