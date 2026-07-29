import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/streak/providers/streak_provider.dart';

import '../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryKeyValueStore store;
  setUp(() => store = InMemoryKeyValueStore());

  test('records practice once per day and advances across days', () async {
    final c = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
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

  test('streak persists across a fresh controller', () async {
    final c1 = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    await c1
        .read(streakProvider.notifier)
        .recordPracticeToday(DateTime(2026, 7, 9));
    expect(c1.read(streakProvider).current, 1);
    c1.dispose();

    // A brand-new container must reload the persisted streak.
    final c2 = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    addTearDown(c2.dispose);
    expect(c2.read(streakProvider).current, 1);
  });
}
