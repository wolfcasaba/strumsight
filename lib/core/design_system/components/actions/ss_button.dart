import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_semantics.dart';
import '../../foundations/ss_spacing.dart';

/// The four button intents this design system distinguishes (Ch13 §11.2).
enum SsButtonVariant { primary, secondary, tertiary, destructive }

/// A button whose footprint never changes between its label and its loading
/// spinner (§5.2): the label stays laid out (at zero opacity) underneath the
/// spinner instead of being replaced by it, so the intrinsic size the button
/// reports is identical either way.
///
/// While [loading] is true, [onPressed] is fully disabled — the caller flips
/// [loading] to true (synchronously, before the async work starts) as the
/// very first thing its own handler does, so a fast second tap always lands
/// on an already-disabled control rather than resubmitting (§5.2).
///
/// [SsButtonVariant.destructive] differs from the other variants in colour
/// **and** in semantics (§5.5, Ch13 §13.1 — "not a state marked by colour
/// alone"): [destructiveSemanticHint] is REQUIRED for that variant and is
/// merged into the button's own accessibility node alongside [label] — the
/// design system never invents this copy itself (same hívó-oldali string
/// ownership rule as [SsIcon.interactive], ADR 0411 §4).
///
/// One screen shows one primary CTA (§5.6); the Stage Mode transport is the
/// documented exception (SDD Ch13 §11.2) and is out of this widget's scope.
final class SsButton extends StatelessWidget {
  const SsButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SsButtonVariant.primary,
    this.loading = false,
    this.icon,
    this.destructiveSemanticHint,
  }) : assert(
         variant != SsButtonVariant.destructive ||
             destructiveSemanticHint != null,
         'SsButtonVariant.destructive requires a non-null destructiveSemanticHint',
       );

  final String label;
  final VoidCallback? onPressed;
  final SsButtonVariant variant;
  final bool loading;
  final IconData? icon;

  /// A screen-reader-only hint distinguishing the destructive intent from
  /// colour alone. Required (and non-null) exactly when
  /// [variant] is [SsButtonVariant.destructive].
  final String? destructiveSemanticHint;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final effectiveOnPressed = loading ? null : onPressed;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18),
          const SizedBox(width: SsSpacing.space2),
        ],
        // Flexible + ellipsis rather than a bare Text: at
        // SsSemantics.maximumTextScale a long label can otherwise outgrow
        // a width-constrained button and overflow the Row (A6).
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );

    // The label stays in the tree (at zero opacity) so the Stack — and with
    // it the button — always reports the same intrinsic size, loading or
    // not (§5.2).
    final child = Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: loading ? 0 : 1, child: content),
        if (loading)
          ExcludeSemantics(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(
                  variant == SsButtonVariant.primary ||
                          variant == SsButtonVariant.destructive
                      ? colors.onBrand
                      : colors.brand,
                ),
              ),
            ),
          ),
      ],
    );

    final button = switch (variant) {
      SsButtonVariant.primary => FilledButton(
        onPressed: effectiveOnPressed,
        child: child,
      ),
      SsButtonVariant.secondary => OutlinedButton(
        onPressed: effectiveOnPressed,
        child: child,
      ),
      SsButtonVariant.tertiary => TextButton(
        onPressed: effectiveOnPressed,
        child: child,
      ),
      SsButtonVariant.destructive => FilledButton(
        style: FilledButton.styleFrom(backgroundColor: colors.danger),
        onPressed: effectiveOnPressed,
        child: child,
      ),
    };

    final sized = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: SsSemantics.minimumInteractiveDimension,
      ),
      child: button,
    );

    if (variant != SsButtonVariant.destructive) {
      return sized;
    }

    // MergeSemantics forces the merge past the button's own semantics
    // boundary (`Semantics(container: true, ...)`, set internally by
    // FilledButton) so [destructiveSemanticHint] lands on the SAME
    // accessibility node as the label, not a separate one a screen reader
    // would announce as an unrelated second stop.
    return MergeSemantics(
      child: Semantics(hint: destructiveSemanticHint, child: sized),
    );
  }
}
