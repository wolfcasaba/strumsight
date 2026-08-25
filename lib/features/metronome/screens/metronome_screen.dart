import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/design_system/public.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/public.dart';
import '../beat_clock.dart';
import '../beat_pulse_dot.dart';
import '../tap_tempo.dart';

/// A standalone metronome tool: set a tempo (slider, ±, or tap-tempo), pick a
/// time signature, and play a click with an accented downbeat + a visual beat
/// pulse. Reuses the pure-Dart synthesised click (`Metronome`). Starts stopped
/// so widget tests advance it deterministically with `pump(Duration)`.
///
/// Migrated onto [SsStageScaffold] (Ch13 §9.9): the main surface keeps only
/// BPM, the beat visualization and the transport (brief §5.6) — the time
/// signature is an "advanced" setting behind the app-bar action, presented
/// through the R13 overlay system ([SsOverlayHost]).
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
  /// continuous instead of rescaling all elapsed time (round 98). UNCHANGED
  /// by this round (brief §0.0/R5.2, AGENTS.md §9) — the click's timing stays
  /// bit-for-bit identical; only the visual layer is re-plumbed below.
  final BeatClock _clock = BeatClock(bpm: 100);
  late final Ticker _ticker;

  /// The `SsBeatClock` PORT (brief §0.0/R5.2): reads the exact same
  /// elapsed-seconds value the click scheduler below already tracks, so the
  /// visual pulse can never drift from the audible click.
  late final MetronomeBeatClockAdapter _beatClockAdapter;

  int _bpm = 100;
  int _beatsPerBar = 4;
  bool _playing = false;
  double _lastSecs = 0;
  int _lastBeat = -1;
  int _currentBeat = 0; // index within the bar, for the per-bar dots

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _beatClockAdapter = MetronomeBeatClockAdapter(
      () => _playing ? _lastSecs : null,
    );
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

  Future<void> _openAdvancedSettings(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final palette = context.palette;
    return SsOverlayHost.showSheetSurface<void>(
      context: context,
      barrierLabel: l10n.metronomeAdvancedSettings,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.metronomeAdvancedSettings,
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: palette.ink,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.metronomeTimeSignature,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: palette.muted,
                ),
              ),
              const SizedBox(height: 8),
              SsChoice<int>(
                options: [
                  for (final n in const [2, 3, 4, 6])
                    SsChoiceOption(value: n, label: '$n/4'),
                ],
                value: _beatsPerBar,
                onChanged: (v) {
                  setState(() => _beatsPerBar = v);
                  setSheetState(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final beatDuration = Duration(microseconds: (60 / _bpm * 1e6).round());

    return SsStageScaffold(
      statusHeader: Row(
        children: [
          if (Navigator.canPop(context))
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          Expanded(
            child: Text(
              l10n.metronomeTitle,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: palette.ink,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: l10n.metronomeAdvancedSettings,
            onPressed: () => _openAdvancedSettings(context, l10n),
          ),
        ],
      ),
      hero: _bpmHero(l10n),
      // The audio-clock-bound visual pulse (A4) — never a `Timer.periodic`.
      feedback: BeatPulseDot(
        clock: _beatClockAdapter,
        beatDuration: beatDuration,
        color: AppColors.primary,
        mutedColor: palette.track,
      ),
      timeline: _beatDots(),
      bottomAction: _actions(l10n),
    );
  }

  /// Big BPM readout + the − / slider / + tempo control. FittedBox scales the
  /// number down on narrow (320px) phones so it never forces a horizontal
  /// overflow, at any text scale (A7).
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
      Text(l10n.metronomeBpm, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            onPressed: () => _setBpm(_bpm - 1),
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 180,
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
    ],
  );

  /// Discrete per-bar position dots (one per beat in the bar), still driven
  /// off the same audio-clock-derived `_currentBeat` as the click itself —
  /// never a separate free-running timer.
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
          icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
          label: Text(_playing ? l10n.metronomeStop : l10n.metronomeStart),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
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
