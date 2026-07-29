import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/learn/providers/metronome_pref_provider.dart';

import '../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to unmuted and toggles', () async {
    final c = ProviderContainer(overrides: preferenceOverrides());
    addTearDown(c.dispose);
    expect(c.read(metronomeMutedProvider), isFalse);
    await c.read(metronomeMutedProvider.notifier).toggle();
    expect(c.read(metronomeMutedProvider), isTrue);
  });

  test('the mute choice persists across a fresh controller', () async {
    final store = InMemoryKeyValueStore();

    final c1 = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    await c1.read(metronomeMutedProvider.notifier).toggle(); // → muted
    expect(store.values[StorageKeys.metronomeMuted], isTrue);
    c1.dispose();

    final c2 = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    addTearDown(c2.dispose);
    expect(c2.read(metronomeMutedProvider), isTrue);
  });
}
