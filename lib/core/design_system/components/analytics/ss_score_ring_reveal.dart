import 'package:flutter/material.dart';

import '../../foundations/ss_motion.dart';
import '../../motion/ss_motion_scope.dart';
import 'ss_score_ring.dart';

/// An [SsScoreRing] whose arc fills from empty to its measured [ratio] over
/// [SsMotion.ringFill] the first time it is shown, and re-fills to a new
/// value when [ratio] changes — the "score reveal" every result and goal
/// surface shares (Ch18 spec §0.2). The centre label follows the arc via
/// [labelBuilder] (default: a rounded percentage), so the number counts up
/// with the ring instead of jumping ahead of it.
///
/// A non-measured [state] renders the plain ring at once with [emptyLabel];
/// reduced motion ([SsMotionScope]) renders the final value at once.
final class SsScoreRingReveal extends StatelessWidget {
  const SsScoreRingReveal({
    super.key,
    required this.state,
    required this.semanticLabel,
    this.ratio,
    this.size = 40,
    this.labelBuilder,
    this.emptyLabel = '—',
    this.duration = SsMotion.ringFill,
  });

  final SsScoreRingState state;

  /// 0..1 target fraction; required when [state] is measured.
  final double? ratio;

  final String semanticLabel;
  final double size;

  /// Builds the centre label for the fraction currently SHOWN (0..1).
  final String Function(double shown)? labelBuilder;

  /// Centre label for a not-applicable / unavailable ring.
  final String emptyLabel;

  final Duration duration;

  /// The default centre label: the shown fraction as a rounded percentage.
  static String percentLabel(double shown) => '${(shown * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    if (state != SsScoreRingState.measured) {
      return SsScoreRing(
        state: state,
        label: emptyLabel,
        semanticLabel: semanticLabel,
        size: size,
      );
    }
    final target = (ratio ?? 0).clamp(0.0, 1.0);
    final label = labelBuilder ?? percentLabel;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: SsMotionScope.durationOf(context, duration),
      curve: SsMotion.emphasizedCurve,
      builder: (context, shown, _) => SsScoreRing(
        state: SsScoreRingState.measured,
        ratio: shown,
        label: label(shown),
        semanticLabel: semanticLabel,
        size: size,
      ),
    );
  }
}
