/// Whether the user has agreed to a Lab capture leaving the recording
/// screen and being written to disk (ADR 0358 D1). The three states are a
/// closed, sealed hierarchy — not a `bool` — because the writer's `write`
/// call only accepts [LabConsentGranted]: a revoked or unknown consent
/// cannot be passed to it, so the "no export without consent" contract is
/// enforced by the type checker, not by a runtime `if`.
sealed class LabConsent {
  const LabConsent();
}

/// The user explicitly agreed to this capture. [consentVersion] identifies
/// which version of the consent copy they agreed to.
final class LabConsentGranted extends LabConsent {
  const LabConsentGranted({required this.consentVersion});

  final String consentVersion;
}

/// The user explicitly declined or withdrew consent for this capture.
final class LabConsentRevoked extends LabConsent {
  const LabConsentRevoked();
}

/// No consent decision has been recorded yet.
final class LabConsentUnknown extends LabConsent {
  const LabConsentUnknown();
}
