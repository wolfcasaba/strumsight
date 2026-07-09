import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/settings/providers/left_handed_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults to right-handed and toggles + persists', () async {
    final c1 = ProviderContainer();
    expect(c1.read(leftHandedProvider), isFalse);
    await c1.read(leftHandedProvider.notifier).set(true);
    expect(c1.read(leftHandedProvider), isTrue);
    c1.dispose();

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(leftHandedProvider);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(c2.read(leftHandedProvider), isTrue);
  });
}
