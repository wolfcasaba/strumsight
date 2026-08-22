/// How loud the celebration layer should be.
///
/// [full] is the loud-by-default behaviour the rest of the app was tuned
/// for; [subtle] keeps the on-screen signal but drops the heavier motion
/// flourishes; [silent] disables the visual celebration entirely while
/// still letting the ledger / streak / mastery evaluators run their normal
/// courses (ADR 0393 §5.1).
enum CelebrationIntensity {
  full('full'),
  subtle('subtle'),
  silent('silent');

  const CelebrationIntensity(this.code);

  /// Stable wire/persistence code.
  final String code;
}

/// Immutable bundle of the five gamification-layer toggles the user can
/// reach from Settings (ADR 0393 §5.3).
///
/// The class is the SINGLE point of truth — every consumer (the celebration
/// coordinator, the reward summary sheet, the achievement a11y labels, the
/// haptic/sound caller) reads from it. Per-tile persistence keys still exist
/// for forward compatibility with future granular sync, but the in-memory
/// state of the notifier is the model, not a hand-rolled subset of fields.
///
/// Defaults are deliberately chosen so the very first run (before any disk
/// read) behaves the same as the previous "all on" build.
final class GamificationPreferences {
  const GamificationPreferences({
    this.intensity = CelebrationIntensity.full,
    this.hapticsEnabled = true,
    this.soundEnabled = true,
    this.reduceMotion = false,
    this.notificationsEnabled = true,
  });

  /// How loud the celebration should be rendered. Honours the §5.1 rule
  /// that the inner evaluation layer keeps running regardless of this
  /// value — only the *display* is suppressed at [CelebrationIntensity.silent].
  final CelebrationIntensity intensity;

  /// Whether the celebration may emit a haptic pulse (system-level).
  final bool hapticsEnabled;

  /// Whether the celebration may play a confirmation sound (system-level).
  final bool soundEnabled;

  /// Whether the presentation layer should dampen or drop transitions and
  /// large motion flourishes. Independent of [MediaQuery.disableAnimationsOf]
  /// — the user can opt in even on a build that does not report the OS
  /// setting, and the two combine.
  final bool reduceMotion;

  /// Whether the OPT-IN motivational reminder (chunk 013's retention TODO)
  /// may fire. Default `true` to match the legacy behaviour; turning it OFF
  /// NEVER awards XP, NEVER unlocks an achievement, NEVER alters the
  /// ledger — §5.2 dark-pattern rule.
  final bool notificationsEnabled;

  /// The defaults the build ships with — exposed so tests and the boot
  /// path can use the exact same source.
  static const GamificationPreferences defaults = GamificationPreferences();

  /// Returns a new instance with the supplied fields replaced. `null`
  /// arguments leave the corresponding field untouched, mirroring the
  /// Riverpod pattern used by the other persisted-preference notifiers.
  GamificationPreferences copyWith({
    CelebrationIntensity? intensity,
    bool? hapticsEnabled,
    bool? soundEnabled,
    bool? reduceMotion,
    bool? notificationsEnabled,
  }) => GamificationPreferences(
    intensity: intensity ?? this.intensity,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
  );

  /// "Is anything visual being shown at all?" — the §6.1 hibás-implementáció
  /// probe (A1 / A2) reads this. The inner evaluation ALWAYS runs; this
  /// answer is purely about the SURFACE.
  bool get isCelebrationVisible => intensity != CelebrationIntensity.silent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GamificationPreferences &&
          intensity == other.intensity &&
          hapticsEnabled == other.hapticsEnabled &&
          soundEnabled == other.soundEnabled &&
          reduceMotion == other.reduceMotion &&
          notificationsEnabled == other.notificationsEnabled;

  @override
  int get hashCode => Object.hash(
    intensity,
    hapticsEnabled,
    soundEnabled,
    reduceMotion,
    notificationsEnabled,
  );

  @override
  String toString() =>
      'GamificationPreferences('
      'intensity: $intensity, '
      'hapticsEnabled: $hapticsEnabled, '
      'soundEnabled: $soundEnabled, '
      'reduceMotion: $reduceMotion, '
      'notificationsEnabled: $notificationsEnabled)';
}
