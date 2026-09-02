import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/feature_flags/public.dart';
import 'package:strumsight/core/storage/storage_migrator.dart'
    show appStorageMigrations;

import '../../tool/check_architecture.dart' show architectureAllowlist;
import '../../tool/check_deprecations.dart';

FeatureFlagDefinition _flag(String key, {DateTime? expiresOn}) {
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
  group('findDeprecatedSites / countExternalImporters — A1', () {
    test(
      'A1 every @Deprecated site gets an inventory item with a callsite count',
      () {
        final files = {
          'lib/features/old/shim.dart':
              "@Deprecated('use new')\nexport '../new/thing.dart';\n",
          'lib/features/new/thing.dart': 'class Thing {}\n',
          'lib/features/consumer_a.dart':
              "import 'package:strumsight/features/old/shim.dart';\n",
          'lib/features/nested/consumer_b.dart': "import '../old/shim.dart';\n",
          'lib/features/unrelated.dart': "import 'dart:async';\n",
        };
        final sites = findDeprecatedSites(files);
        expect(sites, hasLength(1));
        final site = sites.single;
        expect(site.filePath, 'lib/features/old/shim.dart');
        expect(site.line, 1);
        expect(site.message, 'use new');
        // consumer_a.dart (package: import) and nested/consumer_b.dart
        // (relative import, properly resolved against its own directory)
        // both reach the shim; unrelated.dart and the shim's own export do
        // not count.
        expect(site.externalImporterCount, 2);
      },
    );

    test('A1 the real tree reports 12 deprecated sites in 9 files', () {
      final files = readSourceTree(
        projectRoot: Directory.current,
        relativeSubdir: 'lib',
      );
      final sites = findDeprecatedSites(files);
      expect(sites, hasLength(12));
      expect(sites.map((s) => s.filePath).toSet(), hasLength(9));
      expect(
        sites,
        everyElement(
          isA<DeprecatedSite>().having(
            (s) => s.filePath,
            'filePath',
            isNotEmpty,
          ),
        ),
      );
    });

    test('A1 no @Deprecated form is silently missed', () {
      final fixtureFiles = {
        'lib/features/single/single_line.dart':
            "@Deprecated('single line form')\nclass SingleLine {}\n",
        'lib/features/multi/multi_line.dart':
            "@Deprecated(\n"
            "  'a multi-line deprecation message '\n"
            "  'spanning two adjacent string literals',\n"
            ")\n"
            "class MultiLine {}\n",
      };
      final fixtureRawCount = fixtureFiles.values
          .map((source) => '@Deprecated('.allMatches(source).length)
          .fold<int>(0, (sum, count) => sum + count);
      expect(fixtureRawCount, 2);
      expect(findDeprecatedSites(fixtureFiles), hasLength(fixtureRawCount));

      final realFiles = readSourceTree(
        projectRoot: Directory.current,
        relativeSubdir: 'lib',
      );
      final realRawCount = realFiles.values
          .map((source) => '@Deprecated('.allMatches(source).length)
          .fold<int>(0, (sum, count) => sum + count);
      expect(
        findDeprecatedSites(realFiles),
        hasLength(realRawCount),
        reason:
            'raw "@Deprecated(" occurrence count ($realRawCount) must match '
            'findDeprecatedSites — a mismatch means the parser silently '
            'misses a valid @Deprecated form.',
      );
    });
  });

  group('findExpiredFlags — A2 (no second truth, inclusive boundary)', () {
    test('A2 expired flags come from the round-5 checker', () {
      final now = DateTime(2026, 8, 28);
      final registry = [
        _flag('freshFlag', expiresOn: DateTime(2026, 9, 1)),
        _flag('staleFlag', expiresOn: DateTime(2026, 8, 27)),
        _flag('durableFlag'),
      ];
      final expired = findExpiredFlags(registry: registry, now: now);
      expect(expired.map((f) => f.key), ['staleFlag']);
    });

    test('A2 expiry boundary is inclusive on the expiry day', () {
      final now = DateTime(2026, 8, 28);
      final registry = [_flag('todayFlag', expiresOn: DateTime(2026, 8, 28))];
      expect(findExpiredFlags(registry: registry, now: now), isEmpty);
    });
  });

  group('check_deprecations.dart source — A2 has no second expiry truth', () {
    test('A2 the tool has no second expiry truth of its own', () {
      final toolSource = File(
        '${Directory.current.path}/tool/check_deprecations.dart',
      ).readAsStringSync();
      expect(
        toolSource,
        contains(
          "import 'check_feature_flags.dart' show isFeatureFlagExpired;",
        ),
        reason:
            'the tool must import the round-5 checker\'s isFeatureFlagExpired '
            'rather than building its own expiry truth.',
      );
      expect(
        toolSource,
        contains('isFeatureFlagExpired('),
        reason:
            'the expiry decision must call the imported isFeatureFlagExpired.',
      );
      for (final localComparison in const [
        '.isAfter(',
        '.isBefore(',
        '.compareTo(',
      ]) {
        expect(
          toolSource.contains(localComparison),
          isFalse,
          reason:
              'found "$localComparison" in tool/check_deprecations.dart — that '
              'is a second, local day-granularity date comparison duplicating '
              'isFeatureFlagExpired (§0.0/R4).',
        );
      }
    });
  });

  group('allowlistExceedsBaseline — A3 + the threshold cell triple', () {
    test(
      'A3 the shipped architecture allowlist stays at the measured baseline',
      () {
        expect(
          allowlistExceedsBaseline(
            allowlist: architectureAllowlist,
            baseline: architectureAllowlistBaseline,
          ),
          isFalse,
        );
      },
    );

    test('threshold below — 11 entries', () {
      final fixture = {
        for (var i = 0; i < architectureAllowlistBaseline - 1; i++)
          'fixture-entry-$i',
      };
      expect(
        allowlistExceedsBaseline(
          allowlist: fixture,
          baseline: architectureAllowlistBaseline,
        ),
        isFalse,
      );
    });

    test('threshold on — 12 entries', () {
      final fixture = {
        for (var i = 0; i < architectureAllowlistBaseline; i++)
          'fixture-entry-$i',
      };
      expect(
        allowlistExceedsBaseline(
          allowlist: fixture,
          baseline: architectureAllowlistBaseline,
        ),
        isFalse,
      );
    });

    test('threshold above — 13 entries', () {
      final fixture = {
        for (var i = 0; i < architectureAllowlistBaseline + 1; i++)
          'fixture-entry-$i',
      };
      expect(
        allowlistExceedsBaseline(
          allowlist: fixture,
          baseline: architectureAllowlistBaseline,
        ),
        isTrue,
      );
    });
  });

  group('auditTechnicalDebtItems — A4', () {
    test('A4 a debt item without an owner is an issue', () {
      final issues = auditTechnicalDebtItems(
        items: const [
          TechnicalDebtItem(
            name: 'no-owner item',
            path: '',
            owner: '',
            removalCondition: 'some concrete condition',
          ),
        ],
        frozenScopeCells: const [],
      );
      expect(
        issues.map((i) => i.code),
        contains(TechnicalDebtIssueCode.missingOwner),
      );
    });

    test('A4 a debt item without a removal condition is an issue', () {
      final issues = auditTechnicalDebtItems(
        items: const [
          TechnicalDebtItem(
            name: 'no-condition item',
            path: '',
            owner: 'lib/features/example',
            removalCondition: '   ',
          ),
        ],
        frozenScopeCells: const [],
      );
      expect(
        issues.map((i) => i.code),
        contains(TechnicalDebtIssueCode.missingRemovalCondition),
      );
    });

    test('A4 the shipped technical-debt.md is clean', () {
      final debtSource = File(
        '${Directory.current.path}/docs/release/technical-debt.md',
      ).readAsStringSync();
      final contractFreezeSource = File(
        '${Directory.current.path}/docs/release/contract-freeze.md',
      ).readAsStringSync();
      final items = parseTechnicalDebtInventory(debtSource);
      expect(items, isNotEmpty);
      final issues = auditTechnicalDebtItems(
        items: items,
        frozenScopeCells: parseFrozenScopeCells(contractFreezeSource),
      );
      expect(issues, isEmpty, reason: issues.map((i) => i.message).join('\n'));
    });
  });

  group('A5 — supported legacy client and contract freeze', () {
    test('A5 the supported-client migration chain is intact', () {
      expect(appStorageMigrations.length, 22);
      expect(
        migrationChainIntact(actualLength: appStorageMigrations.length),
        isTrue,
      );
      expect(migrationChainIntact(actualLength: 21), isFalse);
    });

    test('A5 no debt item targets a frozen contract scope', () {
      final frozenScopeCells = [
        'lib/app/routing/app_router.dart:180-183',
        'lib/core/storage/storage_migrator.dart',
      ];
      final cleanIssues = auditTechnicalDebtItems(
        items: const [
          TechnicalDebtItem(
            name: 'unrelated item',
            path: 'lib/features/library_v2/',
            owner: 'lib/features/library_v2',
            removalCondition: 'measured migration complete',
          ),
        ],
        frozenScopeCells: frozenScopeCells,
      );
      expect(
        cleanIssues.where(
          (i) => i.code == TechnicalDebtIssueCode.frozenScopeConflict,
        ),
        isEmpty,
      );

      final conflictingIssues = auditTechnicalDebtItems(
        items: const [
          TechnicalDebtItem(
            name: 'frozen-conflict item',
            path: 'lib/app/routing/app_router.dart:180-183',
            owner: 'lib/app/routing',
            removalCondition: 'some condition',
          ),
        ],
        frozenScopeCells: frozenScopeCells,
      );
      expect(
        conflictingIssues.map((i) => i.code),
        contains(TechnicalDebtIssueCode.frozenScopeConflict),
      );
    });
  });

  group('checkDeprecationsAtRoot — the real, shipped tree is green', () {
    test('the real tree audit is clean', () {
      final report = checkDeprecationsAtRoot(
        projectRoot: Directory.current,
        now: DateTime(2026, 9, 2),
      );
      expect(report.isClean, isTrue, reason: report.format());
    });
  });
}
