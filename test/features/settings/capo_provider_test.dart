import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/settings/providers/capo_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to no capo', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(capoProvider), 0);
  });

  test('set persists and clamps to 0..11', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(capoProvider.notifier);

    await n.set(3);
    expect(c.read(capoProvider), 3);

    await n.set(99); // above max
    expect(c.read(capoProvider), CapoNotifier.maxFret);

    await n.set(-5); // below min
    expect(c.read(capoProvider), 0);

    // Persisted to SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('capo_fret'), 0);
  });

  test('a stored value is loaded on build', () async {
    SharedPreferences.setMockInitialValues({'capo_fret': 5});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // First read instantiates the notifier, which kicks off the async prefs
    // load; pump the event loop a few turns so getInstance + apply complete.
    expect(c.read(capoProvider), 0); // default before load resolves
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(c.read(capoProvider), 5);
  });
}
