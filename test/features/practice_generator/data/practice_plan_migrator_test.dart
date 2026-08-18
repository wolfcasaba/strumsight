import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/data/local/practice_plan_migrator.dart';
import 'package:strumsight/features/practice_generator/data/local/practice_plan_serializer.dart';

import '../../../fixtures/practice_generator/plan/plan_fixtures.dart';

/// §6.1 has **three** pinned schema cells this test must keep on opposite
/// sides: below the current supported version migrates forward, current
/// is read unchanged, and above current is a controlled rejection.
void main() {
  group('PracticePlanMigrator', () {
    const migrator = PracticePlanMigrator();

    test(
      'current envelope schema version is supported (current == threshold)',
      () {
        expect(
          () => migrator.ensureSupported(
            envelopeSchemaVersion:
                PracticePlanMigrator.currentSupportedSchemaVersion,
          ),
          returnsNormally,
        );
      },
    );

    test('an envelope strictly newer than the supported version is a '
        'controlled rejection, not a best-effort read (A7, above cell)', () {
      final above = PracticePlanMigrator.currentSupportedSchemaVersion + 1;

      expect(
        () => migrator.ensureSupported(envelopeSchemaVersion: above),
        throwsA(
          isA<PracticePlanMigratorException>().having(
            (e) => e.code,
            'code',
            PracticePlanMigratorErrorCode.schemaVersionTooNew,
          ),
        ),
      );
    });

    test('an envelope strictly older than the current supported version '
        'migrates forward (A7, below cell — current − 1 migrates, '
        'not throws)', () {
      final below = PracticePlanMigrator.currentSupportedSchemaVersion - 1;

      // The migrator accepts any version ≤ current and routes it through
      // [migrateEnvelope]. There is no "tooOld" code: pre-current is
      // *migration territory*, not a rejection.
      expect(
        () => migrator.ensureSupported(envelopeSchemaVersion: below),
        returnsNormally,
      );
      final migrated = migrator.migrateEnvelope(<String, Object?>{
        'schemaVersion': below,
      });
      // The migrator does not relabel the schemaVersion (the body codec
      // reads the migrated envelope). What matters here is that the
      // call did not throw and returned an envelope-shaped map.
      expect(migrated['schemaVersion'], below);
    });

    test('a missing schemaVersion field reads as a controlled '
        'rejection (A7)', () {
      expect(
        () => migrator.readSchemaVersion(null),
        throwsA(
          isA<PracticePlanMigratorException>().having(
            (e) => e.code,
            'code',
            PracticePlanMigratorErrorCode.schemaVersionMissing,
          ),
        ),
      );
    });

    test('a non-integer schemaVersion reads as a controlled rejection', () {
      expect(
        () => migrator.readSchemaVersion('1'),
        throwsA(
          isA<PracticePlanMigratorException>().having(
            (e) => e.code,
            'code',
            PracticePlanMigratorErrorCode.schemaVersionMissing,
          ),
        ),
      );
    });

    test(
      'ensureSupportedFromEnvelope mirrors ensureSupported + the int guard',
      () {
        expect(
          () => migrator.ensureSupportedFromEnvelope(<String, Object?>{
            'schemaVersion': 'not-an-int',
          }),
          throwsA(isA<PracticePlanMigratorException>()),
        );
        expect(
          () => migrator.ensureSupportedFromEnvelope(<String, Object?>{
            'schemaVersion':
                PracticePlanMigrator.currentSupportedSchemaVersion + 1,
          }),
          throwsA(
            isA<PracticePlanMigratorException>().having(
              (e) => e.code,
              'code',
              PracticePlanMigratorErrorCode.schemaVersionTooNew,
            ),
          ),
        );
      },
    );
  });

  group('PracticePlanSerializer checksum (A8)', () {
    const serializer = PracticePlanSerializer();

    test('a body whose bytes were mutated after encoding fails with '
        'checksumMismatch, not a silent read (A8)', () {
      final encoded = _goodEnvelope(serializer);
      final asMap = encoded as Map<String, dynamic>;

      // Mutate the body in a way that does NOT change the structure
      // shape: change a single character in a string field.
      final body = asMap['body'] as Map<String, dynamic>;
      final originalTitle = body['title'] as String;
      body['title'] = '${originalTitle}TAMPERED';
      asMap['body'] = body;
      // Checksum intentionally NOT recomputed — that IS the tampering.

      expect(
        () => serializer.openEnvelope(asMap),
        throwsA(
          isA<PracticePlanSerializerException>().having(
            (e) => e.code,
            'code',
            PracticePlanSerializerErrorCode.checksumMismatch,
          ),
        ),
      );
    });

    test(
      'a replaced checksum with a wrong-but-correctly-shaped envelope is '
      'also rejected (A8 — the checksum must be re-derived before reading)',
      () {
        final encoded = _goodEnvelope(serializer);
        final asMap = encoded as Map<String, dynamic>;
        asMap['checksum'] = 'deadbeef' * 8; // 64 hex chars, wrong hash.

        expect(
          () => serializer.openEnvelope(asMap),
          throwsA(
            isA<PracticePlanSerializerException>().having(
              (e) => e.code,
              'code',
              PracticePlanSerializerErrorCode.checksumMismatch,
            ),
          ),
        );
      },
    );

    test('a freshly re-stamped checksum decodes cleanly (sanity — the '
        'test is guarding against reading without verification, not against '
        'legitimate re-encoding)', () {
      final encoded = _goodEnvelope(serializer);
      final opened = serializer.openEnvelope(encoded);
      expect(opened.body['title'], 'Fixture plan');
    });

    test('a missing checksum field is a controlled rejection', () {
      final encoded = _goodEnvelope(serializer);
      final asMap = Map<String, dynamic>.from(encoded as Map);
      asMap.remove('checksum');

      expect(
        () => serializer.openEnvelope(asMap),
        throwsA(
          isA<PracticePlanSerializerException>().having(
            (e) => e.code,
            'code',
            PracticePlanSerializerErrorCode.checksumMissing,
          ),
        ),
      );
    });
  });
}

Map<String, Object?> _goodEnvelope(PracticePlanSerializer serializer) {
  // The strict encoder requires a non-empty plan — use the public fixture
  // so this test file does not import the wider practice_generator barrel.
  return serializer.encodePlanRecord(plan());
}
