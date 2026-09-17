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
import 'dart:typed_data';

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
import 'package:strumsight/core/audio/codec/platform_audio_decoder.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/application/practice_session_providers.dart';
import 'package:strumsight/features/practice/public.dart'
    show PracticeAttemptResult, PracticeFinishReason, PracticeSessionResult;
import 'package:strumsight/features/analyze/public.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_result.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_tick_source.dart';
import 'package:strumsight/features/song_trainer/data/importers/file_picker_adapter.dart';
import 'package:strumsight/features/song_trainer/data/importers/song_importer.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/data/local/song_document_codec.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_editor_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_import_screen.dart';
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
  List<Override> extraOverrides = const <Override>[],
}) async {
  // MEASURED (record-goldens 35207783427): on the default 800x600 surface the
  // trainer setup's `ListView` never LAYS OUT its last child, so
  // `trainer-setup-start` is not in the element tree and `find.byKey` sees
  // nothing — the walk failed on a viewport, not on the wiring. A tall
  // surface renders the whole form at once and keeps the assertion about
  // navigation rather than about scrolling.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

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
      ...extraOverrides,
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

  // K3/A6 — the audio import walk. Three seams are faked, each for a named
  // reason: the platform decoder has no host implementation, the analyzer
  // would otherwise run thousands of FFTs inside a widget test, and the asset
  // store is in-memory because real `dart:io` never completes inside
  // `testWidgets`' fake-async zone. Everything between them is production:
  // the picker port, the limit profile, the mapper, the normalizer and
  // validator, the repository and the router.
  testWidgets('an audio file imports as a draft and lands in the editor', (
    tester,
  ) async {
    await _bootLibrary(
      tester,
      extraOverrides: <Override>[
        songAssetRepositoryProvider.overrideWithValue(_MemoryAssetStore()),
        songFilePickerAdapterProvider.overrideWithValue(
          const _FakeAudioPicker(),
        ),
        audioSongImportDecoderProvider.overrideWithValue(_fakeDecode),
        audioSongImportAnalyzerProvider.overrideWithValue(_fakeAnalyze),
      ],
    );
    expect(find.byType(SongLibraryScreen), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byType(SongImportScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('song-import-choose-audio')));
    await tester.pumpAndSettle();

    // The draft lands in the EDITOR, behind the review banner — never in a
    // practice session.
    expect(find.byType(SongEditorScreen), findsOneWidget);
    expect(find.byType(SongTrainerScreen), findsNothing);
    expect(find.byKey(const Key('song-editor-draft-banner')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(SongLibraryScreen), findsOneWidget);
    expect(
      find.text('Audio file'),
      findsWidgets,
      reason: 'the library must show the new origin on the imported row',
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

/// Returns a fixed audio source; the notation picker is never reached here.
final class _FakeAudioPicker implements FilePickerAdapter {
  const _FakeAudioPicker();

  @override
  Future<ImportSourceFile?> pickSongFile() async => null;

  @override
  Future<ImportSourceFile?> pickAudioFile() async {
    final bytes = Uint8List.fromList(
      List<int>.generate(4096, (index) => index % 251),
    );
    return ImportSourceFile(
      displayName: 'walkthrough.mp3',
      byteLength: bytes.length,
      mimeType: 'audio/mpeg',
      openRead: () => Stream<List<int>>.value(bytes),
    );
  }

  @override
  Future<void> dispose() async {}
}

/// Stands in for the Android platform decoder, which has no host build.
Future<AppResult<DecodedPcm>> _fakeDecode(
  Uint8List bytes,
  String extension,
) async {
  expect(extension, 'mp3');
  final samples = Float32List(16000 * 4);
  for (var index = 0; index < samples.length; index++) {
    samples[index] = (index % 100) / 100 - 0.5;
  }
  return Success<DecodedPcm>(DecodedPcm(sampleRate: 16000, samples: samples));
}

/// The content-hash asset store, without the filesystem.
final class _MemoryAssetStore implements SongAssetRepository {
  final Map<String, Uint8List> _bytes = <String, Uint8List>{};

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(
    SongAssetWriteRequest request,
  ) async {
    _bytes[request.expectedSha256] = request.bytes;
    return AppResult<SongAssetStoreReceipt>.success(
      SongAssetStoreReceipt(
        assetId: request.assetId,
        sha256: request.expectedSha256,
        byteLength: request.bytes.length,
        duplicate: false,
      ),
    );
  }

  @override
  Future<AppResult<Uint8List?>> get(String sha256) async =>
      AppResult<Uint8List?>.success(_bytes[sha256]);

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

/// A fixed G-C-D reading — the DSP itself is measured by its own suites.
Future<AnalyzeResult> _fakeAnalyze(List<double> pcm, int sampleRate) async {
  return const AnalyzeResult(
    durationSec: 4,
    bpm: 120,
    chords: <TimelineChord>[
      TimelineChord(label: 'G', startSec: 0, endSec: 2),
      TimelineChord(label: 'C', startSec: 2, endSec: 3),
      TimelineChord(label: 'D', startSec: 3, endSec: 4),
    ],
    strums: <TimelineStrum>[
      TimelineStrum(
        direction: StrumDirection.down,
        timeSec: 0.5,
        confidence: 0.9,
      ),
    ],
  );
}
