import 'dart:io';

/// Checks that `docs/sdd/00-index.md` and `docs/sdd/dependency-graph.yaml`
/// stay a machine-verified, drift-free contract for the SDD program
/// (ADR 0443).
///
/// Both files are read with hand-written, line-based parsers rather than a
/// general Markdown- or YAML-parsing package: `docs/sdd/dependency-graph.yaml`
/// is a deliberately restricted YAML subset (ADR 0443 D3 — `package:yaml` is
/// only a transitive dependency, and a direct import would turn
/// `flutter analyze` red via `depend_on_referenced_packages`; see the header
/// comment of that file for the exact supported grammar), and the index
/// table's own cell shape is not uniform (see [parseChapterTable]).
///
/// The logic here is intentionally NOT inside `main()`: [parseChapterTable],
/// [parseDependencyGraph], [countKorHeaders], [parseKorokCount],
/// [findCycle] and [validateSddIndex] all take root- or content-parameters
/// so tests can feed hand-built malformed input (duplicated chapter,
/// dangling reference, cyclic graph) that the real `docs/sdd/` tree cannot
/// produce (ADR 0443 D4). `main()` is only a thin, `exitCode`-setting
/// wrapper around [checkSddIndexAtRoot].

// ---------------------------------------------------------------------------
// Chapter index table
// ---------------------------------------------------------------------------

/// One data row of the `## Fejezetek` table in `docs/sdd/00-index.md`.
final class ChapterTableRow {
  const ChapterTableRow({
    required this.chapterNumber,
    required this.korokRaw,
    required this.korokCount,
    required this.filePath,
    required this.completionReportPath,
    required this.lineNumber,
  });

  final int chapterNumber;
  final String korokRaw;
  final int korokCount;
  final String filePath;
  final String? completionReportPath;
  final int lineNumber;
}

/// Reads the leading integer out of a "Fejlesztési körök" table cell.
///
/// The cell is not a clean integer on every row (measured in ADR 0443 D1 /
/// the round brief §0.0.A P3): some rows carry prose after the number
/// (`"22 — implementation evidence recorded; release blockers remain"`,
/// `"20 (lezárva E02-R20, 2026-08-01)"`), and Chapter 1 — which has no
/// rounds — uses an em dash (`—`) instead of a number. The prose is left
/// untouched; only the leading integer (or the em-dash-as-zero case) is
/// read.
int parseKorokCount(String cell) {
  final trimmed = cell.trim();
  if (trimmed == '—') return 0;
  final match = RegExp(r'^(\d+)').firstMatch(trimmed);
  if (match == null) {
    throw FormatException(
      'cannot read a round count from "Fejlesztési körök" cell: "$trimmed" '
      '(expected a leading integer or a bare em dash "—")',
    );
  }
  return int.parse(match.group(1)!);
}

final _markdownLinkTarget = RegExp(r'\[[^\]]*\]\(([^)]+)\)');

String? _extractLinkTarget(String cell) {
  final match = _markdownLinkTarget.firstMatch(cell.trim());
  if (match == null) return null;
  var target = match.group(1)!.trim();
  if (target.startsWith('./')) target = target.substring(2);
  final fragmentIndex = target.indexOf('#');
  if (fragmentIndex >= 0) target = target.substring(0, fragmentIndex);
  return target;
}

List<String> _splitTableRow(String line) {
  var trimmed = line.trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
  if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
  return trimmed.split('|').map((cell) => cell.trim()).toList();
}

bool _isTableSeparatorLine(String line) {
  final trimmed = line.trim();
  return trimmed.startsWith('|') && RegExp(r'^[\s|:-]+$').hasMatch(trimmed);
}

int _requiredColumnIndex(
  List<String> header,
  String columnName,
  int headerLineNumber,
) {
  final index = header.indexOf(columnName);
  if (index < 0) {
    throw FormatException(
      'docs/sdd/00-index.md:$headerLineNumber: the chapter table header is '
      'missing the required "$columnName" column (found: '
      '${header.map((c) => '"$c"').join(', ')})',
    );
  }
  return index;
}

/// Parses the `## Fejezetek` table out of `docs/sdd/00-index.md` content.
///
/// The table's row shape is NOT uniform (measured in the round brief
/// §0.0.A P2): several rows omit the trailing "Zárójelentés" cell entirely
/// rather than writing it empty. A row is therefore accepted when it has
/// either the full header cell count, or exactly one fewer cell than the
/// header — in the latter case the "Zárójelentés" column (located by name,
/// not by position, so this also tolerates extra trailing columns such as
/// "Státusz"/"Implementation progress"/"Dependency") is treated as empty.
List<ChapterTableRow> parseChapterTable(String indexMarkdown) {
  final lines = indexMarkdown.split('\n');
  var headerLine = -1;
  for (var i = 0; i < lines.length; i++) {
    if (RegExp(r'^\s*\|\s*Chapter\s*\|').hasMatch(lines[i])) {
      headerLine = i;
      break;
    }
  }
  if (headerLine < 0) {
    throw const FormatException(
      'docs/sdd/00-index.md: no chapter table found (expected a line '
      'matching "| Chapter | ...")',
    );
  }
  if (headerLine + 1 >= lines.length ||
      !_isTableSeparatorLine(lines[headerLine + 1])) {
    throw FormatException(
      'docs/sdd/00-index.md:${headerLine + 2}: expected a Markdown table '
      'separator row (e.g. "|---:|---|") after the chapter table header',
    );
  }

  final header = _splitTableRow(lines[headerLine]);
  final chapterIndex = _requiredColumnIndex(header, 'Chapter', headerLine + 1);
  final korokIndex = _requiredColumnIndex(
    header,
    'Fejlesztési körök',
    headerLine + 1,
  );
  final fileIndex = _requiredColumnIndex(header, 'Fájl', headerLine + 1);
  final completionReportIndex = header.indexOf('Zárójelentés');

  final rows = <ChapterTableRow>[];
  for (var i = headerLine + 2; i < lines.length; i++) {
    final line = lines[i];
    if (!line.trim().startsWith('|')) break;
    final lineNumber = i + 1;
    var cells = _splitTableRow(line);

    if (completionReportIndex >= 0 && cells.length == header.length - 1) {
      cells = [
        ...cells.sublist(0, completionReportIndex),
        '',
        ...cells.sublist(completionReportIndex),
      ];
    }
    if (cells.length != header.length) {
      throw FormatException(
        'docs/sdd/00-index.md:$lineNumber: expected ${header.length} cells '
        '(or ${header.length - 1} with "Zárójelentés" omitted), got '
        '${cells.length}: "$line"',
      );
    }

    final chapterCell = cells[chapterIndex].trim();
    final chapterNumber = int.tryParse(chapterCell);
    if (chapterNumber == null) {
      throw FormatException(
        'docs/sdd/00-index.md:$lineNumber: "Chapter" cell is not a plain '
        'integer: "$chapterCell"',
      );
    }

    final korokRaw = cells[korokIndex];
    final korokCount = parseKorokCount(korokRaw);

    final fileCell = cells[fileIndex];
    final filePath = _extractLinkTarget(fileCell);
    if (filePath == null) {
      throw FormatException(
        'docs/sdd/00-index.md:$lineNumber: "Fájl" cell has no Markdown link '
        'target: "$fileCell"',
      );
    }

    String? completionReportPath;
    if (completionReportIndex >= 0) {
      final reportCell = cells[completionReportIndex].trim();
      if (reportCell.isNotEmpty && reportCell != '—') {
        completionReportPath = _extractLinkTarget(reportCell);
        if (completionReportPath == null) {
          throw FormatException(
            'docs/sdd/00-index.md:$lineNumber: "Zárójelentés" cell has no '
            'Markdown link target: "$reportCell"',
          );
        }
      }
    }

    rows.add(
      ChapterTableRow(
        chapterNumber: chapterNumber,
        korokRaw: korokRaw,
        korokCount: korokCount,
        filePath: filePath,
        completionReportPath: completionReportPath,
        lineNumber: lineNumber,
      ),
    );
  }
  return rows;
}

/// Counts chapter round headers (`# Kör N` or `## Kör N`) in a chapter file.
///
/// Both header depths are measured to occur in the repository (round brief
/// §0.0.A P1): Chapter 1–13 files use `# Kör N`, Chapter 14 uses `## Kör N`.
/// Recognizing only one form would silently measure zero rounds for the
/// other — indistinguishable from a correct measurement unless both forms
/// are read.
int countKorHeaders(String chapterMarkdown) {
  final headerPattern = RegExp(r'^#{1,2} Kör \d+');
  var count = 0;
  for (final line in chapterMarkdown.split('\n')) {
    if (headerPattern.hasMatch(line)) count++;
  }
  return count;
}

// ---------------------------------------------------------------------------
// Dependency graph
// ---------------------------------------------------------------------------

final class GraphNode {
  const GraphNode({
    required this.id,
    required this.title,
    required this.criticalPath,
    required this.capabilityGated,
    required this.lineNumber,
  });

  final String id;
  final String title;
  final bool criticalPath;
  final bool capabilityGated;
  final int lineNumber;
}

final class GraphEdge {
  const GraphEdge({
    required this.from,
    required this.to,
    required this.lineNumber,
  });

  final String from;
  final String to;
  final int lineNumber;
}

final class DependencyGraph {
  const DependencyGraph({required this.nodes, required this.edges});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
}

bool _isBlankOrComment(String line) {
  final trimmed = line.trim();
  return trimmed.isEmpty || trimmed.startsWith('#');
}

String _unquote(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

bool _requiredBool(
  Map<String, String> fields,
  String key,
  String nodeId,
  int lineNumber,
) {
  final raw = fields[key];
  if (raw == null) {
    throw FormatException(
      'docs/sdd/dependency-graph.yaml:$lineNumber: node "$nodeId" is '
      'missing the required "$key" field',
    );
  }
  if (raw == 'true') return true;
  if (raw == 'false') return false;
  throw FormatException(
    'docs/sdd/dependency-graph.yaml:$lineNumber: node "$nodeId" field '
    '"$key" must be "true" or "false", got: "$raw"',
  );
}

/// Parses `docs/sdd/dependency-graph.yaml` with a hand-written, line-based
/// parser for the deliberately restricted subset documented in that file's
/// header comment (ADR 0443 D3) — NOT `package:yaml`.
DependencyGraph parseDependencyGraph(String yamlContent) {
  final lines = yamlContent.split('\n');
  var i = 0;

  while (i < lines.length && _isBlankOrComment(lines[i])) {
    i++;
  }
  if (i >= lines.length || lines[i].trim() != 'nodes:') {
    throw FormatException(
      'docs/sdd/dependency-graph.yaml:${i + 1}: expected top-level '
      '"nodes:", got: "${i < lines.length ? lines[i] : '<end of file>'}"',
    );
  }
  i++;

  final nodeHeader = RegExp(r'^  - id: (\S+)$');
  final fieldLine = RegExp(r'^    (\w+): (.*)$');
  final nodes = <GraphNode>[];

  while (true) {
    while (i < lines.length && _isBlankOrComment(lines[i])) {
      i++;
    }
    if (i >= lines.length) {
      throw FormatException(
        'docs/sdd/dependency-graph.yaml:${i + 1}: expected top-level '
        '"edges:" after the node list, reached end of file',
      );
    }
    if (lines[i].trim() == 'edges:' && lines[i] == 'edges:') break;

    final headerMatch = nodeHeader.firstMatch(lines[i]);
    if (headerMatch == null) {
      throw FormatException(
        'docs/sdd/dependency-graph.yaml:${i + 1}: expected a node entry '
        '("  - id: <chNN>") or top-level "edges:", got: "${lines[i]}"',
      );
    }
    final id = headerMatch.group(1)!;
    final lineNumber = i + 1;
    i++;

    final fields = <String, String>{};
    while (i < lines.length &&
        lines[i].startsWith('    ') &&
        !_isBlankOrComment(lines[i])) {
      final match = fieldLine.firstMatch(lines[i]);
      if (match == null) {
        throw FormatException(
          'docs/sdd/dependency-graph.yaml:${i + 1}: expected a '
          '4-space-indented "key: value" node field, got: "${lines[i]}"',
        );
      }
      fields[match.group(1)!] = match.group(2)!;
      i++;
    }

    final titleRaw = fields['title'];
    if (titleRaw == null) {
      throw FormatException(
        'docs/sdd/dependency-graph.yaml:$lineNumber: node "$id" is missing '
        'the required "title" field',
      );
    }
    nodes.add(
      GraphNode(
        id: id,
        title: _unquote(titleRaw),
        criticalPath: _requiredBool(fields, 'critical_path', id, lineNumber),
        capabilityGated: _requiredBool(
          fields,
          'capability_gated',
          id,
          lineNumber,
        ),
        lineNumber: lineNumber,
      ),
    );
  }
  i++; // past the 'edges:' line

  final edgeHeader = RegExp(r'^  - from: (\S+)$');
  final edges = <GraphEdge>[];
  while (i < lines.length) {
    while (i < lines.length && _isBlankOrComment(lines[i])) {
      i++;
    }
    if (i >= lines.length) break;

    final headerMatch = edgeHeader.firstMatch(lines[i]);
    if (headerMatch == null) {
      throw FormatException(
        'docs/sdd/dependency-graph.yaml:${i + 1}: expected an edge entry '
        '("  - from: <chNN>"), got: "${lines[i]}"',
      );
    }
    final from = headerMatch.group(1)!;
    final lineNumber = i + 1;
    i++;

    if (i >= lines.length || !lines[i].startsWith('    to: ')) {
      throw FormatException(
        'docs/sdd/dependency-graph.yaml:${lineNumber + 1}: expected '
        '4-space-indented "to: <chNN>" after edge "from: $from" (line '
        '$lineNumber)',
      );
    }
    final to = lines[i].substring('    to: '.length).trim();
    i++;
    edges.add(GraphEdge(from: from, to: to, lineNumber: lineNumber));
  }

  return DependencyGraph(nodes: nodes, edges: edges);
}

/// Finds a cycle in [graph], returning the cycle as an ordered list of node
/// ids (first id repeated as the last element), or `null` if the graph —
/// restricted to edges between known node ids — is acyclic.
List<String>? findCycle(DependencyGraph graph) {
  final adjacency = <String, List<String>>{
    for (final node in graph.nodes) node.id: <String>[],
  };
  final knownIds = adjacency.keys.toSet();
  for (final edge in graph.edges) {
    if (knownIds.contains(edge.from) && knownIds.contains(edge.to)) {
      adjacency[edge.from]!.add(edge.to);
    }
  }

  const white = 0;
  const gray = 1;
  const black = 2;
  final color = {for (final id in knownIds) id: white};
  final stack = <String>[];

  List<String>? visit(String id) {
    color[id] = gray;
    stack.add(id);
    for (final next in adjacency[id]!) {
      final nextColor = color[next];
      if (nextColor == gray) {
        final cycleStart = stack.indexOf(next);
        return [...stack.sublist(cycleStart), next];
      }
      if (nextColor == white) {
        final found = visit(next);
        if (found != null) return found;
      }
    }
    stack.removeLast();
    color[id] = black;
    return null;
  }

  for (final id in knownIds) {
    if (color[id] == white) {
      final found = visit(id);
      if (found != null) return found;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Cross-checking the table against the measured chapter files and the graph
// ---------------------------------------------------------------------------

enum SddIndexIssueCode {
  duplicateChapter,
  missingChapter,
  missingFile,
  korokMismatch,
  unknownGraphNode,
  cyclicGraph,
}

final class SddIndexIssue {
  const SddIndexIssue(this.code, this.message);

  final SddIndexIssueCode code;
  final String message;
}

final class SddIndexReport {
  SddIndexReport({required List<SddIndexIssue> issues})
    : issues = List.unmodifiable(issues);

  final List<SddIndexIssue> issues;

  bool get isClean => issues.isEmpty;

  String format() {
    if (isClean) return 'SDD index OK (${issues.length} issue(s)).';
    final output = StringBuffer('SDD index check failed:');
    for (final issue in issues) {
      output.writeln();
      output.write('- [${issue.code.name}] ${issue.message}');
    }
    return output.toString();
  }
}

/// Cross-checks a parsed chapter table against a parsed dependency graph and
/// the measurements taken from disk ([measuredKorCounts], [existingFiles]).
///
/// This is the pure, content-parameterized core (ADR 0443 D4): every input
/// is a plain value, so tests can construct a duplicated chapter, a
/// dangling file reference, or a cyclic graph directly — none of which the
/// real `docs/sdd/` tree can produce.
SddIndexReport validateSddIndex({
  required List<ChapterTableRow> rows,
  required DependencyGraph graph,
  required Map<int, int> measuredKorCounts,
  required Set<String> existingFiles,
}) {
  final issues = <SddIndexIssue>[];

  final occurrences = <int, int>{};
  for (final row in rows) {
    occurrences[row.chapterNumber] = (occurrences[row.chapterNumber] ?? 0) + 1;
  }
  for (final entry in occurrences.entries) {
    if (entry.value > 1) {
      issues.add(
        SddIndexIssue(
          SddIndexIssueCode.duplicateChapter,
          'Chapter ${entry.key} szerepel ${entry.value}-szer az index '
          'táblában (pontosan egyszer szabadna).',
        ),
      );
    }
  }
  for (final chapterNumber in measuredKorCounts.keys) {
    if (!occurrences.containsKey(chapterNumber)) {
      issues.add(
        SddIndexIssue(
          SddIndexIssueCode.missingChapter,
          'Chapter $chapterNumber létező fejezet-fájl, de nincs sora az '
          'index táblában.',
        ),
      );
    }
  }

  for (final row in rows) {
    if (!existingFiles.contains(row.filePath)) {
      issues.add(
        SddIndexIssue(
          SddIndexIssueCode.missingFile,
          'Chapter ${row.chapterNumber} "Fájl" hivatkozása nem létező '
          'fájlra mutat: ${row.filePath}',
        ),
      );
    }
    final completionReportPath = row.completionReportPath;
    if (completionReportPath != null &&
        !existingFiles.contains(completionReportPath)) {
      issues.add(
        SddIndexIssue(
          SddIndexIssueCode.missingFile,
          'Chapter ${row.chapterNumber} "Zárójelentés" hivatkozása nem '
          'létező fájlra mutat: $completionReportPath',
        ),
      );
    }
    final measured = measuredKorCounts[row.chapterNumber];
    if (measured != null && measured != row.korokCount) {
      issues.add(
        SddIndexIssue(
          SddIndexIssueCode.korokMismatch,
          'Chapter ${row.chapterNumber}: az index tábla ${row.korokCount} '
          'kört ír ("${row.korokRaw}"), a fejezet-fájlban mért kör-fejlécek '
          'száma $measured.',
        ),
      );
    }
  }

  final knownIds = graph.nodes.map((node) => node.id).toSet();
  for (final edge in graph.edges) {
    for (final id in [edge.from, edge.to]) {
      if (!knownIds.contains(id)) {
        issues.add(
          SddIndexIssue(
            SddIndexIssueCode.unknownGraphNode,
            'dependency-graph.yaml:${edge.lineNumber}: az él ismeretlen '
            'csomópontra hivatkozik: $id',
          ),
        );
      }
    }
  }
  final cycle = findCycle(graph);
  if (cycle != null) {
    issues.add(
      SddIndexIssue(
        SddIndexIssueCode.cyclicGraph,
        'dependency-graph.yaml körkörös függőséget tartalmaz: '
        '${cycle.join(' -> ')}',
      ),
    );
  }

  return SddIndexReport(issues: issues);
}

/// Reads and cross-checks the real `docs/sdd/` tree under [projectRoot].
SddIndexReport checkSddIndexAtRoot({required Directory projectRoot}) {
  final sddDirectory = Directory('${projectRoot.absolute.path}/docs/sdd');
  final indexFile = File('${sddDirectory.path}/00-index.md');
  final graphFile = File('${sddDirectory.path}/dependency-graph.yaml');

  final rows = parseChapterTable(indexFile.readAsStringSync());
  final graph = parseDependencyGraph(graphFile.readAsStringSync());

  final existingFiles = <String>{};
  final measuredKorCounts = <int, int>{};
  final chapterFilePrefix = RegExp(r'^(\d{2})-');
  for (final entry in sddDirectory.listSync()) {
    if (entry is! File || !entry.path.endsWith('.md')) continue;
    final name = entry.uri.pathSegments.last;
    existingFiles.add(name);
    if (name == '00-index.md') continue;
    final match = chapterFilePrefix.firstMatch(name);
    if (match == null) continue;
    measuredKorCounts[int.parse(match.group(1)!)] = countKorHeaders(
      entry.readAsStringSync(),
    );
  }

  return validateSddIndex(
    rows: rows,
    graph: graph,
    measuredKorCounts: measuredKorCounts,
    existingFiles: existingFiles,
  );
}

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/check_sdd_index.dart');
    exitCode = 64;
    return;
  }
  try {
    final report = checkSddIndexAtRoot(projectRoot: Directory.current);
    if (report.isClean) {
      stdout.writeln(report.format());
      return;
    }
    stderr.writeln(report.format());
    exitCode = 1;
  } on Object catch (error, stackTrace) {
    stderr.writeln('SDD index check could not run: $error');
    stderr.writeln(stackTrace);
    exitCode = 2;
  }
}
