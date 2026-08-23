import 'package:flutter/material.dart';

import '../../foundations/ss_breakpoints.dart';
import '../../foundations/ss_elevation.dart';
import '../../foundations/ss_radius.dart';
import '../../foundations/ss_spacing.dart';

/// Token-backed corner treatments available to surface primitives.
enum SsSurfaceRadius {
  md(SsRadius.md),
  lg(SsRadius.lg);

  const SsSurfaceRadius(this.value);

  final double value;
}

/// A themed surface whose level controls its background, border, and shadow.
final class SsSurface extends StatelessWidget {
  const SsSurface({
    super.key,
    required this.child,
    this.elevation = SsElevation.base,
    this.radius = SsSurfaceRadius.md,
    this.safeArea = false,
  });

  final Widget child;
  final SsElevation elevation;
  final SsSurfaceRadius radius;
  final bool safeArea;

  /// Returns the token-backed screen padding for a responsive content width.
  static double screenPaddingForWidth(double width) {
    if (width <= SsBreakpoints.compactMax) return SsSpacing.space4;
    if (width <= SsBreakpoints.mediumMax) return SsSpacing.space6;
    return SsSpacing.space8;
  }

  @override
  Widget build(BuildContext context) {
    final style = elevation.resolve(Theme.of(context));
    final surface = Material(
      color: style.background,
      elevation: style.shadowElevation,
      shadowColor: style.shadowColor,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: style.border, width: style.borderWidth),
        borderRadius: BorderRadius.all(Radius.circular(radius.value)),
      ),
      child: child,
    );

    return safeArea ? SafeArea(child: surface) : surface;
  }
}
