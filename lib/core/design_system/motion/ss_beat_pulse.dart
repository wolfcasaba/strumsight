import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../foundations/ss_colors.dart';
import 'ss_motion_scope.dart';

/// Read-only view of a playback timeline a rhythm-driven animation can
/// poll. The design system defines this port; a caller in `lib/features/**`
/// wires a concrete implementation (e.g. the backing-track player or the
/// metronome clock) in a later round — the design system itself never reads
/// that layer directly (ADR 0274).
abstract interface class SsBeatClock {
  /// The current elapsed playback position, or `null` when no timeline is
  /// live (stopped / not yet started). [SsBeatPulse] re-reads this every
  /// frame, so the getter must be cheap and side-effect free.
  Duration? get position;
}

/// A rhythm-synced pulse indicator driven entirely by [clock] — never by an
/// independent timer (ADR 0274). Every frame it re-reads
/// [SsBeatClock.position] and derives its phase from the *current* position,
/// so a seek, pause, or resume is reflected on the next frame with no
/// accumulated drift: the displayed phase is always the true phase, never an
/// extrapolation from it.
///
/// When [SsMotionScope.reduceMotionOf] resolves to reduced motion, the dot
/// does not scale — but its color still steps with the beat, because the
/// pulse is functional feedback, not decoration (ADR 0274 §5.1 / brief
/// §5.1).
final class SsBeatPulse extends StatefulWidget {
  const SsBeatPulse({
    super.key,
    required this.clock,
    required this.beatDuration,
    this.diameter = 16,
  });

  /// The timeline this pulse follows. Never a locally-owned `Timer`.
  final SsBeatClock clock;

  /// The musical period of one beat (derived from BPM by the caller). This
  /// is a tempo input, not an animation-length token — the same way [clock]
  /// itself is a caller-supplied dependency, not a design-system constant.
  ///
  /// A non-positive value (missing/zero tempo) is a real runtime
  /// possibility, not just a programmer error — the caller derives it from
  /// BPM — so it is treated as equivalent to "no live timeline" (a static
  /// dot) rather than guarded only by an `assert` that release builds drop.
  final Duration beatDuration;

  final double diameter;

  /// Key of the rendered indicator, stable across reduced/full motion, so
  /// tests can locate and inspect it directly.
  static const Key dotKey = ValueKey('ss_beat_pulse_dot');

  /// The ADR 0274 §3 visual-lag tolerance between a rendered beat phase and
  /// the audio clock's true position. The bound is inclusive.
  static const Duration syncTolerance = Duration(milliseconds: 100);

  /// Whether [visualLag] — the absolute difference between what is
  /// rendered and [clock]'s true position — is within [syncTolerance]. Pure
  /// and side-effect free: a direct, testable formalization of the ADR 0274
  /// §3 numeric rule, independent of any running widget.
  static bool isWithinSyncTolerance(Duration visualLag) {
    final lag = visualLag.isNegative ? -visualLag : visualLag;
    return lag <= syncTolerance;
  }

  @override
  State<SsBeatPulse> createState() => _SsBeatPulseState();
}

final class _SsBeatPulseState extends State<SsBeatPulse>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _phase = 0;
  bool _live = false;

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

  void _onTick(Duration elapsed) {
    final position = widget.clock.position;
    final beatMicros = widget.beatDuration.inMicroseconds;
    if (position == null || beatMicros <= 0) {
      if (_live) setState(() => _live = false);
      // The ticker keeps running (does not stop itself) so a later resume
      // is picked up on the very next frame even if the caller never
      // rebuilds this widget — `clock` is polled every tick, pull-style.
      return;
    }
    final phase = (position.inMicroseconds % beatMicros) / beatMicros;
    if (!_live || phase != _phase) {
      setState(() {
        _live = true;
        _phase = phase;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final reduceMotion = SsMotionScope.reduceMotionOf(context);

    if (!_live) {
      return _dot(color: colors.surfaceSunken, scale: 1);
    }
    if (reduceMotion) {
      // No scale under reduced motion, but the color still steps with the
      // beat — quantized to the first/second half so it reads as a discrete
      // state change (ADR 0274 §5.1), not continuous motion. The off-beat
      // tone is a dimmed brand, distinct from `surfaceSunken` — otherwise the
      // second half of every beat would be pixel-identical to "not playing".
      final onBeat = _phase < 0.5;
      final offBeatColor = Color.lerp(colors.surfaceSunken, colors.brand, .45)!;
      return _dot(color: onBeat ? colors.brand : offBeatColor, scale: 1);
    }
    final scale = 1 + (1 - _phase) * 0.3;
    return _dot(color: colors.brand, scale: scale);
  }

  Widget _dot({required Color color, required double scale}) {
    final size = widget.diameter * scale;
    return SizedBox(
      width: widget.diameter * 1.3,
      height: widget.diameter * 1.3,
      child: Center(
        child: Container(
          key: SsBeatPulse.dotKey,
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
