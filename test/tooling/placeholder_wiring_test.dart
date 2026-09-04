import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_placeholder_wiring.dart';
import '../../tool/check_screen_reachability.dart';
import '../e2e/full_app_walkthrough_test.dart' show runCoreWalkthrough;

/// One row of `docs/release/full-app-verification.md`'s §3.2 machine-parsed
/// table, parsed straight out of the markdown (round brief §5.4/2) — the
/// same discipline `screen_reachability_test.dart`'s `_parsePlanRows` uses
/// for `docs/ui/retirement-plan.md`.
final class _ExcludedRow {
  const _ExcludedRow({
    required this.screenPath,
    required this.indok,
    required this.gazda,
    required this.kor,
  });

  final String screenPath;
  final String indok;
  final String gazda;
  final String kor;
}

const _excludedTableHeader = '| Screen | Indok | Gazda | Kör |';
final _korPattern = RegExp(r'^E\d+-R\d+$');

List<_ExcludedRow> _parseExcludedRows(String markdown) {
  final lines = markdown.split('\n');
  final headerIndex = lines.indexOf(_excludedTableHeader);
  if (headerIndex == -1) {
    throw StateError(
      'full-app-verification.md is missing the §3.2 table header',
    );
  }
  final rows = <_ExcludedRow>[];
  for (var i = headerIndex + 2; i < lines.length; i++) {
    final line = lines[i];
    if (!line.startsWith('|')) break;
    final cells = line
        .split('|')
        .sublist(1, line.split('|').length - 1)
        .map((c) => c.trim())
        .toList();
    if (cells.length != 4) {
      throw StateError('malformed excluded-table row: $line');
    }
    rows.add(
      _ExcludedRow(
        screenPath: cells[0].replaceAll('`', ''),
        indok: cells[1],
        gazda: cells[2],
        kor: cells[3],
      ),
    );
  }
  return rows;
}

/// The A5 assertion itself: which rows have an empty Indok/Gazda, or a Kör
/// that is neither `E\d+-R\d+` nor a stated `nincs — <indok>` (with a real,
/// non-empty explanation after the dash). Shared by the real-doc check so
/// a future edit can reuse the same predicate.
List<String> _rowsFailingA5(List<_ExcludedRow> rows) {
  final failing = <String>[];
  for (final row in rows) {
    final emptyIndok = row.indok.trim().isEmpty;
    final emptyGazda = row.gazda.trim().isEmpty;
    final kor = row.kor.trim();
    final validKor =
        _korPattern.hasMatch(kor) ||
        (kor.startsWith('nincs —') && kor.substring(7).trim().isNotEmpty);
    if (emptyIndok || emptyGazda || !validKor) failing.add(row.screenPath);
  }
  return failing;
}

void _writeRoutingSkeleton(Directory fixture, {String appRouterContent = ''}) {
  _write(fixture, 'lib/app/routing/app_router.dart', appRouterContent);
  _write(fixture, 'lib/app/routing/adaptive_shell_routes.dart', '');
  _write(fixture, 'lib/app/routing/route_guards.dart', '');
  _write(fixture, 'lib/app/routing/app_route.dart', '');
}

void _write(Directory root, String relativePath, String content) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

void main() {
  final repository = Directory.current;

  group('A1 — the router and composition layers are placeholder-free '
      'on the real tree', () {
    test('zero unsuppressed findings, exit code 0', () {
      final result = PlaceholderWiring(repository).render();

      expect(
        result.findings,
        isEmpty,
        reason:
            'unexpected placeholder-wiring findings: '
            '${result.findings.map((f) => f.detail).toList()}',
      );
      expect(result.exitCode, 0);
    });

    test('is deterministic across two renders', () {
      final first = PlaceholderWiring(repository).render();
      final second = PlaceholderWiring(repository).render();
      expect(first.toJsonString(), second.toJsonString());
    });
  });

  group('A7 — the exception list is exactly one real, non-vacuous entry', () {
    test('exactly one exception, non-empty reason, nothing vacuous', () {
      expect(placeholderExceptions, hasLength(1));
      expect(placeholderExceptions.single.reason.trim(), isNotEmpty);

      final result = PlaceholderWiring(repository).render();
      expect(result.vacuousExceptions, isEmpty);
      expect(result.suppressedFindings, hasLength(1));
      expect(
        result.suppressedFindings.single.declarationName,
        placeholderExceptions.single.declarationName,
      );
    });
  });

  group('A8 — the measured file set is non-empty and not narrowed', () {
    test('H1 >= 4, H2 >= 14, neither set is empty', () {
      final wiring = PlaceholderWiring(repository);
      expect(wiring.h1Files.length, greaterThanOrEqualTo(4));
      expect(wiring.h2Files.length, greaterThanOrEqualTo(14));

      final result = wiring.render();
      expect(result.fileSetEmpty, isFalse);
    });

    test('an empty measured file set is fail-closed (non-zero exit), '
        'never a vacuous green', () {
      final fixture = Directory.systemTemp.createTempSync(
        'placeholder_wiring_empty_',
      );
      addTearDown(() => fixture.deleteSync(recursive: true));

      final result = PlaceholderWiring(fixture).render();

      expect(result.fileSetEmpty, isTrue);
      expect(result.exitCode, isNot(0));
      expect(result.findings, isEmpty);
    });
  });

  group('P1/P2/P3 rule fixtures — the checker actually flags each shape', () {
    late Directory fixture;

    setUp(() {
      fixture = Directory.systemTemp.createTempSync('placeholder_wiring_');
    });

    tearDown(() => fixture.deleteSync(recursive: true));

    test('P1 — a screen-class constructor with a placeholder named '
        'argument in H1', () {
      _write(fixture, 'lib/features/fixture/screens/orphan_screen.dart', '''
class OrphanScreen {
  const OrphanScreen({required this.items});
  final List<String> items;
}
''');
      _writeRoutingSkeleton(
        fixture,
        appRouterContent: '''
import '../../features/fixture/screens/orphan_screen.dart';

final routes = [
  GoRoute(
    path: '/orphan',
    builder: (_, __) => const OrphanScreen(
      items: [],
    ),
  ),
];
''',
      );
      _write(
        fixture,
        'lib/features/fixture/application/fixture_providers.dart',
        'final fixtureValueProvider = Provider<int>((ref) => 1);\n',
      );

      final result = PlaceholderWiring(fixture).render();

      expect(result.findings, hasLength(1));
      expect(result.findings.single.rule, 'P1');
      expect(result.findings.single.declarationName, 'OrphanScreen.items');
      expect(result.exitCode, isNot(0));
    });

    test('P2 — a top-level provider whose entire builder body is a bare '
        'placeholder literal', () {
      _writeRoutingSkeleton(fixture);
      _write(
        fixture,
        'lib/features/fixture/providers/fixture_providers.dart',
        'final fixtureListProvider = Provider<List<int>>((ref) => const <int>[]);\n',
      );

      final result = PlaceholderWiring(fixture).render();

      expect(result.findings, hasLength(1));
      expect(result.findings.single.rule, 'P2');
      expect(result.findings.single.declarationName, 'fixtureListProvider');
      expect(result.exitCode, isNot(0));
    });

    test('P3 — a top-level const/final declaration whose value is a bare '
        'placeholder literal (boolean-widened)', () {
      _writeRoutingSkeleton(fixture);
      _write(
        fixture,
        'lib/features/fixture/application/fixture_providers.dart',
        'const bool fixtureIsOffline = false;\n',
      );

      final result = PlaceholderWiring(fixture).render();

      expect(result.findings, hasLength(1));
      expect(result.findings.single.rule, 'P3');
      expect(result.findings.single.declarationName, 'fixtureIsOffline');
      expect(result.exitCode, isNot(0));
    });

    test('a local variable / algorithm-internal literal is NOT a finding '
        '(only top-level declarations and named constructor args count)', () {
      _writeRoutingSkeleton(fixture);
      _write(
        fixture,
        'lib/features/fixture/providers/fixture_providers.dart',
        '''
final fixtureCounterProvider = Provider<int>((ref) {
  var counter = 0;
  return counter + 1;
});
''',
      );

      final result = PlaceholderWiring(fixture).render();

      expect(result.findings, isEmpty);
      expect(result.exitCode, 0);
    });
  });

  group('A4/A5 — the walked set and the documented exclusion table exactly '
      'partition the measured-reachable screen set', () {
    late ScreenReachabilityResult measured;
    late Map<String, String> pathByClassName;
    late Set<String> reachablePaths;
    late List<_ExcludedRow> excludedRows;

    setUpAll(() {
      measured = ScreenReachability(repository).render();
      pathByClassName = {
        for (final v in measured.verdicts) v.className: v.screenPath,
      };
      reachablePaths = {
        for (final v in measured.verdicts)
          if (v.isReachable) v.screenPath,
      };
      final doc = File(
        '${repository.path}/docs/release/full-app-verification.md',
      ).readAsStringSync();
      excludedRows = _parseExcludedRows(doc);
    });

    testWidgets(
      'the walked set (from actually RUNNING the walkthrough) and the '
      'excluded table are disjoint, and their union covers every measured '
      'reachable screen',
      (tester) async {
        final walkedClassNames = await runCoreWalkthrough(tester);
        final walkedPaths = <String>{};
        for (final className in walkedClassNames) {
          final path = pathByClassName[className];
          expect(
            path,
            isNotNull,
            reason:
                'walked class "$className" is not one of the measured '
                '*_screen.dart classes',
          );
          walkedPaths.add(path!);
        }
        final excludedPaths = {for (final row in excludedRows) row.screenPath};

        final overlap = walkedPaths.intersection(excludedPaths);
        expect(
          overlap,
          isEmpty,
          reason:
              'a screen must not be BOTH walked and documented as excluded: '
              '$overlap',
        );

        final union = walkedPaths.union(excludedPaths);
        final missing = reachablePaths.difference(union);
        expect(
          missing,
          isEmpty,
          reason:
              'reachable screens missing from both the walk and the '
              'exclusion table (A4): $missing',
        );
      },
    );

    test('every excluded row names a real Indok, Gazda, and a well-formed '
        'Kör (E\\d+-R\\d+ or a stated "nincs — <indok>")', () {
      expect(excludedRows, isNotEmpty);
      expect(
        _rowsFailingA5(excludedRows),
        isEmpty,
        reason: 'excluded rows with an empty or malformed cell',
      );
    });

    // The KÖTELEZŐ valódi-sértés próba shape (screen_reachability_test.dart
    // precedent), applied to THIS round's own A5 predicate: blanking one
    // real row's Gazda in a COPY of the real, parsed rows must turn this
    // cell red — proving the check actually looks at the column instead of
    // trivially passing.
    test('blanking one real row\'s Gazda turns this cell red', () {
      final target = excludedRows.first;
      final mutated = [
        for (final row in excludedRows)
          if (row.screenPath == target.screenPath)
            _ExcludedRow(
              screenPath: row.screenPath,
              indok: row.indok,
              gazda: '',
              kor: row.kor,
            )
          else
            row,
      ];

      expect(_rowsFailingA5(mutated), [target.screenPath]);
    });
  });
}
