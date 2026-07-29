import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/learn/data/lesson_progress_repository.dart';
import 'package:strumsight/features/learn/providers/lesson_progress_provider.dart';
import 'package:strumsight/features/library/data/library_repository.dart';
import 'package:strumsight/features/library/model/analyzed_session.dart';
import 'package:strumsight/features/library/providers/library_providers.dart';
import 'package:strumsight/features/live/model/strum.dart';
import 'package:strumsight/features/progress/data/practice_log_repository.dart';
import 'package:strumsight/features/progress/model/practice_entry.dart';
import 'package:strumsight/features/progress/providers/practice_log_provider.dart';
import 'package:strumsight/features/songs/data/setlists_repository.dart';
import 'package:strumsight/features/songs/data/songs_repository.dart';
import 'package:strumsight/features/songs/model/song.dart';
import 'package:strumsight/features/songs/providers/setlists_provider.dart';
import 'package:strumsight/features/songs/providers/songs_provider.dart';
import 'package:strumsight/features/streak/data/streak_repository.dart';
import 'package:strumsight/features/streak/model/streak_data.dart';
import 'package:strumsight/features/streak/providers/streak_provider.dart';

import '../../support/preference_store.dart';

/// E01-R07 — the six user-content documents, through the repositories the
/// features now depend on.
///
/// What is being pinned down: a corrupt record costs the user THAT record and
/// nothing else (§7.4), each document has a documented and enforced size bound
/// (§7.5), and a returning user's pre-envelope data is still read (the failed-
/// migration safety net).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container([Map<String, Object>? stored]) {
    final c = ProviderContainer(overrides: preferenceOverrides(stored));
    addTearDown(c.dispose);
    return c;
  }

  Map<String, dynamic> songJson(String id) => {
    'id': id,
    'name': 'Song $id',
    'chords': ['C'],
    'pat': 'd-------',
    'bpm': 90,
    'bpb': 4,
  };

  Map<String, dynamic> sessionJson(String id) => {
    'id': id,
    'createdAt': '2026-07-12T10:00:00.000',
    'title': 'Take $id',
    'result': {
      'duration': 1.0,
      'bpm': 90.0,
      'chords': <Object>[],
      'strums': <Object>[],
      'bpb': 4,
    },
  };

  group('one corrupt record never costs the whole document (§7.4)', () {
    test('songs: the readable songs still load', () {
      final c = container({
        StorageKeys.songs: storedCollection([
          songJson('a'),
          {'id': 'broken'}, // no chords / pattern / bpm
          songJson('b'),
        ]),
      });
      expect(c.read(songsProvider).map((s) => s.id), ['a', 'b']);
    });

    test('library: the readable sessions still load', () async {
      final c = container({
        StorageKeys.librarySessions: storedCollection([
          sessionJson('1'),
          {'id': '2', 'createdAt': 'not-a-date', 'title': 'x', 'result': {}},
          sessionJson('3'),
        ]),
      });
      final loaded = await c.read(libraryProvider.future);
      expect(loaded.map((s) => s.id), ['1', '3']);
    });

    test('practice log: the readable moments still load', () {
      final c = container({
        StorageKeys.practiceLog: storedCollection([
          {'day': 20000, 'src': 'live', 'sec': 60},
          {'src': 'live'}, // no day
          {'day': 20001, 'src': 'learn', 'sec': 30},
        ]),
      });
      expect(c.read(practiceLogProvider).map((e) => e.day), [20000, 20001]);
    });

    test('setlists: the readable sets still load', () {
      final c = container({
        StorageKeys.setlists: storedCollection([
          {'id': 'l1', 'name': 'Gig', 'songs': <String>[]},
          {'name': 'no id', 'songs': <String>[]},
        ]),
      });
      expect(c.read(setlistsProvider).single.id, 'l1');
    });

    test('lesson progress: one impossible score does not clear the stars', () {
      final c = container({
        StorageKeys.lessonProgress: storedDocument({
          'first-strums': 0.9,
          'broken': 'not a number',
          'over': 4.2,
          'two-chord-change': 0.75,
        }),
      });
      expect(c.read(lessonProgressProvider), {
        'first-strums': 0.9,
        'two-chord-change': 0.75,
      });
    });

    test('streak: a corrupt document falls back to a fresh streak', () {
      final c = container({
        StorageKeys.streak: storedDocument({'current': -3}),
      });
      expect(c.read(streakProvider), const StreakData());
    });
  });

  group('documented size bounds (§7.5)', () {
    test('the caps are the ones the docs and the UI agree on', () {
      expect(LibraryRepository.maxSessions, 100);
      expect(PracticeLogRepository.maxEntries, 400);
      expect(SongsRepository.maxSongs, 200);
      expect(SetlistsRepository.maxSetlists, 100);
      expect(LessonProgressRepository.maxLessons, 500);
    });

    test('an over-cap songbook is trimmed to the newest on load', () {
      final c = container({
        StorageKeys.songs: storedCollection([
          for (var i = 0; i < SongsRepository.maxSongs + 5; i++)
            songJson('s$i'),
        ]),
      });
      final songs = c.read(songsProvider);
      expect(songs, hasLength(SongsRepository.maxSongs));
      expect(songs.first.id, 's0', reason: 'newest-first: the head survives');
    });

    test(
      'adding at the cap evicts the oldest song, never the new one',
      () async {
        final c = container({
          StorageKeys.songs: storedCollection([
            for (var i = 0; i < SongsRepository.maxSongs; i++) songJson('s$i'),
          ]),
        });
        await c
            .read(songsProvider.notifier)
            .add(
              name: 'Newest',
              chords: const ['G'],
              pattern: const [StrumDirection.down],
              bpm: 90,
            );
        final songs = c.read(songsProvider);
        expect(songs, hasLength(SongsRepository.maxSongs));
        expect(songs.first.name, 'Newest');
        expect(songs.map((s) => s.id), isNot(contains('s199')));
      },
    );

    test('the practice log keeps the NEWEST entries at the cap', () async {
      final c = container({
        StorageKeys.practiceLog: storedCollection([
          for (var i = 0; i < PracticeLogRepository.maxEntries; i++)
            {'day': 20000 + i, 'src': 'live', 'sec': 10},
        ]),
      });
      await c
          .read(practiceLogProvider.notifier)
          .record(
            const PracticeEntry(day: 30000, source: PracticeSource.learn),
          );
      final log = c.read(practiceLogProvider);
      expect(log, hasLength(PracticeLogRepository.maxEntries));
      expect(log.last.day, 30000);
      expect(log.first.day, 20001, reason: 'the oldest moment falls off');
    });

    test('setlists are bounded too', () async {
      final c = container({
        StorageKeys.setlists: storedCollection([
          for (var i = 0; i < SetlistsRepository.maxSetlists; i++)
            {'id': 'l$i', 'name': 'Set $i', 'songs': <String>[]},
        ]),
      });
      await c.read(setlistsProvider.notifier).add('Newest');
      final sets = c.read(setlistsProvider);
      expect(sets, hasLength(SetlistsRepository.maxSetlists));
      expect(sets.first.name, 'Newest');
    });
  });

  group('a returning user keeps their data (legacy keys)', () {
    test(
      'a pre-envelope songbook is read and moved over on the next write',
      () async {
        final store = InMemoryKeyValueStore({
          LegacyStorageKeys.songs: jsonEncode([songJson('old')]),
        });
        final c = ProviderContainer(
          overrides: [preferenceStoreOverride(store)],
        );
        addTearDown(c.dispose);

        expect(c.read(songsProvider).single.id, 'old');

        await c
            .read(songsProvider.notifier)
            .add(
              name: 'New',
              chords: const ['G'],
              pattern: const [StrumDirection.down],
              bpm: 90,
            );
        expect(
          store.contains(LegacyStorageKeys.songs),
          isFalse,
          reason: 'the write completes the move the migration would have done',
        );
        expect(c.read(songsProvider).map((s) => s.name), ['New', 'Song old']);
      },
    );

    test('a pre-envelope streak is read', () {
      final c = container({
        LegacyStorageKeys.streak: jsonEncode(
          const StreakData(
            current: 5,
            longest: 6,
            lastPracticeDay: 20643,
          ).toJson(),
        ),
      });
      expect(c.read(streakProvider).current, 5);
    });
  });

  group('the repositories are usable on their own (§7.2)', () {
    test('a fake repository swaps in without touching the store', () async {
      final fake = _FakeSongsRepository([
        const Song(
          id: 'x',
          name: 'Injected',
          chords: ['C'],
          pattern: [StrumDirection.down],
          bpm: 90,
        ),
      ]);
      final c = ProviderContainer(
        overrides: [songsRepositoryProvider.overrideWithValue(fake)],
      );
      addTearDown(c.dispose);

      expect(c.read(songsProvider).single.name, 'Injected');
      await c.read(songsProvider.notifier).remove('x');
      expect(fake.saved.single, isEmpty);
    });

    test('the streak repository reports "nothing stored" as null', () {
      final c = container();
      expect(c.read(streakRepositoryProvider).load(), isNull);
    });

    test('a session round-trips through the library repository', () async {
      final c = container();
      final repo = c.read(libraryRepositoryProvider);
      final session = AnalyzedSession(
        id: 'r1',
        createdAt: DateTime.utc(2026, 7, 12),
        title: 'Round trip',
        result: AnalyzeResult.empty,
      );
      await repo.save([session]);
      final loaded = await repo.load();
      expect(loaded.single.title, 'Round trip');
      expect(loaded.single.createdAt, session.createdAt);
    });
  });
}

class _FakeSongsRepository implements SongsRepository {
  _FakeSongsRepository(this._songs);

  final List<Song> _songs;
  final List<List<Song>> saved = [];

  @override
  List<Song> load() => _songs;

  @override
  Future<void> save(List<Song> songs) async => saved.add(songs);
}
