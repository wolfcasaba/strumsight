import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/design_system/public.dart';

/// Adapts the metronome's existing phase-preserving [BeatClock] + [Ticker]
/// (ADR 0274 — unchanged, NOT rewritten, brief §0.0/R5.2) to the design
/// system's [SsBeatClock] port: [secondsAt] reads the SAME elapsed-seconds
/// value the click scheduler already tracks, so the audible click's timing
/// is untouched and the visual pulse can never drift from it.
class MetronomeBeatClockAdapter implements SsBeatClock {
  MetronomeBeatClockAdapter(this.secondsAt);

  /// Returns the current elapsed playback time in seconds, or null while
  /// stopped. A plain getter closure, not a stream — [SsBeatClock] is
  /// pull-based by design (L444).
  final double? Function() secondsAt;

  @override
  Duration? get position {
    final secs = secondsAt();
    if (secs == null) return null;
    return Duration(microseconds: (secs * 1e6).round());
  }
}

/// The metronome's audio-clock-driven visual beat pulse (brief §0.0/R5.2,
/// ADR 0274 — the A4 acceptance surface). Every rendered phase comes from
/// [SsBeatClock.position] (never a separate BPM-derived `Timer`), read via
/// its own ticker so the animation is smooth between the parent's per-beat
/// rebuilds.
///
/// Unlike `core/design_system/motion/ss_beat_pulse.dart` (L444 — a generic
/// consumer that must poll forever because it has no positive resume
/// signal), [playing] here is an EXPLICIT signal from the one caller that
/// owns transport state (`MetronomeScreen._playing`): the ticker runs only
/// while playing and is stopped the instant it isn't, restarting the moment
/// [playing] flips back — never a silent, permanently-idle poll. This keeps
/// `pumpAndSettle()` terminating for every OTHER screen/route test that
/// happens to mount a stopped metronome (the default state), which an
/// always-on ticker would hang forever (measured while writing this round's
/// own tests).
///
/// Stays palette-driven instead of reading the design system's
/// `SsColorScheme` theme extension: `AppTheme` (the app's actual runtime
/// theme) registers only `AppPalette` — see the E13-R18 handoff /
/// `SsChordHero`'s doc comment for the same reasoning.
final class BeatPulseDot extends StatefulWidget {
  const BeatPulseDot({
    super.key,
    required this.playing,
    required this.clock,
    required this.beatDuration,
    required this.color,
    required this.mutedColor,
    this.diameter = 16,
  });

  /// Whether the transport is currently running — gates whether this
  /// widget's own ticker is active at all (see class doc).
  final bool playing;

  final SsBeatClock clock;
  final Duration beatDuration;
  final Color color;
  final Color mutedColor;
  final double diameter;

  /// Stable key for the rendered dot so tests can locate and measure it.
  static const Key dotKey = ValueKey('metronome_beat_pulse_dot');

  @override
  State<BeatPulseDot> createState() => _BeatPulseDotState();
}

final class _BeatPulseDotState extends State<BeatPulseDot>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _phase = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.playing) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant BeatPulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing && !oldWidget.playing) {
      _ticker.start();
    } else if (!widget.playing && oldWidget.playing) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final position = widget.clock.position;
    final beatMicros = widget.beatDuration.inMicroseconds;
    if (position == null || beatMicros <= 0) return;
    final phase = (position.inMicroseconds % beatMicros) / beatMicros;
    if (phase != _phase) setState(() => _phase = phase);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.playing) return _dot(color: widget.mutedColor, scale: 1);
    final scale = 1 + (1 - _phase) * 0.3;
    return _dot(color: widget.color, scale: scale);
  }

  Widget _dot({required Color color, required double scale}) {
    final size = widget.diameter * scale;
    return SizedBox(
      width: widget.diameter * 1.3,
      height: widget.diameter * 1.3,
      child: Center(
        child: Container(
          key: BeatPulseDot.dotKey,
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
