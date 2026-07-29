import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/settings/providers/capo_provider.dart';

import '../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to no capo', () {
    final c = ProviderContainer(overrides: preferenceOverrides());
    addTearDown(c.dispose);
    expect(c.read(capoProvider), 0);
  });

  test('set persists and clamps to 0..11', () async {
    final store = InMemoryKeyValueStore();
    final c = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    addTearDown(c.dispose);
    final n = c.read(capoProvider.notifier);

    await n.set(3);
    expect(c.read(capoProvider), 3);

    await n.set(99); // above max
    expect(c.read(capoProvider), CapoNotifier.maxFret);

    await n.set(-5); // below min
    expect(c.read(capoProvider), 0);

    expect(store.values[StorageKeys.capoFret], 0);
  });

  test('a stored value is there on the FIRST read, with no async gap', () {
    final c = ProviderContainer(
      overrides: preferenceOverrides({StorageKeys.capoFret: 5}),
    );
    addTearDown(c.dispose);
    expect(c.read(capoProvider), 5);
  });
}
