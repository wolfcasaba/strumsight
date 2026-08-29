import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_screen_reachability.dart';

/// One row of `docs/ui/retirement-plan.md`'s §6 machine-measured table,
/// parsed straight out of the markdown so A3/A4 check the actual shipped
/// document, not a hand-copied expectation of it.
final class _PlanRow {
  const _PlanRow({
    required this.screenPath,
    required this.verdict,
    required this.ownerRound,
    required this.successor,
    required this.reason,
  });

  final String screenPath;
  final String verdict;
  final String ownerRound;
  final String successor;
  final String reason;
}

List<_PlanRow> _parsePlanRows(String markdown) {
  const header =
      '| Screen | Class | Reachable | Flag-gated | Verdict | Owner round | Successor | Reason |';
  final lines = markdown.split('\n');
  final headerIndex = lines.indexOf(header);
  if (headerIndex == -1) {
    throw StateError('retirement-plan.md is missing the §6 table header');
  }
  final rows = <_PlanRow>[];
  // headerIndex + 1 is the `| --- | ... |` separator row.
  for (var i = headerIndex + 2; i < lines.length; i++) {
    final line = lines[i];
    if (!line.startsWith('|')) break;
    final cells = line
        .split('|')
        .sublist(1, line.split('|').length - 1)
        .map((c) => c.trim())
        .toList();
    if (cells.length != 8) {
      throw StateError('malformed plan row: $line');
    }
    final screenPath = cells[0].replaceAll('`', '');
    rows.add(
      _PlanRow(
        screenPath: screenPath,
        verdict: cells[4],
        ownerRound: cells[5],
        successor: cells[6].replaceAll('`', ''),
        reason: cells[7],
      ),
    );
  }
  return rows;
}

/// The same `grep -q design_system` measurement `docs/ui/migration-status.md`
/// uses for "migrated vs. legacy" — reused here so A3 can tell a
/// reachable-but-ALREADY-migrated screen (no round owed, ADR 0471 D6) apart
/// from a reachable-and-legacy one (round owed).
bool _isMigrated(String repositoryPath, String screenPath) => File(
  '$repositoryPath/$screenPath',
).readAsStringSync().contains('design_system');

/// The A4 assertion itself: which `retire` rows are missing a named
/// successor or a real (non-trivial) reason. Shared by the real-plan check
/// and its real-violation probe so both provably run the same logic.
List<String> _retireRowsMissingSuccessorOrReason(List<_PlanRow> retireRows) {
  final failing = <String>[];
  for (final row in retireRows) {
    final missingSuccessor = row.successor.isEmpty || row.successor == '—';
    final trivialReason = row.reason.trim().length <= 10;
    if (missingSuccessor || trivialReason) failing.add(row.screenPath);
  }
  return failing;
}

void main() {
  final repository = Directory.current;

  group('A1 — every one of the 96 real screens gets a verdict with a source '
      'reference', () {
    test('measures all 96, each with a non-empty source location, '
        'deterministically', () {
      final checker = ScreenReachability(repository);
      final first = checker.render();
      final second = checker.render();

      expect(first.verdicts, hasLength(96));
      expect(first.toJsonString(), second.toJsonString());
      for (final verdict in first.verdicts) {
        expect(verdict.primaryReference.path, isNotEmpty);
        expect(verdict.primaryReference.line, greaterThan(0));
        expect(verdict.declaredAt.path, verdict.screenPath);
      }
    });
  });

  group('A2 — imperative navigation counts as reachable (fixture)', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('reachability_a2_');
      _writeRoutingSkeleton(fixture);
      _write(fixture, 'lib/features/fixture/screens/orphan_screen.dart', '''
class OrphanScreen {
  const OrphanScreen();
}
''');
      _write(fixture, 'lib/features/fixture/pusher.dart', '''
import 'screens/orphan_screen.dart';

void openOrphan() {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const OrphanScreen()),
  );
}
''');
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    test('a screen never named by the router, but constructed elsewhere in '
        'lib/, is reachable', () {
      final result = ScreenReachability(fixture).render();
      final verdict = result.verdicts.singleWhere(
        (v) => v.className == 'OrphanScreen',
      );

      expect(verdict.isDeclarativelyReachable, isFalse);
      expect(verdict.isImperativelyReachable, isTrue);
      expect(verdict.isReachable, isTrue);
      expect(
        verdict.imperativeReferences.single.path,
        'lib/features/fixture/pusher.dart',
      );
    });
  });

  group('A2b — a router that reaches a screen through a public.dart barrel '
      '(class-name match, not file/import-path match)', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('reachability_a2b_');
      _write(fixture, 'lib/features/fixture/screens/hidden_screen.dart', '''
class HiddenScreen {
  const HiddenScreen();
}
''');
      _write(fixture, 'lib/features/fixture/public.dart', '''
library;

export 'screens/hidden_screen.dart';
''');
      // The router imports ONLY the barrel — never the screen file's own
      // path — mirroring the real tree's `vision/public.dart` (ADR 0471 D3,
      // brief §0.0.A/R3).
      _write(fixture, 'lib/app/routing/app_router.dart', '''
import '../../features/fixture/public.dart';

final routes = [
  GoRoute(path: '/hidden', builder: (_, __) => const HiddenScreen()),
];
''');
      _write(fixture, 'lib/app/routing/adaptive_shell_routes.dart', '');
      _write(fixture, 'lib/app/routing/route_guards.dart', '');
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    test('the screen is declaratively reachable even though the router '
        'never imports its file', () {
      final result = ScreenReachability(fixture).render();
      final verdict = result.verdicts.singleWhere(
        (v) => v.className == 'HiddenScreen',
      );

      expect(verdict.isDeclarativelyReachable, isTrue);
      expect(verdict.isReachable, isTrue);
      expect(
        verdict.declarativeReferences.single.source.path,
        'lib/app/routing/app_router.dart',
      );
    });
  });

  group('flag-gating (ADR 0471 D4, fixture)', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('reachability_flag_');
      _write(fixture, 'lib/features/fixture/screens/gated_screen.dart', '''
class GatedScreen {
  const GatedScreen();
}
''');
      _write(fixture, 'lib/app/routing/app_router.dart', '''
final routes = [
  if (someFeatureEnabled) ...[
    GoRoute(path: '/gated', builder: (_, __) => const GatedScreen()),
  ],
];
''');
      _write(fixture, 'lib/app/routing/adaptive_shell_routes.dart', '');
      _write(fixture, 'lib/app/routing/route_guards.dart', '');
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    test('a route registered only under an "...Enabled" if-guard is reported '
        'flag-gated, not silently reachable or dead', () {
      final result = ScreenReachability(fixture).render();
      final verdict = result.verdicts.singleWhere(
        (v) => v.className == 'GatedScreen',
      );

      expect(verdict.isReachable, isTrue);
      expect(verdict.isFlagGated, isTrue);
      expect(verdict.flagConditions, ['someFeatureEnabled']);
    });
  });

  group('A3 — every REACHABLE, still-legacy real screen has a named E15 '
      'round in the plan (plan ↔ measurement cross-check)', () {
    late List<_PlanRow> planRows;
    late Map<String, _PlanRow> planByPath;
    late ScreenReachabilityResult measured;

    setUpAll(() {
      final planFile = File('${repository.path}/docs/ui/retirement-plan.md');
      planRows = _parsePlanRows(planFile.readAsStringSync());
      planByPath = {for (final row in planRows) row.screenPath: row};
      measured = ScreenReachability(repository).render();
    });

    test('the plan has exactly one row per measured screen', () {
      expect(planRows.map((r) => r.screenPath).toSet(), hasLength(96));
      expect(
        planByPath.keys.toSet(),
        measured.verdicts.map((v) => v.screenPath).toSet(),
      );
    });

    test('every reachable-and-legacy screen has a migrate/retire verdict '
        'and a real E15-Rxx owner round', () {
      final ownerlessReachableLegacy = <String>[];
      for (final verdict in measured.verdicts) {
        if (!verdict.isReachable) continue;
        if (_isMigrated(repository.path, verdict.screenPath)) continue;
        final row = planByPath[verdict.screenPath];
        final hasOwner =
            row != null &&
            (row.verdict == 'migrate' || row.verdict == 'retire') &&
            RegExp(r'^E15-R\d+$').hasMatch(row.ownerRound);
        if (!hasOwner) ownerlessReachableLegacy.add(verdict.screenPath);
      }
      expect(
        ownerlessReachableLegacy,
        isEmpty,
        reason:
            'reachable-but-unmigrated screens with no named E15 round '
            '(ADR 0471 D6): $ownerlessReachableLegacy',
      );
    });

    // The KÖTELEZŐ valódi-sértés próba (brief §6.1/§7), automated: dropping
    // one reachable-and-legacy screen's owner round out of a COPY of the
    // real, measured plan rows must turn this cell red — proving the check
    // actually looks at the round column instead of trivially passing.
    test('dropping one real owner round out of a copy of the plan turns '
        'this cell red', () {
      final target = measured.verdicts.firstWhere(
        (v) =>
            v.isReachable &&
            !_isMigrated(repository.path, v.screenPath) &&
            planByPath[v.screenPath]?.ownerRound.startsWith('E15-R') == true,
      );
      final mutatedByPath = Map<String, _PlanRow>.of(planByPath);
      mutatedByPath[target.screenPath] = _PlanRow(
        screenPath: target.screenPath,
        verdict: planByPath[target.screenPath]!.verdict,
        ownerRound: '—',
        successor: planByPath[target.screenPath]!.successor,
        reason: planByPath[target.screenPath]!.reason,
      );

      final ownerlessReachableLegacy = <String>[];
      for (final verdict in measured.verdicts) {
        if (!verdict.isReachable) continue;
        if (_isMigrated(repository.path, verdict.screenPath)) continue;
        final row = mutatedByPath[verdict.screenPath];
        final hasOwner =
            row != null &&
            (row.verdict == 'migrate' || row.verdict == 'retire') &&
            RegExp(r'^E15-R\d+$').hasMatch(row.ownerRound);
        if (!hasOwner) ownerlessReachableLegacy.add(verdict.screenPath);
      }

      expect(ownerlessReachableLegacy, [target.screenPath]);
    });
  });

  group('A4 — every "retire" row in the real plan has a reason AND a named '
      'successor screen', () {
    late List<_PlanRow> retireRows;

    setUpAll(() {
      final planFile = File(
        '${Directory.current.path}/docs/ui/retirement-plan.md',
      );
      final rows = _parsePlanRows(planFile.readAsStringSync());
      retireRows = rows.where((r) => r.verdict == 'retire').toList();
    });

    test('no retire row has an empty successor or a trivial reason', () {
      expect(retireRows, isNotEmpty);
      expect(
        _retireRowsMissingSuccessorOrReason(retireRows),
        isEmpty,
        reason: 'retire rows missing a successor or a real reason',
      );
    });

    // The KÖTELEZŐ valódi-sértés próba for A4 (A3's shape, brief §6.1/§7):
    // blank one real retire row's successor in a COPY of the real, measured
    // plan rows and rerun the SAME assertion helper the cell above uses —
    // proving the check actually looks at the successor column instead of
    // trivially passing.
    test('blanking one real retire row\'s successor turns this cell red', () {
      final target = retireRows.first;
      final mutated = [
        for (final row in retireRows)
          if (row.screenPath == target.screenPath)
            _PlanRow(
              screenPath: row.screenPath,
              verdict: row.verdict,
              ownerRound: row.ownerRound,
              successor: '—',
              reason: row.reason,
            )
          else
            row,
      ];

      expect(_retireRowsMissingSuccessorOrReason(mutated), [target.screenPath]);
    });
  });
}

void _writeRoutingSkeleton(Directory fixture) {
  _write(fixture, 'lib/app/routing/app_router.dart', '// no routes here\n');
  _write(fixture, 'lib/app/routing/adaptive_shell_routes.dart', '');
  _write(fixture, 'lib/app/routing/route_guards.dart', '');
}

void _write(Directory root, String relativePath, String content) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}
