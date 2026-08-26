// Recording Stage (SDD Ch13 Kör 26, UI-35, ADR 0285).
//
// Owns exactly one [AnalysisRecorder] instance handed in by the host —
// this screen never constructs a `MicCapture` itself (brief §0.0/B tilos
// zóna: the V2 application/data layer is out of scope for this round). Every
// exit path (stop, cancel, dispose, permission/error) releases the recorder
// so no run leaves an orphan microphone lease or a stray sample buffer
// (ADR 0285 §5.4, brief A5).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/capture/analysis_recorder.dart';
import '../../data/capture/recording_run.dart';
import '../../data/input/input_limits.dart';
import '../../domain/audio_retention_policy.dart';
import '../../domain/recording_level.dart';
import '../widgets/labels_adapter.dart';

enum _RecordingStage { idle, starting, recording, permissionDenied, error }

/// The recording Stage: a constant capture-state signal, the retention
/// notice, live signal-quality feedback, and the pre-recording capacity
/// limit (ADR 0285 §5.1/§5.5).
final class AnalysisRecordingScreen extends StatefulWidget {
  const AnalysisRecordingScreen({
    required this.recorder,
    required this.onFinished,
    required this.onCancel,
    this.retentionPolicy = AudioRetentionPolicy.defaultPolicy,
    this.maximumDuration = InputLimits.maxDuration,
    this.silenceThresholdDbfs = -45.0,
    super.key,
  });

  final AnalysisRecorder recorder;

  /// Called once recording has stopped — manually, or because the maximum
  /// duration was reached — with the captured run metadata and PCM.
  final void Function(RecordingRun run, List<double> samples) onFinished;

  final VoidCallback onCancel;

  /// The retention policy in effect for this capture (ADR 0217 §0.0/B6).
  /// Defaults to the repository's `keepOriginal: false` guarantee.
  final AudioRetentionPolicy retentionPolicy;

  final Duration maximumDuration;

  /// Presentation-only threshold: below this RMS the Stage shows the
  /// "too quiet" affordance instead of a clipping warning. Not a
  /// recognition threshold — the engine never reads this value.
  final double silenceThresholdDbfs;

  @override
  State<AnalysisRecordingScreen> createState() =>
      _AnalysisRecordingScreenState();
}

class _AnalysisRecordingScreenState extends State<AnalysisRecordingScreen> {
  _RecordingStage _stage = _RecordingStage.idle;
  RecordingRun? _run;
  RecordingLevel? _lastLevel;
  AppFailure? _failure;
  StreamSubscription<RecordingLevel>? _levelSubscription;

  @override
  void dispose() {
    unawaited(_levelSubscription?.cancel());
    // Every exit — including a bare pop while recording — releases the mic
    // lease and drops the sample buffer. AnalysisRecorder.dispose() is
    // idempotent, so this is also safe after an explicit stop/cancel.
    unawaited(widget.recorder.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _stage = _RecordingStage.starting;
      _failure = null;
    });
    final result = await widget.recorder.start();
    if (!mounted) return;
    switch (result) {
      case Success<RecordingRun>(:final value):
        setState(() {
          _run = value;
          _stage = _RecordingStage.recording;
        });
        _levelSubscription = widget.recorder.levels.listen(_onLevel);
      case Failure<RecordingRun>(:final error):
        setState(() {
          _failure = error;
          _stage = error is PermissionFailure
              ? _RecordingStage.permissionDenied
              : _RecordingStage.error;
        });
    }
  }

  void _onLevel(RecordingLevel level) {
    if (!mounted) return;
    setState(() {
      _lastLevel = level;
      _run = widget.recorder.currentRun;
    });
    if (!widget.recorder.isRecording && _stage == _RecordingStage.recording) {
      _finish();
    }
  }

  void _finish() {
    unawaited(_levelSubscription?.cancel());
    _levelSubscription = null;
    final run = widget.recorder.currentRun;
    // The host is expected to navigate away once onFinished fires; resetting
    // to idle here keeps this screen consistent if it stays mounted (e.g. in
    // a test), instead of showing a "live" indicator for a mic that already
    // stopped.
    setState(() {
      _stage = _RecordingStage.idle;
      _lastLevel = null;
    });
    if (run != null) {
      widget.onFinished(run, widget.recorder.samples);
    }
  }

  Future<void> _stop() async {
    await widget.recorder.stop();
    if (!mounted) return;
    _finish();
  }

  Future<void> _cancel() async {
    unawaited(_levelSubscription?.cancel());
    _levelSubscription = null;
    await widget.recorder.dispose();
    if (!mounted) return;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analysisRecordingTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: switch (_stage) {
            _RecordingStage.idle || _RecordingStage.starting => _ReadyBody(
              maximumDuration: widget.maximumDuration,
              retentionPolicy: widget.retentionPolicy,
              starting: _stage == _RecordingStage.starting,
              onStart: _start,
            ),
            _RecordingStage.recording => _RecordingBody(
              run: _run,
              level: _lastLevel,
              retentionPolicy: widget.retentionPolicy,
              silenceThresholdDbfs: widget.silenceThresholdDbfs,
              onStop: _stop,
              onCancel: _cancel,
            ),
            _RecordingStage.permissionDenied => _PermissionDeniedBody(
              onRetry: _start,
              onCancel: _cancel,
            ),
            _RecordingStage.error => _ErrorBody(
              failure: _failure,
              onRetry: _start,
              onCancel: _cancel,
            ),
          },
        ),
      ),
    );
  }
}

final class _ReadyBody extends StatelessWidget {
  const _ReadyBody({
    required this.maximumDuration,
    required this.retentionPolicy,
    required this.starting,
    required this.onStart,
  });

  final Duration maximumDuration;
  final AudioRetentionPolicy retentionPolicy;
  final bool starting;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.analysisRecordingReadyTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.analysisRecordingReadyDescription(maximumDuration.inMinutes),
          key: const Key('analysis-recording-capacity-limit'),
        ),
        const SizedBox(height: 8),
        _RetentionNotice(retentionPolicy: retentionPolicy),
        const Spacer(),
        FilledButton(
          key: const Key('analysis-recording-start'),
          onPressed: starting ? null : onStart,
          child: Text(l10n.analysisRecordingStart),
        ),
      ],
    );
  }
}

final class _RecordingBody extends StatelessWidget {
  const _RecordingBody({
    required this.run,
    required this.level,
    required this.retentionPolicy,
    required this.silenceThresholdDbfs,
    required this.onStop,
    required this.onCancel,
  });

  final RecordingRun? run;
  final RecordingLevel? level;
  final AudioRetentionPolicy retentionPolicy;
  final double silenceThresholdDbfs;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  bool get _isClipping => level?.isClipping ?? false;

  bool get _isQuiet =>
      !_isClipping &&
      (level?.rmsDbfs ?? double.negativeInfinity) < silenceThresholdDbfs;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = AppLocalizationsOverviewLabels(l10n);
    final elapsed = run == null
        ? Duration.zero
        : Duration(
            microseconds:
                run!.sampleCount *
                Duration.microsecondsPerSecond ~/
                (run!.sampleRate == 0 ? 1 : run!.sampleRate),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(
          liveRegion: true,
          label: l10n.analysisRecordingLiveLabel,
          child: Row(
            key: const Key('analysis-recording-live-indicator'),
            children: <Widget>[
              const Icon(Icons.fiber_manual_record, color: Colors.red),
              const SizedBox(width: 8),
              Text(l10n.analysisRecordingLiveLabel),
              const Spacer(),
              Text(
                l10n.analysisRecordingElapsed(labels.formatDuration(elapsed)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _RetentionNotice(retentionPolicy: retentionPolicy),
        const SizedBox(height: 12),
        if (_isClipping)
          _WarningBanner(
            key: const Key('analysis-recording-clipping'),
            icon: Icons.warning_amber_outlined,
            message: l10n.analysisRecordingClippingWarning,
          )
        else if (_isQuiet)
          _WarningBanner(
            key: const Key('analysis-recording-silence'),
            icon: Icons.volume_off_outlined,
            message: l10n.analysisRecordingSilenceWarning,
          ),
        const Spacer(),
        FilledButton(
          key: const Key('analysis-recording-stop'),
          onPressed: onStop,
          child: Text(l10n.analysisRecordingStop),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('analysis-recording-cancel'),
          onPressed: onCancel,
          child: Text(l10n.analysisRecordingCancel),
        ),
      ],
    );
  }
}

final class _RetentionNotice extends StatelessWidget {
  const _RetentionNotice({required this.retentionPolicy});

  final AudioRetentionPolicy retentionPolicy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      child: Row(
        key: const Key('analysis-recording-retention-notice'),
        children: <Widget>[
          Icon(
            retentionPolicy.keepOriginal
                ? Icons.save_outlined
                : Icons.privacy_tip_outlined,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              retentionPolicy.keepOriginal
                  ? l10n.analysisRecordingRetentionKept
                  : l10n.analysisRecordingRetentionDiscarded,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

final class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.icon, required this.message, super.key});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        children: <Widget>[
          Icon(icon, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

final class _PermissionDeniedBody extends StatelessWidget {
  const _PermissionDeniedBody({required this.onRetry, required this.onCancel});

  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.analysisRecordingPermissionDeniedTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(l10n.analysisRecordingPermissionDeniedDescription),
        const Spacer(),
        FilledButton(
          key: const Key('analysis-recording-permission-retry'),
          onPressed: onRetry,
          child: Text(l10n.analysisRecordingPermissionRetry),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onCancel,
          child: Text(l10n.analysisRecordingCancel),
        ),
      ],
    );
  }
}

final class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.failure,
    required this.onRetry,
    required this.onCancel,
  });

  final AppFailure? failure;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.analysisRecordingErrorTitle,
          key: const Key('analysis-recording-error-title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Spacer(),
        FilledButton(
          key: const Key('analysis-recording-error-retry'),
          onPressed: onRetry,
          child: Text(l10n.analysisRecordingErrorRetry),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onCancel,
          child: Text(l10n.analysisRecordingCancel),
        ),
      ],
    );
  }
}
