import 'package:flutter/material.dart';

import '../../foundations/ss_elevation.dart';
import '../../foundations/ss_spacing.dart';
import 'ss_surface.dart';

/// A raised content card using the standard StrumSight radius token.
final class SsCard extends StatelessWidget {
  const SsCard({
    super.key,
    required this.child,
    this.padding = SsSpacing.space4,
  });

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(SsSpacing.space0),
      color: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: SsSurface(
        elevation: SsElevation.raised,
        radius: SsSurfaceRadius.md,
        child: Padding(padding: EdgeInsets.all(padding), child: child),
      ),
    );
  }
}
