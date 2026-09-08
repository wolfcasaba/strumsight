// R30 (re-audit #2 §1/B2) — the Audio Analysis V2 capture chain's WAY BACK,
// measured through the REAL router.
//
// Before this round every step of `/analysis/capture → record → processing →
// overview → metric-detail` was a `context.go` between top-level routes, so
// each arriving screen REPLACED the whole stack: `canPop == false`, nothing
// on the bare app bars, and the metric detail's only control (its empty
// state's "Close") was a `maybePop` with nothing to pop — a silent no-op.
// The user recorded an analysis, read the result, and could only leave by
// leaving the app.
//
// The fix is a NAVIGATION VERB change only — no app bar is touched. That is
// exactly why the pixel goldens are unmoved: they pump these screens as a
// `home:`, where there is nothing to pop and Material therefore implies no
// leading. The back arrows tapped below are that same implied leading, on a
// page that really is pushed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_isolate_runner.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_providers.dart';
import 'package:strumsight/features/audio_analysis/data/capture/recording_run.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_summary.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_metric_detail_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_overview_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_home_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_processing_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_recording_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/controllers/overview_view_model.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../../fixtures/analysis/insights/insight_fixtures.dart';
import '../../../../support/fake_audio.dart';
import '../../../../support/fake_engines.dart';
import '../../../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

/// The shipped development shell with Audio Analysis V2 on — the only build
/// in which the capture routes exist at all.
const _testConfig = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    adaptiveShellEnabled: true,
    audioAnalysisV2Enabled: true,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Future<List<AnalysisSummary>> _noAnalyses(Ref ref) async =>
    const <AnalysisSummary>[];

Future<GoRouter> _openAnalysisHome(WidgetTester tester) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(wakelock: FakeScreenWakelock()),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      analysisRecentSummariesProvider.overrideWith(_noAnalyses),
      // The run never completes: these cells measure the WAY BACK, and a
      // completed run would drag the persistence path — a separate
      // subject — into every one of them.
      analysisV2RunnerProvider.overrideWithValue(_PendingRunner()),
      appConfigProvider.overrideWithValue(_testConfig),
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
      child: MaterialApp.router(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.go(AppRoutes.analysisCapture);
  await tester.pumpAndSettle();
  expect(find.byType(AnalysisHomeScreen), findsOneWidget);
  return router;
}

/// The app bar's implied back arrow on [screen]'s own frame.
Finder _backArrowOf(Type screen) => find.descendant(
  of: find.byType(screen),
  matching: find.byType(BackButton),
);

/// Opens the recording step from the analysis home.
Future<void> _tapRecord(WidgetTester tester) async {
  final target = find.byKey(const Key('analysis-home-record'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Deliberately NOT `pumpAndSettle`: a started run renders an indeterminate
/// `LinearProgressIndicator` whose animation never settles.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Drives the chain up to the processing step the way the router does: the
/// recording screen hands back a finished run, and the route starts the
/// (pending) analysis and navigates.
///
/// The run metadata is fabricated rather than recorded: this file measures
/// NAVIGATION, and a real capture would need the microphone stream to
/// produce the very same two values by a much longer route.
Future<void> _finishRecording(WidgetTester tester) async {
  final recording = tester.widget<AnalysisRecordingScreen>(
    find.byType(AnalysisRecordingScreen),
  );
  recording.onFinished(_run(), List<double>.filled(4800, 0));
  await _pumpFrames(tester);
}

RecordingRun _run() => RecordingRun(
  id: 'run-exit-chain',
  startedAt: DateTime.utc(2026, 9, 8),
  sampleRate: 48000,
  status: RecordingRunStatus.completed,
  sampleCount: 4800,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('the recording step is PUSHED over the analysis home, and its '
      'back arrow returns there', (tester) async {
    final router = await _openAnalysisHome(tester);

    await _tapRecord(tester);

    expect(find.byType(AnalysisRecordingScreen), findsOneWidget);
    expect(router.canPop(), isTrue);

    final back = _backArrowOf(AnalysisRecordingScreen);
    expect(
      back,
      findsOneWidget,
      reason:
          'a `go` left this bare app bar with no leading at all — Material '
          'implies one only once there is a route below',
    );
    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(find.byType(AnalysisRecordingScreen), findsNothing);
    expect(find.byType(AnalysisHomeScreen), findsOneWidget);
  });

  testWidgets('the processing step is PUSHED over the recording step, and '
      'its back arrow returns there', (tester) async {
    final router = await _openAnalysisHome(tester);
    await _tapRecord(tester);

    await _finishRecording(tester);

    expect(find.byType(AnalysisProcessingScreen), findsOneWidget);
    expect(router.canPop(), isTrue);

    await tester.tap(_backArrowOf(AnalysisProcessingScreen));
    await _pumpFrames(tester);

    expect(find.byType(AnalysisRecordingScreen), findsOneWidget);
  });

  testWidgets('R26 preserved — "start over" still lands on the step this run '
      'started from, now by popping instead of replacing the stack', (
    tester,
  ) async {
    await _openAnalysisHome(tester);
    await _tapRecord(tester);
    await _finishRecording(tester);

    final processing = tester.widget<AnalysisProcessingScreen>(
      find.byType(AnalysisProcessingScreen),
    );
    // The restart control only renders in the cancelled/permission/error
    // bodies; the callback itself is the router code under test here.
    processing.onRestart!();
    await _pumpFrames(tester);

    expect(find.byType(AnalysisRecordingScreen), findsOneWidget);
    expect(find.byType(AnalysisProcessingScreen), findsNothing);
  });

  testWidgets('the RESULT can be left by tapping: overview -> details and '
      'all the way back to the analysis home', (tester) async {
    final router = await _openAnalysisHome(tester);
    await _tapRecord(tester);
    await _finishRecording(tester);

    final processing = tester.widget<AnalysisProcessingScreen>(
      find.byType(AnalysisProcessingScreen),
    );
    processing.onViewResult!(buildInsightDocument());
    await _pumpFrames(tester);

    expect(find.byType(AnalysisOverviewScreen), findsOneWidget);
    expect(router.canPop(), isTrue);

    // The app bar's own "see all insights" action — always on screen, unlike
    // the button at the end of the scroll.
    await tester.tap(find.byTooltip(l10n.analysisOverviewSeeAllInsights));
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisMetricDetailScreen), findsOneWidget);

    await tester.tap(_backArrowOf(AnalysisMetricDetailScreen));
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisOverviewScreen), findsOneWidget);

    await tester.tap(_backArrowOf(AnalysisOverviewScreen));
    await _pumpFrames(tester);
    expect(find.byType(AnalysisProcessingScreen), findsOneWidget);

    await tester.tap(_backArrowOf(AnalysisProcessingScreen));
    await _pumpFrames(tester);
    expect(find.byType(AnalysisRecordingScreen), findsOneWidget);

    await tester.tap(_backArrowOf(AnalysisRecordingScreen));
    await tester.pumpAndSettle();
    expect(
      find.byType(AnalysisHomeScreen),
      findsOneWidget,
      reason:
          'every step of the chain must lead back to the analysis home — '
          'this walk is the one the shipped APK could not make at all',
    );
  });

  testWidgets('the metric detail\'s empty-state "Close" is a real exit, not '
      'a silent no-op', (tester) async {
    final router = await _openAnalysisHome(tester);
    await _tapRecord(tester);
    await _finishRecording(tester);
    final processing = tester.widget<AnalysisProcessingScreen>(
      find.byType(AnalysisProcessingScreen),
    );
    processing.onViewResult!(buildInsightDocument());
    await _pumpFrames(tester);

    // A document whose published metric list is empty is the ONE way to
    // reach that empty state — the payload shape the route accepts.
    router.push(
      AppRoutes.analysisMetricDetail,
      extra: const <OverviewMetricCard>[],
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('analysis-metric-detail-empty')),
      findsOneWidget,
    );

    await tester.tap(find.text(l10n.commonClose));
    await tester.pumpAndSettle();

    expect(
      find.byType(AnalysisOverviewScreen),
      findsOneWidget,
      reason:
          'the only control on that state used to be a `maybePop` on a '
          'stack the `go` chain had already thrown away',
    );
  });
}

/// A runner whose run never finishes.
final class _PendingRunner implements AnalysisRunner {
  @override
  AnalysisRunHandle start(AnalysisRunRequest input) => _PendingRun();
}

final class _PendingRun implements AnalysisRunHandle {
  final _progress = StreamController<AnalysisProgressEvent>.broadcast();

  @override
  String get runId => 'pending-run';

  @override
  Stream<AnalysisProgressEvent> get progress => _progress.stream;

  @override
  Future<AnalysisRunResult> get result => Completer<AnalysisRunResult>().future;

  @override
  Future<void> cancel() async {
    await _progress.close();
  }
}
