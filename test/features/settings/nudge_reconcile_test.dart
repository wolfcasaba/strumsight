import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/settings/providers/nudge_enabled_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round-82 devil-advocate fix: the toggle must never LIE. After a
/// force-stop / permission revoke the persisted ON is stale — the startup
/// reconcile verifies with the platform and flips it off honestly. In the
/// test env the notifications platform channel is genuinely missing, which
/// IS the "platform says no" case.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persisted ON + platform says no → reconciled to OFF (persisted too)',
      () async {
    SharedPreferences.setMockInitialValues({'nudge_enabled': true});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(nudgeEnabledProvider.notifier);
    await notifier.reconcile(title: 't', body: 'b');

    expect(container.read(nudgeEnabledProvider), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('nudge_enabled'), isFalse,
        reason: 'the honest OFF must survive the next restart too');
  });

  test('persisted OFF → reconcile is a no-op', () async {
    SharedPreferences.setMockInitialValues({'nudge_enabled': false});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(nudgeEnabledProvider.notifier)
        .reconcile(title: 't', body: 'b');
    expect(container.read(nudgeEnabledProvider), isFalse);
  });
}
