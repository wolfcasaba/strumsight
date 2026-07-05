import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Rounded card with a soft shadow — the app's base surface (theme-aware).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.border,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Card outline. Defaults to the brand hairline border
  /// (`palette.border`, 1px). Pass `Border.fromBorderSide(BorderSide.none)`
  /// to opt a special card out.
  final Border? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(22),
        border: border ?? Border.all(color: context.palette.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}
