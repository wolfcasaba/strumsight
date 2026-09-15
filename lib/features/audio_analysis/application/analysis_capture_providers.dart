// Composition providers for the Analysis V2 capture flow (E17-R02, ADR 0521).
//
// The three capture screens under `presentation/capture/` are pure
// presentation (brief §5.2): they take a recorder, a state and callbacks and
// never read a provider. Everything they need is produced HERE and injected
// by the route builders in `app_router.dart`, so the widgets stay `ref`-free
// and the legacy `AnalyzeScreen` path is never touched (§5.3). Nothing in
// this file constructs a screen — the reachability tool measures the three
// capture screens as flag-gated only while the router is their sole
// constructor.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/config/app_config.dart';
import '../../../core/audio/audio_providers.dart';
import '../../../core/audio/lifecycle/audio_session_lease.dart';
import '../../../core/foundation/app_result.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/logging/logger_provider.dart';
import '../data/capture/analysis_recorder.dart';
import '../data/capture/recording_run.dart';
import '../data/input/analysis_input_validator.dart';
import '../domain/analysis_capability.dart';
import '../domain/analysis_document.dart';
import '../domain/analysis_hotspot.dart';
import '../domain/analysis_input.dart';
import '../domain/analysis_input_summary.dart';
import '../domain/analysis_insight.dart';
import '../domain/analysis_metric.dart';
import '../domain/analysis_mode.dart';
import '../domain/analysis_provenance.dart';
import '../domain/analysis_repository.dart';
import '../domain/analysis_summary.dart';
import '../domain/analysis_timeline.dart';
import '../domain/analysis_warning.dart';
import '../domain/signal_quality_report.dart';
import 'analysis_controller.dart';
import 'analysis_providers.dart';
import 'analysis_state.dart';
import 'save_analysis_use_case.dart';

/// One [AnalysisRecorder] per Recording-Stage visit.
///
/// `autoDispose` because a recorder is single-use: `AnalysisRecordingScreen`
/// disposes it on every exit path (ADR 0285 §5.4) and a disposed recorder
/// refuses `start()`, so the next visit must get a fresh one. The microphone
/// comes from the SAME shared `AudioSessionCoordinator` the Live, Tuner and
/// legacy Analyze engines use (`createMicCapture`, SDD Ch2 Kör 9), under the
/// `analyzeRecorder` owner — a second raw capture would bypass the one-owner
/// rule and could steal a running Live session.
final analysisRecorderProvider = Provider.autoDispose<AnalysisRecorder>((ref) {
  final recorder = AnalysisRecorder(
    mic: createMicCapture(ref, AudioOwner.analyzeRecorder),
  );
  // The screen already releases on every exit path; this covers a builder
  // that read the recorder but never mounted the screen. `dispose` is
  // idempotent, so the double call is safe.
  ref.onDispose(() => unawaited(recorder.dispose()));
  return recorder;
});

/// The one V2 [AnalysisController] the capture flow drives.
///
/// App-lifetime (not `autoDispose`) on purpose, mirroring the legacy
/// `analyzeControllerProvider`: the run is started from the Recording
/// Stage's `onFinished` BEFORE the Processing Stage mounts, and an
/// `autoDispose` notifier with no listener in that gap would be torn down —
/// and its run cancelled — by Riverpod's disposal pass.
final analysisControllerProvider =
    NotifierProvider<AnalysisController, AnalysisState>(AnalysisController.new);

/// Most-recent-first summaries for the Analyze home (index read only, never a
/// document decode — `AnalysisRepository.list` contract).
///
/// `autoDispose` so a fresh visit re-reads the index; a completed capture
/// invalidates it explicitly ([AnalysisCaptureFlow]) because the home stays
/// mounted underneath the pushed capture routes. A repository failure is
/// logged and rendered as an empty list — the home screen has no error slot,
/// and throwing here would only trigger Riverpod's provider-retry timers.
final recentAnalysesProvider =
    FutureProvider.autoDispose<List<AnalysisSummary>>((ref) async {
      final result = await ref.watch(analysisRepositoryProvider).list();
      switch (result) {
        case Success<List<AnalysisSummary>>(:final value):
          return value;
        case Failure<List<AnalysisSummary>>(:final error):
          ref
              .read(appLoggerProvider)
              .warning(
                'analysis.capture.recent_list_failed',
                error: error,
                fields: <String, Object?>{'code': error.code},
              );
          return const <AnalysisSummary>[];
      }
    });

/// The capture → analysis hand-off, composed from the feature's real
/// providers. The route builders call it; the screens never see it.
final analysisCaptureFlowProvider = Provider<AnalysisCaptureFlow>(
  (ref) => AnalysisCaptureFlow(
    controller: ref.watch(analysisControllerProvider.notifier),
    saveAnalysis: ref.watch(saveAnalysisUseCaseProvider),
    repository: ref.watch(analysisRepositoryProvider),
    logger: ref.watch(appLoggerProvider),
    appVersion: ref.watch(appConfigProvider).appVersion,
    onSaved: () => ref.invalidate(recentAnalysesProvider),
  ),
);

/// Validates a finished microphone run at the input boundary, seeds and
/// starts the V2 analysis, and persists a completed document.
final class AnalysisCaptureFlow {
  AnalysisCaptureFlow({
    required AnalysisController controller,
    required SaveAnalysisUseCase saveAnalysis,
    required AnalysisRepository repository,
    required AppLogger logger,
    required String appVersion,
    required void Function() onSaved,
    AnalysisInputValidator validator = const AnalysisInputValidator(),
  }) : _controller = controller,
       _saveAnalysis = saveAnalysis,
       _repository = repository,
       _logger = logger,
       _appVersion = appVersion,
       _onSaved = onSaved,
       _validator = validator;

  final AnalysisController _controller;
  final SaveAnalysisUseCase _saveAnalysis;
  final AnalysisRepository _repository;
  final AppLogger _logger;
  final String _appVersion;
  final void Function() _onSaved;
  final AnalysisInputValidator _validator;

  /// Runs the captured PCM through the stable input rules
  /// ([AnalysisInputValidator]) and starts the analysis. A rejected input
  /// publishes [AnalysisInputError] on the controller instead of starting a
  /// run, so the Processing Stage shows the typed failure with "Start again".
  ///
  /// [samples] is copied synchronously (by `PcmAnalysisInput`) before the
  /// first `await`, so the caller may dispose the recorder right after this
  /// returns its future.
  ///
  /// Completed and degraded documents are saved through the repository
  /// contract; a save failure is logged, never swallowed silently, and the
  /// on-screen result is unaffected (the document is already in memory).
  Future<void> analyzeRecording(RecordingRun run, List<double> samples) async {
    final validated = _validator.validate(
      PcmAnalysisInput(
        samples: samples,
        sampleRate: run.sampleRate,
        channelCount: 1,
        source: AnalysisInputSource.microphone,
      ),
    );
    switch (validated) {
      case Failure<ValidatedPcmAnalysisInput>(:final error):
        _controller.inputError(error);
      case Success<ValidatedPcmAnalysisInput>(:final value):
        final seed = buildCaptureSeedDocument(
          run: run,
          sampleCount: value.input.samples.length,
          appVersion: _appVersion,
        );
        await _controller.analyze(seed, audio: value);
        await _persistResult();
    }
  }

  /// Loads a saved document for the home's "recent analyses" tap. A failure
  /// is logged and surfaced as `null` so the caller can tell the user.
  Future<AnalysisDocument?> loadAnalysis(String documentId) async {
    final result = await _repository.getById(documentId);
    switch (result) {
      case Success<AnalysisDocument>(:final value):
        return value;
      case Failure<AnalysisDocument>(:final error):
        _logger.warning(
          'analysis.capture.open_failed',
          error: error,
          fields: <String, Object?>{'code': error.code},
        );
        return null;
    }
  }

  Future<void> _persistResult() async {
    final document = switch (_controller.state) {
      AnalysisCompleted(:final document) => document,
      AnalysisDegradedCompleted(:final document) => document,
      _ => null,
    };
    if (document == null) return;
    final saved = await _saveAnalysis(
      AnalysisSaveRequest(
        document: document,
        title: autoAnalysisTitle(document),
        customTitle: false,
      ),
    );
    switch (saved) {
      case Success<void>():
        _onSaved();
      case Failure<void>(:final error):
        _logger.warning(
          'analysis.capture.save_failed',
          error: error,
          fields: <String, Object?>{
            'code': error.code,
            'documentId': document.id,
          },
        );
    }
  }
}

/// The legacy auto-title shape ("C · G · Am"): the distinct chord labels in
/// timeline order, or empty when the run recognised no chord — the
/// repository allows an empty title for an untitled capture.
String autoAnalysisTitle(AnalysisDocument document) {
  final labels = <String>{};
  for (final segment in document.timeline.chordSegments) {
    labels.add(segment.label);
  }
  return labels.join(' · ');
}

/// The document seed for one microphone run (ADR 0254 §1).
///
/// The V2 runner reads exactly one field of the seed — its [AnalysisMode] —
/// and the document-assembly stage builds the REAL id, input summary,
/// provenance and signal quality inside the isolate. Every other field here
/// only satisfies the document's own validation; they are labelled as such
/// (`measured: false`, `seed-` ids) so a seed can never pass as a result.
AnalysisDocument buildCaptureSeedDocument({
  required RecordingRun run,
  required int sampleCount,
  required String appVersion,
}) {
  final seedId = 'seed-${run.id}';
  final duration = Duration(
    microseconds:
        sampleCount * Duration.microsecondsPerSecond ~/ run.sampleRate,
  );
  return AnalysisDocument(
    id: seedId,
    schemaVersion: analysisDocumentSchemaVersion,
    createdAt: run.startedAt.toUtc(),
    mode: AnalysisMode.freePlay,
    input: AnalysisInputSummary(
      source: AnalysisInputSource.microphone,
      duration: duration,
      sampleRate: run.sampleRate,
      channelCount: 1,
      fingerprint: seedId,
    ),
    provenance: AnalysisProvenance(
      appVersion: appVersion,
      analyzerVersion: 'seed',
      pipelineVersion: 'seed',
      stageVersions: const <String, String>{},
      dspConfigHash: 'seed',
      modelManifestIds: const <String>[],
      inputFingerprint: seedId,
      platform: 'seed',
      featureFlagSnapshot: const <String, bool>{},
    ),
    signalQuality: SignalQualityReport(
      overall: 0,
      peakDbfs: 0,
      rmsDbfs: 0,
      noiseFloorDbfs: 0,
      clippedSampleRatio: 0,
      silentRatio: 0,
      tonalness: 0,
      measured: false,
    ),
    capabilities: const <CapabilityReport>[],
    timeline: AnalysisTimeline(duration: duration),
    metrics: const <AnalysisMetricResult>[],
    hotspots: const <AnalysisHotspot>[],
    insights: const <AnalysisInsight>[],
    warnings: const <AnalysisWarning>[],
    // A seed carries no result yet; `cancelled` is the one status that can
    // never be mistaken for a finished analysis if it leaked past the runner.
    completion: AnalysisCompletion(status: AnalysisCompletionStatus.cancelled),
  );
}
