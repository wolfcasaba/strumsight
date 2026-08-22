import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/persisted_preference.dart';
import '../../domain/gamification_preferences.dart';
import '../widgets/reward_summary_sheet.dart' show RewardSummaryFeedback;

/// Storage keys for the five gamification preferences.
///
/// Inlined (not [StorageKeys] constants) on purpose: the round-brief
/// `allowed_paths` list scopes this round to the new files; the central
/// key catalogue lives outside the round's writable surface and a follow-up
/// round can promote these constants once the cloud-sync wiring lands.
const String _kIntensity = 'ss.gamification.pref.intensity';
const String _kHaptics = 'ss.gamification.pref.haptics_enabled';
const String _kSound = 'ss.gamification.pref.sound_enabled';
const String _kReduceMotion = 'ss.gamification.pref.reduce_motion';
const String _kNotifications = 'ss.gamification.pref.notifications_enabled';

/// Per-field defaults — kept as a single record so the notifier and the
/// test fixtures agree on the exact same starting point.
const GamificationPreferences _defaults = GamificationPreferences.defaults;

/// Single-source-of-truth notifier for the five gamification toggles
/// (ADR 0393 §5.3).
///
/// Reads are synchronous via [PersistedPreference] so the very first frame
/// already reflects the stored choice (the "default first, real value
/// later" race that the project killed in E01-R06 cannot come back). Writes
/// are local-only in this round — the §0.0 brief explicitly forbids
/// touching [settings_sync.dart], so a future sync round will pick these
/// keys up by reading the same namespaced constants.
class GamificationPreferencesNotifier extends Notifier<GamificationPreferences>
    with PersistedPreference<GamificationPreferences> {
  @override
  GamificationPreferences build() {
    final intensity = _readIntensity();
    return GamificationPreferences(
      intensity: intensity,
      hapticsEnabled:
          preferences.readBool(_kHaptics) ?? _defaults.hapticsEnabled,
      soundEnabled: preferences.readBool(_kSound) ?? _defaults.soundEnabled,
      reduceMotion:
          preferences.readBool(_kReduceMotion) ?? _defaults.reduceMotion,
      notificationsEnabled:
          preferences.readBool(_kNotifications) ??
          _defaults.notificationsEnabled,
    );
  }

  /// Replace the whole bundle. Used by the settings-section chips /
  /// switches — every call persists all five keys, so the disk image and
  /// the in-memory [state] are always in lockstep (the §5.3
  /// "immediately and completely" rule).
  Future<void> set(GamificationPreferences next) async {
    state = next;
    await persist(_kIntensity, (store) async {
      await store.writeString(_kIntensity, next.intensity.code);
      await store.writeBool(_kHaptics, next.hapticsEnabled);
      await store.writeBool(_kSound, next.soundEnabled);
      await store.writeBool(_kReduceMotion, next.reduceMotion);
      await store.writeBool(_kNotifications, next.notificationsEnabled);
    });
  }

  /// Granular setters — kept thin so the UI can update one toggle without
  /// having to rebuild the bundle on its side.
  Future<void> setIntensity(CelebrationIntensity intensity) =>
      set(state.copyWith(intensity: intensity));

  Future<void> setHapticsEnabled(bool value) =>
      set(state.copyWith(hapticsEnabled: value));

  Future<void> setSoundEnabled(bool value) =>
      set(state.copyWith(soundEnabled: value));

  Future<void> setReduceMotion(bool value) =>
      set(state.copyWith(reduceMotion: value));

  Future<void> setNotificationsEnabled(bool value) =>
      set(state.copyWith(notificationsEnabled: value));

  /// Parses the persisted [CelebrationIntensity] code with a graceful
  /// fallback. A future build that adds a new variant cannot crash an
  /// older one — exactly the same shape [ThemeModeController] uses.
  CelebrationIntensity _readIntensity() {
    final raw = preferences.readString(_kIntensity);
    for (final candidate in CelebrationIntensity.values) {
      if (candidate.code == raw) return candidate;
    }
    return _defaults.intensity;
  }
}

/// Public provider — re-exported via `package:strumsight/features/gamification/public.dart`.
final gamificationPreferencesProvider =
    NotifierProvider<GamificationPreferencesNotifier, GamificationPreferences>(
      GamificationPreferencesNotifier.new,
    );

/// Translates the [GamificationPreferences] bundle into the caller-fed
/// [RewardSummaryFeedback] the summary sheet already consumes.
///
/// Kept as a TOP-LEVEL function in the provider layer (NOT a method on the
/// domain model) because the domain must stay Flutter-free — `RewardSummaryFeedback`
/// lives in `presentation/widgets/reward_summary_sheet.dart`, which imports
/// `package:flutter/material.dart`. The §0.0.1 F1 MAJOR fix moved this
/// mapping OUT of `domain/gamification_preferences.dart` so the
/// `architecture` gate stays green and the test file can call it through
/// the `features/gamification/public.dart` barrel.
///
/// The haptics / sound bits are passthroughs; the intensity is encoded via
/// [CelebrationIntensity.silent] — `false` on BOTH channels — because the
/// existing sheet's caller-fed model predates the richer §5 preference
/// surface. This is the *forward* shape the future caller wired in
/// `E13-R32` will read (the §0.0 "future caller" caveat).
RewardSummaryFeedback gamificationFeedbackFor(GamificationPreferences prefs) =>
    RewardSummaryFeedback(
      hapticsEnabled: prefs.hapticsEnabled && prefs.isCelebrationVisible,
      soundEnabled: prefs.soundEnabled && prefs.isCelebrationVisible,
    );
