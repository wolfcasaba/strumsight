import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/settings/providers/left_handed_provider.dart';

import '../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to right-handed and toggles + persists', () async {
    // One store, two container lifetimes — the second must see what the first
    // wrote, exactly like a relaunch does.
    final store = InMemoryKeyValueStore();

    final c1 = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    expect(c1.read(leftHandedProvider), isFalse);
    await c1.read(leftHandedProvider.notifier).set(true);
    expect(c1.read(leftHandedProvider), isTrue);
    expect(store.values[StorageKeys.leftHanded], isTrue);
    c1.dispose();

    final c2 = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    addTearDown(c2.dispose);
    expect(c2.read(leftHandedProvider), isTrue);
  });
}
