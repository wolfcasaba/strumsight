import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../motion/ss_motion_scope.dart';
import 'ss_strum_strings_model.dart';

/// A six-string band that rings when the player strums: the strings swing out
/// and damp away, and a pick mark crosses them in the direction the hand moved.
///
/// The widget is the Flutter shell around [SsStrumStringsModel] — the model owns
/// every number, this owns the clock, the stroke list and the paint. It follows
/// `StrumBurstOverlay`'s ticker discipline exactly: the clock is a LOCAL
/// [Ticker] that runs ONLY while a stroke is alive, stops itself the moment the
/// last one is done and resets its clock to zero. So `pumpAndSettle` terminates,
/// an idle band schedules no frames, and there is no rhythm animation that would
/// fall under ADR 0274's audio-clock rule — this is event-driven decay.
///
/// ## Two sequence counters, because the verdict is slower than the onset
/// The Live pipeline knows "something was struck" tens of milliseconds before it
/// knows which way the hand went, and the band must not stall waiting:
///
/// * [onsetSeq] rises → a stroke with an UNKNOWN direction starts. All six
///   strings ring at once and the neutral [stringColor] brightens — an honest
///   "we heard it, we do not know the order yet". No pick is drawn, because a
///   pick has to travel one way or the other and either way would be a guess the
///   eye reads as a verdict.
/// * [strumSeq] rises with a non-null [isDown] → if the newest stroke started no
///   more than [directionGraceSec] ago and still has no direction, the verdict
///   is committed ON THAT STROKE
///   ([SsStrumStroke.resolveDirection]): the pick sweep starts now while the
///   strings keep ringing from the original onset. Otherwise the verdict belongs
///   to a strum whose onset was never announced, so a fresh directed stroke
///   starts instead. Excited strings then tint towards [downColor] / [upColor].
/// * Both counters rising in the SAME update is a strum whose direction was
///   known at the onset, so it starts as one directed stroke and gets the full
///   string-by-string stagger rather than a simultaneous hit.
///
/// A verdict with a `null` [isDown] is ignored: there is nothing to resolve and
/// nothing to draw (the same rule `StrumBurstOverlay` applies to its sparks).
///
/// ## Reduced motion
/// Under [SsMotionScope] the band is static: no ticker, no frames, no ring-out.
/// The information survives the motion (ADR 0274 §5.1) — the last known
/// direction is shown as a static pick glyph parked at the string the sweep
/// ENDED on (the high E for a down-stroke, the low E for an up-stroke), so the
/// direction is still readable by position and colour.
final class SsStrumStrings extends StatefulWidget {
  const SsStrumStrings({
    super.key,
    required this.onsetSeq,
    required this.strumSeq,
    required this.isDown,
    required this.strength,
    required this.downColor,
    required this.upColor,
    required this.stringColor,
    this.height = 72,
    this.semanticLabel,
  });

  /// Monotonic per-onset counter from the live frame. A rise starts a stroke
  /// with an unknown direction; a rebuild with the same value never does.
  final int onsetSeq;

  /// Monotonic per-strum counter carrying the direction verdict. A rise either
  /// upgrades the newest undirected stroke or starts a directed one.
  final int strumSeq;

  /// Direction of the latest strum: `true` = down, `false` = up, `null` = not
  /// decided yet (a rise of [strumSeq] with `null` here is ignored).
  final bool? isDown;

  /// 0..1 — how hard the strings were hit. Clamped; scales the swing via
  /// [SsStrumStringsModel.peakAmplitude] and the tint of the excited strings.
  final double strength;

  /// Band height in logical pixels. The string spacing, the swing headroom and
  /// the pick mark all derive from it, so the band scales as one piece.
  final double height;

  /// Tint an excited string takes on during a down-stroke.
  final Color downColor;

  /// Tint an excited string takes on during an up-stroke.
  final Color upColor;

  /// Resting colour of the strings, and the colour they brighten to while a
  /// stroke's direction is still unknown.
  final Color stringColor;

  /// When null the band is decorative-only (the caller announces the strum via
  /// its own text or live region) and is excluded from the semantics tree.
  final String? semanticLabel;

  /// How long after an onset a direction verdict is still understood to belong
  /// to THAT onset. Beyond it the verdict starts its own stroke rather than
  /// re-picking strings that have already been ringing for a quarter second.
  static const double directionGraceSec = 0.25;

  @override
  State<SsStrumStrings> createState() => _SsStrumStringsState();
}

final class _SsStrumStringsState extends State<SsStrumStrings>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Strokes currently drawable, oldest first — so the last entry is the newest
  /// stroke, the only one a late verdict may ever be attached to.
  final List<SsStrumStroke> _strokes = [];

  double _nowSec = 0;

  /// Last direction the caller reported, kept even while motion is allowed so
  /// that turning reduced motion on mid-session still has something to show.
  bool? _lastIsDown;

  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = SsMotionScope.reduceMotionOf(context);
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    // Motion was switched off mid-ring: drop the live strokes and stop the
    // clock immediately instead of letting an invisible ticker run out.
    if (reduce) _reset();
  }

  @override
  void didUpdateWidget(SsStrumStrings old) {
    super.didUpdateWidget(old);
    final onsetRose = widget.onsetSeq > old.onsetSeq;
    final strumRose = widget.strumSeq > old.strumSeq;
    final isDown = widget.isDown;
    if (strumRose && isDown != null) _lastIsDown = isDown;

    if (onsetRose && strumRose && isDown != null) {
      // Onset and verdict in the same frame: the direction was known when the
      // strings were hit, so the pick reaches them one by one.
      _startStroke(isDown);
      return;
    }
    if (onsetRose) _startStroke(null);
    if (strumRose && isDown != null) _resolveOrStart(isDown);
  }

  /// Commits a late verdict onto the stroke it belongs to, or starts a directed
  /// stroke when there is no onset to attach it to.
  void _resolveOrStart(bool isDown) {
    if (_reduceMotion) return;
    final newest = _strokes.isEmpty ? null : _strokes.last;
    if (newest != null &&
        newest.isDown == null &&
        _nowSec - newest.startSec <= SsStrumStrings.directionGraceSec) {
      newest.resolveDirection(isDown, _nowSec);
      // The stroke is already alive, so the ticker is already running; starting
      // it again would reset the clock the stroke's startSec is measured on.
      return;
    }
    _startStroke(isDown);
  }

  void _startStroke(bool? isDown) {
    if (_reduceMotion) return;
    _strokes.add(
      SsStrumStroke(
        startSec: _nowSec,
        strength: widget.strength.clamp(0.0, 1.0),
        isDown: isDown,
      ),
    );
    // No setState: this runs from didUpdateWidget and the framework rebuilds
    // right after it; the ticker's first tick repaints from there on.
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    // The ticker's elapsed time restarts from zero on every start(), so the
    // clock is reset to zero whenever it stops: a stroke created while idle
    // starts at 0, exactly the origin the next start() will count from.
    setState(() {
      _nowSec = elapsed.inMicroseconds / 1e6;
      _strokes.removeWhere((s) => SsStrumStringsModel.isDone(s, _nowSec));
      if (_strokes.isEmpty) {
        _ticker.stop();
        _nowSec = 0;
      }
    });
  }

  void _reset() {
    _strokes.clear();
    if (_ticker.isActive) _ticker.stop();
    _nowSec = 0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final band = SizedBox(
      height: widget.height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SsStrumStringsPainter(
            // A const empty list keeps shouldRepaint honest while the band is
            // idle or static: same identity on every rebuild, so no repaint.
            strokes: _reduceMotion || _strokes.isEmpty
                ? const <SsStrumStroke>[]
                : List.unmodifiable(_strokes),
            nowSec: _reduceMotion ? 0 : _nowSec,
            staticIsDown: _reduceMotion ? _lastIsDown : null,
            downColor: widget.downColor,
            upColor: widget.upColor,
            stringColor: widget.stringColor,
          ),
        ),
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: band);
    return Semantics(label: label, image: true, child: band);
  }
}

/// Paints the band for one clock value: six strings, each a polyline bent by
/// [SsStrumStringsModel.displacementAt] under a horizontal sine envelope, plus
/// the pick mark of every stroke that currently has one.
///
/// Stateless with respect to time — it asks the model where everything is at
/// [nowSec] and draws that, so a frame is reproducible from the clock alone.
final class _SsStrumStringsPainter extends CustomPainter {
  _SsStrumStringsPainter({
    required this.strokes,
    required this.nowSec,
    required this.staticIsDown,
    required this.downColor,
    required this.upColor,
    required this.stringColor,
  });

  final List<SsStrumStroke> strokes;
  final double nowSec;

  /// Reduced motion only: the direction to park a static pick glyph for, or
  /// `null` for no glyph (and, while motion is allowed, always `null`).
  final bool? staticIsDown;

  final Color downColor;
  final Color upColor;
  final Color stringColor;

  /// Free space above the low E and below the high E, in string-spacing units.
  /// It has to clear both the widest swing ([SsStrumStringsModel.maxAmplitude],
  /// 0.42) and the pick's run-up ([SsStrumStringsModel.pickOvershoot], 0.8), so
  /// neither a ringing string nor the pick is ever cut off by the band edge.
  static const double _edgeInsetUnits = 0.9;

  /// Stroke width of the low E; every other string is thinner by its gauge.
  static const double _maxStringWidth = 2.4;

  /// Opacity of a string at rest, relative to the caller's [stringColor]. An
  /// excited string rises from here to full opacity.
  static const double _restOpacity = 0.55;

  /// Polyline segments per string: enough for the sine bend to read as a curve
  /// at any band width, few enough to stay a handful of points per frame.
  static const int _segments = 24;

  final Paint _stringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  final Paint _pickPaint = Paint()..style = PaintingStyle.fill;

  /// The vibration ENVELOPE: two faint ghost lines at ± the current
  /// amplitude. A 9–14 Hz sine sampled at 60 fps reads as a slow wobble; the
  /// envelope is what the eye recognises as a string ringing.
  final Paint _ghostPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// Ghost picks behind the sweep — the motion trail of the hand.
  static const List<double> _pickTrailLagSec = [0.012, 0.024, 0.036];
  static const List<double> _pickTrailAlpha = [0.45, 0.28, 0.14];

  /// Reused across strings: one allocation per frame instead of six.
  final Path _path = Path();

  /// The resting string colour, resolved once instead of per string.
  late final Color _restColor = stringColor.withValues(
    alpha: stringColor.a * _restOpacity,
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    const count = SsStrumStringsModel.stringCount;
    final spacing = size.height / ((count - 1) + 2 * _edgeInsetUnits);
    final topY = spacing * _edgeInsetUnits;

    for (var string = 0; string < count; string++) {
      final baseY = topY + string * spacing;
      var displacement = 0.0;
      var excitation = 0.0;
      Color? tint;
      for (final stroke in strokes) {
        displacement += SsStrumStringsModel.displacementAt(
          stroke,
          string,
          nowSec,
        );
        final e = _excitationOf(stroke, string);
        if (e <= excitation) continue;
        excitation = e;
        // The hottest stroke owns the colour: a fresh directed strum overrides
        // the neutral brightening of an onset that is already fading out.
        final isDown = stroke.isDown;
        tint = isDown == null ? null : (isDown ? downColor : upColor);
      }
      displacement = displacement.clamp(
        -SsStrumStringsModel.maxAmplitude,
        SsStrumStringsModel.maxAmplitude,
      );

      // Colour holds longer than the motion (sqrt of the decay): the string
      // still LOOKS struck while its swing has become sub-pixel.
      _stringPaint
        ..strokeWidth = _maxStringWidth * SsStrumStringsModel.gaugeScale(string)
        ..color = _colorFor(tint, math.sqrt(excitation));

      final swing = displacement * spacing;
      if (excitation > 0.03) {
        final envelope =
            excitation *
            SsStrumStringsModel.maxAmplitude *
            SsStrumStringsModel.gaugeScale(string) *
            spacing;
        _ghostPaint
          ..strokeWidth = _stringPaint.strokeWidth * 0.7
          ..color = (tint ?? stringColor).withValues(
            alpha: (0.10 + 0.30 * excitation).clamp(0.0, 0.4),
          );
        for (final sign in const [-1.0, 1.0]) {
          _path.reset();
          _path.moveTo(0, baseY);
          for (var i = 1; i <= _segments; i++) {
            final u = i / _segments;
            _path.lineTo(
              u * size.width,
              baseY + sign * envelope * math.sin(math.pi * u),
            );
          }
          canvas.drawPath(_path, _ghostPaint);
        }
      }
      if (swing == 0) {
        canvas.drawLine(
          Offset(0, baseY),
          Offset(size.width, baseY),
          _stringPaint,
        );
        continue;
      }
      _path.reset();
      _path.moveTo(0, baseY);
      for (var i = 1; i <= _segments; i++) {
        final u = i / _segments;
        // Zero at both ends (the string is fixed at nut and bridge), widest in
        // the middle — the first mode of a plucked string.
        _path.lineTo(u * size.width, baseY + swing * math.sin(math.pi * u));
      }
      canvas.drawPath(_path, _stringPaint);
    }

    final centerX = size.width / 2;
    final staticIsDown = this.staticIsDown;
    if (staticIsDown != null) {
      // Reduced motion: the sweep is gone, its destination is not.
      _drawPick(
        canvas,
        centerX,
        topY + (staticIsDown ? count - 1 : 0) * spacing,
        spacing,
        staticIsDown,
      );
      return;
    }
    for (final stroke in strokes) {
      final isDown = stroke.isDown;
      if (isDown == null) continue;
      // Trail first (older = fainter), then the pick with its glow on top.
      for (var k = _pickTrailLagSec.length - 1; k >= 0; k--) {
        final p = SsStrumStringsModel.pickPositionAt(
          stroke,
          nowSec - _pickTrailLagSec[k],
        );
        if (p == null) continue;
        _drawPick(
          canvas,
          centerX,
          topY + p * spacing,
          spacing,
          isDown,
          alpha: _pickTrailAlpha[k],
        );
      }
      final position = SsStrumStringsModel.pickPositionAt(stroke, nowSec);
      if (position == null) continue;
      final y = topY + position * spacing;
      _drawPick(canvas, centerX, y, spacing, isDown, alpha: 0.22, scale: 1.9);
      _drawPick(canvas, centerX, y, spacing, isDown);
    }
  }

  /// The pick itself: a small rounded rectangle crossing the band, upright the
  /// way a plectrum is held.
  void _drawPick(
    Canvas canvas,
    double centerX,
    double y,
    double spacing,
    bool isDown, {
    double alpha = 1.0,
    double scale = 1.0,
  }) {
    final width = spacing * 0.62 * scale;
    final height = spacing * 1.2 * scale;
    final base = isDown ? downColor : upColor;
    _pickPaint.color = alpha >= 1.0
        ? base
        : base.withValues(alpha: base.a * alpha);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, y),
          width: width,
          height: height,
        ),
        Radius.circular(width * 0.45),
      ),
      _pickPaint,
    );
  }

  /// How hot [string] is under [stroke] right now: the ring-out envelope scaled
  /// by the stroke's strength, 0 outside the ring window.
  ///
  /// It is the DECAY envelope, not `|displacement|`: the displacement crosses
  /// zero on every half period, which would strobe the tint instead of fading
  /// it.
  double _excitationOf(SsStrumStroke stroke, int string) {
    final t = nowSec - SsStrumStringsModel.excitationSec(stroke, string);
    if (t < 0 || t >= SsStrumStringsModel.ringSec) return 0;
    return stroke.strength.clamp(0.0, 1.0) *
        math.exp(-t / SsStrumStringsModel.decayTauSec);
  }

  /// Blends a string from its resting look towards [tint] (or, when the
  /// direction is unknown, towards a fully opaque [stringColor] — the neutral
  /// brightening) by [excitation].
  Color _colorFor(Color? tint, double excitation) {
    if (excitation <= 0) return _restColor;
    return Color.lerp(
      _restColor,
      tint ?? stringColor,
      excitation.clamp(0.0, 1.0),
    )!;
  }

  @override
  bool shouldRepaint(_SsStrumStringsPainter old) =>
      old.nowSec != nowSec ||
      old.strokes != strokes ||
      old.staticIsDown != staticIsDown ||
      old.downColor != downColor ||
      old.upColor != upColor ||
      old.stringColor != stringColor;
}
