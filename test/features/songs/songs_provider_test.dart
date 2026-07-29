import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/songs/model/song.dart';
import 'package:strumsight/features/songs/providers/songs_provider.dart';

import '../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const d = StrumDirection.down;

  // One store shared by every container in a test: the songbook is persisted
  // in it, so a "fresh container" reads what the previous one wrote (E01-R07).
  late InMemoryKeyValueStore store;
  setUp(() => store = InMemoryKeyValueStore());

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    addTearDown(c.dispose);
    return c;
  }

  test('add inserts newest-first and returns a unique id', () async {
    final c = container();
    final ctrl = c.read(songsProvider.notifier);
    final id1 = await ctrl.add(
      name: 'One',
      chords: ['G'],
      pattern: [d],
      bpm: 90,
    );
    final id2 = await ctrl.add(
      name: 'Two',
      chords: ['C'],
      pattern: [d],
      bpm: 90,
    );
    expect(id1, isNot(id2));
    final songs = c.read(songsProvider);
    expect(songs.map((s) => s.name), ['Two', 'One']); // newest first
  });

  test('update replaces by id; unknown id is a no-op', () async {
    final c = container();
    final ctrl = c.read(songsProvider.notifier);
    final id = await ctrl.add(
      name: 'One',
      chords: ['G'],
      pattern: [d],
      bpm: 90,
    );
    final original = c.read(songsProvider).first;
    await ctrl.update(original.copyWith(name: 'Renamed', bpm: 120));
    expect(c.read(songsProvider).single.name, 'Renamed');
    expect(c.read(songsProvider).single.bpm, 120);
    expect(c.read(songsProvider).single.id, id);

    await ctrl.update(
      const Song(id: 'ghost', name: 'x', chords: ['A'], pattern: [d], bpm: 90),
    );
    expect(c.read(songsProvider).length, 1); // no ghost added
  });

  test('remove deletes by id', () async {
    final c = container();
    final ctrl = c.read(songsProvider.notifier);
    final id = await ctrl.add(
      name: 'One',
      chords: ['G'],
      pattern: [d],
      bpm: 90,
    );
    await ctrl.remove(id);
    expect(c.read(songsProvider), isEmpty);
  });

  test('restore re-inserts a removed song at its original position', () async {
    final c = container();
    final ctrl = c.read(songsProvider.notifier);
    // List order after adds (newest-first): [Three, Two, One].
    await ctrl.add(name: 'One', chords: ['G'], pattern: [d], bpm: 90);
    await ctrl.add(name: 'Two', chords: ['C'], pattern: [d], bpm: 90);
    await ctrl.add(name: 'Three', chords: ['D'], pattern: [d], bpm: 90);

    final middle = c.read(songsProvider)[1]; // 'Two' at index 1
    await ctrl.remove(middle.id);
    expect(c.read(songsProvider).map((s) => s.name), ['Three', 'One']);

    // Undo → back at index 1 with all fields intact.
    await ctrl.restore(1, middle);
    expect(c.read(songsProvider).map((s) => s.name), ['Three', 'Two', 'One']);
    expect(c.read(songsProvider)[1].id, middle.id);

    // Idempotent: restoring an already-present song is a no-op.
    await ctrl.restore(1, middle);
    expect(c.read(songsProvider).length, 3);
  });

  test('songs persist across a fresh container', () async {
    final c1 = container();
    await c1
        .read(songsProvider.notifier)
        .add(
          name: 'Persisted',
          chords: ['Em', 'G'],
          pattern: [d, null],
          bpm: 100,
        );

    // A new container re-reads the stored document — synchronously, in build.
    final loaded = container().read(songsProvider);
    expect(loaded.single.name, 'Persisted');
    expect(loaded.single.chords, ['Em', 'G']);
  });
}
