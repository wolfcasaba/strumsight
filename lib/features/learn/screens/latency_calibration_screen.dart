import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/providers/input_latency_provider.dart';
import '../../settings/providers/visual_latency_provider.dart';
import '../audio/metronome.dart';
import '../calibration/latency_calibrator.dart';

/// Rock-Band-style timing calibration (chunk 016b P3): a click plays at
/// 100 BPM; the user taps a big SILENT button on every click; the median tap
/// offset is this device's audio/input delay, saved to
/// [inputLatencyProvider] and applied by the Learn scorer. Starts stopped so
/// widget tests drive it deterministically with `pump(Duration)`.
class LatencyCalibrationScreen extends ConsumerStatefulWidget {
  const LatencyCalibrationScreen({super.key});

  static const int tapsNeeded = 8;

  @override
  ConsumerState<LatencyCalibrationScreen> createState() =>
      _LatencyCalibrationScreenState();
}

class _LatencyCalibrationScreenState
    extends ConsumerState<LatencyCalibrationScreen>
    with SingleTickerProviderStateMixin {
  static const _beatPeriodSec = 0.6; // 100 BPM

  final Metronome _metronome = Metronome();
  LatencyCalibrator _calibrator =
      LatencyCalibrator(beatPeriodSec: _beatPeriodSec);
  late final Ticker _ticker;

  bool _visualMode = false;
  bool _running = false;
  double _elapsedSec = 0;
  int _lastBeat = -1;
  bool _pulse = false;
  double? _lastTapOffset;

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
    _elapsedSec = elapsed.inMicroseconds / 1e6;
    final beat = (_elapsedSec / _beatPeriodSec).floor();
    if (beat != _lastBeat) {
      _lastBeat = beat;
      if (!_visualMode) _metronome.tick(accent: false);
      setState(() => _pulse = true);
    } else if (_pulse && _elapsedSec - _lastBeat * _beatPeriodSec > 0.12) {
      setState(() => _pulse = false);
    }
  }

  void _start() {
    setState(() {
      _calibrator = LatencyCalibrator(beatPeriodSec: _beatPeriodSec);
      _lastTapOffset = null;
      _lastBeat = -1;
      _elapsedSec = 0;
      _running = true;
      _ticker
        ..stop()
        ..start();
    });
  }

  void _stopRun() {
    _ticker.stop();
    setState(() => _running = false);
  }

  /// The tap target is deliberately SILENT — a tap sound would pollute the
  /// measurement (chunk 016b).
  void _onTap() {
    if (!_running) return;
    setState(() {
      _lastTapOffset = _calibrator.registerTap(_elapsedSec);
    });
    if (_calibrator.sampleCount >= LatencyCalibrationScreen.tapsNeeded) {
      _stopRun();
    }
  }

  Future<void> _save() async {
    final offset = _calibrator.offsetSec;
    if (offset == null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ms = (offset * 1000).round();
    if (_visualMode) {
      await ref.read(visualLatencyProvider.notifier).set(ms);
    } else {
      await ref.read(inputLatencyProvider.notifier).set(ms);
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.calibrationSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final savedMs = ref.watch(
        _visualMode ? visualLatencyProvider : inputLatencyProvider);
    final done = !_running &&
        _calibrator.sampleCount >= LatencyCalibrationScreen.tapsNeeded;
    final offset = _calibrator.offsetSec;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.calibrationTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: false, label: Text(l10n.calibrationModeAudio)),
                  ButtonSegment(
                      value: true, label: Text(l10n.calibrationModeVisual)),
                ],
                selected: {_visualMode},
                onSelectionChanged: _running
                    ? null
                    : (s) => setState(() => _visualMode = s.first),
              ),
              const SizedBox(height: 12),
              Text(
                  _visualMode
                      ? l10n.calibrationIntroVisual
                      : l10n.calibrationIntro,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 6),
              Text(l10n.calibrationCurrent('$savedMs'),
                  style: theme.textTheme.bodySmall),
              const Spacer(),
              // Beat pulse.
              AnimatedContainer(
                duration: const Duration(milliseconds: 60),
                width: _pulse ? 34 : 20,
                height: _pulse ? 34 : 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary
                      .withValues(alpha: _pulse ? 1.0 : 0.25),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                done && offset != null
                    ? l10n.calibrationResult('${(offset * 1000).round()}')
                    : '${_calibrator.sampleCount} / '
                        '${LatencyCalibrationScreen.tapsNeeded}',
                style: const TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 30),
              ),
              if (done && !_calibrator.isStable)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(l10n.calibrationUnstable,
                      style: TextStyle(color: AppColors.confidenceMid)),
                ),
              if (_running && _lastTapOffset != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${(_lastTapOffset! * 1000).round()} ms',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const Spacer(),
              if (_running)
                // The big silent tap target.
                SizedBox(
                  width: 180,
                  height: 180,
                  child: FilledButton(
                    onPressed: _onTap,
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      backgroundColor: AppColors.primary,
                    ),
                    child: Text(l10n.calibrationTap,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                )
              else ...[
                if (done && _calibrator.isStable)
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(l10n.calibrationSave),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56)),
                  ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                      done ? l10n.calibrationRetry : l10n.calibrationStart),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56)),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
