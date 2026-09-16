// Learner-loop round 5: the Songs destination of the adaptive shell renders
// the Song Trainer V2 library whenever that rollout is on (it used to open
// the legacy builder list, leaving the trainer reachable only from an
// orphaned lesson list); the legacy builder stays one tap away.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/features/songs/screens/song_list_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

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

Future<void> _pumpSongs(
  WidgetTester tester, {
  required bool songTrainerV2Enabled,
}) async {
  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            songTrainerV2Enabled: songTrainerV2Enabled,
            adaptiveShellEnabled: true,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
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
  container.read(routerProvider).go(AppRoutes.songs);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with the V2 rollout on, the Songs tab is the trainer library '
      'and the legacy builder is one tap away', (tester) async {
    await _pumpSongs(tester, songTrainerV2Enabled: true);

    expect(find.byType(SongLibraryScreen), findsOneWidget);
    expect(find.byType(SongListScreen), findsNothing);

    await tester.tap(find.byKey(const Key('song-library-own-songs')));
    await tester.pumpAndSettle();

    expect(find.byType(SongListScreen), findsOneWidget);
  });

  testWidgets('with the V2 rollout off, the Songs tab stays the legacy list', (
    tester,
  ) async {
    await _pumpSongs(tester, songTrainerV2Enabled: false);

    expect(find.byType(SongListScreen), findsOneWidget);
    expect(find.byType(SongLibraryScreen), findsNothing);
  });
}
