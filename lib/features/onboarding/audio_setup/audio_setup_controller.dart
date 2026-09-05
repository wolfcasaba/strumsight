import 'package:meta/meta.dart';

import '../../live/public.dart';
import 'audio_profile.dart';
import 'audio_profile_store.dart';
import 'audio_setup_step.dart';

/// Explicit run status — never inferred from "does the buffer already hold
/// data" (L305): [AudioSetupController.start]/`recordStep`/`abort` are the
/// only transitions.
enum AudioSetupRunStatus { notStarted, inProgress, completed, aborted }

enum AudioSetupOutcome { success, needsAttention }

/// The outcome of a finished run.
@immutable
class AudioSetupResult {
  const AudioSetupResult({
    required this.outcome,
    required this.advice,
    required this.profile,
  });

  final AudioSetupOutcome outcome;

  /// Non-empty exactly when [outcome] is [AudioSetupOutcome.needsAttention]
  /// (ADR 0519 D2) — concrete placement/retry advice, never a blank string.
  final String advice;

  /// Non-null exactly when [outcome] is [AudioSetupOutcome.success] — a
  /// `needsAttention` run never produces (or saves) a profile.
  final AudioProfile? profile;
}

/// The automatic audio-setup step-machine (ADR 0519). Interruptible: any
/// step may be the last one recorded before [abort] — the run then leaves
/// no trace in [store] (D4). No UI binds to this yet (D8); a test drives it
/// with fake [SignalQualitySnapshot] readings (no real microphone in CI).
class AudioSetupController {
  AudioSetupController({
    required this.store,
    required this.micRouteId,
    required this.sampleRateHz,
    this.inputLatencyMsAtCapture = 0,
    this.visualLatencyMsAtCapture = 0,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AudioProfileStore store;

  /// The mic-route identifier and sample rate this run is measuring under —
  /// stamped onto the saved [AudioProfile] so a later route/rate change can
  /// be detected as staleness (ADR 0519 D3).
  final String micRouteId;
  final int sampleRateHz;

  /// The Settings latency values in effect when this run started — carried
  /// onto the profile unchanged (ADR 0519 D1: never a computed override;
  /// this round has no tap-test measurement of its own).
  final int inputLatencyMsAtCapture;
  final int visualLatencyMsAtCapture;

  final DateTime Function() _now;

  AudioSetupRunStatus _status = AudioSetupRunStatus.notStarted;
  int _stepIndex = 0;
  final List<SignalQualitySnapshot> _collected = [];

  AudioSetupRunStatus get status => _status;

  /// The step the next [recordStep] call will record, or `null` once the
  /// run has finished or been aborted.
  AudioSetupStep? get currentStep => _status == AudioSetupRunStatus.inProgress
      ? AudioSetupStep.sequence[_stepIndex]
      : null;

  /// Begins (or restarts) a run. Any previously collected — but not yet
  /// saved — steps are discarded.
  void start() {
    _status = AudioSetupRunStatus.inProgress;
    _stepIndex = 0;
    _collected.clear();
  }

  /// Records [quality] for the current step and advances. Returns `null`
  /// while steps remain; returns the finished [AudioSetupResult] on the
  /// call that records the LAST step — that same call is the only place
  /// [store] is written (single atomic save, D4).
  Future<AudioSetupResult?> recordStep(SignalQualitySnapshot quality) async {
    if (_status != AudioSetupRunStatus.inProgress) {
      throw StateError(
        'recordStep called while status is $_status, not inProgress',
      );
    }
    _collected.add(quality);
    _stepIndex++;
    if (_stepIndex < AudioSetupStep.sequence.length) {
      return null;
    }
    return _finish();
  }

  /// Aborts a run in progress. The collected step data is discarded in
  /// memory and [store] is never written — a half-finished run leaves no
  /// partial profile (ADR 0519 D4, acceptance #3).
  void abort() {
    _status = AudioSetupRunStatus.aborted;
    _collected.clear();
    _stepIndex = 0;
  }

  Future<AudioSetupResult> _finish() async {
    final overallState = _firstNonGoodState();
    if (overallState != SignalQualityState.good) {
      _status = AudioSetupRunStatus.completed;
      return AudioSetupResult(
        outcome: AudioSetupOutcome.needsAttention,
        advice: _adviceFor(overallState),
        profile: null,
      );
    }
    final profile = AudioProfile(
      schemaVersion: AudioProfile.currentSchemaVersion,
      micRouteId: micRouteId,
      sampleRateHz: sampleRateHz,
      suggestedInputGainDb: _suggestGain(),
      inputLatencyMsAtCapture: inputLatencyMsAtCapture,
      visualLatencyMsAtCapture: visualLatencyMsAtCapture,
      qualityExpectation: overallState,
      confidenceProfile: _confidenceProfile(),
      recordedAt: _now(),
    );
    await store.save(profile);
    _status = AudioSetupRunStatus.completed;
    return AudioSetupResult(
      outcome: AudioSetupOutcome.success,
      advice: '',
      profile: profile,
    );
  }

  /// The first non-[SignalQualityState.good] reading anywhere in the run —
  /// any single bad step disqualifies the whole run from `success` (ADR
  /// 0519 D2): a wizard that only checked the loudest step would miss a
  /// noisy room that only shows up during the silence measurement.
  SignalQualityState _firstNonGoodState() {
    for (final snapshot in _collected) {
      if (snapshot.state != SignalQualityState.good) return snapshot.state;
    }
    return SignalQualityState.good;
  }

  static String _adviceFor(SignalQualityState state) {
    switch (state) {
      case SignalQualityState.tooQuiet:
        return 'Move the phone closer to the guitar, or play a bit louder, '
            'then run setup again.';
      case SignalQualityState.tooLoud:
      case SignalQualityState.clipping:
        return 'Move the phone a little further from the guitar and lower '
            'the strum volume, then run setup again.';
      case SignalQualityState.tooNoisy:
        return 'Find a quieter spot — background noise is drowning out the '
            'guitar — then run setup again.';
      case SignalQualityState.speechLike:
        return 'Make sure only the guitar is audible during setup (no '
            'talking or music playing), then run setup again.';
      case SignalQualityState.unstable:
        return 'Hold the phone steady and keep it in place during setup, '
            'then run setup again.';
      case SignalQualityState.unknown:
        return 'Setup could not get a clear reading — try again somewhere '
            'quiet with the phone close to the guitar.';
      case SignalQualityState.good:
        return '';
    }
  }

  /// A simple heuristic suggestion from the strum/chord steps' peak levels —
  /// informational only, never fed back into any DSP/ML constant (ADR 0519
  /// D1). The silence step (index 0) is excluded since it measures the
  /// noise floor, not playing level.
  double _suggestGain() {
    final peaks = <double>[];
    for (var i = 1; i < _collected.length; i++) {
      final peak = _collected[i].peakDbfs;
      if (peak != null) peaks.add(peak);
    }
    if (peaks.isEmpty) return 0.0;
    final averagePeak = peaks.reduce((a, b) => a + b) / peaks.length;
    const referencePeakDbfs = -6.0;
    return double.parse((referencePeakDbfs - averagePeak).toStringAsFixed(1));
  }

  /// Fraction of steps that read [SignalQualityState.good] — the user's own
  /// "how clean was my setup" number (ADR 0519 D1's confidence-profile),
  /// never a classifier threshold.
  double _confidenceProfile() {
    if (_collected.isEmpty) return 0.0;
    final goodCount = _collected
        .where((s) => s.state == SignalQualityState.good)
        .length;
    return goodCount / _collected.length;
  }
}
