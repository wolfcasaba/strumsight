import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/audio/metronome.dart';
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
  late final Ticker _ticker;

  int _bpm = 100;
  int _beatsPerBar = 4;
  bool _playing = false;
  Duration _start = Duration.zero;
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
    final secs = (elapsed - _start).inMicroseconds / 1e6;
    final beat = (secs * _bpm / 60).floor();
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
        _start = Duration.zero;
        _ticker
          ..stop()
          ..start();
      } else {
        _ticker.stop();
      }
    });
  }

  void _setBpm(int v) => setState(() => _bpm = v.clamp(_minBpm, _maxBpm));

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
          child: Column(
            children: [
              const Spacer(),
              // Beat pulse dots.
              Row(
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
              ),
              const SizedBox(height: 28),
              Text('$_bpm',
                  style: const TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w800,
                      fontSize: 72,
                      height: 1.0,
                      color: AppColors.primary)),
              Text(l10n.metronomeBpm,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
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
              ),
              const SizedBox(height: 20),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final n in const [2, 3, 4, 6])
                    ButtonSegment(value: n, label: Text('$n/4')),
                ],
                selected: {_beatsPerBar},
                onSelectionChanged: (s) =>
                    setState(() => _beatsPerBar = s.first),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _onTap,
                      icon: const Icon(Icons.touch_app_outlined),
                      label: Text(l10n.metronomeTap),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _toggle,
                      icon: Icon(_playing
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded),
                      label: Text(
                          _playing ? l10n.metronomeStop : l10n.metronomeStart),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
        color: active
            ? base
            : base.withValues(alpha: 0.22),
      ),
    );
  }
}
