import 'package:flutter/material.dart';

import '../../foundations/ss_semantics.dart';
import '../../icons/ss_icon.dart';

/// A tappable icon-only control.
///
/// Draws its glyph with [SsIcon.decorative] rather than [SsIcon.interactive]
/// (D5, ADR 0411 §4): [SsIcon.interactive] wraps ITSELF in a `Tooltip` and an
/// `image`-flagged `Semantics` node — nesting that inside this button's own
/// `button`-flagged node would put an `image` semantics node INSIDE a
/// `button` node and duplicate the tooltip. Instead [SsIconButton] owns the
/// tooltip and the button semantics itself: the descendant `IconButton`'s
/// own semantics are excluded entirely (`excludeSemantics: true`, the same
/// technique [SsIcon.interactive] uses for its own glyph), and this widget's
/// single [Semantics] node carries `button: true` and [semanticLabel]
/// instead — never `image`.
final class SsIconButton extends StatelessWidget {
  SsIconButton({
    super.key,
    required this.iconName,
    required String semanticLabel,
    required String tooltip,
    required this.onPressed,
    this.size = SsIconSize.base,
  }) : semanticLabel = _requireNonEmpty(semanticLabel, 'semanticLabel'),
       tooltip = _requireNonEmpty(tooltip, 'tooltip');

  final String iconName;
  final String semanticLabel;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  static String _requireNonEmpty(String value, String field) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        field,
        'must not be empty for an SsIconButton',
      );
    }
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: semanticLabel,
        enabled: onPressed != null,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: SsSemantics.minimumInteractiveDimension,
            minHeight: SsSemantics.minimumInteractiveDimension,
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: SsIcon.decorative(name: iconName, size: size),
          ),
        ),
      ),
    );
  }
}
