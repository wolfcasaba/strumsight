import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/tuner/model/tuning.dart';
import 'package:music_theory/features/tuner/providers/tuner_tuning_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 89 — the selected tuning is a persisted, LOCAL preference (like the
/// A4 reference: device-specific, never synced).
void main() {
  test('defaults to standard tuning', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(tunerTuningProvider), same(Tunings.standard));
  });

  test('set() switches the tuning and persists it by id', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(tunerTuningProvider.notifier).set(Tunings.dropD);
    expect(container.read(tunerTuningProvider), same(Tunings.dropD));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tuner_tuning'), 'dropD');
  });

  test('a persisted id is restored on build', () async {
    SharedPreferences.setMockInitialValues({'tuner_tuning': 'dadgad'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // The prefs load is async — poke the notifier then let it settle.
    container.read(tunerTuningProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(tunerTuningProvider), same(Tunings.dadgad));
  });

  test('junk in prefs falls back to standard instead of crashing', () async {
    SharedPreferences.setMockInitialValues({'tuner_tuning': 'zz-unknown'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(tunerTuningProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(tunerTuningProvider), same(Tunings.standard));
  });
}
