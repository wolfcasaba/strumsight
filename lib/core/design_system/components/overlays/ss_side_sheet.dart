import 'package:flutter/material.dart';

import '../../foundations/ss_elevation.dart';
import '../surfaces/ss_surface.dart';

/// The large-screen counterpart of a bottom sheet (ADR 0279 §5.6) — a
/// fixed-width panel anchored to the trailing edge, never a bottom sheet
/// stretched across a tablet-width screen. `SsOverlayHost.showSheetSurface`
/// selects this shape once the viewport reaches the expanded breakpoint;
/// below that it renders the same [child] inside a bottom sheet instead.
final class SsSideSheet extends StatelessWidget {
  const SsSideSheet({super.key, required this.child, this.width = 420});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SsSurface(
      elevation: SsElevation.modal,
      radius: SsSurfaceRadius.lg,
      child: SizedBox(width: width, child: child),
    );
  }
}
