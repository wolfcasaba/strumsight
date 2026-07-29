import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/chords/providers/favorite_chords_provider.dart';
import 'package:strumsight/features/learn/providers/lesson_progress_provider.dart';
import 'package:strumsight/features/library/model/analyzed_session.dart';
import 'package:strumsight/features/library/providers/library_providers.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/songs/model/setlist.dart';
import 'package:strumsight/features/songs/model/song.dart';
import 'package:strumsight/features/songs/providers/setlists_provider.dart';
import 'package:strumsight/features/songs/providers/songs_provider.dart';
import 'package:strumsight/features/streak/model/streak_data.dart';
import 'package:strumsight/features/streak/providers/streak_provider.dart';

import '../support/preference_store.dart';

/// Round 150 sweep — the r149 race class across every COLLECTION store: a
/// mutation must never wipe what is already stored.
///
/// Since E01-R07 the class is structurally gone rather than guarded: every one
/// of these stores is read **synchronously** in `build()` from the injected
/// key-value store, so there is no "empty default now, stored data later"
/// window for a mutation to fall into (the `Completer` gates were deleted with
/// the async loads that needed them). The sweep stays as the regression proof
/// of the invariant it was written for: a cold-start mutation merges onto the
/// stored data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container(Map<String, Object> stored) {
    final c = ProviderContainer(overrides: preferenceOverrides(stored));
    addTearDown(c.dispose);
    return c;
  }

  test('streak: a cold-start practice EXTENDS the stored streak', () async {
    const old = StreakData(
      current: 7,
      longest: 9,
      lastPracticeDay: 20643,
      freezes: 1,
    );
    final c = container({StorageKeys.streak: storedDocument(old.toJson())});
    // Record for the day AFTER the stored last practice.
    final advanced = await c
        .read(streakProvider.notifier)
        .recordPracticeToday(
          DateTime.fromMillisecondsSinceEpoch(
            (20644 * 24 * 3600 + 12 * 3600) * 1000,
            isUtc: true,
          ),
        );
    expect(advanced, isTrue);
    expect(
      c.read(streakProvider).current,
      8,
      reason: 'a 7-day streak must become 8, never reset to 1',
    );
  });

  test('lesson progress: a cold-start record keeps other lessons', () async {
    final c = container({
      StorageKeys.lessonProgress: storedDocument({'old-lesson': 0.9}),
    });
    await c.read(lessonProgressProvider.notifier).record('new-lesson', 0.8);
    final map = c.read(lessonProgressProvider);
    expect(
      map['old-lesson'],
      0.9,
      reason: 'other lessons\' stars must survive',
    );
    expect(map['new-lesson'], 0.8);
  });

  test('songs: a cold-start add keeps the saved songbook', () async {
    final old = Song(
      id: 'old',
      name: 'Old song',
      chords: const ['C'],
      pattern: const [
        StrumDirection.down,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
      ],
      bpm: 100,
    );
    final c = container({
      StorageKeys.songs: storedCollection([old.toJson()]),
    });
    await c
        .read(songsProvider.notifier)
        .add(
          name: 'New song',
          chords: const ['G'],
          pattern: const [
            StrumDirection.down,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
          ],
          bpm: 90,
        );
    expect(
      c.read(songsProvider).map((s) => s.name),
      containsAll(['Old song', 'New song']),
    );
  });

  test('setlists: a cold-start add keeps the saved sets', () async {
    const old = Setlist(id: 'old', name: 'Old set', songIds: ['a']);
    final c = container({
      StorageKeys.setlists: storedCollection([old.toJson()]),
    });
    await c.read(setlistsProvider.notifier).add('New set');
    expect(
      c.read(setlistsProvider).map((s) => s.name),
      containsAll(['Old set', 'New set']),
    );
  });

  test('favourites: a cold-start toggle keeps other pins', () async {
    final c = container({
      StorageKeys.favoriteChords: <String>['Am', 'G7'],
    });
    await c.read(favoriteChordsProvider.notifier).toggle('C');
    expect(c.read(favoriteChordsProvider), containsAll({'Am', 'G7', 'C'}));
  });

  test('library: a cold-start add keeps the saved sessions', () async {
    final old = AnalyzedSession(
      id: 'old',
      title: 'Old take',
      createdAt: DateTime.utc(2026, 7, 1),
      result: AnalyzeResult.empty,
    );
    final c = container({
      StorageKeys.librarySessions: storedCollection([old.toJson()]),
    });
    final fresh = AnalyzedSession(
      id: 'new',
      title: 'New take',
      createdAt: DateTime.utc(2026, 7, 12),
      result: AnalyzeResult.empty,
    );
    await c.read(libraryProvider.notifier).add(fresh);
    final list = c.read(libraryProvider).value!;
    expect(
      list.map((s) => s.id),
      containsAll(['old', 'new']),
      reason: 'the stored library must survive an add-from-Analyze',
    );
  });
}
