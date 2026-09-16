import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A firework-style spark burst fired at the strike line when a strum lands on
/// beat (chunk 016b P0 "juice"). The geometry is PURE and deterministic (no
/// Random) so it's unit-testable and identical every run; [HitBurstPainter]
/// just draws whatever [particlesAt] returns for the current clock.
///
/// Shared by the Learn highway (strike-line hits) and the Live hero (every
/// detected strum) — it depends on nothing but `dart:ui` geometry, so it
/// lives in `core/widgets` rather than either feature.
class HitBurst {
  HitBurst({
    required this.startSec,
    required this.color,
    required this.strength,
    this.lifeSec = 0.45,
    this.count = 14,
    this.directionSign = -1,
  }) : assert(directionSign == -1 || directionSign == 1);

  /// Elapsed-clock time (lesson seconds) at which the burst was fired.
  final double startSec;
  final Color color;

  /// 0..1 — a PERFECT hit bursts bigger/brighter than an off-beat one.
  final double strength;

  final double lifeSec;
  final int count;

  /// Which way the spark cone opens: `-1` (default) fans UPWARD — the
  /// strike-line burst; `+1` fans DOWNWARD — so a Live down-stroke ↓ throws
  /// its sparks the way the hand moved, and an up-stroke ↑ the other way.
  final double directionSign;

  bool isDone(double nowSec) => nowSec - startSec >= lifeSec;

  /// Active particles at [nowSec], each as an offset from the burst centre plus
  /// its current radius and alpha. Empty once the burst has expired.
  List<BurstParticle> particlesAt(double nowSec) {
    // Same boundary test as [isDone] (direct, not via the division) so the two
    // never disagree at the float edge of the life window.
    final dt = nowSec - startSec;
    if (dt < 0 || dt >= lifeSec) return const [];
    final t = dt / lifeSec;
    final ease = 1 - (1 - t) * (1 - t); // ease-out: fast then settling
    final reach = 26.0 + 40.0 * strength;
    final out = <BurstParticle>[];
    for (var i = 0; i < count; i++) {
      // Direction-biased cone (up by default), deterministic per index (a
      // little variety via sin).
      final base = directionSign * math.pi / 2; // straight up or down
      const spread = math.pi * 0.95;
      final frac = count == 1 ? 0.5 : i / (count - 1);
      final angle = base + (frac - 0.5) * spread + math.sin(i * 2.399) * 0.14;
      final speed = reach * (0.62 + 0.38 * (((i * 37) % 100) / 100));
      final dist = speed * ease;
      final dx = math.cos(angle) * dist;
      final dy = math.sin(angle) * dist + 26 * t * t; // slight gravity
      final radius = (2.4 + 2.2 * strength) * (1 - t);
      final alpha = (1 - t) * (1 - t);
      out.add(BurstParticle(Offset(dx, dy), radius, alpha));
    }
    return out;
  }
}

/// The pick "sweep" that accompanies a burst: a short mark that travels
/// THROUGH the burst centre the way the hand moved — top→bottom for a
/// down-stroke (`directionSign == 1`), bottom→top for an up-stroke — so the
/// motion itself reads the direction, not only the settled glyph shape.
/// Pure geometry on the same clock as [HitBurst.particlesAt]; the caller
/// draws it (and a fading trail by sampling slightly earlier instants).
extension HitBurstSweep on HitBurst {
  /// How long the sweep is visible after [HitBurst.startSec] — shorter than
  /// the spark life, so the pick has "passed" while the sparks still fall.
  static const double lifeSec = 0.22;

  /// Half the distance the mark travels (from `-reach` to `+reach` along the
  /// stroke direction, relative to the burst centre).
  static const double reach = 34.0;

  /// The mark at [nowSec], or null when the sweep is not visible.
  SweepMark? sweepAt(double nowSec) {
    final dt = nowSec - startSec;
    if (dt < 0 || dt >= lifeSec) return null;
    final t = dt / lifeSec;
    final ease = 1 - (1 - t) * (1 - t) * (1 - t); // ease-out cubic: fast start
    final dy = directionSign * (-reach + 2 * reach * ease);
    final alpha = (1 - t) * (0.55 + 0.45 * strength);
    return SweepMark(dy, alpha.clamp(0.0, 1.0), t);
  }
}

/// The sweep mark's vertical [dy] from the burst centre (signed: positive is
/// downward on screen), its [alpha] and its [progress] (0 start → 1 end).
class SweepMark {
  const SweepMark(this.dy, this.alpha, this.progress);
  final double dy;
  final double alpha;
  final double progress;
}

/// One spark: [offset] from the burst centre, current [radius] and [alpha].
class BurstParticle {
  const BurstParticle(this.offset, this.radius, this.alpha);
  final Offset offset;
  final double radius;
  final double alpha;
}

/// Draws every active [bursts] entry, centred at [center], for clock [nowSec].
/// Cheap: one filled circle per live particle, a reused [Paint], tight repaint.
class HitBurstPainter extends CustomPainter {
  HitBurstPainter({
    required this.bursts,
    required this.nowSec,
    required this.center,
  });

  final List<HitBurst> bursts;
  final double nowSec;
  final Offset center;

  final Paint _paint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in bursts) {
      for (final p in b.particlesAt(nowSec)) {
        _paint.color = b.color.withValues(alpha: p.alpha.clamp(0.0, 1.0));
        canvas.drawCircle(center + p.offset, p.radius, _paint);
      }
    }
  }

  @override
  bool shouldRepaint(HitBurstPainter old) =>
      old.nowSec != nowSec || old.bursts != bursts || old.center != center;
}
