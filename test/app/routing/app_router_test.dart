import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/auth/screens/login_screen.dart';
import 'package:strumsight/features/library/public.dart';
import 'package:strumsight/features/library/screens/library_screen.dart';
import 'package:strumsight/features/library/screens/session_detail_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/live/screens/live_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
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
      theme: AppTheme.light(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _RouterHarness {
  const _RouterHarness({required this.container, required this.router});

  final ProviderContainer container;
  final GoRouter router;
}

Future<_RouterHarness> _pumpRouter(
  WidgetTester tester, {
  required bool seen,
  bool accountEnabled = false,
  bool songTrainerEnabled = false,
}) async {
  final engine = FakeStrumEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(engine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(seen)),
      accountEnabledProvider.overrideWithValue(accountEnabled),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: accountEnabled,
            diagnosticsEnabled: true,
            labModeAvailable: true,
            songTrainerV2Enabled: songTrainerEnabled,
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
  return _RouterHarness(container: container, router: router);
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
}
