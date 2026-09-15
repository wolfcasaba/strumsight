import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/design_system/public.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/hit_burst.dart';

/// Wraps the Stage hero and throws a [HitBurst] spark over its ↓/↑ glyph on
/// every NEW detected strum — the Learn highway's strike-line juice (chunk
/// 016b P0) brought to Live, where the moat is actually seen first.
///
/// * A burst fires when [strumSeq] advances (never on a rebuild with the
///   same seq, never on first mount), in the stroke's colour (copper = down,
///   confidence green = up), fanning the way the hand moved, sized by the
///   stroke's [confidence].
/// * The clock is a local [Ticker] that runs ONLY while a burst is alive
///   (≤ 0.45 s) and stops itself — so `pumpAndSettle` terminates and an idle
///   Live screen schedules no frames. This is event-driven decay, not a
///   rhythm animation, so ADR 0274's audio-clock rule does not apply.
/// * Under reduced motion ([SsMotionScope]) no spark is drawn: the glyph
///   itself already carries the direction by shape (ADR 0274 §5.1 — the
///   information stays, only the motion goes).
final class StrumBurstHero extends StatefulWidget {
  const StrumBurstHero({
    super.key,
    required this.child,
    required this.strumSeq,
    required this.isDown,
    required this.confidence,
    this.glyphCenter = defaultGlyphCenter,
  });

  /// The hero readout (chord label + direction glyph) the sparks overlay.
  final Widget child;

  /// Monotonic per-strum counter from the live frame; a rise fires a burst.
  final int strumSeq;

  /// Direction of the latest strum; `null` (no strum yet) never bursts.
  final bool? isDown;

  /// 0..1 — sizes the burst (a confident stroke bursts bigger).
  final double confidence;

  /// Where the sparks originate, given the hero's laid-out size. The default
  /// targets the 48 dp glyph `SsChordHero` places at the row's right edge.
  final Offset Function(Size size) glyphCenter;

  /// Key of the spark overlay — present only while a burst is alive.
  static const Key overlayKey = ValueKey('live_strum_burst_overlay');

  static Offset defaultGlyphCenter(Size size) =>
      Offset(size.width - 24, size.height / 2);

  @override
  State<StrumBurstHero> createState() => _StrumBurstHeroState();
}

final class _StrumBurstHeroState extends State<StrumBurstHero>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<HitBurst> _bursts = [];
  double _nowSec = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didUpdateWidget(StrumBurstHero old) {
    super.didUpdateWidget(old);
    final isDown = widget.isDown;
    if (widget.strumSeq > old.strumSeq && isDown != null) {
      _fire(isDown);
    }
  }

  void _fire(bool isDown) {
    if (SsMotionScope.reduceMotionOf(context)) return;
    _bursts.add(
      HitBurst(
        startSec: _nowSec,
        color: isDown ? AppColors.primary : AppColors.confidenceHigh,
        strength: widget.confidence.clamp(0.35, 1.0),
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
      if (_bursts.isEmpty) {
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
    if (_bursts.isEmpty) return widget.child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          key: StrumBurstHero.overlayKey,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _HeroBurstPainter(
                  bursts: List.unmodifiable(_bursts),
                  nowSec: _nowSec,
                  centerOf: widget.glyphCenter,
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
/// size (the glyph sits at the hero row's right edge, wherever that lands).
final class _HeroBurstPainter extends CustomPainter {
  _HeroBurstPainter({
    required this.bursts,
    required this.nowSec,
    required this.centerOf,
  });

  final List<HitBurst> bursts;
  final double nowSec;
  final Offset Function(Size size) centerOf;

  final Paint _paint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final center = centerOf(size);
    for (final b in bursts) {
      for (final p in b.particlesAt(nowSec)) {
        _paint.color = b.color.withValues(alpha: p.alpha.clamp(0.0, 1.0));
        canvas.drawCircle(center + p.offset, p.radius, _paint);
      }
    }
  }

  @override
  bool shouldRepaint(_HeroBurstPainter old) =>
      old.nowSec != nowSec || old.bursts != bursts;
}
