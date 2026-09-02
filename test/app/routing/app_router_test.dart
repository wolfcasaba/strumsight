import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/audio_analysis/domain/comparison/analysis_comparison.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_metric_catalog.dart';
import 'package:strumsight/features/audio_analysis/presentation/analysis_compare_screen.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/auth/screens/login_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/achievement_detail_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/achievements_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/gamification_hub_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/quests_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/reward_inbox_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/streak_detail_screen.dart';
import 'package:strumsight/features/library/public.dart';
import 'package:strumsight/features/library/screens/library_screen.dart';
import 'package:strumsight/features/library/screens/session_detail_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/plan_setup_screen.dart';
import 'package:strumsight/features/practice_generator/presentation/screens/today_plan_screen.dart';
import 'package:strumsight/features/progress/screens/progress_screen.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_editor_screen.dart';
import 'package:strumsight/features/streak/screens/streak_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

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

class _RouterHarness {
  const _RouterHarness({
    required this.container,
    required this.router,
    required this.songRepository,
  });

  final ProviderContainer container;
  final GoRouter router;
  final InMemorySongRepository songRepository;
}

Future<_RouterHarness> _pumpRouter(
  WidgetTester tester, {
  required bool seen,
  bool accountEnabled = false,
  bool songTrainerEnabled = false,
  bool analysisComparisonEnabled = false,
  bool practiceGeneratorEnabled = false,
}) async {
  final engine = FakeStrumEngine();
  final songRepository = InMemorySongRepository();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(engine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(seen)),
      accountEnabledProvider.overrideWithValue(accountEnabled),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      songRepositoryProvider.overrideWithValue(songRepository),
      songAssetRepositoryProvider.overrideWithValue(
        const _RouterAssetRepository(),
      ),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: accountEnabled,
            diagnosticsEnabled: true,
            labModeAvailable: true,
            songTrainerV2Enabled: songTrainerEnabled,
            analysisComparisonEnabled: analysisComparisonEnabled,
            practiceGeneratorEnabled: practiceGeneratorEnabled,
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
    await engine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _RouterTestApp(),
    ),
  );
  await tester.pumpAndSettle();
  return _RouterHarness(
    container: container,
    router: router,
    songRepository: songRepository,
  );
}

void main() {
  testWidgets('first launch settles on welcome', (tester) async {
    final harness = await _pumpRouter(tester, seen: false);

    expect(harness.router.state.uri.path, AppRoutes.welcome);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('provider change leaves welcome without a context.go call', (
    tester,
  ) async {
    final harness = await _pumpRouter(tester, seen: false);
    expect(harness.router.state.uri.path, AppRoutes.welcome);

    await harness.container.read(onboardingSeenProvider.notifier).complete();
    await tester.pumpAndSettle();

    expect(harness.router.state.uri.path, AppRoutes.live);
    expect(find.byType(LiveScreen), findsOneWidget);
  });

  testWidgets('missing library session argument redirects to library', (
    tester,
  ) async {
    final harness = await _pumpRouter(tester, seen: true);

    harness.router.go(AppRoutes.librarySession);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(harness.router.state.uri.path, AppRoutes.library);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.byType(SessionDetailScreen), findsNothing);
  });

  testWidgets('valid library session argument opens its detail screen', (
    tester,
  ) async {
    final harness = await _pumpRouter(tester, seen: true);
    final session = AnalyzedSession(
      id: 'router-session',
      createdAt: DateTime.utc(2026, 7, 29),
      title: 'Router session',
      result: AnalyzeResult.empty,
    );

    harness.router.go(AppRoutes.librarySession, extra: session);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(harness.router.state.uri.path, AppRoutes.librarySession);
    final detail = tester.widget<SessionDetailScreen>(
      find.byType(SessionDetailScreen),
    );
    expect(detail.session, same(session));
  });

  testWidgets('unknown path is recovered to live', (tester) async {
    final harness = await _pumpRouter(tester, seen: true);

    harness.router.go('/nope');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(harness.router.state.uri.path, AppRoutes.live);
    expect(find.byType(LiveScreen), findsOneWidget);
  });

  testWidgets(
    'analysisComparisonEnabled OFF: the compare route is not reachable',
    (tester) async {
      final harness = await _pumpRouter(
        tester,
        seen: true,
        analysisComparisonEnabled: false,
      );

      harness.router.go(
        AppRoutes.analysisCompare,
        extra: AnalysisComparison(
          beforeAnalysisId: 'before',
          afterAnalysisId: 'after',
          metrics: const <MetricComparison>[],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.live);
      expect(find.byType(AnalysisCompareScreen), findsNothing);
    },
  );

  testWidgets(
    'analysisComparisonEnabled ON: a valid comparison opens the compare screen',
    (tester) async {
      final harness = await _pumpRouter(
        tester,
        seen: true,
        analysisComparisonEnabled: true,
      );

      harness.router.go(
        AppRoutes.analysisCompare,
        extra: AnalysisComparison(
          beforeAnalysisId: 'before',
          afterAnalysisId: 'after',
          metrics: <MetricComparison>[
            MetricComparison(
              metricId: AnalysisMetricId.timingTargetMeanAbsoluteError,
              direction: MetricComparisonDirection.improved,
              confidence: 0.8,
              sampleCount: 10,
              beforeValue: 40,
              afterValue: 30,
              absoluteDelta: -10,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.analysisCompare);
      expect(find.byType(AnalysisCompareScreen), findsOneWidget);
    },
  );

  testWidgets('analysisComparisonEnabled ON: missing extra redirects to live', (
    tester,
  ) async {
    final harness = await _pumpRouter(
      tester,
      seen: true,
      analysisComparisonEnabled: true,
    );

    harness.router.go(AppRoutes.analysisCompare);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(harness.router.state.uri.path, AppRoutes.live);
  });

  // E15-R07 F1 (ADR 0491) — A2: the two Practice Generator routes are
  // registered ONLY behind `practiceGeneratorEnabled`, independently of
  // `practiceEngineV2Enabled`/`adaptiveShellEnabled`. A2 also requires the
  // OFF cell: with the flag off, the route must not exist at all (the
  // router's onException falls back to the entry location), not merely
  // render something different.
  testWidgets(
    'flagged Practice Generator setup route is registered and builds from '
    'the composition root without throwing (A1″, A2 ON)',
    (tester) async {
      final harness = await _pumpRouter(
        tester,
        seen: true,
        practiceGeneratorEnabled: true,
      );

      harness.router.go(AppRoutes.practiceGeneratorSetup);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorSetup);
      expect(find.byType(PlanSetupScreen), findsOneWidget);
    },
  );

  testWidgets(
    'flagged Practice Generator today route is registered and builds from '
    'the composition root without throwing (A1″, A2 ON)',
    (tester) async {
      final harness = await _pumpRouter(
        tester,
        seen: true,
        practiceGeneratorEnabled: true,
      );

      harness.router.go(AppRoutes.practiceGeneratorToday);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.practiceGeneratorToday);
      expect(find.byType(TodayPlanScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Practice Generator routes are NOT registered when the flag is off '
    '(A2 OFF)',
    (tester) async {
      final harness = await _pumpRouter(
        tester,
        seen: true,
        practiceGeneratorEnabled: false,
      );

      harness.router.go(AppRoutes.practiceGeneratorSetup);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.live);
      expect(find.byType(PlanSetupScreen), findsNothing);

      harness.router.go(AppRoutes.practiceGeneratorToday);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.live);
      expect(find.byType(TodayPlanScreen), findsNothing);
    },
  );

  testWidgets('flagged Song Trainer library route is registered', (
    tester,
  ) async {
    final harness = await _pumpRouter(
      tester,
      seen: true,
      songTrainerEnabled: true,
    );

    harness.router.go(AppRoutes.songTrainerLibrary);
    await tester.pumpAndSettle();

    expect(harness.router.state.uri.path, AppRoutes.songTrainerLibrary);
    expect(find.byType(SongLibraryScreen), findsOneWidget);
  });

  testWidgets('flagged Song Trainer editor route is registered with an id', (
    tester,
  ) async {
    final harness = await _pumpRouter(
      tester,
      seen: true,
      songTrainerEnabled: true,
    );

    harness.router.go('/song-trainer/editor/router-song');
    await tester.pumpAndSettle();

    expect(harness.router.state.uri.path, '/song-trainer/editor/router-song');
    expect(find.byType(SongEditorScreen), findsOneWidget);
  });

  testWidgets('library editor entry uses the canonical editor route', (
    tester,
  ) async {
    final harness = await _pumpRouter(
      tester,
      seen: true,
      songTrainerEnabled: true,
    );
    await harness.songRepository.create(_editorDocument('library-song'));

    harness.router.go(AppRoutes.songTrainerLibrary);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('song-editor-open-library-song')));
    await tester.pumpAndSettle();

    expect(harness.router.state.uri.path, '/song-trainer/editor/library-song');
    expect(find.byType(SongEditorScreen), findsOneWidget);
  });

  testWidgets('library offers a canonical new V2 editor route', (tester) async {
    final harness = await _pumpRouter(
      tester,
      seen: true,
      songTrainerEnabled: true,
    );

    harness.router.go(AppRoutes.songTrainerLibrary);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('song-editor-create')));
    await tester.pumpAndSettle();

    expect(harness.router.state.uri.path, '/song-trainer/editor/new');
    expect(find.byType(SongEditorScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('song-editor-save')));
    await tester.pumpAndSettle();

    expect(
      (await harness.songRepository.list(const SongQuery())).valueOrNull,
      hasLength(1),
    );
  });

  testWidgets('successful login pops back to the calling settings screen', (
    tester,
  ) async {
    final harness = await _pumpRouter(tester, seen: true, accountEnabled: true);
    harness.router.go(AppRoutes.settings);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(harness.router.state.uri.path, AppRoutes.login);
    expect(find.byType(LoginScreen), findsOneWidget);

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'player@strumsight.app');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(harness.router.state.uri.path, AppRoutes.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  test('disposing the provider container disposes router resources', () {
    final container = ProviderContainer();
    final router = container.read(routerProvider);

    container.dispose();

    expect(() => router.go(AppRoutes.settings), throwsFlutterError);
  });

  // E08-R30 — Epic 8 route activation. These cells prove that the six new
  // gamification V2 routes are wired into the live router, that the legacy
  // `/streak` and `/progress` deep links remain reachable (ADR §5.1), and
  // that the achievement-list → achievement-detail navigation pushes a
  // matching URL with the path parameter.
  group('E08-R30 — gamification routes', () {
    testWidgets('legacy /streak deep link still resolves to StreakScreen', (
      tester,
    ) async {
      final harness = await _pumpRouter(tester, seen: true);

      harness.router.go(AppRoutes.streak);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.streak);
      expect(find.byType(StreakScreen), findsOneWidget);
    });

    testWidgets('legacy /progress deep link still resolves to ProgressScreen', (
      tester,
    ) async {
      final harness = await _pumpRouter(tester, seen: true);

      harness.router.go(AppRoutes.progress);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.progress);
      expect(find.byType(ProgressScreen), findsOneWidget);
    });

    testWidgets('gamification hub route registers', (tester) async {
      final harness = await _pumpRouter(tester, seen: true);

      harness.router.go(AppRoutes.gamificationHub);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.gamificationHub);
      expect(find.byType(GamificationHubScreen), findsOneWidget);
    });

    testWidgets('achievements route registers with the curated catalog', (
      tester,
    ) async {
      final harness = await _pumpRouter(tester, seen: true);

      harness.router.go(AppRoutes.achievements);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.achievements);
      final screen = tester.widget<AchievementsScreen>(
        find.byType(AchievementsScreen),
      );
      expect(screen.definitions, isNotEmpty);
    });

    testWidgets('achievement detail route resolves the path parameter', (
      tester,
    ) async {
      final harness = await _pumpRouter(tester, seen: true);

      harness.router.go('/gamification/achievement/practice_starter');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        harness.router.state.uri.path,
        '/gamification/achievement/practice_starter',
      );
      final screen = tester.widget<AchievementDetailScreen>(
        find.byType(AchievementDetailScreen),
      );
      expect(screen.achievementId, 'practice_starter');
    });

    testWidgets('quests route registers', (tester) async {
      final harness = await _pumpRouter(tester, seen: true);

      harness.router.go(AppRoutes.quests);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.quests);
      expect(find.byType(QuestsScreen), findsOneWidget);
    });

    testWidgets('streak detail route registers', (tester) async {
      final harness = await _pumpRouter(tester, seen: true);

      harness.router.go(AppRoutes.streakDetail);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.streakDetail);
      expect(find.byType(StreakDetailScreen), findsOneWidget);
    });

    testWidgets('reward inbox route registers', (tester) async {
      final harness = await _pumpRouter(tester, seen: true);

      harness.router.go(AppRoutes.rewardInbox);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(harness.router.state.uri.path, AppRoutes.rewardInbox);
      expect(find.byType(RewardInboxScreen), findsOneWidget);
    });
  });
}

SongDocument _editorDocument(String id) {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId(id),
    revision: 0,
    metadata: SongMetadata(title: id),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: '$id.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'router-test@1',
    ),
    createdAt: now,
    updatedAt: now,
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
    ],
    tempoMap: TempoMap.constant(Tempo(120)),
    meterMap: MeterMap.constant(Meter(4, 4)),
  );
}

final class _RouterAssetRepository implements SongAssetRepository {
  const _RouterAssetRepository();

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(
    SongAssetWriteRequest request,
  ) async => AppResult<SongAssetStoreReceipt>.success(
    SongAssetStoreReceipt(
      assetId: request.assetId,
      sha256: request.expectedSha256,
      byteLength: request.bytes.length,
      duplicate: false,
    ),
  );

  @override
  Future<AppResult<Uint8List?>> get(String sha256) async =>
      const AppResult<Uint8List?>.success(null);

  @override
  Future<AppResult<SongAssetSummary?>> summary(String sha256) async =>
      const AppResult<SongAssetSummary?>.success(null);

  @override
  Future<AppResult<void>> incrementReference(SongAssetHolder holder) async =>
      const AppResult<void>.success(null);

  @override
  Future<AppResult<void>> decrementReference(SongAssetHolder holder) async =>
      const AppResult<void>.success(null);

  @override
  Future<AppResult<void>> permanentlyDelete(String sha256) async =>
      const AppResult<void>.success(null);
}
