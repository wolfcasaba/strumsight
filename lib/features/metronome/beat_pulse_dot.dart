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
/// ADR 0274 — the A4 acceptance surface). Mirrors
/// `core/design_system/motion/ss_beat_pulse.dart`'s pull-every-frame
/// contract exactly (never a locally-owned free-running `Timer`, and the
/// ticker is deliberately never stopped when [SsBeatClock.position] goes
/// null — L444, a "stop when idle" optimisation would make a later resume
/// silently never restart it) but stays palette-driven instead of reading
/// the design system's `SsColorScheme` theme extension: `AppTheme` (the
/// app's actual runtime theme) registers only `AppPalette` — see the E13-R18
/// handoff / `SsChordHero`'s doc comment for the same reasoning.
final class BeatPulseDot extends StatefulWidget {
  const BeatPulseDot({
    super.key,
    required this.clock,
    required this.beatDuration,
    required this.color,
    required this.mutedColor,
    this.diameter = 16,
  });

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
    if (!_live) return _dot(color: widget.mutedColor, scale: 1);
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
