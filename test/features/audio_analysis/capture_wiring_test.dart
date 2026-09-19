// E17-R02 — the missing machine guard over the Analysis V2 capture-flow
// wiring (ADR 0584).
//
// The three capture screens (AnalysisHomeScreen -> AnalysisRecordingScreen
// -> AnalysisProcessingScreen) were wired into `app_router.dart` outside
// the SDD pipeline (`050e45028`, 2026-09-05): no brief, no review, no ADR,
// and — critically — no test in the whole `test/` tree referenced the
// three route constants. This file is that guard (A1-A4, A6); A5/A7 are
// verified by `git diff` in the round's closing report, not by a cell.
//
// A2/A6 assert the type of the widget the router actually renders, not
// just `router.state.uri.path` (L654): a `go()` call can move the URI
// while the user stays stuck on the previous screen.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart'
    show AudioOwner;
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_home_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_processing_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_recording_screen.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

/// Pumps in small, bounded steps until [condition] holds, instead of
/// `pumpAndSettle` — the Processing screen's indeterminate-progress body
/// runs a repeating animation once `AnalysisAnalyzing` lands, which would
/// never let a settle-based pump return.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxSteps = 30,
}) async {
  for (var i = 0; i < maxSteps && !condition(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

/// A minimal, fully-controlled [AnalysisRepository]. A2 only needs `list()`
/// (the home screen's "recent" section); A6 additionally scripts
/// `getById()`. Every other method throws — the composition under test
/// never calls them.
final class _FakeAnalysisRepository implements AnalysisRepository {
  _FakeAnalysisRepository({
    this.summaries = const <AnalysisSummary>[],
    this.getByIdResult,
  });

  final List<AnalysisSummary> summaries;
  final AppResult<AnalysisDocument>? getByIdResult;

  int getByIdCalls = 0;

  @override
  Future<AppResult<List<AnalysisSummary>>> list() async => Success(summaries);

  @override
  Future<AppResult<AnalysisDocument>> getById(String id) async {
    getByIdCalls++;
    final result = getByIdResult;
    if (result == null) throw UnimplementedError();
    return result;
  }

  @override
  Future<AppResult<void>> save(AnalysisSaveRequest request) =>
      throw UnimplementedError();

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

AnalysisSummary _summary(String id) => AnalysisSummary(
  documentId: id,
  title: 'Session $id',
  customTitle: false,
  createdAt: DateTime.utc(2026, 8, 12),
  completionStatus: 'complete',
  documentHash: 'hash-$id',
  sizeBytes: 1024,
);

AnalysisDocument _document(String id) => AnalysisDocument(
  id: id,
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 8, 12),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(minutes: 1),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'fp-$id',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1.0.0',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{},
    dspConfigHash: 'cfg',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fp-$id',
    platform: 'android',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: 0,
    peakDbfs: -3,
    rmsDbfs: -18,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: 0,
  ),
  capabilities: const <CapabilityReport>[],
  timeline: AnalysisTimeline(duration: const Duration(minutes: 1)),
  metrics: const [],
  hotspots: const [],
  insights: const [],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);

class _RouterTestApp extends ConsumerWidget {
  const _RouterTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _CaptureHarness {
  const _CaptureHarness({required this.container, required this.router});

  final ProviderContainer container;
  final GoRouter router;
}

/// Pumps the REAL app composition (`routerProvider`) with the flag on.
/// Overrides land ONLY on the mic seam (`fakeAudioOverrides`) and the
/// repository seam (brief §0.0/A2) — `analysisControllerProvider`,
/// `analysisCaptureRecorderProvider` and every `GoRoute` builder in
/// `app_router.dart` are the real, shipped composition.
Future<_CaptureHarness> _pumpCaptureRouter(
  WidgetTester tester, {
  required AnalysisRepository repository,
}) async {
  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      analysisRepositoryProvider.overrideWithValue(repository),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: true,
            labModeAvailable: true,
            audioAnalysisV2Enabled: true,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  final router = container.read(routerProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await liveEngine.dispose();
    await tunerEngine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _RouterTestApp(),
    ),
  );
  await tester.pumpAndSettle();
  router.go(AppRoutes.analysisCapture);
  await tester.pumpAndSettle();
  return _CaptureHarness(container: container, router: router);
}

void main() {
  group(
    'A1/A3 — the three capture routes live only behind audioAnalysisV2Enabled',
    () {
      GoRouter buildRouter({required bool audioAnalysisV2Enabled}) {
        final container = ProviderContainer(
          overrides: [
            appConfigProvider.overrideWithValue(
              AppConfig(
                environment: AppEnvironment.development,
                apiBaseUrl: AppConfig.devApiBaseUrl,
                flags: FeatureFlags(
                  accountEnabled: false,
                  diagnosticsEnabled: false,
                  labModeAvailable: false,
                  audioAnalysisV2Enabled: audioAnalysisV2Enabled,
                ),
                diagnosticsToken: AppConfig.devDiagnosticsToken,
                buildMode: 'test',
                appVersion: 'test',
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        // Route registration is data assembled once at construction time
        // (`if (audioAnalysisV2Enabled) [...]` in app_router.dart); resolving
        // it here never builds a screen (analysis_overview_screen_test.dart
        // "flag-gated route (F2)" pattern).
        return container.read(routerProvider);
      }

      test('A1 — flag on: all three capture routes resolve', () {
        final router = buildRouter(audioAnalysisV2Enabled: true);
        for (final path in <String>[
          AppRoutes.analysisCapture,
          AppRoutes.analysisRecord,
          AppRoutes.analysisProcessing,
        ]) {
          final match = router.configuration.findMatch(Uri.parse(path));
          expect(match.isError, isFalse, reason: path);
        }
      });

      test('A3 — flag off: all three capture routes are unregistered, and the '
          'legacy /analyze route is unaffected', () {
        final router = buildRouter(audioAnalysisV2Enabled: false);
        for (final path in <String>[
          AppRoutes.analysisCapture,
          AppRoutes.analysisRecord,
          AppRoutes.analysisProcessing,
        ]) {
          final match = router.configuration.findMatch(Uri.parse(path));
          expect(match.isError, isTrue, reason: path);
        }
        final analyzeMatch = router.configuration.findMatch(
          Uri.parse(AppRoutes.analyze),
        );
        expect(analyzeMatch.isError, isFalse);
      });
    },
  );

  group('A4 — the capture widgets stay pure presentation', () {
    test('AnalysisHomeScreen / AnalysisRecordingScreen / '
        'AnalysisProcessingScreen read zero Riverpod providers directly '
        '(ADR 0584 §5.2/§3 — the composition root injects dependencies)', () {
      final files = <String>[
        'lib/features/audio_analysis/presentation/capture/analysis_home_screen.dart',
        'lib/features/audio_analysis/presentation/capture/analysis_recording_screen.dart',
        'lib/features/audio_analysis/presentation/capture/analysis_processing_screen.dart',
      ];
      final riverpodUsage = RegExp(r'ref\.watch|ref\.read|ConsumerWidget');
      for (final file in files) {
        final contents = File(file).readAsStringSync();
        expect(
          riverpodUsage.hasMatch(contents),
          isFalse,
          reason: '$file must stay a pure presentation widget',
        );
      }
    });

    test('the three widgets keep their injected constructor contract', () {
      // Compiles only while every required parameter below still exists —
      // a narrowed/renamed constructor is the regression this cell catches
      // (the widgets are never rendered here; A2 already covers that).
      AnalysisHomeScreen(
        recentAnalyses: const <AnalysisSummary>[],
        onStartRecording: () {},
        onImportFile: () {},
        onOpenAnalysis: (_) {},
      );
      AnalysisRecordingScreen(
        recorder: AnalysisRecorder(
          mic: fakeMicCapture(owner: AudioOwner.analyzeRecorder),
        ),
        onFinished: (_, _) {},
        onCancel: () {},
      );
      AnalysisProcessingScreen(
        state: const AnalysisIdle(),
        onCancel: () {},
        onRestart: () {},
        onViewResult: (_) {},
      );
    });
  });

  group('A2 — home to recording to processing, real providers', () {
    testWidgets(
      'tapping record then stop drives the REAL AnalysisController into '
      'Analyzing, and the Processing screen renders exactly that state',
      (tester) async {
        final repository = _FakeAnalysisRepository();
        final harness = await _pumpCaptureRouter(
          tester,
          repository: repository,
        );

        expect(harness.router.state.uri.path, AppRoutes.analysisCapture);
        expect(find.byType(AnalysisHomeScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('analysis-home-record')));
        await tester.pumpAndSettle();
        expect(harness.router.state.uri.path, AppRoutes.analysisRecord);
        expect(find.byType(AnalysisRecordingScreen), findsOneWidget);

        await tester.tap(find.byKey(const Key('analysis-recording-start')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('analysis-recording-stop')),
          findsOneWidget,
        );

        // NOT pumpAndSettle from here: the Processing screen's
        // indeterminate-progress body runs an infinitely-repeating
        // animation, which would time out a settle-based pump.
        await tester.tap(find.byKey(const Key('analysis-recording-stop')));
        await _pumpUntil(
          tester,
          () =>
              harness.container.read(analysisControllerProvider)
                  is AnalysisAnalyzing &&
              find.byType(AnalysisProcessingScreen).evaluate().isNotEmpty,
        );

        expect(harness.router.state.uri.path, AppRoutes.analysisProcessing);
        expect(find.byType(AnalysisProcessingScreen), findsOneWidget);
        expect(
          harness.container.read(analysisControllerProvider),
          isA<AnalysisAnalyzing>(),
        );

        // Cancel the real run before teardown disposes the container — the
        // controller's own `analyze()` already kicked off the real V2
        // isolate pipeline (ADR 0254); cancel() releases it deterministically
        // instead of leaving that to container disposal.
        await harness.container
            .read(analysisControllerProvider.notifier)
            .cancel();
        await tester.pump();
        expect(
          harness.container.read(analysisControllerProvider),
          isA<AnalysisCancelled>(),
        );

        // MAJOR-1 (review): a `ref.watch` -> `ref.read` regression in the
        // processing route builder leaves the widget tree on whatever it
        // last built (the Analyzing body) even after the controller flips
        // to `AnalysisCancelled` — a plain `find.byType(AnalysisProcessingScreen)`
        // check would stay green through that regression because the
        // STATEFUL widget instance never gets swapped out. Asserting the
        // Cancelled body's own content is in, and the Analyzing body's is
        // out, is what turns red.
        expect(
          find.byKey(const Key('analysis-processing-cancelled-title')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('analysis-processing-restart')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('analysis-processing-step')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('A6 — opening a stored analysis loads the AnalysisDocument, not the '
      'AnalysisSummary', () {
    testWidgets(
      'tapping a recent analysis opens AnalysisTimelineScreen with the '
      'loaded document (not the Live fail-closed route)',
      (tester) async {
        final document = _document('doc-1');
        final summary = _summary('doc-1');
        final repository = _FakeAnalysisRepository(
          summaries: [summary],
          getByIdResult: Success(document),
        );
        final harness = await _pumpCaptureRouter(
          tester,
          repository: repository,
        );

        expect(find.byType(AnalysisHomeScreen), findsOneWidget);
        expect(
          find.byKey(const Key('analysis-home-recent-doc-1')),
          findsOneWidget,
        );

        await tester.tap(find.text(summary.title));
        await tester.pumpAndSettle();

        expect(harness.router.state.uri.path, AppRoutes.analysisTimeline);
        expect(find.byType(AnalysisTimelineScreen), findsOneWidget);
        expect(find.byType(LiveScreen), findsNothing);
        expect(repository.getByIdCalls, 1);
      },
    );

    testWidgets(
      'a load failure keeps the EXISTING fail-closed route to Live — no '
      'new user-facing message',
      (tester) async {
        final summary = _summary('doc-missing');
        final repository = _FakeAnalysisRepository(
          summaries: [summary],
          getByIdResult: const Failure(UnknownFailure()),
        );
        final harness = await _pumpCaptureRouter(
          tester,
          repository: repository,
        );

        await tester.tap(find.text(summary.title));
        await tester.pumpAndSettle();

        expect(harness.router.state.uri.path, AppRoutes.live);
        expect(find.byType(LiveScreen), findsOneWidget);
        expect(find.byType(AnalysisTimelineScreen), findsNothing);
        expect(repository.getByIdCalls, 1);
      },
    );
  });
}
