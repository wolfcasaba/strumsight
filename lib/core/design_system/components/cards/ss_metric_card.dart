import 'package:flutter/material.dart';

import '../../foundations/ss_colors.dart';
import '../../foundations/ss_spacing.dart';
import '../../foundations/ss_typography.dart';
import '../feedback/ss_skeleton.dart';
import '../surfaces/ss_surface.dart';
import 'ss_content_card.dart';

/// The fixed line heights [SsMetricCard] and [SsMetricCardSkeleton] both
/// build from — the SAME numeric constants on both sides, derived once
/// from [SsTypography] (`fontSize * height`, ADR 0273) rather than measured
/// per platform, so the two states are guaranteed the identical footprint
/// (§5.4/A5) instead of merely expected to match.
abstract final class _SsMetricCardGeometry {
  // SsTypography.labelLarge: fontSize 14 * height (20 / 14).
  static const double labelLineHeight = 20;
  // SsTypography.metricLarge: fontSize 28 * height (34 / 28).
  static const double metricLineHeightLarge = 34;
  // SsTypography.metricSmall: fontSize 12 * height 1.5.
  static const double metricLineHeightSmall = 18;
}

/// A mérőszám (metric) tile — Montserrat, tabular-figure digits, read from
/// [SsTypography.metricLarge]/[metricSmall] rather than hardcoded (§0.0/D5).
/// Fixed-width by design (like a dashboard KPI tile), which is also what
/// lets [SsMetricCardSkeleton] reserve the exact same box (§5.4).
final class SsMetricCard extends StatelessWidget {
  const SsMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.onTap,
    this.width = 140,
    this.density = SsCardDensity.expanded,
  });

  final String label;
  final num value;
  final String unit;
  final VoidCallback? onTap;
  final double width;
  final SsCardDensity density;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final isCompact = density == SsCardDensity.compact;
    final metricStyle = isCompact
        ? typography.metricSmall
        : typography.metricLarge;
    final metricHeight = isCompact
        ? _SsMetricCardGeometry.metricLineHeightSmall
        : _SsMetricCardGeometry.metricLineHeightLarge;

    final content = Padding(
      padding: EdgeInsets.all(isCompact ? SsSpacing.space3 : SsSpacing.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _SsMetricCardGeometry.labelLineHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: typography.labelLarge.copyWith(
                  color: colors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(height: SsSpacing.space1),
          SizedBox(
            height: metricHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                SsTypography.metricLabel(value, unit),
                style: metricStyle.copyWith(color: colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );

    final tappable = onTap != null;
    return SizedBox(
      width: width,
      child: SsSurface(
        child: tappable ? InkWell(onTap: onTap, child: content) : content,
      ),
    );
  }
}

/// A geometry-holding placeholder for [SsMetricCard]'s loading state (§5.4)
/// — carries no readable text (`SsSkeleton` excludes itself from semantics),
/// and reserves EXACTLY the box a loaded [SsMetricCard] of the same
/// [density] and [width] would occupy, built from the SAME
/// [_SsMetricCardGeometry] constants.
final class SsMetricCardSkeleton extends StatelessWidget {
  const SsMetricCardSkeleton({
    super.key,
    this.width = 140,
    this.density = SsCardDensity.expanded,
  });

  final double width;
  final SsCardDensity density;

  @override
  Widget build(BuildContext context) {
    final isCompact = density == SsCardDensity.compact;
    final metricHeight = isCompact
        ? _SsMetricCardGeometry.metricLineHeightSmall
        : _SsMetricCardGeometry.metricLineHeightLarge;

    return SizedBox(
      width: width,
      child: SsSurface(
        child: Padding(
          padding: EdgeInsets.all(
            isCompact ? SsSpacing.space3 : SsSpacing.space4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SsSkeleton(
                width: width * .6,
                height: _SsMetricCardGeometry.labelLineHeight,
              ),
              const SizedBox(height: SsSpacing.space1),
              SsSkeleton(width: width * .5, height: metricHeight),
            ],
          ),
        ),
      ),
    );
  }
}
