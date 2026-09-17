// E16-R01/A2 + A3 + A5 — the route-level walk the Song Trainer V2 never had.
//
// MEASURED gap (2026-09-17 review §7): every trainer widget test injected a
// `state:` and an event list directly, so all ~60 of them stayed green while
// the feature was UNREACHABLE — there was not one `push(songTrainerSession)`
// in `lib/`, the Stage never called `prepare()`/`start()`, and the lanes got
// empty lists. This suite drives the REAL router: seeded library → Play →
// setup → Start → a running session with the song's own events → pause.
//
// The Song Trainer's playhead ticker is pinned to a hand-driven double here.
// The production `Timer.periodic` would schedule a frame every 16 ms forever,
// which is exactly what `pumpAndSettle` cannot settle.
import 'dart:convert';
import 'dart:io';

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
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/application/practice_session_providers.dart';
import 'package:strumsight/features/practice/public.dart'
    show PracticeAttemptResult, PracticeFinishReason, PracticeSessionResult;
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_tick_source.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/local/song_document_codec.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_result_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_session_route.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/trainer_setup_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/chord_lane.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/strum_lane.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../support/fake_audio.dart';
import '../support/fake_clock.dart';
import '../support/fake_engines.dart';
import '../support/preference_store.dart';

/// The shipped practice song this walk uses — read from the SAME asset the
/// seed installer bundles, so the walk measures real content, not a fixture.
const String _seedAssetPath = 'assets/songs/seed-harom-akkord-g-c-d.song.json';

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

final class _Walk {
  _Walk({
    required this.container,
    required this.router,
    required this.clock,
    required this.document,
  });

  final ProviderContainer container;
  final GoRouter router;
  final HarnessClock clock;
  final SongDocument document;
}

SongDocument _loadSeedDocument() {
  final raw = File(_seedAssetPath).readAsStringSync();
  return const SongDocumentCodec().decode(utf8.encode(raw));
}

Future<_Walk> _bootLibrary(
  WidgetTester tester, {
  MicrophonePermissionState permission = MicrophonePermissionState.granted,
}) async {
  final document = _loadSeedDocument();
  final repository = InMemorySongRepository(
    clock: () => DateTime.utc(2026, 9, 17),
  );
  await repository.create(document);

  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final clock = HarnessClock();
  final container = ProviderContainer(
    overrides: <Override>[
      ...preferenceOverrides(),
      ...fakeAudioOverrides(
        permissions: FakeMicrophonePermissionGateway(state: permission),
      ),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      songRepositoryProvider.overrideWithValue(repository),
      // Platform boundary: the production player builds an `audioplayers`
      // `AudioPlayer` (a real method channel) the moment the transport is
      // created, and it reads the asset store this harness does not mount.
      backingAudioPlayerProvider.overrideWithValue(FakeBackingAudioPlayer()),
      songTransportTickSourceProvider.overrideWithValue(
        ManualSongTransportTickSource(),
      ),
      practiceSessionClockProvider.overrideWithValue(clock.clock),
      practiceTickSourceProvider.overrideWithValue(clock.tickSource),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: false,
            labModeAvailable: false,
            practiceEngineV2Enabled: true,
            songTrainerV2Enabled: true,
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
    await tester.pump();
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
  final router = container.read(routerProvider);
  router.go(AppRoutes.songs);
  await tester.pumpAndSettle();

  return _Walk(
    container: container,
    router: router,
    clock: clock,
    document: document,
  );
}

void main() {
  testWidgets('the seeded library reaches a running session and pauses it', (
    tester,
  ) async {
    final walk = await _bootLibrary(tester);
    expect(find.byType(SongLibraryScreen), findsOneWidget);

    // 1 — the row's own Play affordance opens the trainer setup.
    await tester.tap(find.byKey(Key('song-play-${walk.document.id.value}')));
    await tester.pumpAndSettle();

    expect(find.byType(TrainerSetupScreen), findsOneWidget);
    expect(
      walk.router.state.uri.path,
      '/song-trainer/setup/${walk.document.id.value}',
    );

    // 2 — Start is no longer deaf: it compiles the config and pushes the
    // session route (measured before this round: ZERO push call sites).
    await tester.ensureVisible(find.byKey(const Key('trainer-setup-start')));
    await tester.tap(find.byKey(const Key('trainer-setup-start')));
    await tester.pumpAndSettle();

    expect(find.byType(SongTrainerSessionRoute), findsOneWidget);
    expect(find.byType(SongTrainerScreen), findsOneWidget);
    expect(
      walk.router.state.uri.path,
      '/song-trainer/session/${walk.document.id.value}',
    );

    // 3 — the count-in completes and the session runs.
    await walk.clock.tick(tester, const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 4 — the lanes carry the song's OWN events, not empty lists.
    final strumLane = tester.widget<StrumLane>(find.byType(StrumLane));
    expect(strumLane.events, isNotEmpty);
    final chordLane = tester.widget<ChordLane>(find.byType(ChordLane));
    expect(chordLane.events, isNotEmpty);

    // 5 — pause reaches the controller and the Stage renders the paused body.
    await tester.tap(find.byKey(const Key('song-trainer-transport-pause')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('song-trainer-paused-position')),
      findsOneWidget,
    );
  });

  testWidgets('a denied microphone explains itself instead of spinning', (
    tester,
  ) async {
    final walk = await _bootLibrary(
      tester,
      permission: MicrophonePermissionState.denied,
    );

    await tester.tap(find.byKey(Key('song-play-${walk.document.id.value}')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('trainer-setup-start')));
    await tester.tap(find.byKey(const Key('trainer-setup-start')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('song-trainer-permission-required')),
      findsOneWidget,
    );
  });

  testWidgets('the result screen CTAs are wired to the router', (tester) async {
    final walk = await _bootLibrary(tester);
    var practiceAgainCalls = 0;

    walk.router.push<void>(
      AppRoutes.songTrainerResult.replaceFirst(
        ':songId',
        walk.document.id.value,
      ),
      extra: SongTrainerResultArgs(
        result: _emptyResult(),
        onPracticeAgain: () => practiceAgainCalls++,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SongResultScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('song-result-retry')));
    await tester.pumpAndSettle();

    expect(practiceAgainCalls, 1);
    expect(walk.router.state.uri.path, AppRoutes.songs);
  });

  testWidgets('back to the library leaves the trainer flow', (tester) async {
    final walk = await _bootLibrary(tester);

    walk.router.push<void>(
      AppRoutes.songTrainerResult.replaceFirst(
        ':songId',
        walk.document.id.value,
      ),
      extra: SongTrainerResultArgs(result: _emptyResult()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('song-result-back-to-library')));
    await tester.pumpAndSettle();

    expect(walk.router.state.uri.path, AppRoutes.songs);
    expect(find.byType(SongLibraryScreen), findsOneWidget);
  });
}

SongTrainerResult _emptyResult() => SongTrainerResult(
  sessionResult: const PracticeSessionResult(
    id: 'walkthrough-result',
    activeDuration: Duration(seconds: 10),
    pausedDuration: Duration.zero,
    attempts: <PracticeAttemptResult>[],
    finishReason: PracticeFinishReason.completedAllTargets,
    highestStableTempo: null,
    coachingSummary: <String>[],
  ),
  verdicts: const <SongTrainerVerdict>[],
  measureResults: const <SongMeasureTrainerResult>[],
  sectionResults: const <SongSectionTrainerResult>[],
);
