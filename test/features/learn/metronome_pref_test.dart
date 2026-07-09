import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/learn/providers/metronome_pref_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to unmuted and toggles', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(metronomeMutedProvider), isFalse);
    await c.read(metronomeMutedProvider.notifier).toggle();
    expect(c.read(metronomeMutedProvider), isTrue);
  });

  test('the mute choice persists across a fresh controller', () async {
    final c1 = ProviderContainer();
    await c1.read(metronomeMutedProvider.notifier).toggle(); // → muted
    c1.dispose();

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(metronomeMutedProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c2.read(metronomeMutedProvider), isTrue);
  });
}
