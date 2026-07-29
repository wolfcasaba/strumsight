import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/key_value_store.dart';
import '../../core/storage/persisted_preference.dart';
import '../../core/storage/storage_keys.dart';

/// Whether the first-run onboarding has been completed. Read once at boot from
/// the store bootstrap opened and overridden into the provider, so the router
/// can gate on it synchronously with no flicker for returning users.
///
/// Default is **true** (assume seen) so widget tests and any un-overridden
/// context skip onboarding; `main` overrides it with the real persisted flag,
/// which is only false on a genuine first launch.
class OnboardingController extends Notifier<bool>
    with PersistedPreference<bool> {
  OnboardingController(this._initial);

  /// The boot-time read. Absent flag = a true first run (show onboarding); a
  /// value of the wrong type degrades to `null` in the store, and a returning
  /// user seeing onboarding once is a far better failure than crashing.
  static bool readSeen(KeyValueStore store) =>
      store.readBool(StorageKeys.onboardingSeen) ?? false;

  final bool _initial;

  @override
  bool build() => _initial;

  /// Mark onboarding complete and persist it.
  Future<void> complete() async {
    state = true;
    await persist(
      StorageKeys.onboardingSeen,
      (store) => store.writeBool(StorageKeys.onboardingSeen, true),
    );
  }
}

final onboardingSeenProvider = NotifierProvider<OnboardingController, bool>(
  () => OnboardingController(true),
);
