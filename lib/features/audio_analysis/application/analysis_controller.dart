import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';

import 'analysis_providers.dart'
    show
        analysisPracticeCreditRecorderProvider,
        analyzeAudioUseCaseProvider,
        cancelAnalysisUseCaseProvider;
import 'analyze_audio_use_case.dart';
import 'analysis_isolate_runner.dart';
import 'analysis_state.dart';
import 'cancel_analysis_use_case.dart';

/// Cross-feature side effect owned by the composition root, keeping the
/// controller free of progress/streak feature imports.
abstract interface class AnalysisPracticeCreditRecorder {
  void record(AnalysisDocument document);
}

/// Coordinates one analysis run. It owns the authoritative active run ID;
/// runner- and pipeline-local counters are never used for stale-event checks.
final class AnalysisController extends Notifier<AnalysisState> {
  /// A három függőség OPCIONÁLIS (2026-09-05).
  ///
  /// Korábban mindhárom kötelező konstruktor-paraméter volt, és ezért a
  /// vezérlőnek NEM lehetett providere: a `NotifierProvider` gyártó
  /// callbackje `ref` nélkül fut, tehát a függőségeket ott nem lehet
  /// feloldani. A vezérlő így soha nem épült fel élesben — ez tartotta
  /// elérhetetlenül a `capture/` képernyőket.
  ///
  /// Megoldás: a `late final` mezők a KOMPOZÍCIÓBÓL oldódnak fel, az első
  /// hozzáféréskor (akkor már van `ref`). A teszt továbbra is átadhatja a
  /// sajátját — a paraméterek neve változatlan.
  AnalysisController({
    AnalyzeAudioUseCase? analyzeAudio,
    CancelAnalysisUseCase? cancelAnalysis,
    AnalysisPracticeCreditRecorder? practiceCredit,
    this.minEventsBetweenEmits = 5,
  }) : _analyzeAudioOverride = analyzeAudio,
       _cancelAnalysisOverride = cancelAnalysis,
       _practiceCreditOverride = practiceCredit {
    if (minEventsBetweenEmits <= 0) {
      throw ArgumentError.value(minEventsBetweenEmits, 'minEventsBetweenEmits');
    }
  }

  final AnalyzeAudioUseCase? _analyzeAudioOverride;
  final CancelAnalysisUseCase? _cancelAnalysisOverride;
  final AnalysisPracticeCreditRecorder? _practiceCreditOverride;

  late final AnalyzeAudioUseCase analyzeAudio =
      _analyzeAudioOverride ?? ref.read(analyzeAudioUseCaseProvider);
  late final CancelAnalysisUseCase cancelAnalysis =
      _cancelAnalysisOverride ?? ref.read(cancelAnalysisUseCaseProvider);
  late final AnalysisPracticeCreditRecorder practiceCredit =
      _practiceCreditOverride ??
      ref.read(analysisPracticeCreditRecorderProvider);
  final int minEventsBetweenEmits;
  final Set<String> _creditedRunIds = <String>{};
  String? _activeRunId;
  AnalysisRunHandle? _activeRun;
  final Set<StreamSubscription<AnalysisProgressEvent>> _progressSubscriptions =
      <StreamSubscription<AnalysisProgressEvent>>{};
  int _eventsSinceEmission = 0;
  int _rejectedLateResults = 0;

  int get rejectedLateResults => _rejectedLateResults;

  @override
  AnalysisState build() {
    ref.onDispose(() {
      for (final subscription in _progressSubscriptions) {
        unawaited(subscription.cancel());
      }
      unawaited(_activeRun?.cancel());
    });
    return const AnalysisIdle();
  }

  void acquiringInput() => state = const AnalysisAcquiringInput();

  void recording() => state = const AnalysisRecording();

  void validating() => state = const AnalysisValidating();

  void permissionDenied() => state = const AnalysisPermissionDenied();

  void inputError(AppFailure failure) => state = AnalysisInputError(failure);

  /// Starts an explicit user-requested analysis. There is no automatic retry.
  Future<void> analyze(
    AnalysisDocument input, {
    required ValidatedPcmAnalysisInput audio,
  }) async {
    final previousRun = _activeRun;
    if (previousRun != null) {
      unawaited(cancelAnalysis(previousRun));
    }
    validating();
    final run = analyzeAudio(input, audio: audio);
    final runId = run.runId;
    _activeRun = run;
    _activeRunId = runId;
    _eventsSinceEmission = 0;
    state = AnalysisAnalyzing(runId: runId);
    late final StreamSubscription<AnalysisProgressEvent> subscription;
    subscription = run.progress.listen(
      _onProgress,
      onDone: () => _progressSubscriptions.remove(subscription),
    );
    _progressSubscriptions.add(subscription);
    final result = await run.result;
    _onResult(runId, result);
  }

  Future<void> cancel() async {
    final run = _activeRun;
    final runId = _activeRunId;
    if (run == null || runId == null) return;
    await cancelAnalysis(run);
    if (_activeRunId != runId) return;
    _activeRun = null;
    _activeRunId = null;
    state = AnalysisCancelled(runId: runId);
  }

  /// The V2 host calls this when its view leaves the foreground.
  void screenDetached() => unawaited(cancel());

  /// The V2 host calls this when the app is backgrounded.
  void appBackgrounded() => unawaited(cancel());

  void _onProgress(AnalysisProgressEvent event) {
    if (event.runId != _activeRunId) {
      _rejectedLateResults++;
      return;
    }
    if (event is! AnalysisPhaseProgressEvent) return;
    _eventsSinceEmission++;
    if (_eventsSinceEmission < minEventsBetweenEmits) return;
    _eventsSinceEmission = 0;
    final current = state;
    if (current is! AnalysisAnalyzing || current.runId != event.runId) return;
    state = AnalysisAnalyzing(
      runId: event.runId,
      phase: event.phase,
      completedUnits: event.completedUnits,
      totalUnits: event.totalUnits,
      emittedProgressEvents: current.emittedProgressEvents + 1,
    );
  }

  void _onResult(String runId, AnalysisRunResult result) {
    if (runId != _activeRunId) {
      _rejectedLateResults++;
      return;
    }
    _activeRun = null;
    _activeRunId = null;
    switch (result.completion) {
      case AnalysisCompletionStatus.complete:
        final document = result.document;
        if (document == null) {
          state = AnalysisError(runId: runId, failure: const UnknownFailure());
          return;
        }
        state = AnalysisCompleted(runId: runId, document: document);
        _creditOnce(runId, document);
      case AnalysisCompletionStatus.degraded:
        final document = result.document;
        if (document == null) {
          state = AnalysisError(runId: runId, failure: const UnknownFailure());
          return;
        }
        state = AnalysisDegradedCompleted(runId: runId, document: document);
      case AnalysisCompletionStatus.cancelled:
        state = AnalysisCancelled(runId: runId);
      case AnalysisCompletionStatus.failed:
        state = AnalysisError(
          runId: runId,
          failure: result.failure ?? const UnknownFailure(),
        );
    }
  }

  void _creditOnce(String runId, AnalysisDocument document) {
    if (!_creditedRunIds.add(runId)) return;
    final hasChord = document.timeline.chordSegments.isNotEmpty;
    final hasStrum = document.timeline.events
        .whereType<StrumEvent>()
        .isNotEmpty;
    if (hasChord || hasStrum) practiceCredit.record(document);
  }
}
