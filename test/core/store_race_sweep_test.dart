import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/chords/providers/favorite_chords_provider.dart';
import 'package:music_theory/features/learn/providers/lesson_progress_provider.dart';
import 'package:music_theory/features/library/providers/library_providers.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/library/model/analyzed_session.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/songs/model/setlist.dart';
import 'package:music_theory/features/songs/model/song.dart';
import 'package:music_theory/features/songs/providers/setlists_provider.dart';
import 'package:music_theory/features/songs/providers/songs_provider.dart';
import 'package:music_theory/features/streak/model/streak_data.dart';
import 'package:music_theory/features/streak/providers/streak_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 150 sweep — the r149 race class across every COLLECTION store: a
/// mutation racing the initial prefs load must never wipe the on-disk data
/// (the old `_dirty`/`_userSet` guards skipped the disk read while the
/// mutation's persist overwrote the blob).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('streak: a cold-start practice EXTENDS the loaded streak', () async {
    const old = StreakData(
        current: 7, longest: 9, lastPracticeDay: 20643, freezes: 1);
    SharedPreferences.setMockInitialValues({
      'practice_streak_v1': jsonEncode(old.toJson()),
    });
    final c = container();
    // Record for the day AFTER the stored last practice — before load lands.
    final advanced = await c
        .read(streakProvider.notifier)
        .recordPracticeToday(DateTime.fromMillisecondsSinceEpoch(
            (20644 * 24 * 3600 + 12 * 3600) * 1000,
            isUtc: true));
    expect(advanced, isTrue);
    expect(c.read(streakProvider).current, 8,
        reason: 'a 7-day streak must become 8, never reset to 1');
  });

  test('lesson progress: a cold-start record keeps other lessons', () async {
    SharedPreferences.setMockInitialValues({
      'lesson_progress_v1': jsonEncode({'old-lesson': 0.9}),
    });
    final c = container();
    await c.read(lessonProgressProvider.notifier).record('new-lesson', 0.8);
    final map = c.read(lessonProgressProvider);
    expect(map['old-lesson'], 0.9,
        reason: 'other lessons\' stars must survive');
    expect(map['new-lesson'], 0.8);
  });

  test('songs: a cold-start add keeps the saved songbook', () async {
    final old = Song(
        id: 'old',
        name: 'Old song',
        chords: const ['C'],
        pattern: const [StrumDirection.down, null, null, null, null, null, null, null],
        bpm: 100);
    SharedPreferences.setMockInitialValues({
      'user_songs_v1': jsonEncode([old.toJson()]),
    });
    final c = container();
    await c.read(songsProvider.notifier).add(
        name: 'New song',
        chords: const ['G'],
        pattern: const [StrumDirection.down, null, null, null, null, null, null, null],
        bpm: 90);
    expect(c.read(songsProvider).map((s) => s.name),
        containsAll(['Old song', 'New song']));
  });

  test('setlists: a cold-start add keeps the saved sets', () async {
    const old = Setlist(id: 'old', name: 'Old set', songIds: ['a']);
    SharedPreferences.setMockInitialValues({
      'user_setlists_v1': jsonEncode([old.toJson()]),
    });
    final c = container();
    await c.read(setlistsProvider.notifier).add('New set');
    expect(c.read(setlistsProvider).map((s) => s.name),
        containsAll(['Old set', 'New set']));
  });

  test('favourites: a cold-start toggle keeps other pins', () async {
    SharedPreferences.setMockInitialValues({
      'favorite_chords': ['Am', 'G7'],
    });
    final c = container();
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
    SharedPreferences.setMockInitialValues({
      'library_sessions': jsonEncode([old.toJson()]),
    });
    final c = container();
    final fresh = AnalyzedSession(
      id: 'new',
      title: 'New take',
      createdAt: DateTime.utc(2026, 7, 12),
      result: AnalyzeResult.empty,
    );
    await c.read(libraryProvider.notifier).add(fresh);
    final list = c.read(libraryProvider).value!;
    expect(list.map((s) => s.id), containsAll(['old', 'new']),
        reason: 'the on-disk library must survive an add-from-Analyze');
  });
}
