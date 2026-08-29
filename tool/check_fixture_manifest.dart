import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Schema version this checker accepts for `test/fixtures/manifest.json`.
const fixtureManifestSchemaVersion = 1;

const _fixtureRoot = 'test/fixtures';
const _manifestRelativePath = 'test/fixtures/manifest.json';
const _sha256Pattern = r'^[0-9a-f]{64}$';

/// Machine-specific path fragments the manifest text may never contain
/// (ADR 0473 D7, L530): a generated release artifact must be reproducible
/// from any checkout, not tied to the generating machine's home directory.
const machinePathFragments = <String>['/home/', '/Users/', r'C:\'];

/// The kinds of fixture-manifest failures this checker enforces.
enum FixtureManifestIssueKind {
  invalidManifestJson,
  wrongSchemaVersion,
  invalidEntry,
  duplicateEntry,
  pathOutsideFixtureTree,
  machinePath,
  missingLicense,
  missingSource,
  containsUserData,
  entryMissingFromDisk,
  fixtureMissingManifestEntry,
  checksumMismatch,
  sizeMismatch,
}

/// One problem found while checking the fixture manifest against the
/// `test/fixtures/` tree.
final class FixtureManifestIssue {
  const FixtureManifestIssue({
    required this.kind,
    required this.path,
    required this.message,
  });

  final FixtureManifestIssueKind kind;
  final String path;
  final String message;

  @override
  String toString() => '$path: $message';
}

/// One well-formed entry read from `test/fixtures/manifest.json`.
final class FixtureManifestEntry {
  const FixtureManifestEntry({
    required this.path,
    required this.bytes,
    required this.sha256,
    required this.license,
    required this.source,
    required this.containsUserData,
  });

  final String path;
  final int bytes;
  final String sha256;
  final String license;
  final String source;
  final bool containsUserData;
}

/// Complete result of checking `test/fixtures/manifest.json` against the
/// `test/fixtures/` tree of a project root.
final class FixtureManifestReport {
  FixtureManifestReport({
    required List<FixtureManifestEntry> entries,
    required List<FixtureManifestIssue> issues,
  }) : entries = List.unmodifiable(entries),
       issues = List.unmodifiable(issues);

  final List<FixtureManifestEntry> entries;
  final List<FixtureManifestIssue> issues;

  bool get isClean => issues.isEmpty;

  /// Human-readable CLI output containing no fixture contents.
  String format() {
    if (isClean) {
      return 'Fixture manifest OK (${entries.length} fixture(s)).';
    }
    final output = StringBuffer('Fixture manifest check failed.');
    for (final issue in issues) {
      output
        ..writeln()
        ..write('- $issue');
    }
    return output.toString();
  }
}

/// Checks `test/fixtures/manifest.json` against the actual
/// `test/fixtures/` tree under [projectRoot] (ADR 0473).
///
/// The corpus is defined by the FILE TREE, not by the manifest (D1): every
/// file under `test/fixtures/` is required to have a manifest entry, except
/// `*.dart` sources, `README.md` files, and the manifest itself (D2) — a
/// manifest entry no fixture file backs on disk is flagged just as loudly
/// as a fixture with no manifest entry.
FixtureManifestReport checkFixtureManifest({required Directory projectRoot}) {
  final issues = <FixtureManifestIssue>[];
  final root = projectRoot.absolute.path;
  final manifestFile = File('$root/$_manifestRelativePath');

  if (!manifestFile.existsSync()) {
    issues.add(
      const FixtureManifestIssue(
        kind: FixtureManifestIssueKind.invalidManifestJson,
        path: _manifestRelativePath,
        message: 'manifest file does not exist',
      ),
    );
    return FixtureManifestReport(entries: const [], issues: issues);
  }

  final manifestText = manifestFile.readAsStringSync();
  for (final fragment in machinePathFragments) {
    if (manifestText.contains(fragment)) {
      issues.add(
        FixtureManifestIssue(
          kind: FixtureManifestIssueKind.machinePath,
          path: _manifestRelativePath,
          message:
              'manifest text contains a machine-specific path fragment: '
              '"$fragment"',
        ),
      );
    }
  }

  Object? decoded;
  try {
    decoded = jsonDecode(manifestText);
  } on FormatException catch (error) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.invalidManifestJson,
        path: _manifestRelativePath,
        message: 'invalid JSON: $error',
      ),
    );
    return FixtureManifestReport(entries: const [], issues: issues);
  }

  if (decoded is! Map<String, Object?>) {
    issues.add(
      const FixtureManifestIssue(
        kind: FixtureManifestIssueKind.invalidManifestJson,
        path: _manifestRelativePath,
        message: 'manifest root must be a JSON object',
      ),
    );
    return FixtureManifestReport(entries: const [], issues: issues);
  }

  if (decoded['schemaVersion'] != fixtureManifestSchemaVersion) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.wrongSchemaVersion,
        path: _manifestRelativePath,
        message: 'schemaVersion must be $fixtureManifestSchemaVersion',
      ),
    );
  }

  final rawEntries = decoded['fixtures'];
  final entries = <FixtureManifestEntry>[];
  final seenPaths = <String>{};
  if (rawEntries is! List<Object?>) {
    issues.add(
      const FixtureManifestIssue(
        kind: FixtureManifestIssueKind.invalidManifestJson,
        path: _manifestRelativePath,
        message: '"fixtures" must be a list',
      ),
    );
  } else {
    for (var index = 0; index < rawEntries.length; index++) {
      final entry = _readEntry(rawEntries[index], index, issues, seenPaths);
      if (entry != null) {
        entries.add(entry);
      }
    }
  }

  final manifestByPath = {for (final entry in entries) entry.path: entry};

  for (final entry in entries) {
    final file = File('$root/${entry.path}');
    if (!file.existsSync()) {
      issues.add(
        FixtureManifestIssue(
          kind: FixtureManifestIssueKind.entryMissingFromDisk,
          path: entry.path,
          message: 'manifest entry has no corresponding file on disk',
        ),
      );
      continue;
    }
    final actualBytes = file.readAsBytesSync();
    if (actualBytes.length != entry.bytes) {
      issues.add(
        FixtureManifestIssue(
          kind: FixtureManifestIssueKind.sizeMismatch,
          path: entry.path,
          message:
              'file is ${actualBytes.length} byte(s), manifest says '
              '${entry.bytes}',
        ),
      );
    }
    final actualSha256 = sha256.convert(actualBytes).toString();
    if (actualSha256 != entry.sha256) {
      issues.add(
        FixtureManifestIssue(
          kind: FixtureManifestIssueKind.checksumMismatch,
          path: entry.path,
          message:
              'sha256 differs from manifest: expected ${entry.sha256}, '
              'actual $actualSha256',
        ),
      );
    }
  }

  for (final path in _walkFixtureFiles(root)) {
    if (!manifestByPath.containsKey(path)) {
      issues.add(
        FixtureManifestIssue(
          kind: FixtureManifestIssueKind.fixtureMissingManifestEntry,
          path: path,
          message: 'fixture file has no manifest entry',
        ),
      );
    }
  }

  return FixtureManifestReport(entries: entries, issues: issues);
}

FixtureManifestEntry? _readEntry(
  Object? raw,
  int index,
  List<FixtureManifestIssue> issues,
  Set<String> seenPaths,
) {
  if (raw is! Map<String, Object?>) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.invalidEntry,
        path: 'fixtures[$index]',
        message: 'entry must be a JSON object',
      ),
    );
    return null;
  }

  final path = raw['path'];
  if (path is! String || path.isEmpty) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.invalidEntry,
        path: 'fixtures[$index]',
        message: 'entry "path" must be a non-empty string',
      ),
    );
    return null;
  }
  if (path.startsWith('/') ||
      path.contains(r'\') ||
      path.contains('..') ||
      !path.startsWith('$_fixtureRoot/')) {
    issues.add(
      FixtureManifestIssue(
        kind: path.startsWith('$_fixtureRoot/')
            ? FixtureManifestIssueKind.machinePath
            : FixtureManifestIssueKind.pathOutsideFixtureTree,
        path: path,
        message: 'entry path must be a repo-relative path under $_fixtureRoot/',
      ),
    );
    return null;
  }
  if (!seenPaths.add(path)) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.duplicateEntry,
        path: path,
        message: 'duplicate manifest entry',
      ),
    );
    return null;
  }

  final license = raw['license'];
  if (license is! String || license.trim().isEmpty) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.missingLicense,
        path: path,
        message: 'entry has no license',
      ),
    );
  }
  final source = raw['source'];
  if (source is! String || source.trim().isEmpty) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.missingSource,
        path: path,
        message: 'entry has no source/provenance',
      ),
    );
  }

  final containsUserData = raw['containsUserData'];
  if (containsUserData is! bool) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.invalidEntry,
        path: path,
        message: 'entry "containsUserData" must be an explicit boolean',
      ),
    );
  } else if (containsUserData) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.containsUserData,
        path: path,
        message:
            'entry declares containsUserData=true — a release fixture must '
            'not carry user data',
      ),
    );
  }

  final sha256Value = raw['sha256'];
  if (sha256Value is! String || !RegExp(_sha256Pattern).hasMatch(sha256Value)) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.invalidEntry,
        path: path,
        message: 'entry "sha256" must be 64 lowercase hex characters',
      ),
    );
    return null;
  }

  final bytesValue = raw['bytes'];
  if (bytesValue is! int || bytesValue < 0) {
    issues.add(
      FixtureManifestIssue(
        kind: FixtureManifestIssueKind.invalidEntry,
        path: path,
        message: 'entry "bytes" must be a non-negative integer',
      ),
    );
    return null;
  }

  return FixtureManifestEntry(
    path: path,
    bytes: bytesValue,
    sha256: sha256Value,
    license: license is String ? license : '',
    source: source is String ? source : '',
    containsUserData: containsUserData == true,
  );
}

/// Lists every repo-relative path under `test/fixtures/` inside [root]
/// that the corpus definition requires a manifest entry for (ADR 0473 D2):
/// every file EXCEPT `*.dart` sources, `README.md` files, and the manifest
/// itself (which cannot describe its own checksum).
Iterable<String> _walkFixtureFiles(String root) sync* {
  final fixtureDir = Directory('$root/$_fixtureRoot');
  if (!fixtureDir.existsSync()) return;
  final prefix = '$root/';
  final entities = fixtureDir.listSync(recursive: true, followLinks: false);
  final relatives = <String>[];
  for (final entity in entities) {
    if (entity is! File) continue;
    final absolute = entity.absolute.path.replaceAll('\\', '/');
    if (!absolute.startsWith(prefix)) continue;
    final relative = absolute.substring(prefix.length);
    if (relative.endsWith('.dart')) continue;
    if (relative == _manifestRelativePath) continue;
    final baseName = relative.substring(relative.lastIndexOf('/') + 1);
    if (baseName == 'README.md') continue;
    relatives.add(relative);
  }
  relatives.sort();
  yield* relatives;
}

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/check_fixture_manifest.dart');
    exitCode = 64;
    return;
  }

  try {
    final report = checkFixtureManifest(projectRoot: Directory.current);
    if (report.isClean) {
      stdout.writeln(report.format());
      return;
    }
    stderr.writeln(report.format());
    exitCode = 1;
  } on Object catch (error, stackTrace) {
    stderr.writeln('Fixture manifest check could not run: $error');
    stderr.writeln(stackTrace);
    exitCode = 2;
  }
}
