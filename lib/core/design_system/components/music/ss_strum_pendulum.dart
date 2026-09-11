import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../foundations/ss_colors.dart';
import '../../motion/ss_beat_pulse.dart' show SsBeatClock;
import '../../motion/ss_motion_scope.dart';
import 'ss_strum_glyph.dart' show SsStrumDirection;

/// The strumming hand's travel, rendered as a pick crossing a band of strings.
///
/// This is the down/up rhythm pillar's headline visual. A bouncing ball — the
/// shape every competitor uses — can say WHEN but never WHICH WAY: the same arc
/// serves a downstroke and an upstroke. Turning the axis ninety degrees fixes
/// that: the marker crosses a horizontal string band, and its direction of
/// travel IS the information being taught.
///
/// ## Why the motion looks the way it does
///
/// The pick leaves the strings at full speed, slows to a turnaround clear of
/// them, and accelerates back — one crossing per half beat, the hand never
/// stopping. Two measured findings shape it:
///
///   - **Uniformly varying velocity** (constant acceleration, a projectile
///     profile) is what [travelAt] implements. A bouncing-ball synchronization
///     study measured this profile as matching AUDITORY metronome accuracy, and
///     as significantly better than a sinusoidal control (p = 0.028). The
///     prettier sine curve is the one that lost.
///   - **People anticipate; they do not react.** Tapping in those studies ran
///     consistently ahead of the visual event (negative mean asynchrony). A
///     flash at the moment of the stroke is therefore useless on its own — what
///     a learner times against is the approach. So the pick spends a visible
///     half-cycle accelerating toward the band before every strike.
///
/// NOT measured, and not claimed: in that study the ball produced ONE event per
/// cycle at a hard reversal, while a strumming hand produces TWO with its
/// turnarounds clear of the strings. Whether the profile's advantage carries
/// over to this shape is open.
///
/// ## Why colour is not load-bearing
///
/// Colour-coded notation measurably helps beginners and measurably becomes a
/// crutch when it is the only channel — the research consensus is that it must
/// be removable. Here direction is carried by the pick's SHAPE (the tip leads
/// the travel) in both full and reduced motion; the two brand tints are
/// redundant reinforcement. Remove all colour and the visual still teaches.
/// Red/green is avoided outright: those two are the classic pair that merges
/// under the most common colour-vision deficiency.
///
/// Research: `docs/research/visual-rhythm-cues-2026-09.md`.
///
/// ## Clock discipline
///
/// Driven by [clock], never by a timer of its own, and every frame derives the
/// phase from the clock's CURRENT position rather than accumulating — so a
/// pause, a seek or a tempo change is exact on the next frame instead of
/// drifting (ADR 0274, the same rule as `SsBeatPulse`). The entire visual is a
/// pure function of the clock position: see [frameAt], which tests call
/// directly without a widget tree.
final class SsStrumPendulum extends StatefulWidget {
  const SsStrumPendulum({
    super.key,
    required this.clock,
    required this.beatDuration,
    required this.struck,
    this.height = 200,
    this.muted = false,
    this.sounding,
    this.semanticLabel,
  });

  /// The timeline this follows. Never a locally-owned `Timer`.
  final SsBeatClock clock;

  /// The musical period of one beat, derived from BPM by the caller. A
  /// non-positive value is treated as "no live timeline" — a real runtime
  /// possibility when tempo is missing, not merely a programmer error.
  final Duration beatDuration;

  /// Which crossings strike the strings, indexed by crossing — TWO per beat,
  /// because the hand crosses going down and again coming back up.
  ///
  /// A `false` entry is a ghost stroke: the hand still travels through it, it
  /// simply misses the strings. That is why a down-quarters exercise is
  /// `[true, false, true, false, …]` rather than four entries — the return is
  /// real movement, it is just not asked for.
  final List<bool> struck;

  final double height;

  /// Whether the exercise is played on DAMPED strings (the right-hand-only
  /// rungs). A damped string does not ring, so it must not be drawn ringing.
  final bool muted;

  /// Which of the six strings the current chord actually sounds, thickest first.
  /// Null means all six — a damped rung has no chord to exclude anything.
  ///
  /// ## Why this is not decoration
  ///
  /// Standard chord notation marks an unplayed string `×` above the nut, and the
  /// instruction that goes with it is to **strum from the lowest non-`×`
  /// string**. Without this list the sweep lit all six strings for every chord,
  /// so an Am (`×02210`) or a D (`××0232`) was animated as though the pick
  /// sounded the bass E — the exact motion that makes those chords muddy, shown
  /// to the learner as the thing to copy. That is not a missing polish, it is the
  /// app demonstrating a fault.
  ///
  /// The hand still TRAVELS across an unplayed string: our own model is that the
  /// hand never stops, and a ghost stroke is one the hand passes through. So the
  /// arc is unchanged and only the SOUND is withheld — the string is drawn dim
  /// and never glows.
  final List<bool>? sounding;

  /// When null the widget is decorative-only and excluded from semantics: the
  /// caller announces the stroke through its own live region.
  final String? semanticLabel;

  /// How long a strike stays lit.
  ///
  /// A presentation constant, not a measured one — said plainly, because the
  /// onset tolerance this pillar grades against IS measured and the two must
  /// not be confused. Its value is bounded rather than chosen by taste: the glow
  /// is clipped to 70% of a half-cycle in [frameAt], so two strokes can never be
  /// lit at once at any tempo.
  static const Duration strikeGlow = Duration(milliseconds: 160);

  /// How long the strike takes to cross all six strings.
  ///
  /// A strum is NOT one instant: the pick meets the strings one at a time, which
  /// is why a chord strummed slowly sounds like an arpeggio. The sweep therefore
  /// starts AT the beat and runs forward — never centred on it — and that
  /// direction is measured, not assumed: in
  /// `test/features/live/strum_timestamp_latency_test.dart` the engine's
  /// reported onset sits 0.0-3.4 ms from the FIRST string of a six-string spread,
  /// so the beat is the sweep's beginning.
  ///
  /// The duration itself is a PRESENTATION constant. A synthesis reference puts
  /// a medium strum near 22 ms per string (~110 ms across six), which is the
  /// right order of magnitude but is an engineering figure rather than something
  /// measured on players — so this is deliberately shorter than that, chosen to
  /// stay clear of the next stroke rather than to assert a physical value. Like
  /// the glow, it is clipped in [stringGlowAt] so two strokes never overlap.
  static const Duration strikeSweep = Duration(milliseconds: 90);

  /// Strings, thickest first — the order a DOWNstroke meets them.
  static const int stringCount = 6;

  /// How lit string [stringIndex] (0 = thickest, at the top) is, [sinceCrossing]
  /// after a stroke travelling [direction], given the time to the next crossing.
  ///
  /// Each string lights when the pick REACHES it and decays from there, so a
  /// still frame of a downstroke shows the low strings already ringing while the
  /// high ones are not yet touched. Direction is then legible from a single
  /// frame — a third channel after shape and motion, and one that survives
  /// greyscale.
  static double stringGlowAt({
    required int stringIndex,
    required Duration sinceCrossing,
    required SsStrumDirection direction,
    required Duration halfCycle,
    List<bool>? sounding,
  }) {
    if (stringIndex < 0 || stringIndex >= stringCount) return 0;
    // An unplayed string is crossed, not sounded. It never lights, whatever the
    // timing says.
    if (sounding != null &&
        stringIndex < sounding.length &&
        !sounding[stringIndex]) {
      return 0;
    }
    final budget = halfCycle.inMicroseconds * 0.7;
    if (budget <= 0) return 0;
    final sweep = math.min(strikeSweep.inMicroseconds.toDouble(), budget * 0.6);
    final glow = math.min(strikeGlow.inMicroseconds.toDouble(), budget - sweep);
    if (glow <= 0) return 0;
    // The sweep is spread across the strings that SOUND, in the order the pick
    // meets them — a downstroke from the thickest sounding string, an upstroke
    // from the thinnest. On a D (××0232) the stroke therefore begins at the D
    // string, which is what "strum from the lowest non-× string" means.
    final played = <int>[
      for (var i = 0; i < stringCount; i++)
        if (sounding == null || i >= sounding.length || sounding[i]) i,
    ];
    final order = direction == SsStrumDirection.down
        ? played.indexOf(stringIndex)
        : played.length - 1 - played.indexOf(stringIndex);
    if (order < 0) return 0;
    // One sounding string has nowhere to sweep to, so it lights at the crossing.
    final reachedAt = played.length <= 1
        ? 0.0
        : sweep * (order / (played.length - 1));
    final since = sinceCrossing.inMicroseconds - reachedAt;
    if (since < 0) return 0;
    return (1 - since / glow).clamp(0.0, 1.0);
  }

  /// Key of the pick, stable across reduced and full motion, so tests can find
  /// and inspect it.
  static const Key pickKey = ValueKey('ss_strum_pendulum_pick');

  /// The hand crosses the strings twice per beat: once going down, once coming
  /// back up. This is physical, not a notation choice, which is why it is a
  /// constant and not a parameter.
  static const int crossingsPerBeat = 2;

  /// Signed travel away from the strings at [u], the progress (0..1) through one
  /// half-cycle: `0` at the strings, `1` at the turnaround, back to `0`.
  ///
  /// Constant acceleration throughout — maximum speed exactly at the strings,
  /// zero at the turnaround. Exposed for direct testing of the profile.
  static double travelAt(double u) => 1 - math.pow(2 * u - 1, 2).toDouble();

  /// The complete visual state at [position], or null when there is no live
  /// timeline (no tempo, or nothing to play).
  ///
  /// Pure and side-effect free: this is the whole animation, and it is a
  /// function of the clock alone.
  static SsStrumPendulumFrame? frameAt({
    required Duration position,
    required Duration beatDuration,
    required List<bool> struck,
  }) {
    final beatMicros = beatDuration.inMicroseconds;
    if (beatMicros <= 0 || struck.isEmpty) return null;

    final halfCycle = beatMicros / crossingsPerBeat;
    final loop = halfCycle * struck.length;
    var elapsed = position.inMicroseconds % loop;
    if (elapsed < 0) elapsed += loop;

    final raw = elapsed / halfCycle;
    final crossing = math.min(raw.floor(), struck.length - 1);
    final u = raw - crossing;

    final isDown = crossing.isEven;
    final travel = (isDown ? 1.0 : -1.0) * travelAt(u);

    // Clipped to a fraction of the half-cycle so a fast tempo can never leave
    // two strokes lit at the same time.
    final glowWindow = math.min(
      strikeGlow.inMicroseconds.toDouble(),
      halfCycle * 0.7,
    );
    final sinceCrossing = u * halfCycle;
    final glow = struck[crossing] && glowWindow > 0
        ? (1 - sinceCrossing / glowWindow).clamp(0.0, 1.0)
        : 0.0;

    return SsStrumPendulumFrame(
      crossingIndex: crossing,
      direction: isDown ? SsStrumDirection.down : SsStrumDirection.up,
      travel: travel,
      strikeGlow: glow,
      isStruck: struck[crossing],
      sinceCrossing: Duration(microseconds: sinceCrossing.round()),
      halfCycle: Duration(microseconds: halfCycle.round()),
    );
  }

  @override
  State<SsStrumPendulum> createState() => _SsStrumPendulumState();
}

/// The pendulum's visual state at one instant.
@immutable
final class SsStrumPendulumFrame {
  const SsStrumPendulumFrame({
    required this.crossingIndex,
    required this.direction,
    required this.travel,
    required this.strikeGlow,
    required this.isStruck,
    required this.sinceCrossing,
    required this.halfCycle,
  });

  /// Which crossing of the pattern is in progress, 0-based.
  final int crossingIndex;

  /// Which way the hand was travelling when it last crossed the strings.
  final SsStrumDirection direction;

  /// Distance from the strings, signed: positive is below them (after a
  /// downstroke), negative above. `0` is exactly at the strings, `±1` at a
  /// turnaround.
  final double travel;

  /// How lit the last strike is, 1 at the moment of contact decaying to 0.
  /// Always 0 for a ghost crossing — there was nothing to hear.
  final double strikeGlow;

  /// Whether this crossing strikes the strings at all.
  final bool isStruck;

  /// How long ago the pick crossed the strings — what the per-string sweep is
  /// derived from.
  final Duration sinceCrossing;

  /// The time from one crossing to the next at the current tempo.
  final Duration halfCycle;

  @override
  bool operator ==(Object other) =>
      other is SsStrumPendulumFrame &&
      other.crossingIndex == crossingIndex &&
      other.direction == direction &&
      other.travel == travel &&
      other.strikeGlow == strikeGlow &&
      other.isStruck == isStruck &&
      other.sinceCrossing == sinceCrossing &&
      other.halfCycle == halfCycle;

  @override
  int get hashCode => Object.hash(
    crossingIndex,
    direction,
    travel,
    strikeGlow,
    isStruck,
    sinceCrossing,
    halfCycle,
  );
}

final class _SsStrumPendulumState extends State<SsStrumPendulum>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  SsStrumPendulumFrame? _frame;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration _) {
    final position = widget.clock.position;
    final frame = position == null
        ? null
        : SsStrumPendulum.frameAt(
            position: position,
            beatDuration: widget.beatDuration,
            struck: widget.struck,
          );
    // The ticker is never stopped, so a later resume is picked up on the very
    // next frame even if the caller never rebuilds — `clock` is polled
    // pull-style, exactly as `SsBeatPulse` does it.
    if (frame != _frame) setState(() => _frame = frame);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final reduceMotion = SsMotionScope.reduceMotionOf(context);
    final painted = CustomPaint(
      key: SsStrumPendulum.pickKey,
      size: Size.infinite,
      painter: _SsStrumPendulumPainter(
        frame: _frame,
        reduceMotion: reduceMotion,
        muted: widget.muted,
        sounding: widget.sounding,
        strings: colors.textSecondary,
        downColor: colors.brand,
        upColor: colors.brandStrong,
        glowBase: colors.brand,
      ),
    );
    final sized = SizedBox(
      height: widget.height,
      width: double.infinity,
      child: painted,
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: sized);
    return Semantics(label: label, excludeSemantics: true, child: sized);
  }
}

class _SsStrumPendulumPainter extends CustomPainter {
  _SsStrumPendulumPainter({
    required this.frame,
    required this.reduceMotion,
    required this.muted,
    required this.sounding,
    required this.strings,
    required this.downColor,
    required this.upColor,
    required this.glowBase,
  });

  final SsStrumPendulumFrame? frame;
  final bool reduceMotion;

  /// Which strings the chord sounds; null means all six. See
  /// [SsStrumPendulum.sounding].
  final List<bool>? sounding;

  /// A damped exercise: the strings are held silent, so they must not be drawn
  /// ringing. The two right-hand rungs look different from the chord rung
  /// because they ARE different exercises.
  final bool muted;
  final Color strings;
  final Color downColor;
  final Color upColor;
  final Color glowBase;

  /// The six string thicknesses, thickest FIRST.
  ///
  /// Thickest at the top is what a player sees looking down at their own
  /// guitar, and it is the reason "down" means low-to-high: the hand travels
  /// from the thick strings toward the thin ones, toward the floor.
  static const List<double> _stringWidths = [3.0, 2.5, 2.0, 1.6, 1.3, 1.0];
  static const double _stringGap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final bandHeight =
        _stringWidths.reduce((a, b) => a + b) +
        _stringGap * (_stringWidths.length - 1);
    final current = frame;

    // Each string lights as the pick REACHES it, so a downstroke shows the low
    // strings ringing while the high ones are still untouched. Direction is then
    // readable from a single frozen frame, with no colour and no motion.
    final tint = current == null
        ? strings
        : current.direction == SsStrumDirection.down
        ? downColor
        : upColor;

    var y = midY - bandHeight / 2;
    for (var i = 0; i < _stringWidths.length; i++) {
      final width = _stringWidths[i];
      y += width / 2;
      final plays = sounding == null || i >= sounding!.length || sounding![i];
      final glow = current == null || !current.isStruck
          ? 0.0
          : SsStrumPendulum.stringGlowAt(
              stringIndex: i,
              sinceCrossing: current.sinceCrossing,
              direction: current.direction,
              halfCycle: current.halfCycle,
              sounding: sounding,
            );
      if (glow > 0) {
        // A struck string is louder AND thicker for a moment — a damped one only
        // flickers, because a damped string does not ring.
        final bloom = muted ? 1.0 : 2.2;
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = tint.withValues(alpha: (muted ? 0.45 : 0.9) * glow)
            ..strokeWidth = width + bloom * glow
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          // An unplayed string is drawn FAINTER but still drawn: it is physically
          // there and the hand crosses it. Removing it would say the guitar has
          // four strings for a D, which is a different falsehood.
          ..color = strings.withValues(
            alpha: plays ? (muted ? 0.4 : 0.7) : 0.22,
          )
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
      y += width / 2 + _stringGap;
    }

    if (current == null) {
      // At rest the pick PARKS on the strings rather than vanishing. An empty
      // band reads as a broken screen — seen on the emulator, where the hero
      // area was 180 px of nothing until the clock started.
      _drawPick(
        canvas,
        center: Offset(size.width / 2, midY),
        pointsDown: true,
        color: strings,
      );
      return;
    }

    // Reduced motion removes the TRAVEL, never the information: the pick parks
    // on the strings and its tip still points the way the hand is going, so
    // direction stays shape-encoded (ADR 0274 §5.1).
    final amplitude = (size.height / 2 - bandHeight / 2 - 18).clamp(0.0, 90.0);
    final offset = reduceMotion ? 0.0 : current.travel * amplitude;
    final isDown = current.direction == SsStrumDirection.down;
    _drawPick(
      canvas,
      center: Offset(size.width / 2, midY + offset),
      pointsDown: isDown,
      color: isDown ? downColor : upColor,
    );
  }

  /// A guitar pick: rounded shoulders, a point that LEADS the travel.
  void _drawPick(
    Canvas canvas, {
    required Offset center,
    required bool pointsDown,
    required Color color,
  }) {
    const halfWidth = 11.0;
    const halfHeight = 14.0;
    final sign = pointsDown ? 1.0 : -1.0;
    final tip = Offset(center.dx, center.dy + sign * halfHeight);
    final backLeft = Offset(
      center.dx - halfWidth,
      center.dy - sign * halfHeight * 0.55,
    );
    final backRight = Offset(
      center.dx + halfWidth,
      center.dy - sign * halfHeight * 0.55,
    );

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(
        center.dx - halfWidth * 1.05,
        center.dy + sign * halfHeight * 0.35,
        backLeft.dx,
        backLeft.dy,
      )
      ..quadraticBezierTo(
        center.dx,
        center.dy - sign * halfHeight * 1.15,
        backRight.dx,
        backRight.dy,
      )
      ..quadraticBezierTo(
        center.dx + halfWidth * 1.05,
        center.dy + sign * halfHeight * 0.35,
        tip.dx,
        tip.dy,
      )
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SsStrumPendulumPainter old) =>
      old.frame != frame ||
      old.reduceMotion != reduceMotion ||
      old.muted != muted ||
      !_sameSounding(old.sounding, sounding) ||
      old.strings != strings ||
      old.downColor != downColor ||
      old.upColor != upColor ||
      old.glowBase != glowBase;

  /// Lists compare by identity in Dart, so a fresh list with the same contents
  /// would repaint every frame. The band is six entries; comparing them is
  /// cheaper than the repaint it avoids.
  static bool _sameSounding(List<bool>? a, List<bool>? b) {
    if (a == null || b == null) return (a == null) == (b == null);
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
