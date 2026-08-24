import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_radius.dart';

/// A geometry-holding loading placeholder (§5.6).
///
/// Reserves the exact box the final content will occupy so nothing jumps
/// once it arrives, and carries no readable text of its own — it is excluded
/// from the semantics tree entirely. The single "loading" announcement for a
/// group of these belongs to the caller (see `SsAsyncState`'s
/// `loadingSemanticLabel`), not to each individual box.
final class SsSkeleton extends StatelessWidget {
  const SsSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = SsRadius.sm,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceSunken,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }
}
