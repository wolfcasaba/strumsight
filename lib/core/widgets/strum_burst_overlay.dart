import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../design_system/public.dart';
import '../theme/app_colors.dart';
import 'hit_burst.dart';

/// Wraps a strum surface (the Live hero, a practice highway, the Song
/// Trainer strum lane) and throws a [HitBurst] spark over it on every NEW
/// detected strum — the Learn highway's strike-line juice (chunk 016b P0)
/// shared by every screen where the moat is seen.
///
/// * A burst fires when [strumSeq] advances (never on a rebuild with the
///   same seq, never on first mount), in the stroke's colour (copper = down,
///   confidence green = up), sized by the caller's [strength]. The MOTION
///   reads the direction: a pick-sweep mark travels through the glyph the
///   way the hand moved (top→bottom for ↓, bottom→top for ↑, with a fading
///   trail — [HitBurstSweep]) and the sparks fan the same way.
/// * Onset-first (round strum-strings): when [onsetSeq] advances — the engine
///   confirmed a HIT, ~70 ms before it knows the direction — a neutral
///   [ImpactRing] snaps outward at once, so the feedback lands with the
///   strike, not with the verdict. The directional burst still follows on
///   [strumSeq]. Surfaces without an onset signal leave [onsetSeq] at 0.
/// * The clock is a local [Ticker] that runs ONLY while a burst is alive
///   (≤ 0.45 s) and stops itself — so `pumpAndSettle` terminates and an idle
///   Live screen schedules no frames. This is event-driven decay, not a
///   rhythm animation, so ADR 0274's audio-clock rule does not apply.
/// * Under reduced motion ([SsMotionScope]) no spark is drawn: the glyph
///   itself already carries the direction by shape (ADR 0274 §5.1 — the
///   information stays, only the motion goes).
final class StrumBurstOverlay extends StatefulWidget {
  const StrumBurstOverlay({
    super.key,
    required this.child,
    required this.strumSeq,
    required this.isDown,
    required this.strength,
    this.onsetSeq = 0,
    this.impactColor,
    this.centerOf = trailingGlyphCenter,
  });

  /// Monotonic per-onset counter from the live frame (bumps before
  /// [strumSeq]); a rise fires the neutral impact ring. 0 = no onset signal.
  final int onsetSeq;

  /// Tint of the impact ring; defaults to the theme's on-surface colour —
  /// deliberately NOT a direction colour.
  final Color? impactColor;

  /// The strum surface the sparks overlay (drawn above it, never blocking
  /// taps).
  final Widget child;

  /// Monotonic per-strum counter from the live frame; a rise fires a burst.
  final int strumSeq;

  /// Direction of the latest strum; `null` (no strum yet) never bursts.
  final bool? isDown;

  /// 0..1 — sizes the burst: Live passes the stroke's confidence, a scored
  /// surface its timing ladder (PERFECT biggest). Clamped to ≥ 0.35 so a
  /// weak stroke still visibly shows its direction.
  final double strength;

  /// Where the sparks originate, given the child's laid-out size. The
  /// default targets the 48 dp glyph `SsChordHero` places at the row's right
  /// edge; a highway passes its strike line, a lane its "now" edge.
  final Offset Function(Size size) centerOf;

  /// Key of the spark overlay — present only while a burst is alive.
  static const Key overlayKey = ValueKey('strum_burst_overlay');

  static Offset trailingGlyphCenter(Size size) =>
      Offset(size.width - 24, size.height / 2);

  @override
  State<StrumBurstOverlay> createState() => _StrumBurstOverlayState();
}

final class _StrumBurstOverlayState extends State<StrumBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<HitBurst> _bursts = [];
  final List<ImpactRing> _rings = [];
  double _nowSec = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(StrumBurstOverlay old) {
    super.didUpdateWidget(old);
    final isDown = widget.isDown;
    if (widget.onsetSeq > old.onsetSeq) _fireImpact();
    if (widget.strumSeq > old.strumSeq && isDown != null) {
      _fire(isDown);
    }
  }

  void _fireImpact() {
    if (SsMotionScope.reduceMotionOf(context)) return;
    _rings.add(
      ImpactRing(startSec: _nowSec, strength: widget.strength.clamp(0.35, 1.0)),
    );
    if (!_ticker.isActive) _ticker.start();
  }

  void _fire(bool isDown) {
    if (SsMotionScope.reduceMotionOf(context)) return;
    _bursts.add(
      HitBurst(
        startSec: _nowSec,
        color: isDown ? AppColors.primary : AppColors.confidenceHigh,
        strength: widget.strength.clamp(0.35, 1.0),
        directionSign: isDown ? 1 : -1,
      ),
    );
    // No setState: this runs from didUpdateWidget, and the framework rebuilds
    // right after it anyway; the ticker's first tick repaints from there on.
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    // The ticker's elapsed time restarts from zero on every `start()`. The
    // clock is therefore reset to zero whenever the ticker stops, so a burst
    // fired while idle starts at 0 — the same origin the next `start()` uses.
    setState(() {
      _nowSec = elapsed.inMicroseconds / 1e6;
      _bursts.removeWhere((b) => b.isDone(_nowSec));
      _rings.removeWhere((r) => r.isDone(_nowSec));
      if (_bursts.isEmpty && _rings.isEmpty) {
        _ticker.stop();
        _nowSec = 0;
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bursts.isEmpty && _rings.isEmpty) return widget.child;
    final impact =
        widget.impactColor ?? Theme.of(context).colorScheme.onSurface;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          key: StrumBurstOverlay.overlayKey,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _HeroBurstPainter(
                  bursts: List.unmodifiable(_bursts),
                  rings: List.unmodifiable(_rings),
                  impactColor: impact,
                  nowSec: _nowSec,
                  centerOf: widget.centerOf,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// [HitBurstPainter]'s sibling for a centre that depends on the laid-out
/// size (the glyph sits at the hero row's right edge, the strike line at a
/// fixed x, wherever the surface lands).
final class _HeroBurstPainter extends CustomPainter {
  _HeroBurstPainter({
    required this.bursts,
    required this.nowSec,
    required this.centerOf,
    this.rings = const [],
    this.impactColor = const Color(0xFFFFFFFF),
  });

  final List<HitBurst> bursts;
  final List<ImpactRing> rings;
  final Color impactColor;

  final Paint _ring = Paint()..style = PaintingStyle.stroke;
  final double nowSec;
  final Offset Function(Size size) centerOf;

  final Paint _paint = Paint()..style = PaintingStyle.fill;

  final Paint _sweep = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// Trail samples behind the sweep mark: earlier instants, fainter.
  static const List<double> _trailLagSec = [0.0, 0.03, 0.06, 0.09];

  /// Half-length of the horizontal pick mark.
  static const double _sweepHalfLength = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final center = centerOf(size);
    // The impact ring first (lowest layer): a direction-free "hit" mark.
    for (final r in rings) {
      final mark = r.ringAt(nowSec);
      if (mark == null) continue;
      _ring
        ..color = impactColor.withValues(alpha: mark.alpha)
        ..strokeWidth = mark.strokeWidth;
      canvas.drawCircle(center, mark.radius, _ring);
    }
    for (final b in bursts) {
      // The pick sweep first (under the sparks): the mark plus a fading
      // trail, all travelling in the stroke's direction through the glyph.
      for (var k = _trailLagSec.length - 1; k >= 0; k--) {
        final mark = b.sweepAt(nowSec - _trailLagSec[k]);
        if (mark == null) continue;
        final fade = 1 - k / _trailLagSec.length;
        _sweep
          ..color = b.color.withValues(alpha: mark.alpha * fade)
          ..strokeWidth = 4 + 2 * fade;
        final y = center.dy + mark.dy;
        canvas.drawLine(
          Offset(center.dx - _sweepHalfLength, y),
          Offset(center.dx + _sweepHalfLength, y),
          _sweep,
        );
      }
      for (final p in b.particlesAt(nowSec)) {
        _paint.color = b.color.withValues(alpha: p.alpha.clamp(0.0, 1.0));
        canvas.drawCircle(center + p.offset, p.radius, _paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HeroBurstPainter old) =>
      old.nowSec != nowSec ||
      old.bursts != bursts ||
      old.rings != rings ||
      old.impactColor != impactColor;
}
