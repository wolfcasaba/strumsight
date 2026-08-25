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

/// The onboarding flow's step-level checkpoint (SDD Ch13 Kör 16, ADR 0281 §5
/// — the flow is resumable, and the old checkpoint state migrates). Ordinal
/// order matters: it is the flow's linear progression AND the persisted
/// on-disk representation (see [OnboardingStepController.readStep]).
enum OnboardingStep { welcome, permission, firstWin, done }

/// Tracks which step of onboarding the user last reached, so a kill or
/// interruption resumes there instead of restarting the whole flow (A6).
class OnboardingStepController extends Notifier<OnboardingStep>
    with PersistedPreference<OnboardingStep> {
  /// New in this round — the legacy build only ever persisted the single
  /// [StorageKeys.onboardingSeen] bool (R4 measured); this key has no
  /// [StorageKeys] entry of its own because `lib/core/storage/` is out of
  /// this round's allowed paths.
  static const String storageKey = 'ss.onboarding.step';

  /// Reads the checkpoint. No checkpoint on disk does NOT mean "start over":
  /// it means no step-aware build has run on this device yet, so the
  /// checkpoint is derived from the legacy single-bool flag — an
  /// already-onboarded user inherits [OnboardingStep.done] rather than being
  /// replayed through a flow they already finished (A7, R4).
  static OnboardingStep readStep(KeyValueStore store) {
    final stored = store.readInt(storageKey);
    if (stored != null &&
        stored >= 0 &&
        stored < OnboardingStep.values.length) {
      return OnboardingStep.values[stored];
    }
    return OnboardingController.readSeen(store)
        ? OnboardingStep.done
        : OnboardingStep.welcome;
  }

  @override
  OnboardingStep build() => readStep(preferences);

  /// Moves the checkpoint forward and persists it immediately — a kill
  /// mid-onboarding resumes at [step], not [OnboardingStep.welcome].
  Future<void> advanceTo(OnboardingStep step) async {
    state = step;
    await persist(
      storageKey,
      (store) => store.writeInt(storageKey, step.index),
    );
  }
}

final onboardingStepProvider =
    NotifierProvider<OnboardingStepController, OnboardingStep>(
      OnboardingStepController.new,
    );
