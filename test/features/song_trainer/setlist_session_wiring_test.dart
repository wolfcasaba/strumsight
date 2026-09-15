// E17-R03 (ADR 0522) — the Setlist session is wired from the setlist DETAIL
// screen (§5.1) through ONE launcher whose mode is a parameter (§5.2 / A3);
// both modes run on the REAL `SetlistSessionController` over the real
// composition — availability from the real song repositories, per-item
// Stages from the shipped Song Trainer pipeline (A2) — and finishing pops
// back to the detail screen, not the root (A4).
//
// The `ProviderScope` mirrors `main.dart`'s seams with in-memory stores:
// `songRepositoryProvider` → `InMemorySongRepository`, the asset store → a
// no-op, plus the Stage's platform edges (audio player, live observation
// gateway, microphone permission) as fakes so no plugin channel is touched.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/data/practice_observation_gateway_provider.dart';
import 'package:strumsight/features/practice/public.dart'
    show practiceMicrophonePermissionProvider;
import 'package:strumsight/features/song_trainer/application/setlists/setlist_session_providers.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/local/in_memory_song_repository.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_song_adapter.dart';
import 'package:strumsight/features/song_trainer/data/migration/legacy_song_reader.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/setlist_result.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_setlist.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_asset_repository.dart';
import 'package:strumsight/features/song_trainer/domain/repositories/song_repository.dart'
    show SongQuery;
import 'package:strumsight/features/song_trainer/presentation/screens/setlist_session_screen.dart';
import 'package:strumsight/features/song_trainer/presentation/screens/song_trainer_screen.dart';
import 'package:strumsight/features/songs/model/setlist.dart';
import 'package:strumsight/features/songs/model/song.dart';
import 'package:strumsight/features/songs/providers/setlists_provider.dart';
import 'package:strumsight/features/songs/providers/songs_provider.dart';
import 'package:strumsight/features/songs/screens/setlist_detail_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_practice_observation_gateway.dart';
import '../../support/preference_store.dart';

const _entry = Key('setlist-session-entry');
const _practiceTile = Key('setlist-session-mode-practice');
const _performanceTile = Key('setlist-session-mode-performance');
const _start = Key('setlist-session-start');

const _pattern = <StrumDirection?>[
  StrumDirection.down, null, StrumDirection.down, null, //
  StrumDirection.down, null, StrumDirection.down, null,
];

/// Lives ONLY in the legacy songbook — the composer must adapt it in memory.
const _legacyOnly = Song(
  id: 'a',
  name: 'First Song',
  chords: ['C', 'G'],
  pattern: _pattern,
  bpm: 100,
);

/// Lives ONLY in the V2 store — the composer must find it there.
const _v2Only = Song(
  id: 'b',
  name: 'Second Song',
  chords: ['G', 'D'],
  pattern: _pattern,
  bpm: 90,
);

/// Referenced by the setlist, present nowhere — must resolve `missingSong`.
const _ghostId = 'ghost';

const _setlistName = 'My Gig';
const _songIds = <String>['a', 'b', _ghostId];
const _setlist = Setlist(id: 's', name: _setlistName, songIds: _songIds);

final DateTime _fixedNow = DateTime.utc(2026, 9, 15);

SongDocument _adapted(Song song) => const LegacySongAdapter()
    .adapt(
      const LegacySongReader().readSong(song.toJson()),
      importedAt: _fixedNow,
    )
    .document;

class _SeededSongs extends SongsController {
  _SeededSongs(this._seed);
  final List<Song> _seed;
  @override
  List<Song> build() {
    super.build(); // opens the r150 write gate (mock prefs are empty)
    return _seed;
  }
}

class _SeededSetlists extends SetlistsController {
  _SeededSetlists(this._seed);
  final List<Setlist> _seed;
  @override
  List<Setlist> build() {
    super.build(); // opens the r150 write gate (mock prefs are empty)
    return _seed;
  }
}

final class _NoopAssetRepository implements SongAssetRepository {
  const _NoopAssetRepository();

  @override
  Future<AppResult<SongAssetStoreReceipt>> put(SongAssetWriteRequest request) =>
      throw UnimplementedError();
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

AppConfig _config({required bool songTrainerV2Enabled}) => AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    accountEnabled: false,
    diagnosticsEnabled: true,
    labModeAvailable: true,
    songTrainerV2Enabled: songTrainerV2Enabled,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

/// A V2 store holding ONLY [_v2Only], so `a` must come from the legacy
/// songbook and `ghost` from nowhere.
Future<InMemorySongRepository> _v2Store() async {
  final repository = InMemorySongRepository(clock: () => _fixedNow);
  final created = await repository.create(_adapted(_v2Only));
  expect(created.isFailure, isFalse);
  return repository;
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required InMemorySongRepository v2,
  bool songTrainerV2Enabled = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...preferenceOverrides(),
        appConfigProvider.overrideWithValue(
          _config(songTrainerV2Enabled: songTrainerV2Enabled),
        ),
        songsProvider.overrideWith(() => _SeededSongs(const [_legacyOnly])),
        setlistsProvider.overrideWith(() => _SeededSetlists(const [_setlist])),
        // The seams main.dart wires, with in-memory stores.
        songRepositoryProvider.overrideWithValue(v2),
        songAssetRepositoryProvider.overrideWithValue(
          const _NoopAssetRepository(),
        ),
        // The Stage's platform edges.
        backingAudioPlayerProvider.overrideWith(
          (ref) => FakeBackingAudioPlayer(),
        ),
        livePracticeObservationGatewayProvider.overrideWith(
          (ref) => FakePracticeObservationGateway(),
        ),
        practiceMicrophonePermissionProvider.overrideWith(
          (ref) => FakeMicrophonePermissionGateway(),
        ),
      ],
      child: MaterialApp(
        theme: SsLightTheme.data(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SetlistDetailScreen(setlistId: 's'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The Stage keeps an indefinite animation alive (skeleton shimmer) and the
/// running session list spins — `pumpAndSettle` would never settle, so route
/// transitions are advanced with fixed pumps.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Leaves the Stage on top the way a guitarist does: back.
Future<void> _leaveStage(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(SongTrainerScreen))).pop();
  await _settleRoute(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A3 — one launcher, the mode is a parameter', () {
    testWidgets('the detail offers exactly one session entry whose chooser '
        'lists both modes', (tester) async {
      await _pumpDetail(tester, v2: await _v2Store());

      expect(find.byKey(_entry), findsOneWidget);
      // The legacy "Play set" path is untouched next to it.
      expect(find.widgetWithText(FilledButton, 'Play set'), findsOneWidget);

      await tester.tap(find.byKey(_entry));
      await tester.pumpAndSettle();

      expect(find.byKey(_practiceTile), findsOneWidget);
      expect(find.byKey(_performanceTile), findsOneWidget);
      expect(find.byType(SetlistSessionScreen), findsNothing);
    });

    testWidgets('flag OFF hides the session entry and keeps Play set', (
      tester,
    ) async {
      await _pumpDetail(
        tester,
        v2: await _v2Store(),
        songTrainerV2Enabled: false,
      );

      expect(find.byKey(_entry), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Play set'), findsOneWidget);
    });
  });

  group('A2 / A4 — both modes run on the real controller and return', () {
    for (final mode in SetlistSessionMode.values) {
      final tile = mode == SetlistSessionMode.practice
          ? _practiceTile
          : _performanceTile;
      final title = mode == SetlistSessionMode.practice
          ? 'Setlist practice'
          : 'Setlist performance';

      testWidgets('${mode.name}: the detail starts the session, availability '
          'comes from the real repositories, each ready item gets its Stage, '
          'and completion pops back to the detail', (tester) async {
        await _pumpDetail(tester, v2: await _v2Store());

        await tester.tap(find.byKey(_entry));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(tile));
        await tester.pumpAndSettle();

        // The session screen runs THIS mode.
        expect(find.byType(SetlistSessionScreen), findsOneWidget);
        expect(find.text(title), findsOneWidget);
        expect(
          tester.widget<SetlistSessionScreen>(
            find.byType(SetlistSessionScreen),
          ).mode,
          mode,
        );

        // Availability from the real repositories, not a constant (§9):
        // `a` (legacy songbook) and `b` (V2 store) are ready, `ghost` is not.
        expect(find.text('Ready'), findsNWidgets(2));
        expect(find.text('Needs repair before it can run'), findsOneWidget);

        // Start → the first ready item's Stage is pushed over the session.
        await tester.tap(find.byKey(_start));
        await _settleRoute(tester);
        var stage = tester.widget<SongTrainerScreen>(
          find.byType(SongTrainerScreen),
        );
        expect(stage.songId, _legacyOnly.id);
        expect(
          stage.inputs!.compilation.isPlaybackOnly,
          mode == SetlistSessionMode.performance,
          reason:
              'Performance stays playback-only; practice compiles scored '
              'inputs from the same document.',
        );

        // Leaving the Stage resolves the item; the next ready item follows.
        await _leaveStage(tester);
        stage = tester.widget<SongTrainerScreen>(
          find.byType(SongTrainerScreen),
        );
        expect(stage.songId, _v2Only.id);

        // Leaving the last Stage completes the run: the missing item was
        // skipped by the real controller, and the session returns to THIS
        // detail screen — not the root (A4).
        await _leaveStage(tester);
        await tester.pumpAndSettle();
        expect(find.byType(SongTrainerScreen), findsNothing);
        expect(find.byType(SetlistSessionScreen), findsNothing);
        expect(find.byType(SetlistDetailScreen), findsOneWidget);
        expect(find.text('Completed 2 of 3 songs.'), findsOneWidget);
      });
    }
  });

  group('SetlistSessionComposer — composition over real repositories', () {
    late InMemorySongRepository v2;
    late SetlistSessionComposer composer;

    setUp(() async {
      v2 = await _v2Store();
      composer = SetlistSessionComposer(songs: v2, clock: () => _fixedNow);
    });

    test(
      'resolves V2, legacy-only and unknown ids honestly and projects the '
      'legacy setlist with persistV2\'s ids without persisting',
      () async {
        final composition = await composer.compose(
          legacySetlist: const LegacySetlistRecord(
            id: 'My Gig 1',
            name: _setlistName,
            songIds: _songIds,
          ),
          legacySongs: [_legacyOnly.toJson()],
          presentStage: (_) async => Duration.zero,
        );

        final setlist = composition.setlist;
        expect(setlist.id, SongIdValidator.safeFilename('My Gig 1'));
        expect(setlist.name, _setlistName);
        expect(setlist.items.map((item) => item.id), [
          '${setlist.id}-0',
          '${setlist.id}-1',
          '${setlist.id}-2',
        ]);
        expect(setlist.items.map(composition.availability), [
          SetlistItemAvailability.ready,
          SetlistItemAvailability.ready,
          SetlistItemAvailability.missingSong,
        ]);
        // Nothing was written to the V2 store.
        final listed = await v2.list(const SongQuery());
        expect(listed.valueOrNull, hasLength(1));
      },
    );

    test(
      'a blank legacy name falls back to the id instead of throwing',
      () async {
        final composition = await composer.compose(
          legacySetlist: const LegacySetlistRecord(
            id: 'unnamed',
            name: '   ',
            songIds: [],
          ),
          legacySongs: const [],
          presentStage: (_) async => Duration.zero,
        );
        expect(composition.setlist.name, 'unnamed');
        expect(composition.setlist.items, isEmpty);
      },
    );

    test(
      'performance runner presents playback-only inputs and reports the '
      'presenter\'s duration; practice runner compiles scored inputs from '
      'the same document',
      () async {
        final presented = <SetlistItemStage>[];
        final composition = await composer.compose(
          legacySetlist: const LegacySetlistRecord(
            id: 's',
            name: 'My Gig',
            songIds: ['a', 'b'],
          ),
          legacySongs: [_legacyOnly.toJson()],
          presentStage: (stage) async {
            presented.add(stage);
            return const Duration(seconds: 42);
          },
        );
        final items = composition.setlist.items;

        final performance = await composition.performanceRunner(items[0]);
        expect(performance.status, SetlistItemResultStatus.completed);
        expect(performance.itemId, items[0].id);
        expect(performance.activeDuration, const Duration(seconds: 42));
        expect(presented.single.inputs.compilation.isPlaybackOnly, isTrue);
        expect(presented.single.document.id, SongId(_legacyOnly.id));

        presented.clear();
        final practice = await composition.createPracticeRunner()(items[1]);
        expect(practice.status, SetlistItemResultStatus.completed);
        expect(practice.itemId, items[1].id);
        expect(presented.single.inputs.compilation.isPlaybackOnly, isFalse);
        expect(presented.single.document.id, SongId(_v2Only.id));
      },
    );

    test('a runner asked for an unresolved item skips it as missingSong '
        'without presenting a Stage', () async {
      var presentations = 0;
      final composition = await composer.compose(
        legacySetlist: const LegacySetlistRecord(
          id: 's',
          name: 'My Gig',
          songIds: [_ghostId],
        ),
        legacySongs: const [],
        presentStage: (_) async {
          presentations++;
          return Duration.zero;
        },
      );
      final item = composition.setlist.items.single;

      final performance = await composition.performanceRunner(item);
      final practice = await composition.createPracticeRunner()(item);

      expect(performance.status, SetlistItemResultStatus.skipped);
      expect(performance.availability, SetlistItemAvailability.missingSong);
      expect(practice.status, SetlistItemResultStatus.skipped);
      expect(presentations, 0);
    });
  });
}
