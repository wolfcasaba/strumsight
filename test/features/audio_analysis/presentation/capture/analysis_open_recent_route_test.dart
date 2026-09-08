// R32 (re-audit #2) — the "recent analyses" list OPENS something, measured
// through the REAL router.
//
// Before this round the card handed an `AnalysisSummary` to
// `/analysis/timeline`, whose redirect accepts an `AnalysisDocument` and
// nothing else: every tap was redirected to `/live`. The list looked like a
// working history and had never opened a single analysis.
//
// The cells below drive the shipped route tree with a fake repository (no
// filesystem, no `path_provider`) and measure the two outcomes a user can
// experience: the saved document opens on the timeline, or the read fails
// and is NAMED without navigating anywhere.
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
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/application/analysis_providers.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_repository.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_summary.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_timeline_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_home_screen.dart';
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

/// The index row for [buildInsightDocument]'s document. A summary carries
/// metadata only — the timeline the screen needs is NOT in here, which is
/// the whole reason the route has to read the document back.
AnalysisSummary _summary(String id) => AnalysisSummary(
  documentId: id,
  title: 'C · G',
  customTitle: false,
  createdAt: DateTime.utc(2026, 9, 1),
  completionStatus: 'complete',
  documentHash: 'hash-$id',
  sizeBytes: 512,
);

final class _Rig {
  const _Rig(this.router, this.repository);

  final GoRouter router;
  final _FakeAnalysisRepository repository;
}

Future<_Rig> _openAnalysisHome(
  WidgetTester tester, {
  required List<AnalysisSummary> summaries,
  AnalysisDocument? document,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final repository = _FakeAnalysisRepository(
    summaries: summaries,
    documents: <String, AnalysisDocument>{?document?.id: ?document},
  );
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(wakelock: FakeScreenWakelock()),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      // `analysisRecentSummariesProvider` is deliberately NOT overridden:
      // the list the user taps must come from the same repository the open
      // path reads back from, or the cells would prove nothing about the
      // id that actually travels.
      analysisRepositoryProvider.overrideWithValue(repository),
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
  return _Rig(router, repository);
}

/// Taps one recent-analysis card and lets the repository read → navigation
/// hop finish.
///
/// Deliberately NOT `pumpAndSettle`: the progress snackbar runs its own
/// entrance/exit animation, and fixed pumps end where a real user's first
/// glance ends.
Future<void> _tapRecent(WidgetTester tester, String id) async {
  final target = find.byKey(Key('analysis-home-recent-$id'));
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('tapping a recent analysis LOADS its document and opens the '
      'timeline on top of the analysis home', (tester) async {
    final document = buildInsightDocument();
    final rig = await _openAnalysisHome(
      tester,
      summaries: <AnalysisSummary>[_summary(document.id)],
      document: document,
    );

    await _tapRecent(tester, document.id);

    expect(
      rig.repository.requestedIds,
      <String>[document.id],
      reason: 'the tapped summary\'s id is what the repository is asked for',
    );
    final timeline = tester.widget<AnalysisTimelineScreen>(
      find.byType(AnalysisTimelineScreen),
    );
    expect(
      timeline.document.id,
      document.id,
      reason:
          'the screen must receive the LOADED document — the summary alone '
          'carries no timeline at all',
    );
    expect(rig.router.state.uri.path, AppRoutes.analysisTimeline);

    // R30 push semantics survive: the timeline sits ON TOP of the home
    // screen, so the way back is the ordinary pop.
    expect(rig.router.canPop(), isTrue);
    rig.router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisTimelineScreen), findsNothing);
    expect(find.byType(AnalysisHomeScreen), findsOneWidget);
  });

  testWidgets('a saved analysis that cannot be read is NAMED, and the user '
      'stays on the analysis home — no /live bounce', (tester) async {
    final rig = await _openAnalysisHome(
      tester,
      summaries: <AnalysisSummary>[_summary('vanished-analysis')],
    );

    await _tapRecent(tester, 'vanished-analysis');

    expect(find.text(l10n.analysisHomeOpenFailed), findsOneWidget);
    expect(find.byType(AnalysisTimelineScreen), findsNothing);
    expect(find.byType(AnalysisHomeScreen), findsOneWidget);
    expect(
      rig.router.state.uri.path,
      AppRoutes.analysisCapture,
      reason:
          'the shipped build sent every tap to /live, because the timeline '
          'redirect rejected the summary it was handed',
    );
  });

  testWidgets('the read is SPOKEN while it runs', (tester) async {
    final document = buildInsightDocument();
    final rig = await _openAnalysisHome(
      tester,
      summaries: <AnalysisSummary>[_summary(document.id)],
      document: document,
    );
    rig.repository.hold = true;

    final target = find.byKey(Key('analysis-home-recent-${document.id}'));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(l10n.analysisHomeOpeningAnalysis), findsOneWidget);
    expect(find.byType(AnalysisTimelineScreen), findsNothing);

    rig.repository.release();
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AnalysisTimelineScreen), findsOneWidget);
  });
}

/// An in-memory [AnalysisRepository]: it answers `list()` with the index the
/// home screen renders and `getById` with the document behind it (or a typed
/// not-found failure, the shape `FileAnalysisRepository` returns for a
/// missing or quarantined file).
final class _FakeAnalysisRepository implements AnalysisRepository {
  _FakeAnalysisRepository({required this.summaries, required this.documents});

  final List<AnalysisSummary> summaries;
  final Map<String, AnalysisDocument> documents;
  final List<String> requestedIds = <String>[];

  /// When true, `getById` parks until [release] — the window in which the
  /// progress message must be on screen.
  bool hold = false;
  Completer<void>? _gate;

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<AppResult<List<AnalysisSummary>>> list() async => Success(summaries);

  @override
  Future<AppResult<AnalysisDocument>> getById(String id) async {
    requestedIds.add(id);
    if (hold) {
      final gate = _gate ??= Completer<void>();
      await gate.future;
    }
    final document = documents[id];
    if (document == null) {
      return const Failure<AnalysisDocument>(
        StorageFailure(
          code: AnalysisRepositoryErrorCode.notFound,
          retryable: false,
        ),
      );
    }
    return Success(document);
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
