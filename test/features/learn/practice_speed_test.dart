import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/learn/providers/practice_speed_provider.dart';

import '../../support/preference_store.dart';

/// Round 132 — the practice-speed preference persists across lessons/sessions
/// (Yousician parity), so a learner who drills at 75% doesn't re-select it on
/// every lesson open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to full speed (1.0)', () {
    final c = ProviderContainer(overrides: preferenceOverrides());
    addTearDown(c.dispose);
    expect(c.read(practiceSpeedProvider), 1.0);
  });

  test('a chosen speed persists across a fresh controller', () async {
    final store = InMemoryKeyValueStore();

    final c1 = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    await c1.read(practiceSpeedProvider.notifier).set(0.75);
    expect(c1.read(practiceSpeedProvider), 0.75);
    c1.dispose();

    final c2 = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    addTearDown(c2.dispose);
    expect(
      c2.read(practiceSpeedProvider),
      0.75,
      reason: 'the drill tempo must stick across sessions',
    );
  });

  test(
    'an off-grid speed is never stored (chips stay representable)',
    () async {
      final store = InMemoryKeyValueStore();
      final c = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
      addTearDown(c.dispose);
      await c.read(practiceSpeedProvider.notifier).set(0.9); // not in options
      expect(
        c.read(practiceSpeedProvider),
        1.0,
        reason: 'rejected, stays default',
      );
      expect(store.contains(StorageKeys.practiceSpeed), isFalse);
    },
  );

  test('a speed picked at startup wins over the stored one', () async {
    // The r132 guard was a `_userSet` flag racing an async prefs load. The load
    // is synchronous now, so the user's pick simply IS the state — this asserts
    // the outcome that guard existed for.
    final store = InMemoryKeyValueStore({StorageKeys.practiceSpeed: 0.5});
    final c = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    addTearDown(c.dispose);

    expect(c.read(practiceSpeedProvider), 0.5);
    await c.read(practiceSpeedProvider.notifier).set(0.75);
    await Future<void>.delayed(Duration.zero);

    expect(c.read(practiceSpeedProvider), 0.75);
    expect(store.values[StorageKeys.practiceSpeed], 0.75);
  });
}
