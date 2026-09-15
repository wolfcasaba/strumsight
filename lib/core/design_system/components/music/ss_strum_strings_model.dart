import 'dart:math' as math;

/// One strum to draw: when it landed, how hard, and — once it is known — which
/// way the hand moved.
///
/// Mutable on purpose. The Live pipeline publishes the ONSET first and the
/// direction verdict a few tens of milliseconds later, so the same stroke
/// object is upgraded in place by [resolveDirection] instead of being replaced.
/// Replacing it would reset [startSec] and restart the ring-out of six strings
/// that are already vibrating on screen — the one artefact this model exists to
/// avoid (see [SsStrumStringsModel.excitationSec]).
final class SsStrumStroke {
  SsStrumStroke({required this.startSec, required this.strength, this.isDown});

  /// Elapsed-clock time (session seconds) of the onset, i.e. the instant the
  /// strings were hit — not the instant the direction was decided.
  final double startSec;

  /// `true` = down-stroke (low E → high E), `false` = up-stroke,
  /// `null` = the onset is known but the direction verdict has not arrived.
  bool? isDown;

  /// 0..1 — a hard, confident strum swings the strings farther than a brush.
  /// Values outside the range are clamped where the model uses them.
  final double strength;

  /// The clock value at which a LATE [isDown] was committed by
  /// [resolveDirection]; `null` when the direction was already known at the
  /// onset (or is still unknown). The pick sweep is drawn from this instant,
  /// while the strings keep ringing from [startSec] —
  /// see [SsStrumStringsModel.pickPositionAt].
  double? directionResolvedSec;

  /// Commits the late direction verdict that arrived at [atSec].
  ///
  /// The FIRST verdict wins: a second call is a no-op, so a re-emitted or
  /// duplicated verdict can never restart a sweep that is already running, and
  /// a stroke constructed with a known direction is never overwritten.
  /// [atSec] is clamped forward to [startSec] — a pick cannot be drawn crossing
  /// the strings before the onset it belongs to.
  void resolveDirection(bool isDown, double atSec) {
    if (this.isDown != null) return;
    this.isDown = isDown;
    directionResolvedSec = math.max(atSec, startSec);
  }
}

/// Pure, clock-driven geometry for a strummed six-string band: six strings
/// drawn top (index 0, low E) to bottom (index 5, high E), a pick that sweeps
/// across them in [sweepSec], and the damped ring-out each string is left with.
///
/// Deterministic and framework-free — `dart:math` only, no Flutter, no
/// `core/music` (the decoupling `SsStrumGlyph` established: a stroke here is an
/// onset, a strength and a direction, never a chord or a tuning). It follows
/// the clock-driven style of `HitBurst` in `core/widgets`: the painter keeps NO
/// state, it simply asks this model where every string and the pick are at the
/// current clock value, so the whole animation is unit-testable without a
/// `WidgetTester` and identical on every run.
///
/// ## Units
/// [displacementAt] returns a signed offset in STRING-SPACING units: 1.0 is the
/// distance between two neighbouring strings, so the painter multiplies by its
/// own spacing and never has to know a pixel size. [peakAmplitude] caps at
/// [maxAmplitude] (< 0.5) so even a full-strength low E never crosses into its
/// neighbour's lane. [pickPositionAt] returns a FRACTIONAL string index in the
/// same coordinate: 0.0 sits on the low E, 5.0 on the high E.
///
/// ## The late-direction case
/// A direction verdict is slower than the onset that triggers it, and the UI
/// must not stall waiting for it. So a stroke with `isDown == null` excites all
/// six strings at [SsStrumStroke.startSec] simultaneously — an honest "something
/// was struck, we do not know the order yet" — and draws no pick. When
/// [SsStrumStroke.resolveDirection] later fills the direction in, the pick sweep
/// starts from that resolve instant while the strings keep ringing from the
/// original onset: the answer arrives late, the physics does not restart.
abstract final class SsStrumStringsModel {
  /// Strings on the band. Index 0 is the low E and is drawn at the TOP, index
  /// [stringCount] - 1 is the high E at the bottom — the orientation a player
  /// sees looking down at their own guitar.
  static const int stringCount = 6;

  /// How long the pick takes to cross all six strings: 60 ms, i.e. ~12 ms per
  /// string ([stringStepSec]). A down-stroke runs 0 → 5, an up-stroke 5 → 0.
  static const double sweepSec = 0.06;

  /// Gap between two neighbouring string excitations during a sweep (12 ms).
  static const double stringStepSec = sweepSec / (stringCount - 1);

  /// How long a struck string stays drawable before it is considered silent.
  static const double ringSec = 0.6;

  /// Decay time constant of the ring-out envelope. The divisor is chosen so the
  /// envelope `exp(-t / decayTauSec)` has fallen to `exp(-4.2)` ≈ 1.5 % — below
  /// the 2 % visibility floor — by the time `t` reaches [ringSec], which is
  /// what makes cutting the string off at [ringSec] invisible rather than a pop.
  static const double decayTauSec = ringSec / 4.2;

  /// Visual vibration frequency of the low E (string 0), in Hz.
  ///
  /// These are DELIBERATELY not the physical fundamentals (82–330 Hz): at any
  /// frame rate those alias into a grey blur. 9–14 Hz is the legible stand-in
  /// that still reads as "the thin strings flutter faster than the fat ones".
  static const double minFrequencyHz = 9;

  /// Visual vibration frequency of the high E (string 5), in Hz.
  static const double maxFrequencyHz = 14;

  /// Peak swing of a full-strength low E, in string-spacing units. Stays well
  /// under 0.5 so no string can visually collide with its neighbour.
  static const double maxAmplitude = 0.42;

  /// Amplitude factor of the thinnest string relative to the thickest one: a
  /// light high E carries far less energy than a wound low E, so it moves less
  /// even when the same pick crosses it.
  static const double trebleGaugeScale = 0.55;

  /// How far outside the outermost strings the pick starts and ends its travel,
  /// in string-spacing units — the run-up before the first string and the
  /// follow-through after the last one, so the sweep reads as one motion rather
  /// than a mark appearing on top of a string.
  static const double pickOvershoot = 0.8;

  /// Visual vibration frequency of [string], ramped linearly from
  /// [minFrequencyHz] (low E) to [maxFrequencyHz] (high E).
  static double frequencyHz(int string) {
    assert(
      string >= 0 && string < stringCount,
      'string $string is outside 0..${stringCount - 1}',
    );
    return minFrequencyHz +
        (maxFrequencyHz - minFrequencyHz) * string / (stringCount - 1);
  }

  /// Gauge weighting of [string]: 1.0 on the low E, [trebleGaugeScale] on the
  /// high E. Bass strings move more.
  static double gaugeScale(int string) {
    assert(
      string >= 0 && string < stringCount,
      'string $string is outside 0..${stringCount - 1}',
    );
    return 1 - (1 - trebleGaugeScale) * string / (stringCount - 1);
  }

  /// Envelope value of [string] at its own excitation instant, in
  /// string-spacing units — the ceiling every [displacementAt] of that string
  /// stays under. Scaled by [SsStrumStroke.strength] and by [gaugeScale].
  static double peakAmplitude(SsStrumStroke stroke, int string) =>
      maxAmplitude * stroke.strength.clamp(0.0, 1.0) * gaugeScale(string);

  /// The instant [string] starts moving.
  ///
  /// * Direction known at the onset → the pick reaches the strings in order, so
  ///   the string is excited `orderIndex * `[stringStepSec]` ` after
  ///   [SsStrumStroke.startSec] (`orderIndex` counts 0 → 5 for a down-stroke and
  ///   5 → 0 for an up-stroke).
  /// * Direction unknown → every string is excited at [SsStrumStroke.startSec]:
  ///   the onset is certain, the order is not, and guessing one would be a lie
  ///   the eye reads as a verdict.
  /// * Direction resolved LATE → still [SsStrumStroke.startSec] for every
  ///   string. Those strings have been ringing since the onset; the verdict
  ///   moves the pick ([pickPositionAt]), never the physics.
  static double excitationSec(SsStrumStroke stroke, int string) {
    assert(
      string >= 0 && string < stringCount,
      'string $string is outside 0..${stringCount - 1}',
    );
    final isDown = stroke.isDown;
    if (isDown == null || stroke.directionResolvedSec != null) {
      return stroke.startSec;
    }
    final orderIndex = isDown ? string : stringCount - 1 - string;
    return stroke.startSec + orderIndex * stringStepSec;
  }

  /// Signed displacement of [string] at [nowSec], in string-spacing units:
  /// `0` before that string's [excitationSec] and once its ring window has
  /// elapsed, otherwise the damped oscillation
  /// `A · exp(-t / `[decayTauSec]`) · sin(2π f t)` with `A` = [peakAmplitude]
  /// and `f` = [frequencyHz].
  ///
  /// It starts at 0 and swings out, the way a plucked string actually leaves
  /// rest, and it is exactly 0 from `excitation + `[ringSec] on, so a stale
  /// stroke draws nothing at all instead of a sub-pixel shiver.
  static double displacementAt(
    SsStrumStroke stroke,
    int string,
    double nowSec,
  ) {
    final t = nowSec - excitationSec(stroke, string);
    if (t < 0 || t >= ringSec) return 0;
    return peakAmplitude(stroke, string) *
        math.exp(-t / decayTauSec) *
        math.sin(2 * math.pi * frequencyHz(string) * t);
  }

  /// Fractional string position of the pick at [nowSec] (0.0 = on the low E,
  /// 5.0 = on the high E), or `null` when there is nothing to draw: no
  /// direction yet, or [nowSec] outside the half-open sweep window
  /// `[sweepStart, sweepStart + `[sweepSec]`)`.
  ///
  /// The sweep starts at [SsStrumStroke.directionResolvedSec] when the verdict
  /// came late, at [SsStrumStroke.startSec] when it was known at the onset. The
  /// pick eases in and out across `[-`[pickOvershoot]`, 5 + `[pickOvershoot]`]`,
  /// mirrored for an up-stroke, so the two directions are exact reflections of
  /// each other. The easing costs at most ~13 ms (under one 60 Hz frame) of
  /// alignment against the linear [excitationSec] stagger, which keeps the
  /// ring-out spacing uniform.
  static double? pickPositionAt(SsStrumStroke stroke, double nowSec) {
    final isDown = stroke.isDown;
    final sweepStart = _sweepStartSec(stroke);
    if (isDown == null || sweepStart == null) return null;
    final dt = nowSec - sweepStart;
    if (dt < 0 || dt >= sweepSec) return null;
    final eased = _easeInOut(dt / sweepSec);
    final near = -pickOvershoot;
    final far = (stringCount - 1) + pickOvershoot;
    return isDown ? near + (far - near) * eased : far + (near - far) * eased;
  }

  /// Whether [stroke] has nothing left to draw at [nowSec]: every string has
  /// finished ringing AND the pick has left the band.
  ///
  /// A stroke whose [SsStrumStroke.startSec] lies in the FUTURE is inert but not
  /// done (same invariant as `HitBurst`), so a caller that rewinds its clock
  /// must clear its stroke list explicitly rather than wait for pruning.
  static bool isDone(SsStrumStroke stroke, double nowSec) =>
      nowSec >= _endSec(stroke);

  /// First clock value at which nothing of [stroke] is drawn any more.
  static double _endSec(SsStrumStroke stroke) {
    var lastExcitation = stroke.startSec;
    for (var string = 0; string < stringCount; string++) {
      final excitation = excitationSec(stroke, string);
      if (excitation > lastExcitation) lastExcitation = excitation;
    }
    var end = lastExcitation + ringSec;
    // A verdict that arrives very late can outlive the ring-out; the stroke is
    // only done once its pick has finished travelling too.
    final sweepStart = _sweepStartSec(stroke);
    if (sweepStart != null && sweepStart + sweepSec > end) {
      end = sweepStart + sweepSec;
    }
    return end;
  }

  /// When the pick starts crossing the band, or `null` while the direction is
  /// unknown and there is no pick to draw.
  static double? _sweepStartSec(SsStrumStroke stroke) => stroke.isDown == null
      ? null
      : stroke.directionResolvedSec ?? stroke.startSec;

  /// Smoothstep: zero velocity at both ends, fastest in the middle — a pick
  /// accelerating into the band and following through out of it.
  static double _easeInOut(double t) => t * t * (3 - 2 * t);
}
