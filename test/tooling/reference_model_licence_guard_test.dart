// E14-R17 licence guard (ADR 0369 D1/D3/D4/D5). The round's allowed_paths
// carries no `tool/**` library file, so the manifest-schema validator, the
// fail-closed reference-artifact tree-walk and the report-structure check all
// live in this one test file rather than an imported checker.
//
// D1: the manifest must carry THREE independent license verdicts (code,
// checkpoint, dataset) — never one merged field, and never the literal
// "unknown"/"n/a" string standing in for an undeclared license (L546: that
// inversion is exactly the falsification cell this file must not get wrong).
// D5: the tree-walk starts from the repository's tracked files, not from the
// manifest's own list, and is not limited to `assets/`.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _manifestRelativePath = 'ml/reference/reference_manifest.json';
const _reportRelativePath = 'docs/eval/reference-model-audit.md';

void main() {
  group(
    'A — manifest schema: three SEPARATE license verdicts (ADR 0369 D1)',
    () {
      test('the real reference_manifest.json passes the schema gate', () {
        final report = _validateManifestSchema(_realManifest());

        expect(report.isClean, isTrue, reason: report.format());
      });

      test('the real manifest pins the exact measured commit, checksum and '
          'byte counts (§0.0 A) — not placeholder or re-measured values', () {
        final document = _realManifest();
        final source = document['source']! as Map<String, Object?>;
        final artifacts = document['artifacts']! as Map<String, Object?>;
        final checkpoint = artifacts['checkpoint']! as Map<String, Object?>;
        final dataset = artifacts['dataset']! as Map<String, Object?>;

        expect(
          source['pinned_commit'],
          '929e403f3256b055c1eea27064ae39f36905359e',
        );
        expect(
          checkpoint['sha256'],
          '80297850d7d2150093d5ae2bcb090466566ad24fa835a5c1e67f16ca38a3ea44',
        );
        expect(checkpoint['bytes'], 134344202);
        expect(dataset['blob_count'], 330);
        expect(dataset['bytes'], 913163829);
      });

      test('a single merged top-level license field is rejected — matrix row: '
          '"egyetlen összevont licenc-mező" (acceptance point 2)', () {
        final document = _realManifest();
        document['license'] = 'Apache-2.0';

        final report = _validateManifestSchema(document);

        expect(report.isClean, isFalse);
        expect(
          report.issues.map((issue) => issue.kind),
          contains(ManifestIssueKind.mergedLicenseField),
        );
      });

      test('a missing checkpoint license block is a typed failure', () {
        final document = _realManifest();
        final artifacts = _mutableCopy(document['artifacts']!);
        final checkpoint = _mutableCopy(artifacts['checkpoint']!);
        checkpoint.remove('license');
        artifacts['checkpoint'] = checkpoint;
        document['artifacts'] = artifacts;

        final report = _validateManifestSchema(document);

        expect(report.isClean, isFalse);
        expect(
          report.issues.map((issue) => issue.kind),
          contains(ManifestIssueKind.missingLicenseField),
        );
      });

      for (final artifactKey in const ['code', 'checkpoint', 'dataset']) {
        for (final placeholder in const [
          'unknown',
          'Unknown',
          'UNKNOWN',
          'n/a',
          'N/A',
          '',
        ]) {
          test('the literal spdx placeholder "$placeholder" on $artifactKey is '
              'rejected even when every other field is present (L546: the '
              'falsification cell must not invert)', () {
            final document = _realManifest();
            final artifacts = _mutableCopy(document['artifacts']!);
            final artifact = _mutableCopy(artifacts[artifactKey]!);
            final license = _mutableCopy(artifact['license']!);
            license['spdx'] = placeholder;
            license['verdict'] = 'blocking';
            artifact['license'] = license;
            artifacts[artifactKey] = artifact;
            document['artifacts'] = artifacts;

            final report = _validateManifestSchema(document);

            expect(report.isClean, isFalse, reason: report.format());
            expect(
              report.issues.map((issue) => issue.kind),
              contains(ManifestIssueKind.placeholderSpdx),
            );
          });
        }
      }

      test('a null spdx WITHOUT a "blocking" verdict is rejected — an '
          'undeclared license can never be silently marked permissive', () {
        final document = _realManifest();
        final artifacts = _mutableCopy(document['artifacts']!);
        final checkpoint = _mutableCopy(artifacts['checkpoint']!);
        final license = _mutableCopy(checkpoint['license']!);
        license['spdx'] = null;
        license['verdict'] = 'permissive_for_research_reproduction';
        checkpoint['license'] = license;
        artifacts['checkpoint'] = checkpoint;
        document['artifacts'] = artifacts;

        final report = _validateManifestSchema(document);

        expect(report.isClean, isFalse);
        expect(
          report.issues.map((issue) => issue.kind),
          contains(ManifestIssueKind.nullSpdxWithoutBlockingVerdict),
        );
      });

      test('a null spdx WITH a "blocking" verdict is accepted — the actual '
          'measured shape of the checkpoint and dataset license fields', () {
        final artifacts = _realManifest()['artifacts']! as Map<String, Object?>;
        final checkpointLicense =
            (artifacts['checkpoint']! as Map<String, Object?>)['license']!
                as Map<String, Object?>;

        expect(checkpointLicense['spdx'], isNull);
        expect(checkpointLicense['verdict'], 'blocking');

        final report = _validateManifestSchema(_realManifest());
        expect(report.isClean, isTrue, reason: report.format());
      });

      test('a non-hex or wrong-length pinned_commit is rejected', () {
        final document = _realManifest();
        final source = _mutableCopy(document['source']!);
        source['pinned_commit'] = 'not-a-commit-hash';
        document['source'] = source;

        final report = _validateManifestSchema(document);

        expect(report.isClean, isFalse);
        expect(
          report.issues.map((issue) => issue.kind),
          contains(ManifestIssueKind.badCommitFormat),
        );
      });

      test('a checkpoint sha256 of the wrong length is rejected', () {
        final document = _realManifest();
        final artifacts = _mutableCopy(document['artifacts']!);
        final checkpoint = _mutableCopy(artifacts['checkpoint']!);
        checkpoint['sha256'] = 'deadbeef';
        artifacts['checkpoint'] = checkpoint;
        document['artifacts'] = artifacts;

        final report = _validateManifestSchema(document);

        expect(report.isClean, isFalse);
        expect(
          report.issues.map((issue) => issue.kind),
          contains(ManifestIssueKind.badChecksumFormat),
        );
      });

      test('a non-positive checkpoint byte count is rejected', () {
        final document = _realManifest();
        final artifacts = _mutableCopy(document['artifacts']!);
        final checkpoint = _mutableCopy(artifacts['checkpoint']!);
        checkpoint['bytes'] = 0;
        artifacts['checkpoint'] = checkpoint;
        document['artifacts'] = artifacts;

        final report = _validateManifestSchema(document);

        expect(report.isClean, isFalse);
        expect(
          report.issues.map((issue) => issue.kind),
          contains(ManifestIssueKind.nonPositiveSize),
        );
      });
    },
  );

  group('B — fail-closed reference-artifact tree guard, NOT limited to '
      'assets/ (ADR 0369 D5)', () {
    test('the real StrumSight tree carries zero unapproved reference-origin '
        'artifacts today (ADR 0369 D3: zero external bytes in the tree)', () {
      final report = _auditReferenceArtifacts(_findProjectRoot());

      expect(report.isClean, isTrue, reason: report.format());
    });

    test('a clean synthetic tree with no reference-origin artifact passes', () {
      final projectRoot = _newTempRepo();
      addTearDown(() => projectRoot.deleteSync(recursive: true));
      _track(projectRoot, 'lib/main.dart', 'void main() {}\n');

      final report = _auditReferenceArtifacts(projectRoot);

      expect(report.isClean, isTrue, reason: report.format());
    });

    for (final location in <String>[
      'assets/ml/weights.ckpt',
      'ml/scratch/weights.ckpt',
      'tool/cache/weights.pt',
      'test/fixtures/model.pth',
      'weights.ckpt',
      'ml/scratch/prepared_dataset.h5',
    ]) {
      test('falsification cell (§7.1): an unaudited checkpoint at "$location" '
          'turns the guard RED, and removing it turns it GREEN again — proves '
          'the guard is not limited to assets/', () {
        final projectRoot = _newTempRepo();
        addTearDown(() => projectRoot.deleteSync(recursive: true));
        _track(projectRoot, 'lib/main.dart', 'void main() {}\n');

        final clean = _auditReferenceArtifacts(projectRoot);
        expect(clean.isClean, isTrue, reason: clean.format());

        _track(projectRoot, location, 'not a real checkpoint, just bytes');
        final flagged = _auditReferenceArtifacts(projectRoot);
        expect(
          flagged.isClean,
          isFalse,
          reason: 'expected $location to be flagged',
        );
        expect(flagged.issues.map((issue) => issue.path), contains(location));

        _untrack(projectRoot, location);
        final green = _auditReferenceArtifacts(projectRoot);
        expect(green.isClean, isTrue, reason: green.format());
      });
    }

    test('a dataset directory carrying the pinned dataset slug is flagged '
        'even nested deep in an unrelated path', () {
      final projectRoot = _newTempRepo();
      addTearDown(() => projectRoot.deleteSync(recursive: true));
      const path = 'ml/experiments/deep/nested/klangio-gst-mm-2025/take1.wav';
      _track(projectRoot, path, 'audio bytes');

      final report = _auditReferenceArtifacts(projectRoot);

      expect(report.isClean, isFalse);
      expect(report.issues.map((issue) => issue.path), contains(path));
    });

    test('an artifact WITH a matching "approved" audit_registry entry passes '
        '— the escape hatch exists even though it is unused today (D2: '
        'NO-GO means the registry stays empty in this round)', () {
      final projectRoot = _newTempRepo();
      addTearDown(() => projectRoot.deleteSync(recursive: true));
      const contents = 'approved fixture checkpoint bytes';
      const path = 'ml/reference/fixtures/approved.ckpt';
      _track(projectRoot, path, contents);
      final sha256Hex = sha256.convert(utf8.encode(contents)).toString();
      _writeManifestWithRegistry(projectRoot, [
        {'sha256': sha256Hex, 'status': 'approved', 'path': path},
      ]);
      _stage(projectRoot, _manifestRelativePath);

      final report = _auditReferenceArtifacts(projectRoot);

      expect(report.isClean, isTrue, reason: report.format());
    });

    test('the real audit_registry is empty — the D2 NO-GO verdict means no '
        'reference artifact is approved for this round', () {
      final registry = _realManifest()['audit_registry'];

      expect(registry, isEmpty);
    });

    test('git ls-files failing (not a repository) fails loudly, never '
        'silently clean', () {
      final notARepository = Directory.systemTemp.createTempSync(
        'strumsight_not_git_',
      );
      addTearDown(() => notARepository.deleteSync(recursive: true));

      expect(
        () => _auditReferenceArtifacts(notARepository),
        throwsA(isA<StateError>()),
        reason: 'an unprovable gate is red, not green',
      );
    });
  });

  group('C — the two measurements never share a table (ADR 0369 D4)', () {
    test('the real report keeps the official fixture and the StrumSight '
        'held-out result in two separate sections, each with its own '
        'corpus-hash field', () {
      final report = _validateReportStructure(_realReportMarkdown());

      expect(report.isClean, isTrue, reason: report.issues.join('\n'));
    });

    test('a report missing the official-fixture heading is rejected', () {
      const markdown = '''
## StrumSight held-out
| metric | value | korpusz-hash |
|---|---|---|
| accuracy | NEM MÉRT | NEM MÉRT |
''';

      final report = _validateReportStructure(markdown);

      expect(report.isClean, isFalse);
    });

    test('a single table naming both measurements in one row is rejected — '
        'matrix row: "a két mérés egy táblában" (acceptance point 3)', () {
      const markdown = '''
## Hivatalos fixture és StrumSight held-out
| measurement | metric | value | korpusz-hash |
|---|---|---|---|
| Hivatalos / StrumSight combined | accuracy | NEM MÉRT | NEM MÉRT |
''';

      final report = _validateReportStructure(markdown);

      expect(report.isClean, isFalse);
      expect(report.mergedTableDetected, isTrue);
    });

    test('two separate, correctly headed tables with their own corpus-hash '
        'field pass', () {
      const markdown = '''
## Hivatalos fixture (Klangio scripts/evaluate.ipynb)
| metric | value | korpusz-hash |
|---|---|---|
| f1 | NEM MÉRT | NEM MÉRT |

## StrumSight held-out
| metric | value | korpusz-hash |
|---|---|---|
| accuracy | NEM MÉRT | NEM MÉRT |
''';

      final report = _validateReportStructure(markdown);

      expect(report.isClean, isTrue, reason: report.issues.join('\n'));
    });
  });
}

// ---------------------------------------------------------------------------
// Group A — manifest schema validation
// ---------------------------------------------------------------------------

enum ManifestIssueKind {
  mergedLicenseField,
  missingArtifactBlock,
  missingLicenseField,
  placeholderSpdx,
  nullSpdxWithoutBlockingVerdict,
  badCommitFormat,
  badChecksumFormat,
  nonPositiveSize,
}

class ManifestIssue {
  ManifestIssue(this.kind, this.path, this.detail);

  final ManifestIssueKind kind;
  final String path;
  final String detail;

  @override
  String toString() => '$path: ${kind.name} — $detail';
}

class ManifestSchemaReport {
  ManifestSchemaReport(this.issues);

  final List<ManifestIssue> issues;

  bool get isClean => issues.isEmpty;

  String format() => issues.map((issue) => issue.toString()).join('\n');
}

const _placeholderLicenceValues = <String>{'unknown', 'n/a', 'na', 'none', ''};

const _requiredLicenseFields = <String>[
  'spdx',
  'source',
  'evidence',
  'verdict',
];

ManifestSchemaReport _validateManifestSchema(Map<String, Object?> document) {
  final issues = <ManifestIssue>[];

  if (document.containsKey('license')) {
    issues.add(
      ManifestIssue(
        ManifestIssueKind.mergedLicenseField,
        'license',
        'a single top-level license field cannot independently cover code, '
            'checkpoint and dataset',
      ),
    );
  }

  final artifacts = document['artifacts'];
  if (artifacts is! Map<String, Object?>) {
    issues.add(
      ManifestIssue(
        ManifestIssueKind.missingArtifactBlock,
        'artifacts',
        'missing artifacts map',
      ),
    );
    return ManifestSchemaReport(issues);
  }

  for (final artifactKey in const ['code', 'checkpoint', 'dataset']) {
    final artifact = artifacts[artifactKey];
    if (artifact is! Map<String, Object?>) {
      issues.add(
        ManifestIssue(
          ManifestIssueKind.missingArtifactBlock,
          artifactKey,
          'missing artifact block',
        ),
      );
      continue;
    }

    final license = artifact['license'];
    if (license is! Map<String, Object?>) {
      issues.add(
        ManifestIssue(
          ManifestIssueKind.missingLicenseField,
          '$artifactKey.license',
          'missing license block',
        ),
      );
      continue;
    }

    for (final field in _requiredLicenseFields) {
      if (!license.containsKey(field)) {
        issues.add(
          ManifestIssue(
            ManifestIssueKind.missingLicenseField,
            '$artifactKey.license.$field',
            'missing required field',
          ),
        );
      }
    }

    final spdx = license['spdx'];
    final verdict = license['verdict'];
    if (spdx == null) {
      if (verdict != 'blocking') {
        issues.add(
          ManifestIssue(
            ManifestIssueKind.nullSpdxWithoutBlockingVerdict,
            '$artifactKey.license.verdict',
            'an undeclared (null) spdx must carry verdict "blocking", got '
                '${verdict.toString()}',
          ),
        );
      }
    } else if (spdx is String &&
        _placeholderLicenceValues.contains(spdx.trim().toLowerCase())) {
      issues.add(
        ManifestIssue(
          ManifestIssueKind.placeholderSpdx,
          '$artifactKey.license.spdx',
          'placeholder value "$spdx" is never a valid license — use a real '
              'SPDX id or explicit null',
        ),
      );
    }

    for (final field in const ['source', 'evidence']) {
      final value = license[field];
      if (value is String &&
          _placeholderLicenceValues.contains(value.trim().toLowerCase())) {
        issues.add(
          ManifestIssue(
            ManifestIssueKind.placeholderSpdx,
            '$artifactKey.license.$field',
            'placeholder value "$value"',
          ),
        );
      }
    }
  }

  final source = document['source'];
  if (source is Map<String, Object?>) {
    final commit = source['pinned_commit'];
    if (commit is! String || !RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
      issues.add(
        ManifestIssue(
          ManifestIssueKind.badCommitFormat,
          'source.pinned_commit',
          'must be a 40-character lowercase hex commit hash',
        ),
      );
    }
  } else {
    issues.add(
      ManifestIssue(
        ManifestIssueKind.missingArtifactBlock,
        'source',
        'missing source block',
      ),
    );
  }

  final checkpoint = artifacts['checkpoint'];
  if (checkpoint is Map<String, Object?>) {
    final sha256Value = checkpoint['sha256'];
    if (sha256Value is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256Value)) {
      issues.add(
        ManifestIssue(
          ManifestIssueKind.badChecksumFormat,
          'checkpoint.sha256',
          'must be a 64-character lowercase hex sha256',
        ),
      );
    }
    final bytes = checkpoint['bytes'];
    if (bytes is! int || bytes <= 0) {
      issues.add(
        ManifestIssue(
          ManifestIssueKind.nonPositiveSize,
          'checkpoint.bytes',
          'must be a positive integer',
        ),
      );
    }
  }

  final dataset = artifacts['dataset'];
  if (dataset is Map<String, Object?>) {
    final bytes = dataset['bytes'];
    if (bytes is! int || bytes <= 0) {
      issues.add(
        ManifestIssue(
          ManifestIssueKind.nonPositiveSize,
          'dataset.bytes',
          'must be a positive integer',
        ),
      );
    }
    final blobCount = dataset['blob_count'];
    if (blobCount is! int || blobCount <= 0) {
      issues.add(
        ManifestIssue(
          ManifestIssueKind.nonPositiveSize,
          'dataset.blob_count',
          'must be a positive integer',
        ),
      );
    }
  }

  return ManifestSchemaReport(issues);
}

// ---------------------------------------------------------------------------
// Group B — fail-closed reference-artifact tree guard
// ---------------------------------------------------------------------------

enum ArtifactAuditIssueKind { unapprovedReferenceArtifact }

class ArtifactAuditIssue {
  ArtifactAuditIssue(this.kind, this.path, this.reason);

  final ArtifactAuditIssueKind kind;
  final String path;
  final String reason;
}

class ArtifactAuditReport {
  ArtifactAuditReport(this.issues);

  final List<ArtifactAuditIssue> issues;

  bool get isClean => issues.isEmpty;

  String format() =>
      issues.map((issue) => '${issue.path}: ${issue.reason}').join('\n');
}

// Measured against the pinned upstream commit's `.gitattributes`, which puts
// SIX extensions under Git-LFS: `*.pth *.pt *.ckpt *.cpkt *.h5 *.pkl` (`cpkt`
// is upstream's own misspelling variant, also LFS-tracked). `safetensors` is
// kept as a general reference-checkpoint signature beyond this one upstream.
const _referenceCheckpointExtensions = <String>{
  'ckpt',
  'cpkt',
  'pt',
  'pth',
  'h5',
  'pkl',
  'safetensors',
};
const _referenceDatasetSlug = 'klangio-gst-mm-2025';

bool _looksLikeReferenceCheckpoint(String relativePath) {
  final dot = relativePath.lastIndexOf('.');
  if (dot < 0) return false;
  final extension = relativePath.substring(dot + 1).toLowerCase();
  return _referenceCheckpointExtensions.contains(extension);
}

bool _looksLikeReferenceDatasetPath(String relativePath) =>
    relativePath.toLowerCase().split('/').contains(_referenceDatasetSlug);

/// Walks the repository's TRACKED files (ADR 0473 D1 pattern: the tree
/// defines the corpus, not the manifest's own list) and flags any file whose
/// name signature matches a known reference-model artifact shape, unless the
/// manifest's `audit_registry` carries an `approved` entry for its sha256.
ArtifactAuditReport _auditReferenceArtifacts(Directory projectRoot) {
  final trackedFiles = _gitLsFiles(projectRoot);
  final approvedShas = _loadApprovedAuditShas(projectRoot);
  final issues = <ArtifactAuditIssue>[];

  for (final relativePath in trackedFiles) {
    final isCandidate =
        _looksLikeReferenceCheckpoint(relativePath) ||
        _looksLikeReferenceDatasetPath(relativePath);
    if (!isCandidate) continue;

    final file = File('${projectRoot.path}/$relativePath');
    if (!file.existsSync()) continue;
    final sha256Hex = sha256.convert(file.readAsBytesSync()).toString();
    if (approvedShas.contains(sha256Hex)) continue;

    issues.add(
      ArtifactAuditIssue(
        ArtifactAuditIssueKind.unapprovedReferenceArtifact,
        relativePath,
        'recognized as a reference-model-derived artifact (checkpoint '
        'extension or dataset path signature) with no "approved" entry '
        'in $_manifestRelativePath audit_registry',
      ),
    );
  }

  return ArtifactAuditReport(issues);
}

List<String> _gitLsFiles(Directory projectRoot) {
  final result = Process.runSync('git', [
    'ls-files',
  ], workingDirectory: projectRoot.path);
  if (result.exitCode != 0) {
    throw StateError(
      'git ls-files failed in ${projectRoot.path}: ${result.stderr}',
    );
  }
  return (result.stdout as String)
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
}

Set<String> _loadApprovedAuditShas(Directory projectRoot) {
  final manifestFile = File('${projectRoot.path}/$_manifestRelativePath');
  if (!manifestFile.existsSync()) return <String>{};
  final document =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
  final registry = document['audit_registry'];
  if (registry is! List) return <String>{};
  return registry
      .cast<Map<String, Object?>>()
      .where((entry) => entry['status'] == 'approved')
      .map((entry) => (entry['sha256']! as String).toLowerCase())
      .toSet();
}

// ---------------------------------------------------------------------------
// Group C — report structure validation
// ---------------------------------------------------------------------------

class ReportStructureReport {
  ReportStructureReport({
    required this.mergedTableDetected,
    required this.issues,
  });

  final bool mergedTableDetected;
  final List<String> issues;

  bool get isClean => issues.isEmpty;
}

ReportStructureReport _validateReportStructure(String markdown) {
  final issues = <String>[];

  final officialHeadingMatches = RegExp(
    r'^#{1,3}\s.*(hivatalos.*fixture|official.*fixture)',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(markdown);
  final heldOutHeadingMatches = RegExp(
    r'^#{1,3}\s.*strumsight.*held.?out',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(markdown);

  if (!officialHeadingMatches) {
    issues.add(
      'missing a dedicated "hivatalos fixture" / "official fixture" heading',
    );
  }
  if (!heldOutHeadingMatches) {
    issues.add('missing a dedicated "StrumSight held-out" heading');
  }

  final corpusHashMentions = RegExp(
    r'korpusz.?hash|corpus.?hash',
    caseSensitive: false,
  ).allMatches(markdown).length;
  if (corpusHashMentions < 2) {
    issues.add(
      'fewer than two corpus-hash fields — each measurement must carry its '
      'own',
    );
  }

  // The exact anti-pattern D4 forbids: one table row naming BOTH
  // measurements — a merged comparison / averaged number.
  final mergedRow = markdown.split('\n').any((line) {
    if (!line.trim().startsWith('|')) return false;
    final lowerLine = line.toLowerCase();
    final namesOfficial =
        lowerLine.contains('hivatalos') || lowerLine.contains('official');
    final namesHeldOut =
        lowerLine.contains('strumsight') ||
        lowerLine.contains('held-out') ||
        lowerLine.contains('held out');
    return namesOfficial && namesHeldOut;
  });
  if (mergedRow) {
    issues.add(
      'a single table row references both measurements — they must never '
      'share a row',
    );
  }

  return ReportStructureReport(mergedTableDetected: mergedRow, issues: issues);
}

// ---------------------------------------------------------------------------
// Shared fixture helpers
// ---------------------------------------------------------------------------

Directory _findProjectRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (_isRegularFile('${candidate.path}/pubspec.yaml') &&
        _isRegularFile('${candidate.path}/AGENTS.md')) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not find the StrumSight repository root.');
    }
    candidate = parent;
  }
}

bool _isRegularFile(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) ==
    FileSystemEntityType.file;

Map<String, Object?> _realManifest() =>
    jsonDecode(
          File(
            '${_findProjectRoot().path}/$_manifestRelativePath',
          ).readAsStringSync(),
        )
        as Map<String, Object?>;

String _realReportMarkdown() =>
    File('${_findProjectRoot().path}/$_reportRelativePath').readAsStringSync();

/// Deep-enough mutable copy for test mutation: a JSON-decoded map's nested
/// maps are fixed-size, so tests that mutate a nested block need their own
/// growable copy rather than touching the decoded document in place.
Map<String, Object?> _mutableCopy(Object? value) =>
    Map<String, Object?>.of(value! as Map<String, Object?>);

Directory _newTempRepo() {
  final projectRoot = Directory.systemTemp.createTempSync(
    'strumsight_reference_licence_guard_',
  );
  Process.runSync('git', const [
    'init',
    '-q',
  ], workingDirectory: projectRoot.path);
  Process.runSync('git', const [
    'config',
    'user.email',
    'gate@example.invalid',
  ], workingDirectory: projectRoot.path);
  Process.runSync('git', const [
    'config',
    'user.name',
    'Gate Test',
  ], workingDirectory: projectRoot.path);
  return projectRoot;
}

void _write(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void _stage(Directory root, String relativePath) {
  Process.runSync('git', [
    'add',
    '-f',
    relativePath,
  ], workingDirectory: root.path);
}

void _track(Directory root, String relativePath, String contents) {
  _write(root, relativePath, contents);
  _stage(root, relativePath);
}

void _untrack(Directory root, String relativePath) {
  Process.runSync('git', [
    'rm',
    '-q',
    '-f',
    relativePath,
  ], workingDirectory: root.path);
}

void _writeManifestWithRegistry(
  Directory root,
  List<Map<String, Object?>> approvedEntries,
) {
  _write(
    root,
    _manifestRelativePath,
    jsonEncode(<String, Object?>{
      'schema_version': 1,
      'audit_registry': approvedEntries,
    }),
  );
}
