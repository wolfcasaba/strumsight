import 'feature_flag_definition.dart';

/// A source of opinions about feature-flag values, keyed by
/// [FeatureFlagDefinition.key]. Returns `null` when the source has no
/// opinion about a given key — distinct from an explicit `false` — so
/// [FeatureFlagResolver] can fall through to the next, weaker source
/// (ADR 0446 D2) instead of treating "unknown" as "off" or "on".
abstract interface class FeatureFlagSource {
  bool? valueFor(String key);
}

/// One signed payload from the remote flag channel.
///
/// ADR 0446 D3 introduces the `remote` source at the INTERFACE level only —
/// there is no real network channel or cryptographic verification in this
/// round. [signatureValid] stands in for whatever a future implementation's
/// signature check would produce, so the priority chain's fail-closed
/// behaviour around a bad signature (ADR 0446 D2) is mechanically testable
/// today with fakes.
final class SignedFeatureFlagPayload {
  const SignedFeatureFlagPayload({
    required this.value,
    required this.signatureValid,
  });

  final bool value;

  /// When `false`, [value] MUST be ignored by [FeatureFlagResolver] exactly
  /// as if this source had not responded at all — not fatally: no
  /// exception, no partial acceptance of [value].
  final bool signatureValid;
}

/// The remote, signed source in the priority chain (ADR 0446 D2 row 2).
abstract interface class RemoteFeatureFlagSource {
  /// Returns the signed payload for [key], or `null` if the source has no
  /// opinion about that key.
  SignedFeatureFlagPayload? fetch(String key);
}

/// Which link of the priority chain produced a [FeatureFlagResolution].
enum FeatureFlagResolutionOrigin {
  /// The `emergency` source turned this flag off (ADR 0446 D1). This is the
  /// only way `emergency` can ever win — it never sources `wonBy == emergency`
  /// with `value == true`.
  emergencyOff,
  remote,
  capability,
  local,
  failClosedDefault,
}

final class FeatureFlagResolution {
  const FeatureFlagResolution({required this.value, required this.origin});

  final bool value;
  final FeatureFlagResolutionOrigin origin;
}

/// Resolves one [FeatureFlagDefinition] against the fail-closed priority
/// chain of ADR 0446 D2:
///
/// 1. `emergency` — can only ever turn a flag OFF (D1). A `true` opinion is
///    treated exactly like no opinion (falls through); a `false` opinion
///    wins immediately and unconditionally, ahead of every other source.
/// 2. `remote` — honoured only when its payload's signature verifies; a bad
///    signature is treated like no opinion, not a fatal error (D2).
/// 3. `capability` — device/platform capability gate.
/// 4. `local` — the existing compile-time `bool.fromEnvironment` path.
/// 5. Neither of the above has an opinion: [FeatureFlagDefinition.failClosedDefault].
///
/// None of these steps caches a prior resolution or falls back to "the last
/// known value" — a missing/unknown source is indistinguishable from a
/// source that was never configured, and both fall through to the next,
/// weaker link (D2's explicitly rejected weakening).
final class FeatureFlagResolver {
  const FeatureFlagResolver({
    this.emergency,
    this.remote,
    this.capability,
    this.local,
  });

  final FeatureFlagSource? emergency;
  final RemoteFeatureFlagSource? remote;
  final FeatureFlagSource? capability;
  final FeatureFlagSource? local;

  FeatureFlagResolution resolve(FeatureFlagDefinition definition) {
    final emergencyValue = emergency?.valueFor(definition.key);
    if (emergencyValue == false) {
      return const FeatureFlagResolution(
        value: false,
        origin: FeatureFlagResolutionOrigin.emergencyOff,
      );
    }

    final payload = remote?.fetch(definition.key);
    if (payload != null && payload.signatureValid) {
      return FeatureFlagResolution(
        value: payload.value,
        origin: FeatureFlagResolutionOrigin.remote,
      );
    }

    final capabilityValue = capability?.valueFor(definition.key);
    if (capabilityValue != null) {
      return FeatureFlagResolution(
        value: capabilityValue,
        origin: FeatureFlagResolutionOrigin.capability,
      );
    }

    final localValue = local?.valueFor(definition.key);
    if (localValue != null) {
      return FeatureFlagResolution(
        value: localValue,
        origin: FeatureFlagResolutionOrigin.local,
      );
    }

    return FeatureFlagResolution(
      value: definition.failClosedDefault,
      origin: FeatureFlagResolutionOrigin.failClosedDefault,
    );
  }
}
