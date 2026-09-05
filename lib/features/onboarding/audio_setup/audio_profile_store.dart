import 'dart:convert';

import '../../../core/storage/key_value_store.dart';
import 'audio_profile.dart';

/// Persists the single most-recent [AudioProfile] (ADR 0519).
///
/// Feature-local storage key (R4/D7): `lib/core/storage/` is out of this
/// round's allowed paths, so this store does not add a `StorageKeys` entry —
/// it follows the merge-elt precedent
/// `OnboardingStepController.storageKey = 'ss.onboarding.step'`
/// (`lib/features/onboarding/onboarding_provider.dart:64`).
class AudioProfileStore {
  const AudioProfileStore(this._store);

  final KeyValueStore _store;

  /// New in this round — has no `StorageKeys` entry of its own because
  /// `lib/core/storage/` is out of this round's allowed paths (R4/D7).
  static const String storageKey = 'ss.onboarding.audio_profile';

  /// Reads and decodes the stored profile, migrating a supported legacy
  /// schema forward. `null` when nothing has been saved yet. A malformed or
  /// future-schema blob throws — fail-closed, never a default profile (D5).
  AudioProfile? read() {
    final raw = _store.readString(storageKey);
    if (raw == null) return null;
    return AudioProfile.decode(jsonDecode(raw));
  }

  /// [read], but returns `null` instead of a profile whose captured
  /// mic-route or sample rate no longer matches the live environment (D3) —
  /// a stale profile is never handed to a caller as valid.
  AudioProfile? readValid({
    required String currentMicRouteId,
    required int currentSampleRateHz,
  }) {
    final profile = read();
    if (profile == null) return null;
    if (profile.isStaleFor(
      currentMicRouteId: currentMicRouteId,
      currentSampleRateHz: currentSampleRateHz,
    )) {
      return null;
    }
    return profile;
  }

  /// Atomic single-write save (D4) — the caller invokes this once, with the
  /// complete profile from a finished run. There is deliberately no
  /// step-by-step write API on this store: a half-finished run must never
  /// leave a partial profile behind.
  Future<void> save(AudioProfile profile) =>
      _store.writeString(storageKey, jsonEncode(profile.toJson()));

  /// Deletes the stored profile, if any. Actually removes the key — not a
  /// flag flip — so a subsequent [read] is `null`.
  Future<void> clear() => _store.remove(storageKey);
}
