import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/providers/practice_speed_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 132 — the practice-speed preference persists across lessons/sessions
/// (Yousician parity), so a learner who drills at 75% doesn't re-select it on
/// every lesson open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to full speed (1.0)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(practiceSpeedProvider), 1.0);
  });

  test('a chosen speed persists across a fresh controller', () async {
    final c1 = ProviderContainer();
    await c1.read(practiceSpeedProvider.notifier).set(0.75);
    expect(c1.read(practiceSpeedProvider), 0.75);
    c1.dispose();

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(practiceSpeedProvider); // trigger load
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c2.read(practiceSpeedProvider), 0.75,
        reason: 'the drill tempo must stick across sessions');
  });

  test('an off-grid speed is never stored (chips stay representable)', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(practiceSpeedProvider.notifier).set(0.9); // not in options
    expect(c.read(practiceSpeedProvider), 1.0, reason: 'rejected, stays default');
  });

  test('a late prefs load does not clobber a speed the user just picked',
      () async {
    // Seed a stored 0.5, then immediately set 0.75 before the async load runs.
    SharedPreferences.setMockInitialValues({'practice_speed_v1': 0.5});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(practiceSpeedProvider); // kicks off _load()
    await c.read(practiceSpeedProvider.notifier).set(0.75); // user beats the load
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c.read(practiceSpeedProvider), 0.75,
        reason: 'the _userSet guard must win over a late stored value');
  });
}
