import 'package:flutter/material.dart';

/// Whether [SsScoreRing] paints a real measurement or an explicit absence.
/// [measured] is the only state that reads [SsScoreRing.ratio] — the other
/// two never fall back to a numeric placeholder (ADR 0286 §1 applied to a
/// generic score, not only a metric card).
enum SsScoreRingState { measured, notApplicable, unavailable }

/// Compact circular score indicator used alongside a metric or summary
/// value. Deliberately painted with a static [CustomPainter] arc rather than
/// `CircularProgressIndicator(value: null)`: an indeterminate indicator runs
/// a repeating animation that never settles, which would hang
/// `tester.pumpAndSettle()` in every screen that embeds this widget.
///
/// This widget reads the ambient [Theme] colour scheme and text theme
/// directly (not the design system's [ThemeExtension]s) because it is
/// embedded in `audio_analysis` screens whose widget tests pump a bare
/// `MaterialApp` without the app's theme extensions registered.
final class SsScoreRing extends StatelessWidget {
  const SsScoreRing({
    super.key,
    required this.state,
    required this.label,
    required this.semanticLabel,
    this.ratio,
    this.size = 40,
  });

  final SsScoreRingState state;

  /// 0..1 fraction. Only painted when [state] is [SsScoreRingState.measured].
  final double? ratio;

  /// Short text painted in the centre of the ring (e.g. "82%" or "—").
  final String label;

  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fraction = state == SsScoreRingState.measured
        ? (ratio ?? 0).clamp(0.0, 1.0)
        : 0.0;
    final arcColor = state == SsScoreRingState.measured
        ? colorScheme.primary
        : colorScheme.outline;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            CustomPaint(
              size: Size(size, size),
              painter: _ScoreRingPainter(
                fraction: fraction,
                trackColor: colorScheme.surfaceContainerHighest,
                arcColor: arcColor,
              ),
            ),
            Text(
              label,
              style: textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

final class _ScoreRingPainter extends CustomPainter {
  const _ScoreRingPainter({
    required this.fraction,
    required this.trackColor,
    required this.arcColor,
  });

  final double fraction;
  final Color trackColor;
  final Color arcColor;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * 0.12;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, 6.28319, false, trackPaint);
    if (fraction <= 0) return;
    final arcPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    const start = -1.5707963; // -90 degrees, i.e. 12 o'clock.
    canvas.drawArc(rect, start, 6.28319 * fraction, false, arcPaint);
  }

  @override
  bool shouldRepaint(_ScoreRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.arcColor != arcColor;
}
