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

import '../../../../core/design_system/public.dart';
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    // Görgethető, de a `Spacer` megtartva (2026-09-05): fekvő tájolásban,
    // 2.0-s szöveg-méretnél a tartalom 64 pixellel túlcsordult, és az
    // indítás-gomb levágódott — pont a képernyő egyetlen művelete.
    // A `LayoutBuilder` + `IntrinsicHeight` együtt azt adja, hogy amíg VAN
    // hely, a `Spacer` lenyomja a gombot az aljára; amint nincs, a tartalom
    // görgethetővé válik ahelyett, hogy levágódna.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  l10n.analysisRecordingReadyTitle,
                  style: typography.titleLarge.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: SsSpacing.space2),
                Text(
                  l10n.analysisRecordingReadyDescription(
                    maximumDuration.inMinutes,
                  ),
                  key: const Key('analysis-recording-capacity-limit'),
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: SsSpacing.space2),
                _RetentionNotice(retentionPolicy: retentionPolicy),
                const Spacer(),
                SsButton(
                  key: const Key('analysis-recording-start'),
                  label: l10n.analysisRecordingStart,
                  onPressed: starting ? null : onStart,
                ),
              ],
            ),
          ),
        ),
      ),
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
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
              Icon(Icons.fiber_manual_record, color: colors.danger),
              const SizedBox(width: SsSpacing.space2),
              Text(
                l10n.analysisRecordingLiveLabel,
                style: typography.bodyMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                l10n.analysisRecordingElapsed(labels.formatDuration(elapsed)),
                style: typography.bodyMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: SsSpacing.space3),
        _RetentionNotice(retentionPolicy: retentionPolicy),
        const SizedBox(height: SsSpacing.space3),
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
        SsButton(
          key: const Key('analysis-recording-stop'),
          label: l10n.analysisRecordingStop,
          onPressed: onStop,
        ),
        const SizedBox(height: SsSpacing.space2),
        SsButton(
          key: const Key('analysis-recording-cancel'),
          label: l10n.analysisRecordingCancel,
          variant: SsButtonVariant.secondary,
          onPressed: onCancel,
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
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
            color: colors.textSecondary,
          ),
          const SizedBox(width: SsSpacing.space2),
          Expanded(
            child: Text(
              retentionPolicy.keepOriginal
                  ? l10n.analysisRecordingRetentionKept
                  : l10n.analysisRecordingRetentionDiscarded,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Row(
        children: <Widget>[
          Icon(icon, color: colors.danger),
          const SizedBox(width: SsSpacing.space2),
          Expanded(
            child: Text(
              message,
              style: typography.bodyMedium.copyWith(color: colors.textPrimary),
            ),
          ),
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.analysisRecordingPermissionDeniedTitle,
          style: typography.titleLarge.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: SsSpacing.space2),
        Text(
          l10n.analysisRecordingPermissionDeniedDescription,
          style: typography.bodyMedium.copyWith(color: colors.textSecondary),
        ),
        const Spacer(),
        SsButton(
          key: const Key('analysis-recording-permission-retry'),
          label: l10n.analysisRecordingPermissionRetry,
          onPressed: onRetry,
        ),
        const SizedBox(height: SsSpacing.space2),
        SsButton(
          label: l10n.analysisRecordingCancel,
          variant: SsButtonVariant.secondary,
          onPressed: onCancel,
        ),
      ],
    );
  }
}

/// The engine/general-recorder failure state (`_RecordingStage.error`):
/// `SsFailureState` renders the code-mapped title/message/action (ADR 0277).
/// The `analysis-recording-error-title` key moves to the whole failure
/// widget — the pinned key still identifies exactly one widget in the tree,
/// literally satisfying the existing cell (§0.0.A/R4).
///
/// A non-retryable failure maps to the `contactSupport` action, which this
/// screen has no handler for — so `onRetry` alone would leave the failure
/// section with zero buttons (review M3, same defect class as B1).
/// Restarting capture (`onRetry` calls `_start` again) is always a valid
/// next step here regardless of failure classification, so the explicit
/// "Retry" button is restored on that branch instead of being silently
/// dropped.
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
    final presentation = SsFailurePresentation.from(
      l10n,
      failure ?? const UnknownFailure(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: SsFailureState(
            key: const Key('analysis-recording-error-title'),
            presentation: presentation,
            onRetry: presentation.retryable ? onRetry : null,
          ),
        ),
        if (!presentation.retryable) ...<Widget>[
          SsButton(
            key: const Key('analysis-recording-error-retry'),
            label: l10n.analysisRecordingErrorRetry,
            onPressed: onRetry,
          ),
          const SizedBox(height: SsSpacing.space2),
        ],
        SsButton(
          label: l10n.analysisRecordingCancel,
          variant: SsButtonVariant.secondary,
          onPressed: onCancel,
        ),
      ],
    );
  }
}
