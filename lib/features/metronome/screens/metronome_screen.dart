import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/audio/metronome.dart';
import '../beat_clock.dart';
import '../tap_tempo.dart';

/// A standalone metronome tool: set a tempo (slider, ±, or tap-tempo), pick a
/// time signature, and play a click with an accented downbeat + a visual beat
/// pulse. Reuses the pure-Dart synthesised click (`Metronome`). Starts stopped
/// so widget tests advance it deterministically with `pump(Duration)`.
class MetronomeScreen extends StatefulWidget {
  const MetronomeScreen({super.key});

  @override
  State<MetronomeScreen> createState() => _MetronomeScreenState();
}

class _MetronomeScreenState extends State<MetronomeScreen>
    with SingleTickerProviderStateMixin {
  static const _minBpm = 40;
  static const _maxBpm = 240;

  final Metronome _metronome = Metronome();
  final TapTempo _tapTempo = TapTempo(minBpm: _minBpm, maxBpm: _maxBpm);

  /// Phase-preserving clock: a mid-play tempo change keeps the beat position
  /// continuous instead of rescaling all elapsed time (round 98).
  final BeatClock _clock = BeatClock(bpm: 100);
  late final Ticker _ticker;

  int _bpm = 100;
  int _beatsPerBar = 4;
  bool _playing = false;
  double _lastSecs = 0;
  int _lastBeat = -1;
  int _currentBeat = 0; // index within the bar, for the visual pulse

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _metronome.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _lastSecs = elapsed.inMicroseconds / 1e6;
    final beat = _clock.beatsAt(_lastSecs).floor();
    if (beat != _lastBeat) {
      _lastBeat = beat;
      final inBar = beat % _beatsPerBar;
      final downbeat = inBar == 0;
      _metronome.tick(accent: downbeat);
      setState(() => _currentBeat = inBar);
    }
  }

  void _toggle() {
    setState(() {
      _playing = !_playing;
      if (_playing) {
        // Ticker elapsed restarts at zero on each start(), so count from 0.
        _lastBeat = -1;
        _currentBeat = 0;
        _lastSecs = 0;
        _clock.reset();
        _ticker
          ..stop()
          ..start();
      } else {
        _ticker.stop();
      }
    });
  }

  void _setBpm(int v) {
    final clamped = v.clamp(_minBpm, _maxBpm);
    // Anchor the phase at "now" so a mid-play change never jumps the beat.
    _clock.setBpm(clamped, atSecs: _playing ? _lastSecs : 0);
    setState(() => _bpm = clamped);
  }

  void _onTap() {
    final bpm = _tapTempo.tap(DateTime.now());
    if (bpm != null) _setBpm(bpm);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.metronomeTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          // Landscape phones lay the controls out in two columns so nothing is
          // crowded; portrait keeps the single tall column. Either way the
          // content scrolls when it is taller than the viewport, so there is
          // never a vertical overflow (small portrait / short landscape).
          child: LayoutBuilder(
            builder: (context, constraints) {
              final landscape = constraints.maxWidth > constraints.maxHeight;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: landscape
                        ? _landscapeBody(l10n)
                        : _portraitBody(l10n),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Single-column layout for portrait; Spacers breathe when there is room.
  Widget _portraitBody(AppLocalizations l10n) => Column(
        children: [
          const Spacer(),
          _beatDots(),
          const SizedBox(height: 28),
          _bpmHero(l10n),
          const SizedBox(height: 16),
          _tempoSlider(),
          const SizedBox(height: 20),
          _timeSignature(),
          const Spacer(),
          _actions(l10n),
        ],
      );

  /// Two-column layout for landscape: the hero + beat pulse on the left, the
  /// slider / time-signature / tap+play controls on the right.
  Widget _landscapeBody(AppLocalizations l10n) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _beatDots(),
                const SizedBox(height: 24),
                _bpmHero(l10n),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _tempoSlider(),
                const SizedBox(height: 16),
                _timeSignature(),
                const SizedBox(height: 20),
                _actions(l10n),
              ],
            ),
          ),
        ],
      );

  /// Visual beat-pulse dots (one per beat in the bar).
  Widget _beatDots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _beatsPerBar; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: _BeatDot(
                active: _playing && i == _currentBeat,
                downbeat: i == 0,
              ),
            ),
        ],
      );

  /// Big BPM readout. FittedBox scales the number down on narrow (320px)
  /// phones so it never forces a horizontal overflow.
  Widget _bpmHero(AppLocalizations l10n) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$_bpm',
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w800,
                fontSize: 72,
                height: 1.0,
                color: AppColors.primary,
              ),
            ),
          ),
          Text(
            l10n.metronomeBpm,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );

  /// − / slider / + tempo control.
  Widget _tempoSlider() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filledTonal(
            onPressed: () => _setBpm(_bpm - 1),
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: Slider(
              value: _bpm.toDouble(),
              min: _minBpm.toDouble(),
              max: _maxBpm.toDouble(),
              onChanged: (v) => _setBpm(v.round()),
            ),
          ),
          IconButton.filledTonal(
            onPressed: () => _setBpm(_bpm + 1),
            icon: const Icon(Icons.add),
          ),
        ],
      );

  /// Time-signature toggle (2/4, 3/4, 4/4, 6/4).
  Widget _timeSignature() => SegmentedButton<int>(
        showSelectedIcon: false,
        segments: [
          for (final n in const [2, 3, 4, 6])
            ButtonSegment(value: n, label: Text('$n/4')),
        ],
        selected: {_beatsPerBar},
        onSelectionChanged: (s) => setState(() => _beatsPerBar = s.first),
      );

  /// Tap-tempo + start/stop actions.
  Widget _actions(AppLocalizations l10n) => Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _onTap,
              icon: const Icon(Icons.touch_app_outlined),
              label: Text(l10n.metronomeTap),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _toggle,
              icon: Icon(
                _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
              label: Text(
                _playing ? l10n.metronomeStop : l10n.metronomeStart,
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
          ),
        ],
      );
}

class _BeatDot extends StatelessWidget {
  const _BeatDot({required this.active, required this.downbeat});
  final bool active;
  final bool downbeat;

  @override
  Widget build(BuildContext context) {
    final base = downbeat ? AppColors.primary : AppColors.confidenceHigh;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      width: active ? 26 : 16,
      height: active ? 26 : 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? base : base.withValues(alpha: 0.22),
      ),
    );
  }
}
