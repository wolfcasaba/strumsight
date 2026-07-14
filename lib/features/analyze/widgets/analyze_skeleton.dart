import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_palette.dart';

/// A shimmering placeholder that previews the shape of the analyze result
/// timeline — a row of summary chips plus a list of chord-row cards (label box
/// + time line + a strum lane) — while the DSP runs during
/// `AnalyzePhase.analyzing`. It mirrors [TimelineView]'s layout so a
/// multi-second analyze feels like the result is materialising rather than the
/// UI being frozen behind a bare spinner.
///
/// The shimmer LOOPS (`onPlay: (c) => c.repeat()`). That is safe here because
/// no widget test ever renders the analyzing phase: the only widget tests that
/// build AnalyzeScreen exercise the idle / micError / recording phases, while
/// the analyzing → done transitions are covered by pure controller unit tests
/// that never mount this widget. If you ever add a widget test that reaches the
/// analyzing phase, drive it with `tester.pump(duration)` — NOT
/// `pumpAndSettle()` — because a repeating animation never settles.
class AnalyzeSkeleton extends StatelessWidget {
  const AnalyzeSkeleton({super.key, this.label});

  /// Optional accessibility label announced for the whole skeleton (e.g. the
  /// "Analyzing…" copy) so the phase is conveyed to screen readers without
  /// cluttering the visual placeholder.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary chip row — mirrors TimelineView's duration / BPM / strums
        // pills.
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SkeletonBox(width: 56, height: 28, radius: 999),
            _SkeletonBox(width: 76, height: 28, radius: 999),
            _SkeletonBox(width: 104, height: 28, radius: 999),
          ],
        ),
        const SizedBox(height: 16),
        // A few placeholder chord-row cards.
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          const _SkeletonChordRow(),
        ],
      ],
    );

    // A single sweeping highlight over the whole placeholder block. `muted`
    // over `track` gives visible contrast in BOTH light and dark themes.
    final shimmer = content.animate(onPlay: (c) => c.repeat()).shimmer(
          duration: 1200.ms,
          color: palette.muted.withValues(alpha: 0.35),
        );

    return Semantics(
      label: label,
      container: true,
      child: shimmer,
    );
  }
}

/// One placeholder card matching [TimelineView]'s chord row: a chord-label
/// block on the left and a stacked time line + strum lane on the right.
class _SkeletonChordRow extends StatelessWidget {
  const _SkeletonChordRow();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: const Row(
        children: [
          _SkeletonBox(width: 40, height: 28, radius: 8), // chord label
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: 96, height: 12, radius: 6), // time range
                SizedBox(height: 8),
                _SkeletonBox(width: 140, height: 16, radius: 6), // strum lane
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A muted, rounded placeholder rectangle drawn from theme tokens.
class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 8,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: palette.track,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
