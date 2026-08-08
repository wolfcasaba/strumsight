import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/bootstrap/app_bootstrap.dart';
import 'package:strumsight/app/bootstrap/bootstrap_result.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/app/strumsight_app.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/core/network/dio_factory.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/analyze/screens/analyze_screen.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/diagnostics/providers/diagnostics_providers.dart';
import 'package:strumsight/features/learn/screens/lesson_list_screen.dart';
import 'package:strumsight/features/library/screens/library_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/progress/screens/progress_screen.dart';
import 'package:strumsight/features/settings/providers/lab_mode_provider.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/songs/screens/song_list_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/features/ai_tutor/presentation/screens/tutor_home_screen.dart';
import 'package:strumsight/features/vision/public.dart';

import '../support/fake_audio.dart';
import '../support/fake_auth.dart';
import '../support/fake_engines.dart';
import '../support/preference_store.dart';

const _apiBaseUrl = 'https://api.strumsight.test';
const _appVersion = '1.0.0+1';

final class _NetworkProbe implements HttpClientAdapter {
  int accountFactoryCreations = 0;
  final List<RequestOptions> requests = <RequestOptions>[];

  DioFactory createAccountFactory(AppConfig config, AppLogger logger) {
    accountFactoryCreations++;
    return DioFactory(
      baseUrl: config.apiBaseUrl,
      appVersion: config.appVersion,
      logger: logger,
      adapter: this,
      correlationIdGenerator: () => 'offline-network-guard',
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _AppHarness {
  const _AppHarness({
    required this.container,
    required this.router,
    required this.network,
    required this.tokenStore,
  });

  final ProviderContainer container;
  final GoRouter router;
  final _NetworkProbe network;
  final FakeTokenStore tokenStore;
}

Future<_AppHarness> _bootApp(
  WidgetTester tester, {
  required bool accountEnabled,
  FeatureFlags? flags,
}) async {
  final store = InMemoryKeyValueStore({StorageKeys.onboardingSeen: true});
  final result = await AppBootstrap.run(
    rawEnvironment: AppEnvironment.production.name,
    apiBaseUrl: _apiBaseUrl,
    accountEnabled: accountEnabled,
    diagnosticsToken: '',
    buildMode: 'release',
    loadVersion: () async => _appVersion,
    openStore: () async => Success<KeyValueStore>(store),
    logger: const NoopAppLogger(),
  );

  expect(result, isA<BootstrapSuccess>());
  final success = result as BootstrapSuccess;
  expect(success.config.flags.accountEnabled, accountEnabled);
  expect(success.config.flags.diagnosticsEnabled, isFalse);
  expect(success.onboardingSeen, isTrue);

  final config = flags != null
      ? AppConfig(
          environment: success.config.environment,
          apiBaseUrl: success.config.apiBaseUrl,
          flags: flags,
          diagnosticsToken: success.config.diagnosticsToken,
          buildMode: success.config.buildMode,
          appVersion: success.config.appVersion,
        )
      : success.config;

  final network = _NetworkProbe();
  final tokenStore = FakeTokenStore();
  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      keyValueStoreProvider.overrideWithValue(success.keyValueStore),
      appLoggerProvider.overrideWithValue(const NoopAppLogger()),
      diagnosticsConsentProvider.overrideWith(
        (ref) => ref.watch(labModeProvider),
      ),
      onboardingSeenProvider.overrideWith(
        () => OnboardingController(success.onboardingSeen),
      ),
      tokenStoreProvider.overrideWithValue(tokenStore),
      accountDioFactoryProvider.overrideWith(
        (ref) => network.createAccountFactory(
          ref.watch(appConfigProvider),
          ref.watch(appLoggerProvider),
        ),
      ),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
    ],
  );
  final router = container.read(routerProvider);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await liveEngine.dispose();
    await tunerEngine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const StrumSightApp(),
    ),
  );
  await tester.pumpAndSettle();
  await container.read(authControllerProvider.future);
  await tester.pump();

  expect(container.read(authControllerProvider).value, isNull);
  return _AppHarness(
    container: container,
    router: router,
    network: network,
    tokenStore: tokenStore,
  );
}

Future<void> _buildMainScreens(WidgetTester tester, _AppHarness harness) async {
  const screens = <({String route, Type type})>[
    (route: AppRoutes.live, type: LiveScreen),
    (route: AppRoutes.analyze, type: AnalyzeScreen),
    (route: AppRoutes.learn, type: LessonListScreen),
    (route: AppRoutes.library, type: LibraryScreen),
    (route: AppRoutes.settings, type: SettingsScreen),
    (route: AppRoutes.tuner, type: TunerScreen),
    (route: AppRoutes.songs, type: SongListScreen),
    (route: AppRoutes.progress, type: ProgressScreen),
  ];

  for (final screen in screens) {
    harness.router.go(screen.route);
    await tester.pumpAndSettle();

    expect(harness.router.state.uri.path, screen.route);
    expect(find.byType(screen.type), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: '${screen.route} must build without an asynchronous error',
    );
  }
}

void _expectNoNetwork(_AppHarness harness) {
  expect(
    [harness.network.accountFactoryCreations, harness.network.requests.length],
    [0, 0],
    reason:
        'app boot and top-level screens must neither create an account '
        'Dio client nor reach its transport adapter',
  );
  expect(harness.container.read(diagnosticsApiClientProvider), isNull);
  expect(harness.container.read(diagnosticsUploaderProvider).client, isNull);
}

void main() {
  testWidgets(
    'account and diagnostics disabled: full boot and main screens stay offline',
    (tester) async {
      final harness = await _bootApp(tester, accountEnabled: false);

      await _buildMainScreens(tester, harness);

      expect(harness.tokenStore.reads, 0);
      _expectNoNetwork(harness);
    },
  );

  testWidgets(
    'account enabled but signed out: full boot and main screens stay offline',
    (tester) async {
      final harness = await _bootApp(tester, accountEnabled: true);

      await _buildMainScreens(tester, harness);

      expect(harness.tokenStore.reads, 1);
      _expectNoNetwork(harness);
    },
  );

  testWidgets(
    'aiTutor enabled with cloud OFF: tutor home screen stays offline',
    (tester) async {
      final harness = await _bootApp(
        tester,
        accountEnabled: false,
        flags: const FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
          aiTutorEnabled: true,
          aiTutorCloudEnabled: false,
        ),
      );

      // Navigate to tutor home — a plain StatelessWidget with no providers
      harness.router.go(AppRoutes.tutorHome);
      await tester.pumpAndSettle();
      expect(harness.router.state.uri.path, AppRoutes.tutorHome);
      expect(find.byType(TutorHomeScreen), findsOneWidget);

      _expectNoNetwork(harness);
    },
  );

  testWidgets('vision enabled: session route stays offline', (tester) async {
    final harness = await _bootApp(
      tester,
      accountEnabled: false,
      flags: const FeatureFlags(
        accountEnabled: false,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        visionEnabled: true,
      ),
    );

    harness.router.go(AppRoutes.visionSession);
    await tester.pumpAndSettle();

    expect(harness.router.state.uri.path, AppRoutes.visionSession);
    expect(find.byType(VisionSessionScreen), findsOneWidget);

    final store = harness.container.read(keyValueStoreProvider);
    final repository = VisionSessionRepository(store: store);
    await repository.save(
      _offlineVisionResult(),
      modelVersions: const <String, String>{'hand_landmarker': '1.2.3'},
    );
    final export =
        jsonDecode(VisionExport(store: store).exportJson())
            as Map<String, dynamic>;
    expect(export['sessions'], hasLength(1));

    _expectNoNetwork(harness);
  });
}

VisionSessionResult _offlineVisionResult() => VisionSessionResult(
  session: VisionSession(
    id: VisionSessionId.create('offline-network-guard'),
    startedAt: DateTime.utc(2026, 8, 8),
  ),
  endedAt: DateTime.utc(2026, 8, 8, 0, 1),
  endReason: VisionSessionEndReason.explicitStop,
  qualitySummary: VisionQualitySummary.fromFrames(const <VisionFrameQuality>[]),
  calibrationState: CalibrationLossState.tracking,
  sessionSummary: const <VisionInsight>[],
  observedFrameCount: 0,
);
