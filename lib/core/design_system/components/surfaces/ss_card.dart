import 'package:flutter/material.dart';

import '../../foundations/ss_elevation.dart';
import '../../foundations/ss_spacing.dart';
import 'ss_surface.dart';

/// A raised content card using the standard StrumSight radius token.
final class SsCard extends StatelessWidget {
  const SsCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SsSurface(
      elevation: SsElevation.raised,
      radius: SsSurfaceRadius.md,
      child: Padding(
        padding: const EdgeInsets.all(SsSpacing.space4),
        child: child,
      ),
    );
  }
}
