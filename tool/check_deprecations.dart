import 'dart:io';

import 'package:strumsight/core/feature_flags/public.dart';
import 'package:strumsight/core/storage/storage_migrator.dart'
    show appStorageMigrations;

import 'check_architecture.dart' show architectureAllowlist;
import 'check_feature_flags.dart' show isFeatureFlagExpired;

/// Audits the technical-debt surface named by the E12-R35 round brief
/// (`docs/rounds/e12-r35-technical-debt-and-flag-cleanup.md`): the
/// `@Deprecated` compatibility shims, the cross-feature architecture
/// allowlist (must not grow past its measured baseline), the feature-flag
/// catalog's expired entries (via the Round-5 checker only — no second
/// truth, §0.0/R4), and `docs/release/technical-debt.md`'s own inventory
/// (every item needs an owner and a removal condition, and none may target
/// a `docs/release/contract-freeze.md` frozen scope).
///
/// The logic here is intentionally NOT inside `main()`: every audit step is
/// a content- or root-parameterized pure function
/// ([findDeprecatedSites], [countExternalImporters],
/// [allowlistExceedsBaseline], [findExpiredFlags], [parseTechnicalDebtInventory],
/// [parseFrozenScopeCells], [auditTechnicalDebtItems], [migrationChainIntact])
/// so tests can feed hand-built fixture input the real checked-in tree
/// cannot produce (mirrors `tool/check_feature_flags.dart`, §0.0/R2+R4).
/// `main()` is only a thin, `exitCode`-setting wrapper around
/// [checkDeprecationsAtRoot].

// ---------------------------------------------------------------------
// Architecture allowlist threshold (A3 + the threshold cell triple)
// ---------------------------------------------------------------------

/// The measured `architectureAllowlist` (`tool/check_architecture.dart`)
/// entry count as of the round's pre-flight (§0.0/R1, `main @ 496264d9`).
/// This allowlist may only shrink — see §5.1 of the round brief.
const architectureAllowlistBaseline = 12;

/// Whether [allowlist] has grown past [baseline]. The boundary is
/// inclusive: a set the same size as [baseline] is NOT a violation (§6,
/// "a határ INKLUZÍV").
bool allowlistExceedsBaseline({
  required Set<String> allowlist,
  required int baseline,
}) {
  return allowlist.length > baseline;
}

// ---------------------------------------------------------------------
// @Deprecated inventory (A1)
// ---------------------------------------------------------------------

/// Matches a standalone `@Deprecated(...)` annotation whose argument is one
/// or more adjacent string literals (single or double quoted), across one
/// or more physical lines — covers both `@Deprecated('...')` and the
/// multi-line, adjacent-literal form Dart uses for long messages:
/// ```dart
/// @Deprecated(
///   'first part '
///   'second part',
/// )
/// ```
/// Anchored to (optional leading whitespace then) the start of a line,
/// mirroring `check_feature_flags.dart`'s `_fieldPattern` so a mention
/// inside a doc comment or a commented-out line is never matched. Each
/// quoted segment is matched by its own character class (`[^']*`/`[^"]*`)
/// rather than a dot-all span up to the closing `)`, so a literal
/// parenthesis inside the message (e.g. "via appConfigProvider
/// (lib/app/config/).") does not truncate the match early.
final _deprecatedPattern = RegExp(
  r"""^\s*@Deprecated\(\s*((?:'[^']*'|"[^"]*")(?:\s*(?:'[^']*'|"[^"]*"))*)\s*,?\s*\)""",
  multiLine: true,
);

/// Matches a single quoted string literal, used to pull the individual
/// segments out of a [_deprecatedPattern] match's argument capture so
/// adjacent-literal messages are joined the way Dart itself concatenates
/// them.
final _deprecatedMessageSegmentPattern = RegExp('\'([^\']*)\'|"([^"]*)"');

/// Joins the quoted-literal segments inside [argumentText] (the capture
/// group from [_deprecatedPattern]) the way Dart concatenates adjacent
/// string literals.
String _extractDeprecatedMessage(String argumentText) {
  final buffer = StringBuffer();
  for (final match in _deprecatedMessageSegmentPattern.allMatches(
    argumentText,
  )) {
    buffer.write(match.group(1) ?? match.group(2) ?? '');
  }
  return buffer.toString();
}

/// Matches a top-level `import` or `export` directive's target string,
/// whichever quote style is used.
final _importExportPattern = RegExp(
  r"""^\s*(?:import|export)\s+(?:'([^']+)'|"([^"]+)")""",
  multiLine: true,
);

int _lineNumberAt(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

/// Resolves an `import`/`export` target string written inside
/// [importerPath] to a repo-relative path (e.g. `lib/core/music/chord.dart`),
/// or `null` for a `dart:`/external `package:` target this tree does not
/// contain. Handles both `package:strumsight/...` targets and relative
/// (`../../core/...`) targets by walking [importerPath]'s directory —
/// a plain suffix/substring match is not enough because a relative import
/// commonly omits path segments (e.g. `features/`) that a suffix compare
/// would require (measured while building this tool: a naive suffix match
/// undercounted `lib/features/progress/`'s real importers 6-for-17).
String? _resolveImportTarget(String importerPath, String importString) {
  const packagePrefix = 'package:strumsight/';
  if (importString.startsWith(packagePrefix)) {
    return 'lib/${importString.substring(packagePrefix.length)}';
  }
  if (importString.startsWith('package:') || importString.startsWith('dart:')) {
    return null;
  }
  final importerDir = importerPath.contains('/')
      ? importerPath.substring(0, importerPath.lastIndexOf('/'))
      : '';
  final segments = [...importerDir.split('/'), ...importString.split('/')];
  final resolved = <String>[];
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (resolved.isNotEmpty) resolved.removeLast();
    } else {
      resolved.add(segment);
    }
  }
  return resolved.join('/');
}

/// Counts how many files in [filesByPath], other than [filePath] itself,
/// import or export [filePath] — the "still in use elsewhere" measurement
/// a removal decision needs (§5.3: "a `progress_v2` nulla KÜLSŐ hívóhelye
/// önmagában NEM töröl-engedély", the reverse of this same measurement).
int countExternalImporters({
  required String filePath,
  required Map<String, String> filesByPath,
}) {
  var count = 0;
  for (final entry in filesByPath.entries) {
    if (entry.key == filePath) continue;
    for (final match in _importExportPattern.allMatches(entry.value)) {
      final target = match.group(1) ?? match.group(2);
      if (target == null) continue;
      if (_resolveImportTarget(entry.key, target) == filePath) {
        count++;
        break;
      }
    }
  }
  return count;
}

final class DeprecatedSite {
  const DeprecatedSite({
    required this.filePath,
    required this.line,
    required this.message,
    required this.externalImporterCount,
  });

  final String filePath;
  final int line;
  final String message;

  /// The number of OTHER files in the tree that import or export
  /// [filePath] — a count of importing FILES, not import statements or
  /// call sites within them (see [countExternalImporters]).
  final int externalImporterCount;
}

/// Finds every `@Deprecated(...)` site in [filesByPath], each carrying the
/// MEASURED external-importer count of the file it lives in (A1: "az audit
/// MINDEN `@Deprecated` elemhez kiad egy tételt, benne a MÉRT
/// hívóhely-számmal").
List<DeprecatedSite> findDeprecatedSites(Map<String, String> filesByPath) {
  final sites = <DeprecatedSite>[];
  for (final entry in filesByPath.entries) {
    final filePath = entry.key;
    final source = entry.value;
    for (final match in _deprecatedPattern.allMatches(source)) {
      sites.add(
        DeprecatedSite(
          filePath: filePath,
          line: _lineNumberAt(source, match.start),
          message: _extractDeprecatedMessage(match.group(1)!),
          externalImporterCount: countExternalImporters(
            filePath: filePath,
            filesByPath: filesByPath,
          ),
        ),
      );
    }
  }
  return sites;
}

/// Reads every `.dart` file under `<projectRoot>/<relativeSubdir>` into a
/// map keyed by its repo-relative path (posix separators), for use as
/// [findDeprecatedSites]'/[countExternalImporters]'s content input.
Map<String, String> readSourceTree({
  required Directory projectRoot,
  required String relativeSubdir,
}) {
  final base = Directory('${projectRoot.absolute.path}/$relativeSubdir');
  if (!base.existsSync()) return const {};
  final rootPrefixLength = projectRoot.absolute.path.length + 1;
  final files = <String, String>{};
  for (final entity in base.listSync(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final relativePath = entity.path
          .substring(rootPrefixLength)
          .replaceAll(Platform.pathSeparator, '/');
      files[relativePath] = entity.readAsStringSync();
    }
  }
  return files;
}

// ---------------------------------------------------------------------
// Expired feature flags (A2) — exclusively via the Round-5 checker
// ---------------------------------------------------------------------

final class ExpiredFlagItem {
  const ExpiredFlagItem({required this.key, required this.expiresOn});

  final String key;
  final DateTime expiresOn;
}

/// Every [registry] entry whose expiration has lapsed as of [now], per
/// [isFeatureFlagExpired] (`tool/check_feature_flags.dart`, Kör 5) — the
/// ONLY expiration decision this tool makes (§0.0/R4: no second, local
/// date comparison).
List<ExpiredFlagItem> findExpiredFlags({
  required List<FeatureFlagDefinition> registry,
  required DateTime now,
}) {
  return [
    for (final definition in registry)
      if (definition.expiresOn != null &&
          isFeatureFlagExpired(expiresOn: definition.expiresOn!, now: now))
        ExpiredFlagItem(key: definition.key, expiresOn: definition.expiresOn!),
  ];
}

// ---------------------------------------------------------------------
// docs/release/technical-debt.md inventory (A4, A5)
// ---------------------------------------------------------------------

final class TechnicalDebtItem {
  const TechnicalDebtItem({
    required this.name,
    required this.path,
    required this.owner,
    required this.removalCondition,
  });

  final String name;

  /// The path this item concerns, or the empty string / [noSinglePathMarker]
  /// when the item spans no single checkable path (e.g. a scattered TODO
  /// cluster). Any other non-empty value is treated as a real path and is
  /// checked against the frozen scope by [auditTechnicalDebtItems].
  final String path;
  final String owner;
  final String removalCondition;
}

/// The recognized `docs/release/technical-debt.md` Path-column marker for
/// "this item spans no single checkable path" (a scattered TODO cluster).
/// Only the empty string and this exact marker opt an item out of the
/// frozen-scope check in [auditTechnicalDebtItems] — every other non-empty
/// value is checked, so a row cannot silently dodge the guard by writing a
/// non-path placeholder into its Path cell.
const noSinglePathMarker = '—';

/// Extracts the content between `<!-- <markerName>:begin -->` and
/// `<!-- <markerName>:end -->` markers, or an empty string if either marker
/// is missing (mirrors `docs/release/contract-freeze.md`'s own
/// `contract-freeze:begin`/`:end` convention).
String _extractMarkedBlock(String source, String markerName) {
  final beginMarker = '<!-- $markerName:begin -->';
  final endMarker = '<!-- $markerName:end -->';
  final start = source.indexOf(beginMarker);
  final end = source.indexOf(endMarker);
  if (start == -1 || end == -1 || end < start) return '';
  return source.substring(start + beginMarker.length, end);
}

final _tableSeparatorCellPattern = RegExp(r'^:?-+:?$');

/// Parses a GitHub-flavoured markdown pipe table out of [block], dropping
/// the header row and the `---` separator row, and returns each remaining
/// row as a list of trimmed cell strings.
List<List<String>> _parseMarkdownTableRows(String block) {
  final tableLines = block
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.startsWith('|'))
      .toList();
  final rows = <List<String>>[];
  for (final line in tableLines) {
    final cells = line.split('|').map((cell) => cell.trim()).toList();
    // Drop the empty leading/trailing cells produced by the line's
    // leading/trailing pipe.
    final trimmed = cells.length >= 2
        ? cells.sublist(1, cells.length - 1)
        : cells;
    if (trimmed.every((cell) => _tableSeparatorCellPattern.hasMatch(cell))) {
      continue;
    }
    rows.add(trimmed);
  }
  return rows.isEmpty ? rows : rows.sublist(1);
}

/// Parses the `technical-debt:begin`/`:end`-marked table in
/// `docs/release/technical-debt.md`'s source into [TechnicalDebtItem]s.
/// Table columns (in order): Item, Path, Owner, Removal condition.
List<TechnicalDebtItem> parseTechnicalDebtInventory(String source) {
  final rows = _parseMarkdownTableRows(
    _extractMarkedBlock(source, 'technical-debt'),
  );
  return [
    for (final row in rows)
      if (row.length >= 4)
        TechnicalDebtItem(
          name: row[0],
          path: row[1],
          owner: row[2],
          removalCondition: row[3],
        ),
  ];
}

/// Parses the `frozen_scope` column out of `docs/release/contract-freeze.md`'s
/// `contract-freeze:begin`/`:end`-marked table (columns: contract,
/// frozen_scope, evidence, resolution_condition).
List<String> parseFrozenScopeCells(String contractFreezeSource) {
  final rows = _parseMarkdownTableRows(
    _extractMarkedBlock(contractFreezeSource, 'contract-freeze'),
  );
  return [
    for (final row in rows)
      if (row.length >= 2) row[1],
  ];
}

enum TechnicalDebtIssueCode {
  missingOwner,
  missingRemovalCondition,
  frozenScopeConflict,
}

final class TechnicalDebtAuditIssue {
  const TechnicalDebtAuditIssue(this.code, this.message);

  final TechnicalDebtIssueCode code;
  final String message;
}

/// Validates [items] against §5.2 (every item needs a non-empty owner AND
/// a non-empty removal condition) and §0.0/R5 (no item's [TechnicalDebtItem.path]
/// may fall inside a [frozenScopeCells] entry from
/// `docs/release/contract-freeze.md`). Only an empty path or
/// [noSinglePathMarker] opts an item out of the frozen-scope check — every
/// other non-empty path value is checked.
List<TechnicalDebtAuditIssue> auditTechnicalDebtItems({
  required List<TechnicalDebtItem> items,
  required List<String> frozenScopeCells,
}) {
  final issues = <TechnicalDebtAuditIssue>[];
  for (final item in items) {
    if (item.owner.trim().isEmpty) {
      issues.add(
        TechnicalDebtAuditIssue(
          TechnicalDebtIssueCode.missingOwner,
          'debt item "${item.name}" has no owner.',
        ),
      );
    }
    if (item.removalCondition.trim().isEmpty) {
      issues.add(
        TechnicalDebtAuditIssue(
          TechnicalDebtIssueCode.missingRemovalCondition,
          'debt item "${item.name}" has no removal condition.',
        ),
      );
    }
    final path = item.path.trim();
    if (path.isNotEmpty &&
        path != noSinglePathMarker &&
        frozenScopeCells.any((cell) => cell.contains(path))) {
      issues.add(
        TechnicalDebtAuditIssue(
          TechnicalDebtIssueCode.frozenScopeConflict,
          'debt item "${item.name}" targets path "$path", which falls '
          'inside a docs/release/contract-freeze.md frozen scope.',
        ),
      );
    }
  }
  return issues;
}

// ---------------------------------------------------------------------
// Supported-client migration chain (A5)
// ---------------------------------------------------------------------

/// The measured `appStorageMigrations` (`lib/core/storage/storage_migrator.dart`)
/// step count (§0.0/R5, `docs/release/client-migration.md` §1).
const supportedClientMigrationChainBaseline = 22;

/// Whether the supported-client boot migration chain is still exactly
/// [expectedLength] steps — any change (added, removed, or reordered
/// steps) needs the release evidence in `client-migration.md` re-measured,
/// which is out of this round's scope (§0.0/R5).
bool migrationChainIntact({
  required int actualLength,
  int expectedLength = supportedClientMigrationChainBaseline,
}) {
  return actualLength == expectedLength;
}

// ---------------------------------------------------------------------
// Root-level orchestration
// ---------------------------------------------------------------------

final class DeprecationAuditReport {
  const DeprecationAuditReport({
    required this.deprecatedSites,
    required this.expiredFlags,
    required this.allowlistExceeded,
    required this.debtIssues,
    required this.migrationChainOk,
  });

  final List<DeprecatedSite> deprecatedSites;
  final List<ExpiredFlagItem> expiredFlags;
  final bool allowlistExceeded;
  final List<TechnicalDebtAuditIssue> debtIssues;
  final bool migrationChainOk;

  bool get isClean =>
      expiredFlags.isEmpty &&
      !allowlistExceeded &&
      debtIssues.isEmpty &&
      migrationChainOk;

  String format() {
    final output = StringBuffer();
    final fileCount = deprecatedSites.map((s) => s.filePath).toSet().length;
    output.writeln(
      'Deprecation audit: ${deprecatedSites.length} @Deprecated site(s) in '
      '$fileCount file(s).',
    );
    for (final site in deprecatedSites) {
      output.writeln(
        '  - ${site.filePath}:${site.line} '
        '(${site.externalImporterCount} external importer file(s)) '
        '${site.message}',
      );
    }
    output.writeln(
      'Architecture allowlist: '
      '${allowlistExceeded ? "EXCEEDS the measured baseline" : "within the measured baseline"}.',
    );
    output.writeln(
      'Supported-client migration chain: '
      '${migrationChainOk ? "intact" : "CHANGED — client-migration.md needs re-measuring"}.',
    );
    if (expiredFlags.isEmpty) {
      output.writeln('Expired feature flags: none.');
    } else {
      output.writeln('Expired feature flags:');
      for (final flag in expiredFlags) {
        output.writeln(
          '  - [expiredFlag] ${flag.key} expired on '
          '${flag.expiresOn.toIso8601String()}.',
        );
      }
    }
    if (debtIssues.isEmpty) {
      output.writeln('docs/release/technical-debt.md: clean.');
    } else {
      output.writeln('docs/release/technical-debt.md issues:');
      for (final issue in debtIssues) {
        output.writeln('  - [${issue.code.name}] ${issue.message}');
      }
    }
    return output.toString();
  }
}

/// Runs the full audit against the real, checked-in tree under
/// [projectRoot], with [now] injected for the expiration check (A2).
DeprecationAuditReport checkDeprecationsAtRoot({
  required Directory projectRoot,
  required DateTime now,
}) {
  final libFiles = readSourceTree(
    projectRoot: projectRoot,
    relativeSubdir: 'lib',
  );
  final debtSource = File(
    '${projectRoot.absolute.path}/docs/release/technical-debt.md',
  ).readAsStringSync();
  final contractFreezeSource = File(
    '${projectRoot.absolute.path}/docs/release/contract-freeze.md',
  ).readAsStringSync();

  return DeprecationAuditReport(
    deprecatedSites: findDeprecatedSites(libFiles),
    expiredFlags: findExpiredFlags(registry: featureFlagRegistry, now: now),
    allowlistExceeded: allowlistExceedsBaseline(
      allowlist: architectureAllowlist,
      baseline: architectureAllowlistBaseline,
    ),
    debtIssues: auditTechnicalDebtItems(
      items: parseTechnicalDebtInventory(debtSource),
      frozenScopeCells: parseFrozenScopeCells(contractFreezeSource),
    ),
    migrationChainOk: migrationChainIntact(
      actualLength: appStorageMigrations.length,
    ),
  );
}

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/check_deprecations.dart');
    exitCode = 64;
    return;
  }
  try {
    final report = checkDeprecationsAtRoot(
      projectRoot: Directory.current,
      now: DateTime.now(),
    );
    if (report.isClean) {
      stdout.writeln(report.format());
      return;
    }
    stderr.writeln(report.format());
    exitCode = 1;
  } on Object catch (error, stackTrace) {
    stderr.writeln('Deprecation audit could not run: $error');
    stderr.writeln(stackTrace);
    exitCode = 2;
  }
}
