// R34 (audit M11) — the analysis COMPARISON has an entry point, measured
// through the REAL router.
//
// Measured before this round: `CompareAnalysesUseCase` is the only producer
// of an `AnalysisComparison` and had ZERO `lib/` callers, while
// `analysisComparisonEnabled` was ON in the shipped development build. The
// use case, the compatibility evaluator, the screen and its ARB copy were
// all finished; `/analysis/compare` had never been navigated to, so the
// route's own redirect ("no `AnalysisComparison` extra → `/live`") was the
// only thing a deep link could ever reach.
//
// The cells below drive the shipped route tree with a fake repository (no
// filesystem, no `path_provider`) and measure what a user can experience:
// the action appears only where a comparison is possible, the two chosen
// SAVED DOCUMENTS are read back and compared, and a failed read is named
// without navigating anywhere.
library;

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
import 'package:strumsight/features/audio_analysis/presentation/analysis_compare_screen.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_compare_picker.dart';
import 'package:strumsight/features/audio_analysis/presentation/capture/analysis_home_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../fixtures/analysis/insights/insight_fixtures.dart';
import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

/// The shipped development shell: Audio Analysis V2 on (the capture routes
/// exist at all) and the comparison flag on (the compare route is
/// registered). [comparison] is the dimension the "flag off" cell moves.
AppConfig _config({required bool comparison}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    adaptiveShellEnabled: true,
    audioAnalysisV2Enabled: true,
    analysisComparisonEnabled: comparison,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

/// An index row. A summary carries metadata only — no metric is in here,
/// which is exactly why the comparison has to read both documents back.
AnalysisSummary _summary(String id, {required int day}) => AnalysisSummary(
  documentId: id,
  title: 'C · G',
  customTitle: false,
  createdAt: DateTime.utc(2026, 9, day),
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
  Map<String, AnalysisDocument> documents = const <String, AnalysisDocument>{},
  bool comparison = true,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final repository = _FakeAnalysisRepository(
    summaries: summaries,
    documents: documents,
  );
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(wakelock: FakeScreenWakelock()),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      // Deliberately NOT overriding `analysisRecentSummariesProvider`: the
      // list the user picks from must come from the same repository the
      // compare path reads back from, or the cells would prove nothing
      // about the ids that actually travel.
      analysisRepositoryProvider.overrideWithValue(repository),
      appConfigProvider.overrideWithValue(_config(comparison: comparison)),
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

/// Opens the picker, selects [ids] and confirms.
///
/// Deliberately NOT `pumpAndSettle` after the confirm: the progress
/// snackbar runs its own entrance/exit animation, and fixed pumps end where
/// a real user's first glance ends.
Future<void> _compare(WidgetTester tester, List<String> ids) async {
  await tester.tap(find.byKey(const Key('analysis-home-compare')));
  await tester.pumpAndSettle();
  for (final id in ids) {
    final tile = find.byKey(Key('analysis-compare-pick-$id'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
  }
  await tester.tap(find.byKey(const Key('analysis-compare-confirm')));
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('picking two saved analyses LOADS both documents and opens the '
      'comparison on top of the analysis home', (tester) async {
    final before = buildInsightDocument(
      metrics: buildInsightMetrics(targetMean: 40),
    );
    final after = buildInsightDocument(
      metrics: buildInsightMetrics(targetMean: 20),
    );
    final rig = await _openAnalysisHome(
      tester,
      summaries: <AnalysisSummary>[
        _summary('older', day: 1),
        _summary('newer', day: 2),
      ],
      documents: <String, AnalysisDocument>{
        'older': before,
        'newer': after,
      },
    );

    await _compare(tester, <String>['older', 'newer']);

    expect(
      rig.repository.requestedIds..sort(),
      <String>['newer', 'older'],
      reason: 'both chosen summaries are read back as full documents',
    );
    final screen = tester.widget<AnalysisCompareScreen>(
      find.byType(AnalysisCompareScreen),
    );
    expect(
      screen.comparison.metrics,
      isNotEmpty,
      reason:
          'the comparison is the use case\'s output over the two LOADED '
          'documents — a summary carries no metric at all',
    );
    expect(rig.router.state.uri.path, AppRoutes.analysisCompare);

    // `push`, not `go`: the comparison sits ON TOP of the analysis home.
    expect(rig.router.canPop(), isTrue);
    rig.router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisCompareScreen), findsNothing);
    expect(find.byType(AnalysisHomeScreen), findsOneWidget);
  });

  testWidgets('the OLDER capture is the "before" side, whatever order the '
      'user tapped', (tester) async {
    final rig = await _openAnalysisHome(
      tester,
      summaries: <AnalysisSummary>[
        _summary('older', day: 1),
        _summary('newer', day: 2),
      ],
      documents: <String, AnalysisDocument>{
        'older': buildInsightDocument(),
        'newer': buildInsightDocument(),
      },
    );

    // Newest tapped FIRST — tap order must not decide which side is
    // "before", or the screen could render an improvement that ran
    // backwards.
    await _compare(tester, <String>['newer', 'older']);

    expect(
      rig.repository.requestedIds,
      <String>['older', 'newer'],
      reason: 'the older document is fetched as the before side first',
    );
  });

  testWidgets('an analysis that cannot be read is NAMED, and the user stays '
      'on the analysis home', (tester) async {
    final rig = await _openAnalysisHome(
      tester,
      summaries: <AnalysisSummary>[
        _summary('older', day: 1),
        _summary('vanished', day: 2),
      ],
      documents: <String, AnalysisDocument>{'older': buildInsightDocument()},
    );

    await _compare(tester, <String>['older', 'vanished']);

    expect(find.text(l10n.analysisCompareLoadFailed), findsOneWidget);
    expect(find.byType(AnalysisCompareScreen), findsNothing);
    expect(find.byType(AnalysisHomeScreen), findsOneWidget);
    expect(
      rig.router.state.uri.path,
      AppRoutes.analysisCapture,
      reason:
          'a miss must not navigate — the compare route redirects a missing '
          'extra to /live, which is the wrong page dressed up as a link',
    );
  });

  testWidgets('a single saved analysis offers NO compare action — there is '
      'nothing to compare it against', (tester) async {
    await _openAnalysisHome(
      tester,
      summaries: <AnalysisSummary>[_summary('only', day: 1)],
      documents: <String, AnalysisDocument>{'only': buildInsightDocument()},
    );

    expect(find.byKey(const Key('analysis-home-compare')), findsNothing);
  });

  testWidgets('with the comparison flag OFF the action is absent — the '
      'compare route is not registered in that build', (tester) async {
    await _openAnalysisHome(
      tester,
      summaries: <AnalysisSummary>[
        _summary('older', day: 1),
        _summary('newer', day: 2),
      ],
      documents: <String, AnalysisDocument>{
        'older': buildInsightDocument(),
        'newer': buildInsightDocument(),
      },
      comparison: false,
    );

    expect(find.byKey(const Key('analysis-home-compare')), findsNothing);
  });

  testWidgets('the picker refuses a third selection instead of silently '
      'swapping one of the two', (tester) async {
    await _openAnalysisHome(
      tester,
      summaries: <AnalysisSummary>[
        _summary('a', day: 1),
        _summary('b', day: 2),
        _summary('c', day: 3),
      ],
      documents: <String, AnalysisDocument>{
        'a': buildInsightDocument(),
        'b': buildInsightDocument(),
        'c': buildInsightDocument(),
      },
    );

    await tester.tap(find.byKey(const Key('analysis-home-compare')));
    await tester.pumpAndSettle();
    for (final id in <String>['a', 'b', 'c']) {
      final tile = find.byKey(Key('analysis-compare-pick-$id'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pump();
    }

    final third = tester.widget<CheckboxListTile>(
      find.byKey(const Key('analysis-compare-pick-c')),
    );
    expect(
      third.value,
      isFalse,
      reason: 'the third tap is refused, so the confirmed pair is the '
          'one the user actually picked',
    );
    expect(find.byType(AnalysisComparePicker), findsOneWidget);
  });
}

/// An in-memory [AnalysisRepository]: `list()` answers with the index the
/// home screen renders, `getById` with the document behind it (or the typed
/// not-found failure `FileAnalysisRepository` returns for a missing file).
final class _FakeAnalysisRepository implements AnalysisRepository {
  _FakeAnalysisRepository({required this.summaries, required this.documents});

  final List<AnalysisSummary> summaries;
  final Map<String, AnalysisDocument> documents;
  final List<String> requestedIds = <String>[];

  @override
  Future<AppResult<List<AnalysisSummary>>> list() async => Success(summaries);

  @override
  Future<AppResult<AnalysisDocument>> getById(String id) async {
    requestedIds.add(id);
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
