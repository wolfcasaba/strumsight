import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards `docs/sdd/program-completion-report.md` and
/// `docs/roadmap/next-six-months.md` (round brief `docs/rounds/`
/// `e12-r36-program-completion-and-next-roadmap.md`, §0.0.A P5): a green
/// gate alone is not evidence a completion report is honest, because a
/// checker that only ever runs against the real, checked-in tree can be
/// green for the WRONG reason (`docs/LESSONS.md` L118) — it never proves it
/// can turn red on a report that lies. Every acceptance point (A1-A5) below
/// therefore has at least one hand-built, RED-proving cell first, on input
/// the real tree cannot produce, before the matching cell measures the real
/// files (mirrors `tool/check_deprecations.dart`'s pure-function shape,
/// E12-R35).
///
/// Every parsing/comparison step is a content-parameterized pure function —
/// `tool/` is out of this round's allowed-files list (§4), so these live
/// here rather than in a shared tool module.

// ---------------------------------------------------------------------
// docs/execution/pipeline-queue.tsv — the single machine source of status
// ---------------------------------------------------------------------

final _queueDataLinePattern = RegExp(r'^(E\d+)-R\d+\t.*\t([A-Za-z]+)$');

/// Counts, per queue prefix (`E01`, `E12`, ...), how many rows carry each
/// status string — the same measurement as the round brief §0.0.A P2's
/// `awk` reproduction command, expressed as a pure function over [tsv]'s
/// text so a test can feed a synthetic queue.
Map<String, Map<String, int>> parseQueueCounts(String tsv) {
  final counts = <String, Map<String, int>>{};
  for (final line in tsv.split('\n')) {
    final match = _queueDataLinePattern.firstMatch(line.trim());
    if (match == null) continue;
    final prefix = match.group(1)!;
    final status = match.group(2)!;
    final byStatus = counts.putIfAbsent(prefix, () => <String, int>{});
    byStatus[status] = (byStatus[status] ?? 0) + 1;
  }
  return counts;
}

// ---------------------------------------------------------------------
// docs/sdd/program-completion-report.md §3 completion matrix
// ---------------------------------------------------------------------

final class CompletionMatrixRow {
  const CompletionMatrixRow({
    required this.lane,
    required this.queuePrefix,
    required this.done,
    required this.pending,
    required this.prepared,
    required this.hold,
    required this.reportStatus,
  });

  final String lane;

  /// The queue prefix cell's raw text (e.g. `E01`), or `—` for a lane with
  /// no queue-tracked rounds at all (Chapter 1).
  final String queuePrefix;
  final int done;
  final int pending;
  final int prepared;
  final int hold;
  final String reportStatus;

  /// Rows with any non-`done` count are lanes still open — the queue's own
  /// definition of "not finished yet".
  int get openCount => pending + prepared + hold;
}

List<String> _splitPipeRow(String line) {
  var trimmed = line.trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
  if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
  return trimmed.split('|').map((cell) => cell.trim()).toList();
}

/// Parses the `## 3. Completion matrix` table out of a
/// `program-completion-report.md`-shaped [markdown]: columns Sáv |
/// Fejezet / cím | Queue-előtag | done | pending | prepared | hold |
/// Riport-státusz | Bizonyíték.
List<CompletionMatrixRow> parseCompletionMatrix(String markdown) {
  final lines = markdown.split('\n');
  final headerIndex = lines.indexWhere(
    (line) => line.trim().startsWith('| Sáv |'),
  );
  if (headerIndex == -1) {
    throw const FormatException(
      'program-completion-report.md: no "| Sáv |" completion-matrix header found',
    );
  }
  final rows = <CompletionMatrixRow>[];
  for (var i = headerIndex + 2; i < lines.length; i++) {
    final line = lines[i];
    if (!line.trim().startsWith('|')) break;
    final cells = _splitPipeRow(line);
    if (cells.length < 9) {
      throw FormatException(
        'program-completion-report.md: completion-matrix row has '
        '${cells.length} cell(s), expected 9: "$line"',
      );
    }
    rows.add(
      CompletionMatrixRow(
        lane: cells[0],
        queuePrefix: cells[2],
        done: int.parse(cells[3]),
        pending: int.parse(cells[4]),
        prepared: int.parse(cells[5]),
        hold: int.parse(cells[6]),
        reportStatus: cells[7],
      ),
    );
  }
  return rows;
}

/// A1 — flags every matrix row whose done/pending/prepared/hold counts
/// don't match the measured [queueCounts] for its queue prefix. Rows whose
/// prefix is `—` (no queue rows at all, e.g. Chapter 1) are skipped.
List<String> compareMatrixToQueue(
  List<CompletionMatrixRow> rows,
  Map<String, Map<String, int>> queueCounts,
) {
  final issues = <String>[];
  for (final row in rows) {
    if (row.queuePrefix == '—') continue;
    final measured = queueCounts[row.queuePrefix] ?? const {};
    final reported = {
      'done': row.done,
      'pending': row.pending,
      'prepared': row.prepared,
      'hold': row.hold,
    };
    for (final status in reported.keys) {
      final measuredCount = measured[status] ?? 0;
      final reportedCount = reported[status]!;
      if (measuredCount != reportedCount) {
        issues.add(
          '${row.lane} (${row.queuePrefix}): reports $status='
          '$reportedCount, queue measures $status=$measuredCount',
        );
      }
    }
  }
  return issues;
}

/// A1-coverage — flags every queue prefix present in [queueCounts] that has
/// no row at all in the completion matrix (a lane the report silently
/// omits, rather than a lane it mismeasures — [compareMatrixToQueue] only
/// ever looks at rows that exist). [rows] is the parsed matrix.
/// `parseQueueCounts` never produces a `—` key (its data-line pattern
/// requires `E\d+`), so the Chapter-1 exception in [compareMatrixToQueue]
/// needs no counterpart here.
List<String> findLanesMissingFromMatrix(
  Map<String, Map<String, int>> queueCounts,
  List<CompletionMatrixRow> rows,
) {
  final reportedPrefixes = rows.map((row) => row.queuePrefix).toSet();
  return [
    for (final prefix in queueCounts.keys)
      if (!reportedPrefixes.contains(prefix))
        'queue prefix "$prefix" has no row in the completion matrix',
  ];
}

final _wordSplitPattern = RegExp(r'[^\p{L}]+', unicode: true);

Set<String> _lowercaseWords(String text) => text
    .toLowerCase()
    .split(_wordSplitPattern)
    .where((word) => word.isNotEmpty)
    .toSet();

/// A2 — flags every OPEN row (`openCount > 0`) whose report-status text
/// claims full closure ("kész"/"lezárva" as a standalone word) without also
/// carrying an open qualifier ("nyitva"/"nyitott"). A row that is genuinely
/// fully done (`openCount == 0`) is allowed to say "lezárva".
List<String> findOpenLaneMarkedClosed(List<CompletionMatrixRow> rows) {
  final issues = <String>[];
  for (final row in rows) {
    if (row.openCount == 0) continue;
    final words = _lowercaseWords(row.reportStatus);
    final claimsClosed = words.contains('kész') || words.contains('lezárva');
    final claimsOpen = words.contains('nyitva') || words.contains('nyitott');
    if (claimsClosed && !claimsOpen) {
      issues.add(
        '${row.lane} (${row.queuePrefix}): open lane '
        '(openCount=${row.openCount}) but report-status claims closure: '
        '"${row.reportStatus}"',
      );
    }
  }
  return issues;
}

// ---------------------------------------------------------------------
// A3 — evidence files (the "## ... Bizonyíték-források" bullet list)
// ---------------------------------------------------------------------

final _evidenceBulletPattern = RegExp(r'^-\s*`([^`]+)`', multiLine: true);

/// Extracts every `- \`path\`` bullet anywhere in [markdown] (no
/// section-boundary check). In today's report this happens to return
/// exactly the §7 evidence-sources list, because no bullet elsewhere in
/// the document starts with a backtick — that is a property of the current
/// prose, not an invariant this function enforces.
List<String> parseEvidencePaths(String markdown) => [
  for (final match in _evidenceBulletPattern.allMatches(markdown))
    match.group(1)!,
];

/// A3 — every path in [evidencePaths] must be present in [existingPaths].
List<String> findMissingEvidence(
  List<String> evidencePaths,
  Set<String> existingPaths,
) => [
  for (final path in evidencePaths)
    if (!existingPaths.contains(path)) path,
];

// ---------------------------------------------------------------------
// docs/sdd/program-completion-report.md §5 human gates table
// ---------------------------------------------------------------------

final class HumanGateRow {
  const HumanGateRow({
    required this.gate,
    required this.roundRef,
    required this.state,
  });

  final String gate;
  final String roundRef;
  final String state;
}

/// Parses the "Emberi kapu | Kör-hivatkozás | Állapot" table out of a
/// `program-completion-report.md`-shaped [markdown].
List<HumanGateRow> parseHumanGateRows(String markdown) {
  final lines = markdown.split('\n');
  final headerIndex = lines.indexWhere(
    (line) => line.trim().startsWith('| Emberi kapu |'),
  );
  if (headerIndex == -1) {
    throw const FormatException(
      'program-completion-report.md: no "| Emberi kapu |" table header found',
    );
  }
  final rows = <HumanGateRow>[];
  for (var i = headerIndex + 2; i < lines.length; i++) {
    final line = lines[i];
    if (!line.trim().startsWith('|')) break;
    final cells = _splitPipeRow(line);
    if (cells.length < 3) {
      throw FormatException(
        'program-completion-report.md: human-gates row has '
        '${cells.length} cell(s), expected 3: "$line"',
      );
    }
    rows.add(HumanGateRow(gate: cells[0], roundRef: cells[1], state: cells[2]));
  }
  return rows;
}

/// A5 — flags every row whose Állapot cell is not exactly `NYITOTT` — a
/// human gate the report claims as done.
List<String> findHumanGatesMarkedDone(String markdown) => [
  for (final row in parseHumanGateRows(markdown))
    if (row.state != 'NYITOTT')
      'human gate "${row.gate}" has Állapot="${row.state}", expected NYITOTT',
];

/// A5-coverage — flags every entry in [expectedGateRefs] with no matching
/// row in [rows]: a human gate the table omits entirely, rather than
/// mislabels (which [findHumanGatesMarkedDone] already catches). A ref
/// matches a row when it equals the row's Kör-hivatkozás cell (e.g.
/// `E12-R27`) or appears as a substring of the row's Emberi kapu cell — the
/// real-guitar-APK-test row carries no round reference, so it can only be
/// matched by its gate-name text.
List<String> findMissingHumanGates(
  List<String> expectedGateRefs,
  List<HumanGateRow> rows,
) => [
  for (final expected in expectedGateRefs)
    if (!rows.any(
      (row) => row.roundRef == expected || row.gate.contains(expected),
    ))
      'expected human gate "$expected" has no row in the table',
];

/// The eight human gates the round brief §5.3 requires this program's §5
/// table to always list: the seven `E12-R27`…`E12-R33` round references,
/// plus the real guitar APK test, which carries no round reference and is
/// matched by name instead.
const humanGateCoverageExpectedRefs = [
  'E12-R27',
  'E12-R28',
  'E12-R29',
  'E12-R30',
  'E12-R31',
  'E12-R32',
  'E12-R33',
  'gitáros APK-teszt',
];

// ---------------------------------------------------------------------
// docs/roadmap/next-six-months.md — outcome-based roadmap items
// ---------------------------------------------------------------------

final class RoadmapItem {
  const RoadmapItem({required this.title, required this.body});

  final String title;
  final String body;
}

final _roadmapHeadingPattern = RegExp(r'^## (.+)$', multiLine: true);

/// Splits a `next-six-months.md`-shaped [markdown] into its numbered `## `
/// items.
List<RoadmapItem> parseRoadmapItems(String markdown) {
  final matches = _roadmapHeadingPattern.allMatches(markdown).toList();
  final items = <RoadmapItem>[];
  for (var i = 0; i < matches.length; i++) {
    final bodyStart = matches[i].end;
    final bodyEnd = i + 1 < matches.length
        ? matches[i + 1].start
        : markdown.length;
    items.add(
      RoadmapItem(
        title: matches[i].group(1)!.trim(),
        body: markdown.substring(bodyStart, bodyEnd).trim(),
      ),
    );
  }
  return items;
}

final _roundIdPattern = RegExp(r'\bE\d{2}-R\d{2}\b');
final _nonLetterOrDigitPattern = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

String? _extractLabelValue(String body, String label) {
  // The lookahead's label-name class must be `\p{L}` (Unicode letters), not
  // an ASCII/Latin-1 range: "Mérőszám" contains "ő" (U+0151), outside
  // Latin-1 Supplement, so an `À-ÿ`-style range silently fails to stop the
  // non-greedy capture at that boundary and swallows the next label whole
  // (measured while building this function — the "only round IDs" A4 cell
  // came back empty because of exactly this).
  final pattern = RegExp(
    '\\*\\*$label:\\*\\*([\\s\\S]*?)(?=\\n\\*\\*[\\p{L} ]+:\\*\\*|\$)',
    unicode: true,
  );
  return pattern.firstMatch(body)?.group(1)?.trim();
}

/// A4 — validates a single roadmap item against the round brief §0.0.A
/// P5.1 machine shape: an `**Outcome:**` line whose text survives stripping
/// every round-id token (i.e. it says something beyond "these rounds ran"),
/// a `**Mérőszám:**` line containing a digit, and a `**Forrás:**` line.
List<String> validateRoadmapItem(RoadmapItem item) {
  final issues = <String>[];

  final outcome = _extractLabelValue(item.body, 'Outcome');
  if (outcome == null) {
    issues.add('"${item.title}": missing **Outcome:**');
  } else {
    final strippedOfRoundIds = outcome
        .replaceAll(_roundIdPattern, '')
        .replaceAll(_nonLetterOrDigitPattern, '')
        .trim();
    if (strippedOfRoundIds.isEmpty) {
      issues.add(
        '"${item.title}": Outcome is only a list of round IDs, not an '
        'outcome statement',
      );
    }
  }

  final measure = _extractLabelValue(item.body, 'Mérőszám');
  if (measure == null) {
    issues.add('"${item.title}": missing **Mérőszám:**');
  } else if (!RegExp(r'\d').hasMatch(measure)) {
    issues.add('"${item.title}": Mérőszám has no number in it');
  }

  final source = _extractLabelValue(item.body, 'Forrás');
  if (source == null || source.isEmpty) {
    issues.add('"${item.title}": missing **Forrás:**');
  }

  return issues;
}

// ---------------------------------------------------------------------
// RED-proving cells — hand-built input the real tree cannot produce
// ---------------------------------------------------------------------

void main() {
  group('parseQueueCounts', () {
    test('counts data rows by prefix and status, skips comments/headers', () {
      const tsv = '''
# a comment line
round\tbrief\tengine\tadr\tstatus
E01-R01\tdocs/rounds/x.md\tcodex\t0001\tdone
E01-R02\tdocs/rounds/y.md\tcodex\t0002\thold
E02-R01\tdocs/rounds/z.md\tcodex\t0003\tdone
''';
      final counts = parseQueueCounts(tsv);
      expect(counts['E01'], {'done': 1, 'hold': 1});
      expect(counts['E02'], {'done': 1});
    });
  });

  group('A1 — completion matrix vs. queue mismatch (RED-proving)', () {
    test(
      'a synthetic queue where a prefix status differs from the report is flagged',
      () {
        const queueTsv = '''
E10-R01\tdocs/rounds/a.md\tcodex\t0001\tdone
E10-R02\tdocs/rounds/b.md\tcodex\t0002\tdone
''';
        const reportMarkdown = '''
| Sáv | Fejezet / cím | Queue-előtag | done | pending | prepared | hold | Riport-státusz | Bizonyíték |
|---|---|---|---:|---:|---:|---:|---|---|
| Ch11 | Epic 10: Offline AI | E10 | 1 | 0 | 0 | 0 | lezárva | — |
''';
        final rows = parseCompletionMatrix(reportMarkdown);
        final issues = compareMatrixToQueue(rows, parseQueueCounts(queueTsv));
        expect(issues, isNotEmpty);
        expect(issues.single, contains('done=1'));
        expect(issues.single, contains('queue measures done=2'));
      },
    );

    test('a matching queue and report produces no issue', () {
      const queueTsv = '''
E10-R01\tdocs/rounds/a.md\tcodex\t0001\thold
E10-R02\tdocs/rounds/b.md\tcodex\t0002\thold
''';
      const reportMarkdown = '''
| Sáv | Fejezet / cím | Queue-előtag | done | pending | prepared | hold | Riport-státusz | Bizonyíték |
|---|---|---|---:|---:|---:|---:|---|---|
| Ch11 | Epic 10: Offline AI | E10 | 0 | 0 | 0 | 2 | nyitva | — |
''';
      final rows = parseCompletionMatrix(reportMarkdown);
      expect(compareMatrixToQueue(rows, parseQueueCounts(queueTsv)), isEmpty);
    });
  });

  group('lane-coverage — a queue prefix silently missing from the matrix '
      '(RED-proving)', () {
    test('a queue prefix with no matching matrix row at all is flagged, even '
        'though compareMatrixToQueue sees no mismatch (there is no row to '
        'mismeasure)', () {
      const queueTsv = '''
E15-R01\tdocs/rounds/a.md\tcodex\t0001\tpending
E15-R02\tdocs/rounds/b.md\tcodex\t0002\tpending
''';
      const reportMarkdown = '''
| Sáv | Fejezet / cím | Queue-előtag | done | pending | prepared | hold | Riport-státusz | Bizonyíték |
|---|---|---|---:|---:|---:|---:|---|---|
| Ch11 | Epic 10: Offline AI | E10 | 0 | 0 | 0 | 0 | lezárva | — |
''';
      final rows = parseCompletionMatrix(reportMarkdown);
      final queueCounts = parseQueueCounts(queueTsv);
      expect(compareMatrixToQueue(rows, queueCounts), isEmpty);
      final issues = findLanesMissingFromMatrix(queueCounts, rows);
      expect(issues, isNotEmpty);
      expect(issues.single, contains('E15'));
    });

    test('every queue prefix having a matrix row produces no issue', () {
      const queueTsv = '''
E10-R01\tdocs/rounds/a.md\tcodex\t0001\thold
''';
      const reportMarkdown = '''
| Sáv | Fejezet / cím | Queue-előtag | done | pending | prepared | hold | Riport-státusz | Bizonyíték |
|---|---|---|---:|---:|---:|---:|---|---|
| Ch11 | Epic 10: Offline AI | E10 | 0 | 0 | 0 | 1 | nyitva | — |
''';
      final rows = parseCompletionMatrix(reportMarkdown);
      final queueCounts = parseQueueCounts(queueTsv);
      expect(findLanesMissingFromMatrix(queueCounts, rows), isEmpty);
    });
  });

  group('A2 — an open lane marked closed (RED-proving)', () {
    test('a hold-on lane reported as "kész" is flagged', () {
      const reportMarkdown = '''
| Sáv | Fejezet / cím | Queue-előtag | done | pending | prepared | hold | Riport-státusz | Bizonyíték |
|---|---|---|---:|---:|---:|---:|---|---|
| Ch11 | Epic 10: Offline AI | E10 | 0 | 0 | 0 | 32 | lezárva, minden kör kész | — |
''';
      final rows = parseCompletionMatrix(reportMarkdown);
      final issues = findOpenLaneMarkedClosed(rows);
      expect(issues, isNotEmpty);
      expect(issues.single, contains('Ch11'));
    });

    test(
      'the same hold-on lane honestly marked "nyitva" produces no issue',
      () {
        const reportMarkdown = '''
| Sáv | Fejezet / cím | Queue-előtag | done | pending | prepared | hold | Riport-státusz | Bizonyíték |
|---|---|---|---:|---:|---:|---:|---|---|
| Ch11 | Epic 10: Offline AI | E10 | 0 | 0 | 0 | 32 | nyitva (hold: a TELJES sáv) | — |
''';
        final rows = parseCompletionMatrix(reportMarkdown);
        expect(findOpenLaneMarkedClosed(rows), isEmpty);
      },
    );

    test('a genuinely fully-done lane (openCount 0) may say "lezárva"', () {
      const reportMarkdown = '''
| Sáv | Fejezet / cím | Queue-előtag | done | pending | prepared | hold | Riport-státusz | Bizonyíték |
|---|---|---|---:|---:|---:|---:|---|---|
| Ch2 | Epic 1: Core Platform | E01 | 0 | 0 | 0 | 0 | lezárva (E01-R16) | — |
''';
      final rows = parseCompletionMatrix(reportMarkdown);
      expect(findOpenLaneMarkedClosed(rows), isEmpty);
    });
  });

  group('A3 — evidence file existence (RED-proving)', () {
    test('a bullet referencing a non-existent file is flagged', () {
      const markdown = '''
- `docs/execution/pipeline-queue.tsv`
- `docs/sdd/does-not-exist-anywhere.md`
''';
      final paths = parseEvidencePaths(markdown);
      final missing = findMissingEvidence(paths, {
        'docs/execution/pipeline-queue.tsv',
      });
      expect(missing, ['docs/sdd/does-not-exist-anywhere.md']);
    });

    test('every referenced path present in existingPaths yields no issue', () {
      const markdown = '''
- `docs/execution/pipeline-queue.tsv`
- `docs/sdd/00-index.md`
''';
      final paths = parseEvidencePaths(markdown);
      final missing = findMissingEvidence(paths, {
        'docs/execution/pipeline-queue.tsv',
        'docs/sdd/00-index.md',
      });
      expect(missing, isEmpty);
    });
  });

  group('A4 — roadmap item shape (RED-proving)', () {
    test('an item with no **Mérőszám:** line is flagged', () {
      const markdown = '''
## 1. Something happens

**Outcome:** users can do a new thing they could not do before.

**Forrás:** a test file.
''';
      final items = parseRoadmapItems(markdown);
      expect(items, hasLength(1));
      final issues = validateRoadmapItem(items.single);
      expect(issues, isNotEmpty);
      expect(issues.any((issue) => issue.contains('Mérőszám')), isTrue);
    });

    test('an item whose Outcome is only a list of round IDs is flagged '
        '(the §5.2 "feature-list roadmap" weakening)', () {
      const markdown = '''
## 1. Chapter 14 rounds

**Outcome:** E14-R20, E14-R21, E14-R22.

**Mérőszám:** 3 rounds land.

**Forrás:** the pipeline queue.
''';
      final items = parseRoadmapItems(markdown);
      final issues = validateRoadmapItem(items.single);
      expect(issues, isNotEmpty);
      expect(
        issues.any((issue) => issue.contains('only a list of round IDs')),
        isTrue,
      );
    });

    test('a fully-shaped item produces no issue', () {
      const markdown = '''
## 1. Something happens

**Outcome:** users can do a new thing they could not do before.

**Mérőszám:** at least 1 documented session with zero crashes.

**Forrás:** a manual test log under docs/release/.
''';
      final items = parseRoadmapItems(markdown);
      expect(validateRoadmapItem(items.single), isEmpty);
    });
  });

  group('A5 — human gates marked done (RED-proving)', () {
    test('a gate whose Állapot is not NYITOTT is flagged', () {
      const markdown = '''
| Emberi kapu | Kör-hivatkozás | Állapot |
|---|---|---|
| Zárt béta valós elindítása | E12-R27 | KÉSZ |
''';
      final issues = findHumanGatesMarkedDone(markdown);
      expect(issues, isNotEmpty);
      expect(issues.single, contains('Zárt béta'));
    });

    test('every gate correctly marked NYITOTT produces no issue', () {
      const markdown = '''
| Emberi kapu | Kör-hivatkozás | Állapot |
|---|---|---|
| Zárt béta valós elindítása | E12-R27 | NYITOTT |
''';
      expect(findHumanGatesMarkedDone(markdown), isEmpty);
    });
  });

  group('human-gate-coverage — a gate row silently missing from the table '
      '(RED-proving)', () {
    test('deleting one of the seven E12-R27…E12-R33 rows is flagged, even '
        'though the remaining rows are all honestly NYITOTT', () {
      const markdown = '''
| Emberi kapu | Kör-hivatkozás | Állapot |
|---|---|---|
| Zárt béta valós elindítása | E12-R27 | NYITOTT |
| Nyílt béta + canary cohort valós aktiválása | E12-R29 | NYITOTT |
| Feature-freeze utáni végső regresszió valós elfogadása | E12-R30 | NYITOTT |
| Produkciós deploy + belső kohort valós művelete | E12-R31 | NYITOTT |
| Szakaszos rollout 1→20% valós művelete | E12-R32 | NYITOTT |
| Szakaszos rollout 50→100% + GA valós művelete | E12-R33 | NYITOTT |
| Valódi gitáros APK-teszt (a végső acceptance predikátum) | — | NYITOTT |
''';
      final rows = parseHumanGateRows(markdown);
      expect(findHumanGatesMarkedDone(markdown), isEmpty);
      final issues = findMissingHumanGates(humanGateCoverageExpectedRefs, rows);
      expect(issues, isNotEmpty);
      expect(issues.single, contains('E12-R28'));
    });

    test('deleting the real-guitar-APK-test row (no round reference) is '
        'flagged too', () {
      const markdown = '''
| Emberi kapu | Kör-hivatkozás | Állapot |
|---|---|---|
| Zárt béta valós elindítása | E12-R27 | NYITOTT |
| Béta stabilizáció valós felhasználói visszajelzés alapján | E12-R28 | NYITOTT |
| Nyílt béta + canary cohort valós aktiválása | E12-R29 | NYITOTT |
| Feature-freeze utáni végső regresszió valós elfogadása | E12-R30 | NYITOTT |
| Produkciós deploy + belső kohort valós művelete | E12-R31 | NYITOTT |
| Szakaszos rollout 1→20% valós művelete | E12-R32 | NYITOTT |
| Szakaszos rollout 50→100% + GA valós művelete | E12-R33 | NYITOTT |
''';
      final rows = parseHumanGateRows(markdown);
      final issues = findMissingHumanGates(humanGateCoverageExpectedRefs, rows);
      expect(issues, isNotEmpty);
      expect(issues.single, contains('gitáros APK-teszt'));
    });

    test('all eight expected gates present produces no issue', () {
      const markdown = '''
| Emberi kapu | Kör-hivatkozás | Állapot |
|---|---|---|
| Zárt béta valós elindítása | E12-R27 | NYITOTT |
| Béta stabilizáció valós felhasználói visszajelzés alapján | E12-R28 | NYITOTT |
| Nyílt béta + canary cohort valós aktiválása | E12-R29 | NYITOTT |
| Feature-freeze utáni végső regresszió valós elfogadása | E12-R30 | NYITOTT |
| Produkciós deploy + belső kohort valós művelete | E12-R31 | NYITOTT |
| Szakaszos rollout 1→20% valós művelete | E12-R32 | NYITOTT |
| Szakaszos rollout 50→100% + GA valós művelete | E12-R33 | NYITOTT |
| Valódi gitáros APK-teszt (a végső acceptance predikátum) | — | NYITOTT |
''';
      final rows = parseHumanGateRows(markdown);
      expect(
        findMissingHumanGates(humanGateCoverageExpectedRefs, rows),
        isEmpty,
      );
    });
  });

  // ---------------------------------------------------------------------
  // The real, checked-in tree — same functions, real files
  // ---------------------------------------------------------------------

  group('the real tree (docs/execution/pipeline-queue.tsv, '
      'docs/sdd/program-completion-report.md, '
      'docs/roadmap/next-six-months.md)', () {
    late String queueTsv;
    late String reportMarkdown;
    late String roadmapMarkdown;

    setUpAll(() {
      queueTsv = File('docs/execution/pipeline-queue.tsv').readAsStringSync();
      reportMarkdown = File(
        'docs/sdd/program-completion-report.md',
      ).readAsStringSync();
      roadmapMarkdown = File(
        'docs/roadmap/next-six-months.md',
      ).readAsStringSync();
    });

    test('A1 — every matrix row matches the measured queue counts', () {
      final rows = parseCompletionMatrix(reportMarkdown);
      expect(rows, isNotEmpty);
      final issues = compareMatrixToQueue(rows, parseQueueCounts(queueTsv));
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    test(
      'lane-coverage — every queue prefix has a row in the completion matrix',
      () {
        final rows = parseCompletionMatrix(reportMarkdown);
        final issues = findLanesMissingFromMatrix(
          parseQueueCounts(queueTsv),
          rows,
        );
        expect(issues, isEmpty, reason: issues.join('\n'));
      },
    );

    test('A2 — no open lane is marked closed', () {
      final rows = parseCompletionMatrix(reportMarkdown);
      final issues = findOpenLaneMarkedClosed(rows);
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    test('A3 — every evidence-source path exists on disk', () {
      final paths = parseEvidencePaths(reportMarkdown);
      expect(paths, isNotEmpty);
      final missing = <String>[
        for (final path in paths)
          if (!File(path).existsSync()) path,
      ];
      expect(missing, isEmpty, reason: missing.join('\n'));
    });

    test('A4 — every roadmap item is a well-shaped, measurable outcome', () {
      final items = parseRoadmapItems(roadmapMarkdown);
      expect(items, isNotEmpty);
      final issues = <String>[
        for (final item in items) ...validateRoadmapItem(item),
      ];
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    test('A5 — every human gate is explicitly NYITOTT', () {
      final issues = findHumanGatesMarkedDone(reportMarkdown);
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    test('human-gate-coverage — all eight expected gates have a row in §5', () {
      final rows = parseHumanGateRows(reportMarkdown);
      final issues = findMissingHumanGates(humanGateCoverageExpectedRefs, rows);
      expect(issues, isEmpty, reason: issues.join('\n'));
    });

    // The KÖTELEZŐ valódi-sértés próba (brief §6.1/§10), automated in its
    // two distinct forms — the manual on-disk form of both is documented in
    // the round's §10 handoff:
    //
    // (a) only the Riport-státusz TEXT is rewritten to claim closure, the
    //     row's own done/pending/prepared/hold cells are untouched (exactly
    //     what editing the report's prose by hand would do) — A2 must turn
    //     red on this alone, independently of A1, since the row's own
    //     numbers still (truthfully) show 32 open rounds.
    // (b) only the row's COUNTS are rewritten to move the 32 hold rounds
    //     into done, the status text is untouched — A1 must turn red
    //     against the real, measured queue, independently of A2, since
    //     openCount now (falsely) reads as 0.
    test('(a) rewriting only Epic 10\'s status text to claim closure turns A2 '
        'red while A1 stays green', () {
      final rows = parseCompletionMatrix(reportMarkdown);
      final mutated = [
        for (final row in rows)
          if (row.queuePrefix == 'E10')
            CompletionMatrixRow(
              lane: row.lane,
              queuePrefix: row.queuePrefix,
              done: row.done,
              pending: row.pending,
              prepared: row.prepared,
              hold: row.hold,
              reportStatus: 'lezárva, minden kör kész',
            )
          else
            row,
      ];
      final queueCounts = parseQueueCounts(queueTsv);
      expect(compareMatrixToQueue(mutated, queueCounts), isEmpty);
      expect(findOpenLaneMarkedClosed(mutated), isNotEmpty);
    });

    test('(b) rewriting only Epic 10\'s counts to move hold into done turns '
        'A1 red against the real measured queue while A2 stays green', () {
      final rows = parseCompletionMatrix(reportMarkdown);
      final mutated = [
        for (final row in rows)
          if (row.queuePrefix == 'E10')
            CompletionMatrixRow(
              lane: row.lane,
              queuePrefix: row.queuePrefix,
              done: row.done + row.hold,
              pending: row.pending,
              prepared: row.prepared,
              hold: 0,
              reportStatus: row.reportStatus,
            )
          else
            row,
      ];
      final queueCounts = parseQueueCounts(queueTsv);
      expect(compareMatrixToQueue(mutated, queueCounts), isNotEmpty);
      expect(findOpenLaneMarkedClosed(mutated), isEmpty);
    });
  });
}
