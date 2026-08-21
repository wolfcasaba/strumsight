import 'package:flutter/material.dart';

import '../../foundations/ss_elevation.dart';
import '../../foundations/ss_spacing.dart';
import 'ss_surface.dart';

/// A caller-fed hero presentation surface for Stage Mode compositions.
final class SsHeroCard extends StatelessWidget {
  const SsHeroCard({
    super.key,
    required this.child,
    this.padding = SsSpacing.space6,
  });

  final Widget child;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return SsSurface(
      elevation: SsElevation.overlay,
      radius: SsSurfaceRadius.lg,
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
  }
}
