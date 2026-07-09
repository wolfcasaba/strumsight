import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/songs/model/song.dart';
import 'package:music_theory/features/songs/providers/songs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const d = StrumDirection.down;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('add inserts newest-first and returns a unique id', () async {
    final c = container();
    final ctrl = c.read(songsProvider.notifier);
    final id1 = await ctrl.add(name: 'One', chords: ['G'], pattern: [d], bpm: 90);
    final id2 = await ctrl.add(name: 'Two', chords: ['C'], pattern: [d], bpm: 90);
    expect(id1, isNot(id2));
    final songs = c.read(songsProvider);
    expect(songs.map((s) => s.name), ['Two', 'One']); // newest first
  });

  test('update replaces by id; unknown id is a no-op', () async {
    final c = container();
    final ctrl = c.read(songsProvider.notifier);
    final id = await ctrl.add(name: 'One', chords: ['G'], pattern: [d], bpm: 90);
    final original = c.read(songsProvider).first;
    await ctrl.update(original.copyWith(name: 'Renamed', bpm: 120));
    expect(c.read(songsProvider).single.name, 'Renamed');
    expect(c.read(songsProvider).single.bpm, 120);
    expect(c.read(songsProvider).single.id, id);

    await ctrl.update(const Song(
        id: 'ghost', name: 'x', chords: ['A'], pattern: [d], bpm: 90));
    expect(c.read(songsProvider).length, 1); // no ghost added
  });

  test('remove deletes by id', () async {
    final c = container();
    final ctrl = c.read(songsProvider.notifier);
    final id = await ctrl.add(name: 'One', chords: ['G'], pattern: [d], bpm: 90);
    await ctrl.remove(id);
    expect(c.read(songsProvider), isEmpty);
  });

  test('songs persist across a fresh container (shared_preferences)', () async {
    final c1 = container();
    await c1.read(songsProvider.notifier).add(
        name: 'Persisted', chords: ['Em', 'G'], pattern: [d, null], bpm: 100);

    // A new container re-reads from prefs.
    final c2 = container();
    // Force build + let the async _load complete.
    c2.read(songsProvider);
    await Future<void>.delayed(Duration.zero);
    final loaded = c2.read(songsProvider);
    expect(loaded.single.name, 'Persisted');
    expect(loaded.single.chords, ['Em', 'G']);
  });
}
