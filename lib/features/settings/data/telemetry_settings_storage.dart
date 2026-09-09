/// Persisted keys for the opt-in beta telemetry consent (SDD Ch14 Kör 41,
/// ADR 0542 D3).
///
/// These live here rather than in `lib/core/storage/storage_keys.dart` for
/// the same reason `GamificationStorageKeys` does: the feature owns its own
/// keys, and the shared catalogue stays the platform's. They follow the
/// `ss.` namespace so a StrumSight key remains recognisable in a device
/// dump, and [all] exists so a guard test (and the Privacy Center's
/// delete-all) can enumerate every key the consent writes without reading
/// the notifier's source.
library;

abstract final class TelemetryStorageKeys {
  /// `TelemetryConsentState.name`.
  static const String consentState = 'ss.telemetry.consent_state';

  /// `TelemetryConsentVersion.name` — which consent COPY was answered.
  static const String consentVersion = 'ss.telemetry.consent_version';

  /// The rotating pseudonym's upper 32 bits.
  static const String pseudonymHighBits = 'ss.telemetry.pseudonym_high';

  /// The rotating pseudonym's lower 32 bits.
  static const String pseudonymLowBits = 'ss.telemetry.pseudonym_low';

  /// The day (whole days since the Unix epoch, UTC) the pseudonym was
  /// issued — a day number, never an instant.
  static const String pseudonymIssuedOnDay = 'ss.telemetry.pseudonym_day';

  /// Whether the device is enrolled in the Ch14 Kör 40 field study.
  static const String fieldStudyEnrolled = 'ss.telemetry.field_study_enrolled';

  /// Every key this feature writes. Revocation and delete-all must visit
  /// this exact list, because [KeyValueStore] cannot enumerate keys.
  static const List<String> all = <String>[
    consentState,
    consentVersion,
    pseudonymHighBits,
    pseudonymLowBits,
    pseudonymIssuedOnDay,
    fieldStudyEnrolled,
  ];

  /// The subset that identifies the device's study participation — the keys
  /// a revocation must erase, not merely overwrite with "denied".
  static const List<String> pseudonymKeys = <String>[
    pseudonymHighBits,
    pseudonymLowBits,
    pseudonymIssuedOnDay,
  ];
}
