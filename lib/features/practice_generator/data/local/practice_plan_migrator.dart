/// Schema migration for the local practice-plan envelope (ADR 0267).
///
/// The envelope's `schemaVersion` is what this migrator gates on (§5.6):
/// older envelopes migrate **up** to the current version, the current
/// version passes through unchanged, and a newer envelope is a controlled
/// rejection — never a best-effort read.
///
/// The three cells defined in brief §6.1:
///
/// | incoming schemaVersion                | behaviour                                     |
/// |---------------------------------------|-----------------------------------------------|
/// | any value < [currentSupportedSchemaVersion] | migrates forward to `current`          |
/// | == [currentSupportedSchemaVersion]    | returned unchanged                            |
/// | > [currentSupportedSchemaVersion]     | throws [PracticePlanMigratorException]        |
///
/// The migrator never throws at parse time — it requires the
/// already-decoded envelope shape and decides whether the schema version
/// is acceptable, then returns the *migrated* body for the serializer to
/// validate (checksum etc.) and the body codec to decode.
///
/// Schema 1 is the initial envelope; no field renames or removals yet.
/// When the envelope shape changes, add a `_migrateVxToVy` step here and
/// bump [currentSupportedSchemaVersion] — a reader that did not get the
/// bump cannot migrate the new shape forward and will reject it
/// (intentional: never best-effort).
library;

/// Why a schema version was rejected.
abstract final class PracticePlanMigratorErrorCode {
  /// The envelope's `schemaVersion` field was absent or not an `int`.
  static const String schemaVersionMissing =
      'practice_plan.migrator.schemaVersion.missing';

  /// Newer than [PracticePlanMigrator.currentSupportedSchemaVersion].
  static const String schemaVersionTooNew =
      'practice_plan.migrator.schemaVersion.too_new';
}

/// Thrown when an envelope's `schemaVersion` is outside what this build
/// understands.
class PracticePlanMigratorException implements Exception {
  PracticePlanMigratorException(this.code, {this.field, this.foundVersion});

  final String code;
  final String? field;
  final int? foundVersion;

  @override
  String toString() =>
      'PracticePlanMigratorException($code'
      '${field == null ? '' : ', field: $field'}'
      '${foundVersion == null ? '' : ', found: $foundVersion'})';
}

/// Stateless schema-migration policy for the local plan store.
class PracticePlanMigrator {
  const PracticePlanMigrator();

  /// The envelope schema version this build writes and reads natively.
  ///
  /// Bump in the same change that introduces a `_migrateVxToVy` step — a
  /// reader that did not get the bump cannot migrate the new shape forward
  /// and will reject it (intentional: never best-effort).
  static const int currentSupportedSchemaVersion = 1;

  /// Validates [envelopeSchemaVersion] and applies any needed migration.
  ///
  /// * [envelopeSchemaVersion] `> currentSupportedSchemaVersion` is a
  ///   controlled rejection — the build has no migration forward for an
  ///   unknown future envelope.
  /// * `== currentSupportedSchemaVersion` is a no-op pass-through.
  /// * `< currentSupportedSchemaVersion` is migrated forward via
  ///   [migrateEnvelope]; [envelopeSchemaVersion] (the input integer) is
  ///   returned so callers can audit what was passed in.
  int ensureSupported({required int envelopeSchemaVersion}) {
    if (envelopeSchemaVersion > currentSupportedSchemaVersion) {
      throw PracticePlanMigratorException(
        PracticePlanMigratorErrorCode.schemaVersionTooNew,
        field: 'schemaVersion',
        foundVersion: envelopeSchemaVersion,
      );
    }
    return envelopeSchemaVersion;
  }

  /// Decodes the envelope's `schemaVersion` (required, must be an `int`)
  /// and applies the migration policy in one call.
  int readSchemaVersion(Object? raw) {
    if (raw is! int) {
      throw PracticePlanMigratorException(
        PracticePlanMigratorErrorCode.schemaVersionMissing,
        field: 'schemaVersion',
      );
    }
    return raw;
  }

  /// Convenience: validates a decoded envelope map's schemaVersion.
  int ensureSupportedFromEnvelope(Map<String, Object?> envelope) {
    final raw = envelope['schemaVersion'];
    final version = readSchemaVersion(raw);
    return ensureSupported(envelopeSchemaVersion: version);
  }

  /// Migrates [envelope] forward to [currentSupportedSchemaVersion].
  ///
  /// Today's only known older version (`0`) maps to schema 1 with no
  /// field renames — a real migration step will be added the first time
  /// the envelope shape changes, and this method is the one place to
  /// extend.
  Map<String, Object?> migrateEnvelope(Map<String, Object?> envelope) {
    final raw = envelope['schemaVersion'];
    final from = readSchemaVersion(raw);
    if (from == currentSupportedSchemaVersion) return envelope;
    return _migrateVxToCurrent(envelope, from);
  }

  Map<String, Object?> _migrateVxToCurrent(
    Map<String, Object?> envelope,
    int fromVersion,
  ) {
    // Today: only one known prior shape (v0 → v1) and it is a no-op
    // (no field renames happened between v0 and v1). When the envelope
    // schema changes, branch on [fromVersion] here.
    return envelope;
  }
}
