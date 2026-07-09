import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/streak/providers/streak_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('records practice once per day and advances across days', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(streakProvider.notifier);

    expect(c.read(streakProvider).current, 0);

    expect(await n.recordPracticeToday(DateTime(2026, 7, 9, 10)), isTrue);
    expect(c.read(streakProvider).current, 1);

    // Same day again → no advance.
    expect(await n.recordPracticeToday(DateTime(2026, 7, 9, 22)), isFalse);
    expect(c.read(streakProvider).current, 1);

    // Next day → advance.
    expect(await n.recordPracticeToday(DateTime(2026, 7, 10, 8)), isTrue);
    expect(c.read(streakProvider).current, 2);
  });

  test('streak persists across a fresh controller (shared_preferences)',
      () async {
    final c1 = ProviderContainer();
    await c1.read(streakProvider.notifier).recordPracticeToday(
          DateTime(2026, 7, 9),
        );
    expect(c1.read(streakProvider).current, 1);
    c1.dispose();

    // A brand-new container must reload the persisted streak.
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(streakProvider); // trigger build → async _load
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c2.read(streakProvider).current, 1);
  });
}
