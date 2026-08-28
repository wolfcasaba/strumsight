/// The risk tier of a feature flag, used to prioritise incident review and
/// audit attention (ADR 0446).
///
/// This is a coarse, human-assigned judgement recorded alongside each
/// [FeatureFlagDefinition] — it is not derived mechanically. `high` is used
/// for capabilities that read `FeatureFlags.usesNetwork`
/// (`lib/app/config/feature_flags.dart:299`) or whose own doc comment names
/// a network/data-egress path (cloud calls, uploads, accepted writes).
enum FeatureFlagRisk { low, medium, high }

/// A single, typed, auditable catalog entry describing one field of
/// `lib/app/config/feature_flags.dart`'s `FeatureFlags` class (ADR 0446).
///
/// This type intentionally does NOT reference `FeatureFlags` itself — see
/// the `lib/core/feature_flags/feature_flag_registry.dart` header comment
/// for why (ADR 0446 D5). The binding between a [key] here and the real
/// `FeatureFlags` field of the same name is made a machine-checked fact by
/// `tool/check_feature_flags.dart` (ADR 0446 D4), not by this type.
final class FeatureFlagDefinition {
  const FeatureFlagDefinition({
    required this.key,
    required this.owner,
    required this.risk,
    required this.failClosedDefault,
    required this.killSwitchPath,
    this.adr,
    this.expiresOn,
  });

  /// The exact `FeatureFlags` field name this entry describes, e.g.
  /// `"communityWritesEnabled"`. Matched against
  /// `lib/app/config/feature_flags.dart` by `tool/check_feature_flags.dart`.
  final String key;

  /// The subsystem accountable for this capability's rollout decisions
  /// (a `lib/features/<feature>` directory, or a `lib/app/**` area for
  /// cross-cutting availability switches).
  final String owner;

  final FeatureFlagRisk risk;

  /// The value this flag resolves to when no [FeatureFlagSource] in the
  /// priority chain has an opinion (ADR 0446 D2) — the safe state to fail
  /// into. Every entry in the shipped registry uses `false`: every cataloged
  /// capability is safe absent, which is also each field's compile-time
  /// default in `lib/app/config/feature_flags.dart`.
  final bool failClosedDefault;

  /// Where/how an operator turns this capability off in an incident —
  /// either a dart-define name, or (for capabilities with no runtime
  /// toggle yet) the exact `lib/app/config/feature_flags.dart` source
  /// location that would need to change, so the path is never a dead end.
  final String killSwitchPath;

  /// The ADR that authorised this capability, when `feature_flags.dart`
  /// cites one directly in its own doc comment for this field. `null` when
  /// no such citation exists — this is left unclaimed rather than guessed.
  final String? adr;

  /// Inclusive expiration date (ADR 0446 D6): the flag is still valid ON
  /// this date and lapses the day after. `null` means a durable capability
  /// switch with no dated rollout end.
  final DateTime? expiresOn;
}
