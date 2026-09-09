/// The opt-in consent model for beta telemetry (SDD Ch14 Kör 41, ADR 0542).
///
/// Two shape decisions are deliberate and machine-checked by
/// `test/core/telemetry/telemetry_redaction_test.dart` A1, which forbids a
/// bare `String` FIELD anywhere under `lib/core/telemetry`:
///
/// - the consent state is a THREE-value closed enum, not a `bool`, because a
///   boolean cannot tell "never asked" from "said no", and the difference
///   decides whether the app may ask again;
/// - the consent COPY version is a closed enum too, and the pseudonym stores
///   64 random BITS rather than a text field. Neither type has a slot a
///   free string could occupy, so neither can become a smuggling route.
library;

import 'dart:math';

enum TelemetryConsentState {
  /// No decision has been recorded. The DEFAULT, and a refusal at the gate.
  notAsked,

  /// The user explicitly agreed, for a named [TelemetryConsentVersion] of
  /// the consent copy.
  granted,

  /// The user explicitly declined, or revoked a previous grant.
  denied;

  /// The only value that permits collection. Written as an explicit switch
  /// (no `default`) so a future state cannot silently join the permitted
  /// side merely by being added to the enum.
  bool get permitsCollection => switch (this) {
    TelemetryConsentState.granted => true,
    TelemetryConsentState.notAsked || TelemetryConsentState.denied => false,
  };
}

/// Which version of the consent COPY a stored decision answers.
///
/// A grant is a grant to specific words. When the copy changes, the old
/// value stays in this enum and [current] moves on, so an existing grant
/// stops satisfying [TelemetryConsentRecord.permitsCollection] instead of
/// silently transferring to text the user never read.
enum TelemetryConsentVersion {
  /// The beta consent copy shipped with SDD Ch14 Kör 41.
  ch14Beta1;

  /// The version the app currently presents.
  static const TelemetryConsentVersion current = ch14Beta1;

  /// Parses a persisted version name, fail-closed: an unknown or missing
  /// value yields `null`, and the caller must treat that as "not asked".
  static TelemetryConsentVersion? tryParse(String? name) {
    if (name == null) return null;
    for (final version in TelemetryConsentVersion.values) {
      if (version.name == name) return version;
    }
    return null;
  }
}

/// A rotating, pseudonymous participant id.
///
/// This is the ONLY identifier beta telemetry may carry, and it is
/// deliberately derived from nothing on the device: no advertising id, no
/// install id, no hardware serial, no account id. It is 64 random bits
/// generated here, rotated on a schedule and thrown away on revocation, so
/// two reports more than [rotationPeriod] apart cannot be joined back into
/// one participant history.
final class TelemetryPseudonymId {
  const TelemetryPseudonymId({
    required this.highBits,
    required this.lowBits,
    required this.issuedOnDay,
  });

  /// How long one id may be reused before it must be replaced.
  static const Duration rotationPeriod = Duration(days: 7);

  /// The rendered id's length in hex characters (2 × 32 bits).
  static const int hexLength = 16;

  /// The upper 32 random bits.
  final int highBits;

  /// The lower 32 random bits.
  final int lowBits;

  /// The day the id was issued, as whole days since the Unix epoch (UTC).
  /// A day number, not an instant: a millisecond timestamp is precise
  /// enough to correlate a report with an unrelated log line.
  final int issuedOnDay;

  /// The opaque wire form: [hexLength] lower-case hex characters. A getter,
  /// not a stored field — there is no text slot on this type at all.
  String get value =>
      highBits.toRadixString(16).padLeft(8, '0') +
      lowBits.toRadixString(16).padLeft(8, '0');

  /// Whether this id must be replaced before it is used again on [nowUtc].
  bool isExpiredAt(DateTime nowUtc) =>
      dayOf(nowUtc) - issuedOnDay >= rotationPeriod.inDays;

  /// Generates a fresh id. [random] and [nowUtc] are injected so the
  /// generator stays pure and testable — no ambient clock, no global RNG.
  static TelemetryPseudonymId generate({
    required Random random,
    required DateTime nowUtc,
  }) => TelemetryPseudonymId(
    highBits: random.nextInt(1 << 32),
    lowBits: random.nextInt(1 << 32),
    issuedOnDay: dayOf(nowUtc),
  );

  /// Rebuilds an id from its persisted parts, fail-closed: any part that is
  /// missing or out of the 32-bit range yields `null` rather than a
  /// half-valid id (which would then be reported as if it were real).
  static TelemetryPseudonymId? restore({
    required int? highBits,
    required int? lowBits,
    required int? issuedOnDay,
  }) {
    if (highBits == null || lowBits == null || issuedOnDay == null) return null;
    const maxBits = 1 << 32;
    if (highBits < 0 || highBits >= maxBits) return null;
    if (lowBits < 0 || lowBits >= maxBits) return null;
    if (issuedOnDay < 0) return null;
    return TelemetryPseudonymId(
      highBits: highBits,
      lowBits: lowBits,
      issuedOnDay: issuedOnDay,
    );
  }

  /// Whether [candidate] has the exact opaque shape [value] promises. The
  /// redaction guard uses it: a value that is not opaque-shaped is not an
  /// id, it is a leak wearing an id's field name.
  static bool isWellFormedValue(String candidate) =>
      candidate.length == hexLength &&
      candidate.codeUnits.every(_isLowerHexDigit);

  /// Whole days between the Unix epoch and [instant], in UTC.
  static int dayOf(DateTime instant) =>
      instant.toUtc().difference(DateTime.utc(1970)).inDays;

  static bool _isLowerHexDigit(int codeUnit) =>
      (codeUnit >= 0x30 && codeUnit <= 0x39) ||
      (codeUnit >= 0x61 && codeUnit <= 0x66);

  @override
  bool operator ==(Object other) =>
      other is TelemetryPseudonymId &&
      other.highBits == highBits &&
      other.lowBits == lowBits &&
      other.issuedOnDay == issuedOnDay;

  @override
  int get hashCode => Object.hash(highBits, lowBits, issuedOnDay);

  @override
  String toString() => 'TelemetryPseudonymId($value, day $issuedOnDay)';
}

/// The consent decision plus the pseudonym it authorises.
///
/// Revocation produces a record with NO pseudonym ([revoked]): keeping the
/// id "in case they come back" would keep a linkable identifier alive after
/// the user withdrew permission for exactly that.
final class TelemetryConsentRecord {
  const TelemetryConsentRecord({
    required this.state,
    required this.version,
    this.pseudonym,
  });

  /// The default on a device that has never been asked.
  static const TelemetryConsentRecord initial = TelemetryConsentRecord(
    state: TelemetryConsentState.notAsked,
    version: TelemetryConsentVersion.current,
  );

  final TelemetryConsentState state;

  /// Which version of the consent copy the user answered.
  final TelemetryConsentVersion version;

  /// Present only while [state] is [TelemetryConsentState.granted].
  final TelemetryPseudonymId? pseudonym;

  /// Whether collection is permitted right now: the user granted consent,
  /// they granted it for the copy currently shipped, and a pseudonym exists
  /// to attach. All three, fail-closed.
  bool get permitsCollection =>
      state.permitsCollection &&
      version == TelemetryConsentVersion.current &&
      pseudonym != null;

  /// Whether the user must be asked again — either no decision exists, or
  /// the stored one answers superseded copy.
  bool get needsDecision =>
      state == TelemetryConsentState.notAsked ||
      version != TelemetryConsentVersion.current;

  /// The record after an explicit grant of the currently shipped copy.
  static TelemetryConsentRecord granted(TelemetryPseudonymId id) =>
      TelemetryConsentRecord(
        state: TelemetryConsentState.granted,
        version: TelemetryConsentVersion.current,
        pseudonym: id,
      );

  /// The record after an explicit refusal or a revocation. The pseudonym is
  /// dropped, not retained.
  static const TelemetryConsentRecord revoked = TelemetryConsentRecord(
    state: TelemetryConsentState.denied,
    version: TelemetryConsentVersion.current,
  );

  @override
  bool operator ==(Object other) =>
      other is TelemetryConsentRecord &&
      other.state == state &&
      other.version == version &&
      other.pseudonym == pseudonym;

  @override
  int get hashCode => Object.hash(state, version, pseudonym);

  @override
  String toString() =>
      'TelemetryConsentRecord(${state.name}, ${version.name}, '
      'pseudonym: ${pseudonym == null ? 'none' : 'present'})';
}
