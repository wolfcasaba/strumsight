import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// A single shimmering placeholder block — the base of every skeleton. Uses the
/// theme track color with a brand-tinted shimmer sweep (premium loading state,
/// replaces bare CircularProgressIndicators on list/grid loads).
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: p.track,
        borderRadius: BorderRadius.circular(radius),
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1100.ms,
          color: AppColors.primary.withValues(alpha: 0.16),
        );
  }
}

/// Skeleton mimicking a horizontal recipe row (thumb + two text lines).
class SkeletonRecipeRow extends StatelessWidget {
  const SkeletonRecipeRow({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Skeleton(width: 70, height: 70, radius: 16),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Skeleton(width: 180, height: 14),
                SizedBox(height: 8),
                Skeleton(width: 110, height: 12),
                SizedBox(height: 8),
                Skeleton(width: 80, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertical list of recipe-row skeletons (search / feed / saved loads).
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.padding});
  final int count;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, _) => const SkeletonRecipeRow(),
    );
  }
}

/// A 2-column grid of card skeletons (cookbooks / grid search / discover).
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.count = 6});
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GridView.count(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      crossAxisCount: 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 0.82,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Skeleton(
                  height: 104,
                  radius: 20,
                  width: double.infinity,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Skeleton(width: 120, height: 13),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Skeleton(width: 70, height: 11),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
