import 'package:flutter/material.dart';

import '../../foundations/ss_semantics.dart';
import '../../foundations/ss_spacing.dart';

/// A settings-style row where the FULL row is the touch target (§5.4), not
/// just the [Switch] thumb — a small target next to a wide label is exactly
/// where an accidental miss makes a setting toggle unreliably.
///
/// The visible [Switch] never receives pointer events directly
/// (`IgnorePointer(ignoringSemantics: false, ...)`): every tap anywhere in
/// the row — including visually over the switch — goes through the same
/// [InkWell], so there is exactly one code path that can flip [value] and no
/// risk of the row and the switch double-toggling each other.
/// [MergeSemantics] combines the label and the switch's own `toggled`
/// semantics into one accessible node spanning the whole row.
///
/// **NEM elfogadható gyengítés (§5.4):** only the [Switch] itself reacting to
/// taps. That leaves a target far under the 48 dp minimum
/// ([SsSemantics.minimumInteractiveDimension]).
final class SsSwitchRow extends StatelessWidget {
  const SsSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SsSemantics.minimumInteractiveDimension,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SsSpacing.space4,
              vertical: SsSpacing.space2,
            ),
            child: MergeSemantics(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: theme.textTheme.bodyLarge),
                        if (subtitle case final subtitle?)
                          Text(subtitle, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: SsSpacing.space2),
                  IgnorePointer(
                    ignoringSemantics: false,
                    child: Switch(
                      value: value,
                      onChanged: onChanged == null ? null : (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
