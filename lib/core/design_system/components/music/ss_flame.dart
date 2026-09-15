import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../foundations/ss_motion.dart';
import '../../motion/ss_motion_scope.dart';

/// The three pinned flame sizes (Ch18 spec §11): S for the Live header
/// badge, M for a card, L for the streak hero.
enum SsFlameSize {
  small(16),
  medium(40),
  large(72);

  const SsFlameSize(this.dimension);

  /// Logical width and height of the glyph box.
  final double dimension;
}

/// The practice-streak flame — the one mascot-like glyph of the habit loop
/// (Ch18 spec §11, chunk 013). A painted shape, not an icon font glyph, so
/// it reads the same on every platform and can be re-tinted per state:
/// [lit] draws it in [color] with a lighter core, unlit draws the same shape
/// in [dimColor] — the shape stays, only the heat goes.
///
/// It "ignites" once — a grow-and-settle from the base with a short glow —
/// when [lit] flips false → true, when [ignition] increases (the caller's
/// "daily credit" counter, e.g. the streak length), or on mount when
/// [igniteOnMount] is set. The gesture is finite ([SsMotion.celebration])
/// and the widget is static otherwise: no idle flicker (§9.7 — no endless
/// decoration), so a screen with a flame schedules no frames on its own.
/// Under reduced motion ([SsMotionScope]) the flame never animates — state
/// changes snap.
///
/// Theme-agnostic: reads no theme extension, so legacy `AppTheme` screens
/// can host it.
final class SsFlame extends StatefulWidget {
  const SsFlame({
    super.key,
    required this.lit,
    required this.color,
    this.size = SsFlameSize.medium,
    this.dimColor = const Color(0xFF6E7480),
    this.ignition = 0,
    this.igniteOnMount = false,
    this.semanticLabel,
  });

  /// Whether the streak is alive (draws in [color]) or not ([dimColor]).
  final bool lit;

  /// The lit flame's colour; the core is a lighter blend of it.
  final Color color;

  /// The unlit flame's colour.
  final Color dimColor;

  final SsFlameSize size;

  /// A monotonic counter; an increase while lit plays the ignite gesture.
  final int ignition;

  /// Play the ignite gesture on the first frame (a hero reveal).
  final bool igniteOnMount;

  /// Spoken label; null excludes the glyph from semantics (the caller's
  /// count or label already carries the meaning).
  final String? semanticLabel;

  /// Streak lengths that count as a milestone (spec §11.3).
  static const List<int> milestones = [7, 30, 100];

  /// The milestone [days] lands on, or null when it is an ordinary day.
  static int? milestoneFor(int days) => milestones.contains(days) ? days : null;

  /// Peak scale of the ignite overshoot.
  static const double overshoot = 1.18;

  /// Starting scale of the ignite gesture.
  static const double igniteFrom = 0.6;

  /// Where in the gesture (0..1) the overshoot peaks.
  static const double peakAt = 0.45;

  /// The ignite gesture's scale at [t] (0..1): grows from [igniteFrom] to
  /// [overshoot] until [peakAt], then settles to exactly 1. Pure, for tests.
  static double igniteScale(double t) {
    if (t <= 0) return igniteFrom;
    if (t >= 1) return 1;
    if (t < peakAt) {
      final u = SsMotion.enter.transform(t / peakAt);
      return igniteFrom + (overshoot - igniteFrom) * u;
    }
    final u = Curves.easeInOut.transform((t - peakAt) / (1 - peakAt));
    return overshoot + (1 - overshoot) * u;
  }

  @override
  State<SsFlame> createState() => _SsFlameState();
}

final class _SsFlameState extends State<SsFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _mounted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: SsMotion.celebration,
      value: 1,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_mounted) return;
    _mounted = true;
    if (widget.igniteOnMount && widget.lit) _ignite();
  }

  @override
  void didUpdateWidget(SsFlame old) {
    super.didUpdateWidget(old);
    if (!widget.lit) return;
    if (!old.lit || widget.ignition > old.ignition) _ignite();
  }

  void _ignite() {
    if (SsMotionScope.reduceMotionOf(context)) return;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dimension = widget.size.dimension;
    final glyph = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // The glow rises and falls with the gesture: 0 at rest, peaking at
        // the overshoot, gone once settled.
        final t = _controller.value;
        return CustomPaint(
          size: Size(dimension, dimension),
          painter: SsFlamePainter(
            color: widget.lit ? widget.color : widget.dimColor,
            lit: widget.lit,
            scale: SsFlame.igniteScale(t),
            glow: t < 1 ? math.sin(t * math.pi) : 0,
          ),
        );
      },
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: glyph);
    return Semantics(label: label, image: true, child: glyph);
  }
}

/// Paints [SsFlame]: an outer flame in [color] and a lighter core, scaled
/// by [scale] about the base centre (a flame grows from its foot), with an
/// optional soft [glow] halo behind it while igniting.
final class SsFlamePainter extends CustomPainter {
  const SsFlamePainter({
    required this.color,
    required this.lit,
    required this.scale,
    required this.glow,
  });

  final Color color;
  final bool lit;

  /// Uniform scale about the bottom-centre anchor; 1 at rest.
  final double scale;

  /// 0..1 halo strength; 0 draws no halo.
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    canvas.save();
    // Scale about the base so the flame grows upward, never into the ground.
    canvas.translate(w / 2, h);
    canvas.scale(scale);
    canvas.translate(-w / 2, -h);

    final outer = flamePath(w, h);
    if (glow > 0) {
      canvas.drawPath(
        outer,
        Paint()
          ..color = color.withValues(alpha: 0.45 * glow.clamp(0.0, 1.0))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.22),
      );
    }
    canvas.drawPath(outer, Paint()..color = color);
    // The core reads as heat when lit, as a mere highlight when not — the
    // shape difference is what tells the states apart without colour.
    final core = Color.lerp(color, const Color(0xFFFFFFFF), lit ? 0.55 : 0.2)!;
    canvas.drawPath(corePath(w, h), Paint()..color = core);
    canvas.restore();
  }

  /// The outer flame: a leaning teardrop with a shoulder notch on the left,
  /// tip at the top centre, foot filling the bottom.
  static Path flamePath(double w, double h) => Path()
    ..moveTo(0.50 * w, 0.02 * h)
    ..cubicTo(0.62 * w, 0.25 * h, 0.95 * w, 0.45 * h, 0.92 * w, 0.68 * h)
    ..cubicTo(0.90 * w, 0.88 * h, 0.72 * w, 1.00 * h, 0.50 * w, 1.00 * h)
    ..cubicTo(0.28 * w, 1.00 * h, 0.10 * w, 0.88 * h, 0.08 * w, 0.68 * h)
    ..cubicTo(0.05 * w, 0.50 * h, 0.30 * w, 0.42 * h, 0.30 * w, 0.24 * h)
    ..cubicTo(0.38 * w, 0.32 * h, 0.45 * w, 0.18 * h, 0.50 * w, 0.02 * h)
    ..close();

  /// The inner core: a small teardrop sitting on the foot.
  static Path corePath(double w, double h) => Path()
    ..moveTo(0.50 * w, 0.46 * h)
    ..cubicTo(0.66 * w, 0.62 * h, 0.70 * w, 0.86 * h, 0.50 * w, 0.94 * h)
    ..cubicTo(0.30 * w, 0.86 * h, 0.34 * w, 0.62 * h, 0.50 * w, 0.46 * h)
    ..close();

  @override
  bool shouldRepaint(SsFlamePainter old) =>
      old.color != color ||
      old.lit != lit ||
      old.scale != scale ||
      old.glow != glow;
}
