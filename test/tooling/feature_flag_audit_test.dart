import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/feature_flags/public.dart';

import '../../tool/check_feature_flags.dart';

FeatureFlagDefinition _definitionOf(String key, {DateTime? expiresOn}) {
  return FeatureFlagDefinition(
    key: key,
    owner: 'lib/features/test',
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    killSwitchPath: 'n/a (fixture)',
    expiresOn: expiresOn,
  );
}

void main() {
  group('parseFeatureFlagFieldNames', () {
    test('reads every `final bool <name>;` field, ignoring other members', () {
      const source = '''
final class FeatureFlags {
  const FeatureFlags({required this.accountEnabled, this.visionEnabled = false});

  final bool accountEnabled;
  final bool visionEnabled;

  bool get usesNetwork => accountEnabled;
}
''';
      expect(parseFeatureFlagFieldNames(source), {
        'accountEnabled',
        'visionEnabled',
      });
    });

    test('an empty source yields an empty set, not a crash', () {
      expect(parseFeatureFlagFieldNames(''), isEmpty);
    });
  });

  group(
    'isFeatureFlagExpired — the threshold cell triple (round brief §0.0 R4, '
    'inclusive boundary, injected now)',
    () {
      final now = DateTime(2026, 8, 28);

      test('expiresOn = yesterday → expired (PIROS)', () {
        expect(
          isFeatureFlagExpired(expiresOn: DateTime(2026, 8, 27), now: now),
          isTrue,
        );
      });

      test('expiresOn = today → still valid (ZÖLD, inclusive boundary)', () {
        expect(
          isFeatureFlagExpired(expiresOn: DateTime(2026, 8, 28), now: now),
          isFalse,
        );
      });

      test('expiresOn = tomorrow → still valid (ZÖLD)', () {
        expect(
          isFeatureFlagExpired(expiresOn: DateTime(2026, 8, 29), now: now),
          isFalse,
        );
      });
    },
  );

  group('auditFeatureFlagRegistry — A1 (completeness)', () {
    test(
      'a source field with no catalog entry is flagged missingCatalogEntry',
      () {
        final report = auditFeatureFlagRegistry(
          sourceFieldNames: {'accountEnabled', 'visionEnabled'},
          registry: [_definitionOf('accountEnabled')],
          now: DateTime(2026, 8, 28),
        );
        expect(report.isClean, isFalse);
        final issue = report.issues.singleWhere(
          (i) => i.code == FeatureFlagAuditIssueCode.missingCatalogEntry,
        );
        expect(issue.message, contains('visionEnabled'));
      },
    );

    test('a catalog entry with no matching source field is flagged '
        'unknownCatalogEntry', () {
      final report = auditFeatureFlagRegistry(
        sourceFieldNames: {'accountEnabled'},
        registry: [_definitionOf('accountEnabled'), _definitionOf('ghostFlag')],
        now: DateTime(2026, 8, 28),
      );
      expect(report.isClean, isFalse);
      final issue = report.issues.singleWhere(
        (i) => i.code == FeatureFlagAuditIssueCode.unknownCatalogEntry,
      );
      expect(issue.message, contains('ghostFlag'));
    });

    test('a duplicated catalog key is flagged duplicateCatalogEntry', () {
      final report = auditFeatureFlagRegistry(
        sourceFieldNames: {'accountEnabled'},
        registry: [
          _definitionOf('accountEnabled'),
          _definitionOf('accountEnabled'),
        ],
        now: DateTime(2026, 8, 28),
      );
      expect(
        report.issues.map((i) => i.code),
        contains(FeatureFlagAuditIssueCode.duplicateCatalogEntry),
      );
    });

    test('a matching set of fields and catalog keys reports clean', () {
      final report = auditFeatureFlagRegistry(
        sourceFieldNames: {'accountEnabled', 'visionEnabled'},
        registry: [
          _definitionOf('accountEnabled'),
          _definitionOf('visionEnabled'),
        ],
        now: DateTime(2026, 8, 28),
      );
      expect(report.isClean, isTrue, reason: report.format());
    });
  });

  group('auditFeatureFlagRegistry — A5 (expiration)', () {
    test('an expired flag turns the audit red', () {
      final report = auditFeatureFlagRegistry(
        sourceFieldNames: {'staleFlag'},
        registry: [
          _definitionOf('staleFlag', expiresOn: DateTime(2026, 8, 27)),
        ],
        now: DateTime(2026, 8, 28),
      );
      expect(report.isClean, isFalse);
      final issue = report.issues.singleWhere(
        (i) => i.code == FeatureFlagAuditIssueCode.expiredFlag,
      );
      expect(issue.message, contains('staleFlag'));
    });

    test('a flag with no expiresOn (a durable capability switch) never '
        'expires', () {
      final report = auditFeatureFlagRegistry(
        sourceFieldNames: {'durableFlag'},
        registry: [_definitionOf('durableFlag')],
        now: DateTime(2099, 1, 1),
      );
      expect(report.isClean, isTrue, reason: report.format());
    });
  });

  group('checkFeatureFlagsAtRoot — R5 (the real, shipped catalog is green)', () {
    test('the real registry matches the real feature_flags.dart source with '
        'no expired entries', () {
      final report = checkFeatureFlagsAtRoot(
        projectRoot: Directory.current,
        now: DateTime(2026, 8, 28),
      );
      expect(report.isClean, isTrue, reason: report.format());
    });

    // The KÖTELEZŐ valódi-sértés próba (brief §6.1 / §6): dropping one
    // vision* entry out of a copy of the real registry, checked against the
    // real, measured source field names, must turn A1 red — the automated
    // form of the manual probe documented in the round's §10 handoff (which
    // also mutates the real registry file on disk, re-runs the gate, and
    // restores it).
    test('dropping the visionExperimentalFineFretEnabled entry out of the real '
        'registry turns A1 red against the real measured source fields', () {
      final sourceFile = File(
        '${Directory.current.absolute.path}/lib/app/config/feature_flags.dart',
      );
      final realFieldNames = parseFeatureFlagFieldNames(
        sourceFile.readAsStringSync(),
      );
      final mutatedRegistry = featureFlagRegistry
          .where((d) => d.key != 'visionExperimentalFineFretEnabled')
          .toList();

      final report = auditFeatureFlagRegistry(
        sourceFieldNames: realFieldNames,
        registry: mutatedRegistry,
        now: DateTime(2026, 8, 28),
      );

      expect(report.isClean, isFalse);
      final issue = report.issues.singleWhere(
        (i) => i.code == FeatureFlagAuditIssueCode.missingCatalogEntry,
      );
      expect(issue.message, contains('visionExperimentalFineFretEnabled'));
    });
  });
}
