import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/feature_flags/public.dart';

import '../../tool/check_feature_flags.dart';

FeatureFlagDefinition _definitionOf(
  String key, {
  DateTime? expiresOn,
  String owner = 'lib/features/test',
  String killSwitchPath = 'n/a (fixture)',
}) {
  return FeatureFlagDefinition(
    key: key,
    owner: owner,
    risk: FeatureFlagRisk.low,
    failClosedDefault: false,
    killSwitchPath: killSwitchPath,
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

    // F1 (round brief §1, review MINOR-1): the reviewer's measured probe
    // added `final bool? probeNullableFlag;` and
    // `final bool probeInitializedFlag = true;` directly to `FeatureFlags`
    // and the OLD pattern (`final bool (\w+);`, no `?`, no initializer)
    // silently missed both — `dart run tool/check_feature_flags.dart` still
    // exited 0. This cell is RED on that old pattern (it would only see
    // `accountEnabled` and `plainFlag`) and GREEN on the fixed one, which
    // also must not be fooled by a getter or a doc-comment bait line.
    test('reads the plain, nullable, and initialized field forms alike, '
        'ignoring a getter and a doc-comment bait line', () {
      const source = '''
final class FeatureFlags {
  const FeatureFlags({required this.accountEnabled});

  /// Docs sometimes show a snippet like `final bool commentBaitEnabled;` —
  /// that must not be mistaken for a real field.
  final bool accountEnabled;
  final bool? probeNullableFlag;
  final bool probeInitializedFlag = true;
  final bool plainFlag;

  bool get usesNetwork => accountEnabled;
}
''';
      expect(parseFeatureFlagFieldNames(source), {
        'accountEnabled',
        'probeNullableFlag',
        'probeInitializedFlag',
        'plainFlag',
      });
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

    // F1 end-to-end: a nullable field and an initialized field, parsed
    // straight out of source via [parseFeatureFlagFieldNames], are still
    // caught as uncataloged. On the OLD field pattern this cell was RED for
    // the wrong reason — `parseFeatureFlagFieldNames` returned an EMPTY set
    // for this source (neither form matched `final bool (\w+);`), so the
    // completeness loop had nothing to iterate over and `report.isClean`
    // came back `true`: the audit silently passed with two real fields
    // missing from the catalog, exactly the review's measured escape.
    test('a nullable field and an initialized field parsed from source are '
        'still flagged missingCatalogEntry when uncataloged', () {
      const source = '''
final class Probe {
  final bool? probeNullableFlag;
  final bool probeInitializedFlag = true;
}
''';
      final fieldNames = parseFeatureFlagFieldNames(source);
      final report = auditFeatureFlagRegistry(
        sourceFieldNames: fieldNames,
        registry: const [],
        now: DateTime(2026, 8, 28),
      );
      expect(report.isClean, isFalse);
      expect(
        report.issues,
        everyElement(
          isA<FeatureFlagAuditIssue>().having(
            (i) => i.code,
            'code',
            FeatureFlagAuditIssueCode.missingCatalogEntry,
          ),
        ),
      );
      final messages = report.issues.map((i) => i.message).join('\n');
      expect(messages, contains('probeNullableFlag'));
      expect(messages, contains('probeInitializedFlag'));
    });
  });

  group('auditFeatureFlagRegistry — A1 (metadata completeness)', () {
    test('an entry with an empty owner is flagged incompleteCatalogEntry', () {
      final report = auditFeatureFlagRegistry(
        sourceFieldNames: {'accountEnabled'},
        registry: [_definitionOf('accountEnabled', owner: '')],
        now: DateTime(2026, 8, 28),
      );
      expect(report.isClean, isFalse);
      final issue = report.issues.singleWhere(
        (i) => i.code == FeatureFlagAuditIssueCode.incompleteCatalogEntry,
      );
      expect(issue.message, contains('accountEnabled'));
      expect(issue.message, contains('owner'));
    });

    test('an entry with a whitespace-only killSwitchPath is flagged '
        'incompleteCatalogEntry', () {
      final report = auditFeatureFlagRegistry(
        sourceFieldNames: {'accountEnabled'},
        registry: [_definitionOf('accountEnabled', killSwitchPath: '   ')],
        now: DateTime(2026, 8, 28),
      );
      expect(report.isClean, isFalse);
      final issue = report.issues.singleWhere(
        (i) => i.code == FeatureFlagAuditIssueCode.incompleteCatalogEntry,
      );
      expect(issue.message, contains('accountEnabled'));
      expect(issue.message, contains('killSwitchPath'));
    });

    test('the real registry has no empty owner or kill-switch path (40/40 '
        'entries complete)', () {
      final report = auditFeatureFlagRegistry(
        sourceFieldNames: featureFlagRegistry.map((d) => d.key).toSet(),
        registry: featureFlagRegistry,
        now: DateTime(2026, 8, 28),
      );
      expect(
        report.issues.where(
          (i) => i.code == FeatureFlagAuditIssueCode.incompleteCatalogEntry,
        ),
        isEmpty,
        reason: report.format(),
      );
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
