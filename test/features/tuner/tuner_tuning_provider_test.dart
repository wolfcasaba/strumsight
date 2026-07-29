import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/tuner/model/tuning.dart';
import 'package:strumsight/features/tuner/providers/tuner_tuning_provider.dart';

import '../../support/preference_store.dart';

/// Round 89 — the selected tuning is a persisted, LOCAL preference (like the
/// A4 reference: device-specific, never synced).
void main() {
  test('defaults to standard tuning', () async {
    final container = ProviderContainer(overrides: preferenceOverrides());
    addTearDown(container.dispose);
    expect(container.read(tunerTuningProvider), same(Tunings.standard));
  });

  test('set() switches the tuning and persists it by id', () async {
    final store = InMemoryKeyValueStore();
    final container = ProviderContainer(
      overrides: [preferenceStoreOverride(store)],
    );
    addTearDown(container.dispose);
    await container.read(tunerTuningProvider.notifier).set(Tunings.dropD);
    expect(container.read(tunerTuningProvider), same(Tunings.dropD));
    expect(store.values[StorageKeys.tunerTuning], 'dropD');
  });

  test('a persisted id is restored on build', () async {
    final container = ProviderContainer(
      overrides: preferenceOverrides({StorageKeys.tunerTuning: 'dadgad'}),
    );
    addTearDown(container.dispose);
    expect(container.read(tunerTuningProvider), same(Tunings.dadgad));
  });

  test('junk in prefs falls back to standard instead of crashing', () async {
    final container = ProviderContainer(
      overrides: preferenceOverrides({StorageKeys.tunerTuning: 'zz-unknown'}),
    );
    addTearDown(container.dispose);
    expect(container.read(tunerTuningProvider), same(Tunings.standard));
  });
}
