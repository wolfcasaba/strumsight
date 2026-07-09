import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/songs/providers/setlists_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('add / addSong / removeAt', () async {
    final c = container();
    final ctrl = c.read(setlistsProvider.notifier);
    final id = await ctrl.add('Gig');
    await ctrl.addSong(id, 'song1');
    await ctrl.addSong(id, 'song2');
    await ctrl.addSong(id, 'song1'); // duplicates allowed
    expect(c.read(setlistsProvider).single.songIds, ['song1', 'song2', 'song1']);

    await ctrl.removeAt(id, 1);
    expect(c.read(setlistsProvider).single.songIds, ['song1', 'song1']);
  });

  test('reorder moves an item using ReorderableListView semantics', () async {
    final c = container();
    final ctrl = c.read(setlistsProvider.notifier);
    final id = await ctrl.add('Set');
    for (final s in ['x', 'y', 'z']) {
      await ctrl.addSong(id, s);
    }
    // Move index 0 (x) to the end (newIndex = length = 3).
    await ctrl.reorder(id, 0, 3);
    expect(c.read(setlistsProvider).single.songIds, ['y', 'z', 'x']);
    // Move index 2 (x) back to the front.
    await ctrl.reorder(id, 2, 0);
    expect(c.read(setlistsProvider).single.songIds, ['x', 'y', 'z']);
  });

  test('rename + remove', () async {
    final c = container();
    final ctrl = c.read(setlistsProvider.notifier);
    final id = await ctrl.add('Old');
    await ctrl.rename(id, 'New');
    expect(c.read(setlistsProvider).single.name, 'New');
    await ctrl.remove(id);
    expect(c.read(setlistsProvider), isEmpty);
  });

  test('persists across a fresh container', () async {
    final c1 = container();
    final id = await c1.read(setlistsProvider.notifier).add('Persisted');
    await c1.read(setlistsProvider.notifier).addSong(id, 'song1');

    final c2 = container();
    c2.read(setlistsProvider);
    await Future<void>.delayed(Duration.zero);
    expect(c2.read(setlistsProvider).single.name, 'Persisted');
    expect(c2.read(setlistsProvider).single.songIds, ['song1']);
  });
}
