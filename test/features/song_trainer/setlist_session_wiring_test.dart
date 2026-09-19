// E17-R03 — the Setlist V2 session wiring (ADR 0585).
//
// A2: the Song Library's entry affordance opens the V2 setlist route.
// A3/A4: both Practice and Performance start from the ONE `_startSession`
// entry point, wired through the REAL provider graph, and the mounted
// `SetlistSessionScreen` owns a REAL `SetlistSessionController`.
// A5: availability comes from the real `SongRepository` — a song missing
// from an EMPTY index snapshot is `missingSong`, and the controller never
// invokes the runner for it (never a constant `ready`).
// A6: the runner's `SetlistItemResult` reflects the session's OWN measured
// outcome — leaving a pushed session before it reports one is `partial`,
// never a synthesized `completed` (this is also the §6.1 mandatory
// falsification cell: hard-coding the runner to `completed` turns this red).
// A7: leaving the session returns to the V2 setlist list underneath, never
// past it to the app root.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/song_trainer/application/setlists/setlist_session_controller.dart';
import 'package:strumsight/features/song_trainer/application/setlists/setlist_session_providers.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_trainer_session_launcher.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_tick_source.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/data/local/song_document_codec.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/setlist_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/setlist_repository.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_list_screen_v2.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_session_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_library_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_session_route.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/preference_store.dart';

const String _seedAssetPath = 'assets/songs/seed-harom-akkord-g-c-d.song.json';

SongDocument _loadSeedDocument() {
  final raw = File(_seedAssetPath).readAsStringSync();
  return const SongDocumentCodec().decode(utf8.encode(raw));
}

void main() {
  testWidgets(
    'A2 — the song library entry affordance opens the V2 setlist route',
    (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.songTrainerLibrary,
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.songTrainerLibrary,
            builder: (_, _) => const SongLibraryScreen(),
          ),
          GoRoute(
            path: AppRoutes.songTrainerSetlists,
            builder: (_, _) => const Scaffold(body: Text('setlists-stub')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            songRepositoryProvider.overrideWithValue(InMemorySongRepository()),
          ],
          child: MaterialApp.router(
            theme: SsLightTheme.data(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('song-library-open-setlists')));
      await tester.pumpAndSettle();

      expect(find.text('setlists-stub'), findsOneWidget);
    },
  );

  testWidgets(
    'A3/A4 — both modes start from the ONE entry point, wired through the '
    'real provider graph, onto the real SetlistSessionController',
    (tester) async {
      final document = _loadSeedDocument();
      final repository = InMemorySongRepository(
        clock: () => DateTime.utc(2026, 9, 19),
      );
      await repository.create(document);
      final setlist = _oneItemSetlist(songId: document.id);

      // A3's own evidence requirement: build every dependency from a REAL
      // ProviderContainer — the same provider graph app_router.dart's
      // Consumer builder reads — not hand-rolled fakes.
      final container = ProviderContainer(
        overrides: <Override>[
          songRepositoryProvider.overrideWithValue(repository),
          setlistRepositoryProvider.overrideWithValue(
            _FakeSetlistRepository(<SongSetlist>[setlist]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _app(
          SetlistListScreenV2(
            controller: container.read(setlistControllerProvider),
            clock: container.read(songTrainerClockProvider),
            songRepository: container.read(songRepositoryProvider),
            sessionLauncher: container.read(songTrainerSessionLauncherProvider),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('setlist-start-practice-${setlist.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(SetlistSessionScreen), findsOneWidget);
      expect(find.text('Setlist practice'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SetlistSessionScreen), findsNothing);

      await tester.tap(
        find.byKey(Key('setlist-start-performance-${setlist.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SetlistSessionScreen), findsOneWidget);
      expect(find.text('Setlist performance'), findsOneWidget);
    },
  );

  testWidgets(
    'A5 — a song missing from the real repository index is skipped as '
    'missingSong; the controller never invokes the runner for it',
    (tester) async {
      final repository = InMemorySongRepository();
      // The index is intentionally EMPTY — no song was ever created.
      final snapshot = await loadSetlistAvailabilitySnapshot(repository);
      final availability = buildSetlistAvailabilityResolver(snapshot);

      final item = SongSetlistItem(
        id: 'missing-item',
        songId: SongId('does-not-exist'),
      );
      var runnerInvoked = false;
      final controller = SetlistSessionController(
        availability: availability,
        practiceRunner: (setlistItem) async {
          runnerInvoked = true;
          return SetlistItemResult.completed(itemId: setlistItem.id);
        },
        performanceRunner: (setlistItem) async {
          runnerInvoked = true;
          return SetlistItemResult.completed(itemId: setlistItem.id);
        },
      );

      final result = await controller.run(
        setlist: _oneItemSetlist(songId: item.songId, item: item),
        mode: SetlistSessionMode.practice,
      );

      expect(
        runnerInvoked,
        isFalse,
        reason:
            'a missingSong item is never handed to the runner — the '
            'controller skips it itself',
      );
      expect(result.itemResults.single.status, SetlistItemResultStatus.skipped);
      expect(
        result.itemResults.single.availability,
        SetlistItemAvailability.missingSong,
      );
    },
  );

  testWidgets(
    'A6/§6.1 — leaving a pushed session before it reports a result never '
    'produces a synthesized completed (mandatory falsification cell: '
    'hard-coding the runner to `completed` makes this assertion fail)',
    (tester) async {
      final document = _loadSeedDocument();
      final repository = InMemorySongRepository(
        clock: () => DateTime.utc(2026, 9, 19),
      );
      await repository.create(document);
      final setlist = _oneItemSetlist(songId: document.id);

      final container = ProviderContainer(
        overrides: <Override>[
          ...preferenceOverrides(),
          songRepositoryProvider.overrideWithValue(repository),
          setlistRepositoryProvider.overrideWithValue(
            _FakeSetlistRepository(<SongSetlist>[setlist]),
          ),
          // Playback-only (TrainerMode.pitch) never reads a microphone
          // provider, but the transport still needs a non-platform player
          // and a tick source that does not schedule a real `Timer.periodic`
          // — a real one would run forever and `pumpAndSettle` could never
          // settle (measured pattern, test/e2e/song_trainer_walkthrough_test.dart).
          backingAudioPlayerProvider.overrideWithValue(
            FakeBackingAudioPlayer(),
          ),
          songTransportTickSourceProvider.overrideWithValue(
            ManualSongTransportTickSource(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _appWithContainer(
          container,
          SetlistListScreenV2(
            controller: container.read(setlistControllerProvider),
            clock: container.read(songTrainerClockProvider),
            songRepository: container.read(songRepositoryProvider),
            sessionLauncher: container.read(songTrainerSessionLauncherProvider),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Performance mode (TrainerMode.pitch under the hood) needs no
      // microphone/scoring provider chain to reach a running session.
      await tester.tap(
        find.byKey(Key('setlist-start-performance-${setlist.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setlist-session-start')), findsOneWidget);

      // Start the setlist run — this pushes the real SongTrainerSessionRoute
      // for the one real item. The tick source is hand-driven (no real
      // Timer.periodic), so pumpAndSettle is safe here.
      await tester.tap(find.byKey(const Key('setlist-session-start')));
      await tester.pumpAndSettle();
      expect(find.byType(SongTrainerSessionRoute), findsOneWidget);

      // Leave BEFORE the transport ever reaches SongTransportPhase.completed
      // — exactly the "abandoned session" case D4 forbids synthesizing a
      // result for.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('setlist-session-result')), findsOneWidget);
      expect(
        find.textContaining('Completed 0 of 1'),
        findsOneWidget,
        reason:
            'an early exit must be measured as NOT completed — a runner '
            'hard-coded to `completed` would report "Completed 1 of 1" here',
      );
    },
  );

  testWidgets(
    'A7 — leaving the session returns to the V2 setlist list, never past '
    'it to the app root',
    (tester) async {
      final document = _loadSeedDocument();
      final repository = InMemorySongRepository(
        clock: () => DateTime.utc(2026, 9, 19),
      );
      await repository.create(document);
      final setlist = _oneItemSetlist(songId: document.id);

      final container = ProviderContainer(
        overrides: <Override>[
          songRepositoryProvider.overrideWithValue(repository),
          setlistRepositoryProvider.overrideWithValue(
            _FakeSetlistRepository(<SongSetlist>[setlist]),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _rootThenList(
          SetlistListScreenV2(
            controller: container.read(setlistControllerProvider),
            clock: container.read(songTrainerClockProvider),
            songRepository: container.read(songRepositoryProvider),
            sessionLauncher: container.read(songTrainerSessionLauncherProvider),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open list'));
      await tester.pumpAndSettle();
      expect(find.byType(SetlistListScreenV2), findsOneWidget);

      await tester.tap(find.byKey(Key('setlist-start-practice-${setlist.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(SetlistSessionScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(SetlistListScreenV2), findsOneWidget);
      expect(find.byType(SetlistSessionScreen), findsNothing);
      expect(
        find.text('app root'),
        findsNothing,
        reason: 'popping the session must land on the list, not the root',
      );
    },
  );
}

SongSetlist _oneItemSetlist({required SongId songId, SongSetlistItem? item}) {
  final now = DateTime.utc(2026, 9, 19);
  return SongSetlist(
    id: 'setlist-wiring',
    name: 'Wiring setlist',
    createdAt: now,
    updatedAt: now,
    items: <SongSetlistItem>[
      item ?? SongSetlistItem(id: 'item-1', songId: songId),
    ],
  );
}

Widget _app(Widget home) => MaterialApp(
  theme: SsLightTheme.data(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// Same as [_app], but attaches [container] via [UncontrolledProviderScope]
/// so a REAL `ConsumerStatefulWidget` reached deeper in the push chain
/// (`SongTrainerSessionRoute`) resolves against the SAME, already-overridden
/// container instead of throwing for a missing `ProviderScope`.
Widget _appWithContainer(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(container: container, child: _app(home));

/// A distinguishable root beneath the list, so A7 can tell "back to the
/// list" apart from "popped all the way to the root" — the two would look
/// identical if the list were the `home:` route itself.
Widget _rootThenList(Widget list) => MaterialApp(
  theme: SsLightTheme.data(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => list)),
          child: const Text('open list'),
        ),
      ),
    ),
  ),
);

final class _FakeSetlistRepository implements SetlistRepository {
  _FakeSetlistRepository(List<SongSetlist> initial)
    : _setlists = <String, SongSetlist>{
        for (final setlist in initial) setlist.id: setlist,
      };

  final Map<String, SongSetlist> _setlists;

  @override
  Future<AppResult<List<SongSetlist>>> list() async =>
      AppResult<List<SongSetlist>>.success(_setlists.values.toList());

  @override
  Future<AppResult<SongSetlist?>> get(String id) async =>
      AppResult<SongSetlist?>.success(_setlists[id]);

  @override
  Future<AppResult<void>> save(SongSetlist setlist) async {
    _setlists[setlist.id] = setlist;
    return const AppResult<void>.success(null);
  }

  @override
  Future<AppResult<void>> delete(String id) async {
    _setlists.remove(id);
    return const AppResult<void>.success(null);
  }
}
