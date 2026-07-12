import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/progress/model/practice_entry.dart';
import 'package:music_theory/features/progress/providers/practice_log_provider.dart';
import 'package:music_theory/features/songs/providers/songs_provider.dart';
import 'package:music_theory/features/streak/providers/streak_provider.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 158 probe (b): the r149/r150 load-gate Completers live on the
/// notifier INSTANCE. `ref.invalidate` must not re-run `_load` on an
/// already-completed Completer (StateError) nor leave the write gate stuck.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('invalidate + mutate works on every gated store', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    // First lifecycle: touch + mutate.
    await c.read(practiceLogProvider.notifier).record(PracticeEntry(
        day: 20000,
        source: PracticeSource.live,
        seconds: 60,
        strokes: 5));
    await c.read(streakProvider.notifier).recordPracticeToday();
    await c
        .read(songsProvider.notifier)
        .add(name: 'S', chords: const ['C'], pattern: const [
      StrumDirection.down, null, null, null, null, null, null, null,
    ], bpm: 90);

    // Invalidate → the providers rebuild; a second full lifecycle must work.
    c.invalidate(practiceLogProvider);
    c.invalidate(streakProvider);
    c.invalidate(songsProvider);
    await Future<void>.delayed(Duration.zero);

    await c.read(practiceLogProvider.notifier).record(PracticeEntry(
        day: 20001,
        source: PracticeSource.learn,
        seconds: 30,
        strokes: 3));
    expect(c.read(practiceLogProvider).length, 2,
        reason: 'post-invalidate record must merge with the persisted entry');
    await c
        .read(songsProvider.notifier)
        .add(name: 'T', chords: const ['G'], pattern: const [
      StrumDirection.down, null, null, null, null, null, null, null,
    ], bpm: 80);
    expect(c.read(songsProvider).length, 2);
  });
}
