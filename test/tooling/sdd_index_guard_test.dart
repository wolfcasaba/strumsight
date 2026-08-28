import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_sdd_index.dart';

void main() {
  group(
    'parseKorokCount — A8 (round brief §0.0.A P3, four measured forms)',
    () {
      test('plain integer', () {
        expect(parseKorokCount('16'), 16);
      });

      test('integer followed by a parenthetical note', () {
        expect(parseKorokCount('20 (lezárva E02-R20, 2026-08-01)'), 20);
      });

      test('integer followed by an em-dash note', () {
        expect(
          parseKorokCount(
            '30 — implementation evidence recorded; rollout stays at shadow, '
            'release blockers remain',
          ),
          30,
        );
      });

      test('bare em dash means zero rounds', () {
        expect(parseKorokCount('—'), 0);
      });

      test('throws a location-naming error on unparseable content', () {
        expect(
          () => parseKorokCount('tervben'),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('cannot read a round count'),
            ),
          ),
        );
      });
    },
  );

  group('countKorHeaders — A5 (both round-header forms)', () {
    test('counts single-# headers (Chapter 1-13 style)', () {
      const content = '''
# Kör 1 — Alpha
some body text
# Kör 2 — Beta
''';
      expect(countKorHeaders(content), 2);
    });

    test('counts double-## headers (Chapter 14 style)', () {
      const content = '''
## Kör 01 — Alpha
some body text
## Kör 02 — Beta
## Kör 03 — Gamma
''';
      expect(countKorHeaders(content), 3);
    });

    test('a file using only one form does not count the other as zero by '
        'accident (mixed content, both forms present)', () {
      const content = '''
# Kör 1 — Alpha
## Not a round header, just a subsection
## Kör 02 — Beta
''';
      expect(countKorHeaders(content), 2);
    });

    test('a header inside a code fence is still a line match (line-based, '
        'not Markdown-structure-aware by design)', () {
      const content = '# Kör 1 — Alpha';
      expect(countKorHeaders(content), 1);
    });
  });

  group('parseChapterTable — A8 (5- and 6-cell row tolerance)', () {
    const header =
        '| Chapter | Cím | Fejlesztési körök | Fő előfeltétel | Fájl | '
        'Zárójelentés |';
    const separator = '|---:|---|---:|---|---|---|';

    test('reads a 6-cell row (Zárójelentés present)', () {
      final markdown =
          '''
$header
$separator
| 1 | Alpha | 5 | — | [`a.md`](a.md) | [`a-report.md`](a-report.md) |
''';
      final rows = parseChapterTable(markdown);
      expect(rows, hasLength(1));
      expect(rows.single.chapterNumber, 1);
      expect(rows.single.korokCount, 5);
      expect(rows.single.filePath, 'a.md');
      expect(rows.single.completionReportPath, 'a-report.md');
    });

    test('reads a 5-cell row (Zárójelentés omitted entirely)', () {
      final markdown =
          '''
$header
$separator
| 2 | Beta | 7 | Chapter 1 | [`b.md`](b.md) |
''';
      final rows = parseChapterTable(markdown);
      expect(rows, hasLength(1));
      expect(rows.single.chapterNumber, 2);
      expect(rows.single.korokCount, 7);
      expect(rows.single.filePath, 'b.md');
      expect(rows.single.completionReportPath, isNull);
    });

    test('tolerates the two row shapes mixed in the same table', () {
      final markdown =
          '''
$header
$separator
| 1 | Alpha | 5 | — | [`a.md`](a.md) | [`a-report.md`](a-report.md) |
| 2 | Beta | 7 | Chapter 1 | [`b.md`](b.md) |
''';
      final rows = parseChapterTable(markdown);
      expect(rows.map((row) => row.chapterNumber), [1, 2]);
    });

    test('tolerates extra trailing columns beyond Zárójelentés (Státusz / '
        'Implementation progress / Dependency)', () {
      const widerHeader =
          '| Chapter | Cím | Fejlesztési körök | Fő előfeltétel | Fájl | '
          'Zárójelentés | Státusz | Implementation progress | Dependency |';
      const widerSeparator = '|---:|---|---:|---|---|---|---|---|---|';
      final markdown =
          '''
$widerHeader
$widerSeparator
| 1 | Alpha | 5 | — | [`a.md`](a.md) | [`a-report.md`](a-report.md) | ok | ld. baseline | — |
| 2 | Beta | 7 | Chapter 1 | [`b.md`](b.md) | tervezett | nincs mérés | ch01 |
''';
      final rows = parseChapterTable(markdown);
      expect(rows, hasLength(2));
      expect(rows[0].completionReportPath, 'a-report.md');
      expect(rows[1].completionReportPath, isNull);
      expect(rows[1].korokCount, 7);
    });

    test('rejects a row with a structurally wrong cell count', () {
      final markdown =
          '''
$header
$separator
| 1 | Alpha | 5 |
''';
      expect(() => parseChapterTable(markdown), throwsFormatException);
    });
  });

  group(
    'parseDependencyGraph — own restricted-subset parser (ADR 0443 D3)',
    () {
      test('parses nodes and edges', () {
        const yaml = '''
# a comment
nodes:
  - id: cha
    title: "Alpha"
    critical_path: true
    capability_gated: false
  - id: chb
    title: "Beta"
    critical_path: false
    capability_gated: true
edges:
  - from: cha
    to: chb
''';
        final graph = parseDependencyGraph(yaml);
        expect(graph.nodes.map((n) => n.id), ['cha', 'chb']);
        expect(graph.nodes.first.criticalPath, isTrue);
        expect(graph.nodes.first.capabilityGated, isFalse);
        expect(graph.nodes.last.title, 'Beta');
        expect(graph.edges, hasLength(1));
        expect(graph.edges.single.from, 'cha');
        expect(graph.edges.single.to, 'chb');
      });

      test('a node missing critical_path throws a location-naming error '
          '(A6 — the field must be present, not just true somewhere)', () {
        const yaml = '''
nodes:
  - id: cha
    title: "Alpha"
    capability_gated: false
edges:
''';
        expect(
          () => parseDependencyGraph(yaml),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              allOf(contains('cha'), contains('critical_path')),
            ),
          ),
        );
      });

      test(
        'rejects a node field that is not indented by exactly four spaces',
        () {
          const yaml = '''
nodes:
  - id: cha
  title: "Alpha"
edges:
''';
          expect(() => parseDependencyGraph(yaml), throwsFormatException);
        },
      );

      test(
        'rejects package:yaml-style flow collections (unsupported shape)',
        () {
          const yaml = '''
nodes:
  - id: cha
    title: "Alpha"
    critical_path: true
    capability_gated: [false]
edges:
''';
          expect(
            () => parseDependencyGraph(yaml),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'message',
                contains('must be "true" or "false"'),
              ),
            ),
          );
        },
      );
    },
  );

  group('findCycle — A4', () {
    DependencyGraph graphOf(List<String> ids, List<(String, String)> edges) {
      return DependencyGraph(
        nodes: [
          for (final id in ids)
            GraphNode(
              id: id,
              title: id,
              criticalPath: false,
              capabilityGated: false,
              lineNumber: 0,
            ),
        ],
        edges: [
          for (final (from, to) in edges)
            GraphEdge(from: from, to: to, lineNumber: 0),
        ],
      );
    }

    test('an acyclic graph has no cycle', () {
      final graph = graphOf(
        ['a', 'b', 'c'],
        [('a', 'b'), ('b', 'c'), ('a', 'c')],
      );
      expect(findCycle(graph), isNull);
    });

    test('a direct cycle is detected', () {
      final graph = graphOf(['a', 'b'], [('a', 'b'), ('b', 'a')]);
      expect(findCycle(graph), ['a', 'b', 'a']);
    });

    test('a longer cycle is detected', () {
      final graph = graphOf(
        ['a', 'b', 'c'],
        [('a', 'b'), ('b', 'c'), ('c', 'a')],
      );
      final cycle = findCycle(graph);
      expect(cycle, isNotNull);
      expect(cycle!.first, cycle.last);
      expect(cycle.toSet(), {'a', 'b', 'c'});
    });
  });

  group('validateSddIndex — the mérce-mátrix cells (A1-A4, A9)', () {
    ChapterTableRow rowOf({
      required int chapterNumber,
      required int korokCount,
      String? filePath,
      String? completionReportPath,
    }) {
      return ChapterTableRow(
        chapterNumber: chapterNumber,
        korokRaw: '$korokCount',
        korokCount: korokCount,
        filePath: filePath ?? '$chapterNumber.md',
        completionReportPath: completionReportPath,
        lineNumber: 0,
      );
    }

    final cleanGraph = DependencyGraph(
      nodes: [
        GraphNode(
          id: 'ch01',
          title: 'Alpha',
          criticalPath: true,
          capabilityGated: false,
          lineNumber: 0,
        ),
      ],
      edges: const [],
    );

    test('A1 — a duplicated chapter row is flagged', () {
      final report = validateSddIndex(
        rows: [
          rowOf(chapterNumber: 1, korokCount: 5),
          rowOf(chapterNumber: 1, korokCount: 5),
        ],
        graph: cleanGraph,
        measuredKorCounts: {1: 5},
        existingFiles: {'1.md'},
      );
      expect(report.isClean, isFalse);
      expect(
        report.issues.map((issue) => issue.code),
        contains(SddIndexIssueCode.duplicateChapter),
      );
    });

    test('A1 — a chapter file with no index row is flagged as missing', () {
      final report = validateSddIndex(
        rows: [rowOf(chapterNumber: 1, korokCount: 5)],
        graph: cleanGraph,
        measuredKorCounts: {1: 5, 2: 3},
        existingFiles: {'1.md', '2.md'},
      );
      expect(
        report.issues.map((issue) => issue.code),
        contains(SddIndexIssueCode.missingChapter),
      );
    });

    test('A2 — a dangling Fájl reference is flagged', () {
      final report = validateSddIndex(
        rows: [
          rowOf(chapterNumber: 1, korokCount: 5, filePath: 'does-not-exist.md'),
        ],
        graph: cleanGraph,
        measuredKorCounts: {1: 5},
        existingFiles: {'1.md'},
      );
      expect(
        report.issues.map((issue) => issue.code),
        contains(SddIndexIssueCode.missingFile),
      );
    });

    test('A2 — a dangling Zárójelentés reference is flagged', () {
      final report = validateSddIndex(
        rows: [
          rowOf(
            chapterNumber: 1,
            korokCount: 5,
            filePath: '1.md',
            completionReportPath: 'ghost-report.md',
          ),
        ],
        graph: cleanGraph,
        measuredKorCounts: {1: 5},
        existingFiles: {'1.md'},
      );
      expect(
        report.issues.map((issue) => issue.code),
        contains(SddIndexIssueCode.missingFile),
      );
    });

    test(
      'A3 — the checker measures the round count from the chapter file, '
      'not from the index cell (the NOT-acceptable weakening from brief §5.1)',
      () {
        final report = validateSddIndex(
          rows: [rowOf(chapterNumber: 12, korokCount: 42, filePath: '12.md')],
          graph: cleanGraph,
          measuredKorCounts: {12: 36},
          existingFiles: {'12.md'},
        );
        final mismatch = report.issues.singleWhere(
          (issue) => issue.code == SddIndexIssueCode.korokMismatch,
        );
        expect(mismatch.message, contains('42'));
        expect(mismatch.message, contains('36'));
      },
    );

    test('A3 — a matching round count produces no mismatch issue', () {
      final report = validateSddIndex(
        rows: [rowOf(chapterNumber: 12, korokCount: 36, filePath: '12.md')],
        graph: cleanGraph,
        measuredKorCounts: {12: 36},
        existingFiles: {'12.md'},
      );
      expect(
        report.issues.map((issue) => issue.code),
        isNot(contains(SddIndexIssueCode.korokMismatch)),
      );
    });

    test('A4 — a cyclic dependency graph is flagged even when every '
        'chapter row and file link is otherwise clean', () {
      final cyclicGraph = DependencyGraph(
        nodes: [
          GraphNode(
            id: 'ch01',
            title: 'Alpha',
            criticalPath: false,
            capabilityGated: false,
            lineNumber: 0,
          ),
          GraphNode(
            id: 'ch02',
            title: 'Beta',
            criticalPath: false,
            capabilityGated: false,
            lineNumber: 0,
          ),
        ],
        edges: const [
          GraphEdge(from: 'ch01', to: 'ch02', lineNumber: 0),
          GraphEdge(from: 'ch02', to: 'ch01', lineNumber: 0),
        ],
      );
      final report = validateSddIndex(
        rows: [rowOf(chapterNumber: 1, korokCount: 5, filePath: '1.md')],
        graph: cyclicGraph,
        measuredKorCounts: {1: 5},
        existingFiles: {'1.md'},
      );
      expect(
        report.issues.map((issue) => issue.code),
        contains(SddIndexIssueCode.cyclicGraph),
      );
    });

    test('a graph edge referencing an unknown node id is flagged', () {
      final graph = DependencyGraph(
        nodes: [
          GraphNode(
            id: 'ch01',
            title: 'Alpha',
            criticalPath: false,
            capabilityGated: false,
            lineNumber: 0,
          ),
        ],
        edges: const [GraphEdge(from: 'ch01', to: 'ch99', lineNumber: 3)],
      );
      final report = validateSddIndex(
        rows: [rowOf(chapterNumber: 1, korokCount: 5, filePath: '1.md')],
        graph: graph,
        measuredKorCounts: {1: 5},
        existingFiles: {'1.md'},
      );
      expect(
        report.issues.map((issue) => issue.code),
        contains(SddIndexIssueCode.unknownGraphNode),
      );
    });

    test('a fully consistent table + graph reports clean', () {
      final report = validateSddIndex(
        rows: [rowOf(chapterNumber: 1, korokCount: 5, filePath: '1.md')],
        graph: cleanGraph,
        measuredKorCounts: {1: 5},
        existingFiles: {'1.md'},
      );
      expect(report.isClean, isTrue, reason: report.format());
    });
  });

  group('A9 — the checker never depends on package:yaml', () {
    // Matches only an actual import/export directive, not the many
    // legitimate prose mentions of "package:yaml" in doc comments (ADR 0443
    // D3 rationale) or in this very assertion's string literal.
    final yamlImportDirective = RegExp(
      '''(?:import|export)\\s*['"]package:yaml''',
    );

    test('tool/check_sdd_index.dart contains no package:yaml import', () {
      final source = File('tool/check_sdd_index.dart').readAsStringSync();
      expect(yamlImportDirective.hasMatch(source), isFalse);
    });

    test('test/tooling/sdd_index_guard_test.dart contains no package:yaml '
        'import either', () {
      final source = File(
        'test/tooling/sdd_index_guard_test.dart',
      ).readAsStringSync();
      expect(yamlImportDirective.hasMatch(source), isFalse);
    });
  });

  group('checkSddIndexAtRoot — A7 (the real, checked-in docs/sdd/ tree)', () {
    test('the real index and dependency graph are clean', () {
      final report = checkSddIndexAtRoot(projectRoot: Directory.current);
      expect(report.isClean, isTrue, reason: report.format());
    });

    // Round brief §0.0.A P1 — the measured per-chapter round-header counts.
    // A future edit that adds/removes a round header in any chapter file,
    // or that lets a chapter file drift from its index row again, must turn
    // this test (and the A7 test above) red rather than silently pass.
    test('measured round counts match the round brief §0.0.A P1 table', () {
      final expected = <int, int>{
        1: 0,
        2: 16,
        3: 20,
        4: 22,
        5: 24,
        6: 30,
        7: 30,
        8: 30,
        9: 30,
        10: 32,
        11: 32,
        12: 36,
        13: 36,
        14: 42,
      };
      final sddDirectory = Directory('docs/sdd');
      final measured = <int, int>{};
      final prefix = RegExp(r'^(\d{2})-');
      for (final entry in sddDirectory.listSync()) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        final name = entry.uri.pathSegments.last;
        if (name == '00-index.md') continue;
        final match = prefix.firstMatch(name);
        if (match == null) continue;
        measured[int.parse(match.group(1)!)] = countKorHeaders(
          entry.readAsStringSync(),
        );
      }
      expect(measured, expected);
    });

    // The KÖTELEZŐ valódi-sértés próba (brief §6.1 / §6): writing the
    // stale Chapter 12 round count (42) back into a parsed copy of the real
    // table must turn A3 red on the real, measured file counts — this is
    // the automated form of the manual probe documented in the round's
    // §10 handoff (which mutates the real 00-index.md on disk, re-runs the
    // gate, and restores it).
    test('reverting Chapter 12 to the stale index value (42) turns A3 red '
        'against the real measured chapter-file count', () {
      final indexMarkdown = File('docs/sdd/00-index.md').readAsStringSync();
      final rows = parseChapterTable(indexMarkdown)
          .map(
            (row) => row.chapterNumber == 12
                ? ChapterTableRow(
                    chapterNumber: row.chapterNumber,
                    korokRaw: '42',
                    korokCount: 42,
                    filePath: row.filePath,
                    completionReportPath: row.completionReportPath,
                    lineNumber: row.lineNumber,
                  )
                : row,
          )
          .toList();
      final graph = parseDependencyGraph(
        File('docs/sdd/dependency-graph.yaml').readAsStringSync(),
      );
      final sddDirectory = Directory('docs/sdd');
      final existingFiles = <String>{};
      final measuredKorCounts = <int, int>{};
      final prefix = RegExp(r'^(\d{2})-');
      for (final entry in sddDirectory.listSync()) {
        if (entry is! File || !entry.path.endsWith('.md')) continue;
        final name = entry.uri.pathSegments.last;
        existingFiles.add(name);
        if (name == '00-index.md') continue;
        final match = prefix.firstMatch(name);
        if (match == null) continue;
        measuredKorCounts[int.parse(match.group(1)!)] = countKorHeaders(
          entry.readAsStringSync(),
        );
      }

      final report = validateSddIndex(
        rows: rows,
        graph: graph,
        measuredKorCounts: measuredKorCounts,
        existingFiles: existingFiles,
      );

      expect(report.isClean, isFalse);
      final mismatch = report.issues.singleWhere(
        (issue) => issue.code == SddIndexIssueCode.korokMismatch,
      );
      expect(mismatch.message, contains('Chapter 12'));
      expect(mismatch.message, contains('42'));
      expect(mismatch.message, contains('36'));
    });
  });
}
