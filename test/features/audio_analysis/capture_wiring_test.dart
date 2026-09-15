// E17-R02 (ADR 0521) — the Analysis V2 capture flow is wired end to end:
// Practice Area Hub entry → home → recording → processing → overview,
// through the REAL `routerProvider` and a real `ProviderContainer`. Only
// the platform edges are faked (a scripted `FakeAudioCapture` behind the
// shared `AudioSessionCoordinator`, an in-memory repository, an
// `AnalysisRunner` that never spawns an isolate), so the cells measure the
// composition, not the DSP: the recorder holds the SAME coordinator lease
// Live uses, the captured PCM — not the pre-E17-R02 empty placeholder —
// reaches the runner, the completed document is saved and appears in
// "recent analyses", and a rejected input surfaces as the typed input
// error instead of a run.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/audio/audio_providers.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_home_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_processing_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_recording_screen.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const _entryKey = ValueKey('practice-hub-analysis-v2');

// --- Real-router harness (mirrors test/app/routing/app_router_test.dart) ---

class _RouterTestApp extends ConsumerWidget {
  const _RouterTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: SsLightTheme.data(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

final class _Harness {
  const _Harness({
    required this.container,
    required this.router,
    required this.capture,
    required this.runner,
    required this.repository,
  });

  final ProviderContainer container;
  final GoRouter router;
  final FakeAudioCapture capture;
  final _ScriptedRunner runner;
  final _InMemoryAnalysisRepository repository;
}

AppConfig _config({required bool audioAnalysisV2Enabled}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: true,
    labModeAvailable: true,
    audioAnalysisV2Enabled: audioAnalysisV2Enabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Future<_Harness> _pumpRouter(WidgetTester tester) async {
  final engine = FakeStrumEngine();
  final capture = FakeAudioCapture();
  final runner = _ScriptedRunner();
  final repository = _InMemoryAnalysisRepository();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(captureFactory: () => capture),
      strumEngineProvider.overrideWithValue(engine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      appConfigProvider.overrideWithValue(
        _config(audioAnalysisV2Enabled: true),
      ),
      analysisRepositoryProvider.overrideWithValue(repository),
      analysisV2RunnerProvider.overrideWithValue(runner),
    ],
  );
  final router = container.read(routerProvider);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await engine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _RouterTestApp(),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(
    container: container,
    router: router,
    capture: capture,
    runner: runner,
    repository: repository,
  );
}

/// Home → recording → a started, live microphone run. Shared by the cells
/// below so each one asserts a single hand-off.
Future<_Harness> _startRecording(WidgetTester tester) async {
  final harness = await _pumpRouter(tester);

  harness.router.go(AppRoutes.analysisHome);
  await tester.pumpAndSettle();
  expect(find.byType(AnalysisHomeScreen), findsOneWidget);

  await tester.tap(find.byKey(const Key('analysis-home-record')));
  await tester.pumpAndSettle();
  expect(harness.router.state.uri.path, AppRoutes.analysisRecording);
  expect(find.byType(AnalysisRecordingScreen), findsOneWidget);

  await tester.tap(find.byKey(const Key('analysis-recording-start')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const Key('analysis-recording-live-indicator')),
    findsOneWidget,
  );
  return harness;
}

Future<void> _stopRecording(WidgetTester tester, _Harness harness) async {
  await tester.tap(find.byKey(const Key('analysis-recording-stop')));
  await tester.pumpAndSettle();
  expect(harness.router.state.uri.path, AppRoutes.analysisProcessing);
  expect(find.byType(AnalysisProcessingScreen), findsOneWidget);
  // `pushReplacement`, not `push`: the Recording Stage is gone, so its
  // recorder was disposed and cannot hold a stray sample buffer.
  expect(find.byType(AnalysisRecordingScreen), findsNothing);
}

void main() {
  group('E17-R02 A2 — home → recording → processing, real providers', () {
    testWidgets(
      'the recorder holds the shared analyzeRecorder lease while live and '
      'releases it on stop',
      (tester) async {
        final harness = await _startRecording(tester);
        final coordinator = harness.container.read(
          audioSessionCoordinatorProvider,
        );
        expect(coordinator.activeOwner, AudioOwner.analyzeRecorder);
        expect(harness.capture.startCalls, 1);

        harness.capture.emit(List<double>.filled(44100, 0.1));
        await tester.pump();
        await _stopRecording(tester, harness);

        expect(coordinator.activeOwner, isNull);
        expect(harness.capture.stopCalls, 1);
      },
    );

    testWidgets(
      'a finished run reaches the V2 runner with the captured PCM and a '
      'freePlay seed, and the Processing Stage shows the live run',
      (tester) async {
        final harness = await _startRecording(tester);
        harness.capture.emit(List<double>.filled(44100, 0.1));
        await tester.pump();
        await _stopRecording(tester, harness);

        final request = harness.runner.requests.single;
        // The pre-E17-R02 use case sent an EMPTY placeholder; the flow now
        // hands the real capture (one second at the fake's 44.1 kHz) over.
        expect(request.audio.input.samples.length, 44100);
        expect(request.audio.input.sampleRate, 44100);
        expect(request.audio.input.source, AnalysisInputSource.microphone);
        expect(request.seed.mode, AnalysisMode.freePlay);
        expect(request.seed.signalQuality.measured, isFalse);
        expect(
          harness.container.read(analysisControllerProvider),
          isA<AnalysisAnalyzing>(),
        );
        expect(
          find.byKey(const Key('analysis-processing-starting-bar')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a completed run is saved, opens the overview with the document, and '
      'lists in recent analyses on the way back',
      (tester) async {
        final harness = await _startRecording(tester);
        harness.capture.emit(List<double>.filled(44100, 0.1));
        await tester.pump();
        await _stopRecording(tester, harness);

        final document = _document(id: 'wired-document');
        harness.runner.handles.single.complete(
          AnalysisRunResult(
            completion: AnalysisCompletionStatus.complete,
            document: document,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('analysis-processing-completed-title')),
          findsOneWidget,
        );
        final saved = harness.repository.saved.single;
        expect(saved.document.id, 'wired-document');
        expect(saved.title, 'C · G');
        expect(saved.customTitle, isFalse);

        await tester.tap(
          find.byKey(const Key('analysis-processing-view-result')),
        );
        await tester.pumpAndSettle();
        expect(harness.router.state.uri.path, AppRoutes.analysisOverview);
        expect(find.byType(AnalysisOverviewScreen), findsOneWidget);

        harness.router.go(AppRoutes.analysisHome);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('analysis-home-recent-wired-document')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a too-short capture never starts a run and the Processing Stage '
      'shows the typed input error with "Start again"',
      (tester) async {
        final harness = await _startRecording(tester);
        // 100 samples at 44.1 kHz is far below the 250 ms input minimum.
        harness.capture.emit(List<double>.filled(100, 0.1));
        await tester.pump();
        await _stopRecording(tester, harness);

        expect(harness.runner.requests, isEmpty);
        expect(
          harness.container.read(analysisControllerProvider),
          isA<AnalysisInputError>(),
        );
        expect(
          find.byKey(const Key('analysis-processing-input-error')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('analysis-processing-restart')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a microphone already held by Live is a controlled busy failure, not '
      'a second capture',
      (tester) async {
        final harness = await _pumpRouter(tester);
        final coordinator = harness.container.read(
          audioSessionCoordinatorProvider,
        );
        final live = fakeMicCapture(
          owner: AudioOwner.live,
          coordinator: coordinator,
        );
        expect(await live.start((_) {}), isA<Success<int>>());

        harness.router.go(AppRoutes.analysisRecording);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('analysis-recording-start')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('analysis-recording-error-title')),
          findsOneWidget,
        );
        expect(coordinator.activeOwner, AudioOwner.live);
        expect(harness.capture.startCalls, 0);
        await live.stop();
      },
    );

    testWidgets('cancelling the Recording Stage pops back to home', (
      tester,
    ) async {
      final harness = await _startRecording(tester);

      await tester.tap(find.byKey(const Key('analysis-recording-cancel')));
      await tester.pumpAndSettle();

      expect(harness.router.state.uri.path, AppRoutes.analysisHome);
      expect(find.byType(AnalysisHomeScreen), findsOneWidget);
      expect(
        harness.container.read(audioSessionCoordinatorProvider).activeOwner,
        isNull,
      );
    });
  });

  group('E17-R02 — the Practice Area Hub entry point', () {
    testWidgets('appears only while audioAnalysisV2Enabled is on', (
      tester,
    ) async {
      await _pumpHub(tester, audioAnalysisV2Enabled: false);
      expect(find.byKey(_entryKey), findsNothing);

      await _pumpHub(tester, audioAnalysisV2Enabled: true);
      expect(find.byKey(_entryKey), findsOneWidget);
    });

    testWidgets('pushes the V2 analysis home', (tester) async {
      final router = await _pumpHub(tester, audioAnalysisV2Enabled: true);

      await tester.tap(find.byKey(_entryKey));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, AppRoutes.analysisHome);
    });
  });
}

// --- Hub harness (mirrors test/features/practice_hub/*_test.dart) ---------

Future<GoRouter> _pumpHub(
  WidgetTester tester, {
  required bool audioAnalysisV2Enabled,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.practiceHub,
    routes: [
      GoRoute(
        path: AppRoutes.practiceHub,
        builder: (_, _) => const PracticeAreaHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.analysisHome,
        builder: (_, _) => const SizedBox.shrink(),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          _config(audioAnalysisV2Enabled: audioAnalysisV2Enabled),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

// --- Fakes -----------------------------------------------------------------

/// An [AnalysisRunner] that records every request and lets the test finish
/// each run by hand — no isolate, no DSP.
final class _ScriptedRunner implements AnalysisRunner {
  final List<AnalysisRunRequest> requests = <AnalysisRunRequest>[];
  final List<_ScriptedHandle> handles = <_ScriptedHandle>[];

  @override
  AnalysisRunHandle start(AnalysisRunRequest input) {
    requests.add(input);
    final handle = _ScriptedHandle('scripted-run-${handles.length + 1}');
    handles.add(handle);
    return handle;
  }
}

final class _ScriptedHandle implements AnalysisRunHandle {
  _ScriptedHandle(this.runId);

  @override
  final String runId;
  final StreamController<AnalysisProgressEvent> _progress =
      StreamController<AnalysisProgressEvent>.broadcast();
  final Completer<AnalysisRunResult> _result = Completer<AnalysisRunResult>();

  @override
  Stream<AnalysisProgressEvent> get progress => _progress.stream;

  @override
  Future<AnalysisRunResult> get result => _result.future;

  @override
  Future<void> cancel() async {
    if (_result.isCompleted) return;
    await _progress.close();
    _result.complete(
      const AnalysisRunResult(completion: AnalysisCompletionStatus.cancelled),
    );
  }

  void complete(AnalysisRunResult result) {
    _result.complete(result);
    unawaited(_progress.close());
  }
}

final class _InMemoryAnalysisRepository implements AnalysisRepository {
  final List<AnalysisSaveRequest> saved = <AnalysisSaveRequest>[];

  @override
  Future<AppResult<List<AnalysisSummary>>> list() async =>
      Success<List<AnalysisSummary>>(<AnalysisSummary>[
        for (final request in saved.reversed)
          AnalysisSummary(
            documentId: request.document.id,
            title: request.title,
            customTitle: request.customTitle,
            createdAt: request.document.createdAt,
            completionStatus: request.document.completion.status.name,
            documentHash: 'a' * 64,
            sizeBytes: 1,
          ),
      ]);

  @override
  Future<AppResult<AnalysisDocument>> getById(String id) async {
    for (final request in saved) {
      if (request.document.id == id) {
        return Success<AnalysisDocument>(request.document);
      }
    }
    return const Failure<AnalysisDocument>(
      StorageFailure(code: AnalysisRepositoryErrorCode.notFound),
    );
  }

  @override
  Future<AppResult<void>> save(AnalysisSaveRequest request) async {
    saved.add(request);
    return const Success<void>(null);
  }

  @override
  Future<AppResult<void>> replace(String id, AnalysisSaveRequest request) =>
      throw UnimplementedError();

  @override
  Future<AppResult<void>> rename({
    required String id,
    required String newTitle,
  }) => throw UnimplementedError();

  @override
  Future<AppResult<void>> delete(String id) => throw UnimplementedError();
}

/// A minimal, renderable completed document (the overview-screen fixture
/// shape) with two chords so the auto-title has something to say.
AnalysisDocument _document({required String id}) => AnalysisDocument(
  id: id,
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 9, 15),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(seconds: 1),
    sampleRate: 44100,
    channelCount: 1,
    fingerprint: 'fp-$id',
  ),
  provenance: AnalysisProvenance(
    appVersion: 'test',
    analyzerVersion: 'test',
    pipelineVersion: 'test',
    stageVersions: const <String, String>{},
    dspConfigHash: 'test',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fp-$id',
    platform: 'test',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: .9,
    peakDbfs: -3,
    rmsDbfs: -20,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: .9,
  ),
  capabilities: const <CapabilityReport>[],
  timeline: AnalysisTimeline(
    duration: const Duration(seconds: 1),
    chordSegments: <ChordSegment>[
      ChordSegment(
        id: 'chord-c',
        start: Duration.zero,
        end: const Duration(milliseconds: 500),
        confidence: .9,
        label: 'C',
      ),
      ChordSegment(
        id: 'chord-g',
        start: const Duration(milliseconds: 500),
        end: const Duration(seconds: 1),
        confidence: .9,
        label: 'G',
      ),
    ],
  ),
  metrics: const <AnalysisMetricResult>[],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);
