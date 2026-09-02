// Feature-freeze policy gate (E12-R30). Follows the
// `test/tooling/ga_scope_test.dart` pattern: a Dart gate test that shells
// out to `python3 tool/release/verify_freeze.py` against both the real
// tree and synthetic fixtures built from temp-dir copies (never committed).
//
// A1 = freeze-era change classification (the closed `documentation` /
// `release-tooling` / `blocker-fix` set, `docs/release/feature-freeze.md`).
// A2 = every known-issues.md row carries a non-empty title/impact/workaround
// and a known severity. A3 = every P0/P1 known-issues.md row exists (with
// matching severity) in blockers.md — this group also carries the brief
// §6.1 "valódi-sértés próba". A4 = the CHANGELOG.md release-header block
// matches the MEASURED pubspec.yaml + manifest-generator sources. A7 = all
// three marker-block parsers (feature-freeze classes, known-issues,
// CHANGELOG header) are fail-closed: a missing marker block, a malformed
// row and an empty block are all non-zero exits (L566/L571/L573/L575).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _tool = 'tool/release/verify_freeze.py';
const _featureFreeze = 'docs/release/feature-freeze.md';
const _knownIssues = 'docs/release/known-issues.md';
const _blockers = 'docs/release/blockers.md';
const _changelog = 'CHANGELOG.md';

ProcessResult _run(List<String> args) =>
    Process.runSync('python3', [_tool, ...args]);

Directory _tempDir() =>
    Directory.systemTemp.createTempSync('strumsight_freeze_policy_');

File _writeIn(Directory dir, String name, String contents) =>
    File('${dir.path}/$name')..writeAsStringSync(contents);

void main() {
  group('self-check — python3 is on PATH', () {
    test('a missing python3 would turn every cell below red, not skip it', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });
  });

  group('sanity — the shipped documents validate against the real tree', () {
    test(
      'exit 0 with only default paths (no --since/--changes-file) — the '
      'default call classifies too (MAJOR-1: it falls back to '
      'feature-freeze.md\'s freeze_base_sha, it does not silently skip A1)',
      () {
        final result = _run([]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout.toString(), contains('ok'));
        expect(
          result.stdout.toString(),
          contains('changed path(s) classified'),
        );
      },
    );

    test('exit 0 classifying the real freeze-era diff since freeze_base_sha '
        '(§7 — this round\'s own diff is documentation + release-tooling '
        'only)', () {
      final result = _run(['--since', '4ac78365']);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('changed path(s) classified'));
    });
  });

  group('A1 — freeze-era change classification (the closed 3-class set)', () {
    test('a path matching no documentation/release-tooling prefix and named '
        'by no blocker id is a non-zero exit naming the path', () {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final changes = _writeIn(
        dir,
        'changes.tsv',
        'lib/features/practice/some_screen.dart\tunrelated tidy-up, no blocker cited\n',
      );

      final result = _run(['--changes-file', changes.path]);
      expect(result.exitCode, 1);
      expect(
        result.stderr.toString(),
        contains('lib/features/practice/some_screen.dart'),
      );
      expect(result.stderr.toString(), contains('not classified'));
    });

    test('documentation and release-tooling paths need no blocker id (exit '
        '0)', () {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final changes = _writeIn(
        dir,
        'changes.tsv',
        'docs/release/some-doc.md\tdoc update, no blocker\n'
            'CHANGELOG.md\tdoc update, no blocker\n'
            'tool/release/some_tool.py\ttooling update, no blocker\n'
            'test/tooling/some_test.dart\ttooling update, no blocker\n',
      );

      final result = _run(['--changes-file', changes.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test('a non-doc/tooling path is accepted when the commit names an open '
        'P0/P1/P2 blockers.md id', () {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final changes = _writeIn(
        dir,
        'changes.tsv',
        'lib/core/storage/json_document_store.dart\t'
            'fix: R-STAGE-01 staging migration retry handling\n',
      );

      final result = _run(['--changes-file', changes.path]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test('a non-doc/tooling path citing a blocker id that does not exist in '
        'blockers.md is a non-zero exit naming the path', () {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final changes = _writeIn(
        dir,
        'changes.tsv',
        'lib/core/storage/json_document_store.dart\t'
            'fix: R-DOES-NOT-EXIST-01 made up blocker\n',
      );

      final result = _run(['--changes-file', changes.path]);
      expect(result.exitCode, 1);
      expect(
        result.stderr.toString(),
        contains('lib/core/storage/json_document_store.dart'),
      );
    });

    test('a blocker id whose severity is P3 does not authorize a blocker-fix '
        '(§5.1 "P0/P1/P2 blocker-javítás", feature-freeze.md class table '
        'note)', () {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final blockers = _writeIn(
        dir,
        'blockers.md',
        '| ID | Severity | Cím |\n'
            '|---|---|---|\n'
            '| R-TEST-01 | P3 | synthetic P3 fixture row |\n',
      );
      final changes = _writeIn(
        dir,
        'changes.tsv',
        'lib/core/storage/json_document_store.dart\tfix: R-TEST-01 minor tidy\n',
      );
      // A minimal known-issues fixture with no P0/P1 rows, so the only
      // finding this run can produce is the A1 classification finding under
      // test — isolates it from A3's cross-check against --blockers, which
      // this fixture's single-row blockers.md would otherwise also trip.
      final knownIssues = _writeIn(
        dir,
        'known-issues.md',
        '<!-- known-issues:begin -->\n'
            '| id | severity | title | impact | workaround |\n'
            '|---|---|---|---|---|\n'
            '| `K-FIXTURE-01` | `P2` | fixture row | fixture impact | fixture workaround |\n'
            '<!-- known-issues:end -->\n',
      );

      final result = _run([
        '--blockers',
        blockers.path,
        '--changes-file',
        changes.path,
        '--known-issues',
        knownIssues.path,
      ]);
      expect(result.exitCode, 1);
      expect(
        result.stderr.toString(),
        contains('lib/core/storage/json_document_store.dart'),
      );
    });

    test('a product path changed since freeze_base_sha, on a bare call with '
        'no --since/--changes-file override, is a non-zero exit naming the '
        'path (MAJOR-1 regression — the default call used to skip '
        'classification entirely and print "ok" with exit 0)', () {
      final repoDir = _tempDir();
      addTearDown(() => repoDir.deleteSync(recursive: true));
      void git(List<String> args) {
        final result = Process.runSync(
          'git',
          args,
          workingDirectory: repoDir.path,
        );
        expect(
          result.exitCode,
          0,
          reason: 'git ${args.join(' ')} failed: ${result.stderr}',
        );
      }

      git(['init', '-q']);
      git(['config', 'user.email', 'freeze-test@strumsight.app']);
      git(['config', 'user.name', 'freeze-test']);
      _writeIn(repoDir, 'seed.txt', 'seed\n');
      git(['add', '-A']);
      git(['commit', '-q', '-m', 'seed']);
      final baseSha = Process.runSync('git', [
        'rev-parse',
        'HEAD',
      ], workingDirectory: repoDir.path).stdout.toString().trim();
      _writeIn(repoDir, 'lib_stub.dart', '// not classified\n');
      git(['add', '-A']);
      git(['commit', '-q', '-m', 'unrelated tidy-up, no blocker cited']);

      final featureFreeze = _writeIn(repoDir, 'feature-freeze.md', '''
<!-- freeze-base:begin -->
freeze_base_sha: $baseSha
approver_role: freeze-test fixture
<!-- freeze-base:end -->

<!-- freeze-classes:begin -->
| class | path_prefixes | requires_blocker_id |
|---|---|---|
| `documentation` | `docs/`, `CHANGELOG.md` | `no` |
| `release-tooling` | `tool/release/`, `test/tooling/` | `no` |
| `blocker-fix` | `*` | `yes` |
<!-- freeze-classes:end -->
''');

      final result = Process.runSync('python3', [
        File(_tool).absolute.path,
        '--feature-freeze',
        featureFreeze.path,
        '--known-issues',
        File(_knownIssues).absolute.path,
        '--blockers',
        File(_blockers).absolute.path,
        '--changelog',
        File(_changelog).absolute.path,
        '--pubspec',
        File('pubspec.yaml').absolute.path,
        '--manifest-generator',
        File('tool/generate_release_manifest.dart').absolute.path,
      ], workingDirectory: repoDir.path);
      expect(result.exitCode, 1, reason: result.stderr.toString());
      expect(result.stderr.toString(), contains('lib_stub.dart'));
      expect(result.stderr.toString(), contains('not classified'));
    });

    test('--since and --changes-file together is a usage error (exit 2)', () {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final changes = _writeIn(dir, 'changes.tsv', 'docs/x.md\tmsg\n');

      final result = _run([
        '--since',
        '4ac78365',
        '--changes-file',
        changes.path,
      ]);
      expect(result.exitCode, 2);
    });

    test('an invalid --since revision is a usage error (exit 2)', () {
      final result = _run(['--since', 'not-a-real-revision-xyz']);
      expect(result.exitCode, 2);
    });
  });

  group('A2 — every known-issues.md row carries a non-empty title/impact/'
      'workaround and a known severity', () {
    test('an empty workaround cell is a non-zero exit naming the id (§6.1: '
        'a known-issues sor megkerülő-út cellája üres marad)', () {
      final issuesText = File(_knownIssues).readAsStringSync();
      const marker = '| `R-DEVICE-01` | `P2` |';
      expect(issuesText, contains(marker));
      final lineStart = issuesText.indexOf(marker);
      final lineEnd = issuesText.indexOf('\n', lineStart);
      final originalLine = issuesText.substring(lineStart, lineEnd);
      final lastPipe = originalLine.lastIndexOf('|');
      final secondLastPipe = originalLine.lastIndexOf('|', lastPipe - 1);
      final blankedLine =
          '${originalLine.substring(0, secondLastPipe + 1)} ${originalLine.substring(lastPipe)}';
      expect(blankedLine, isNot(originalLine));
      final mangled = issuesText.replaceFirst(originalLine, blankedLine);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'known-issues.md', mangled);

      final result = _run(['--known-issues', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('R-DEVICE-01'));
      expect(result.stderr.toString(), contains('workaround'));
    });

    test('an unknown severity value is a non-zero exit naming it', () {
      final issuesText = File(_knownIssues).readAsStringSync();
      const original = '| `R-DEVICE-01` | `P2` |';
      const mangled = '| `R-DEVICE-01` | `P9` |';
      expect(issuesText, contains(original));
      final mangledText = issuesText.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'known-issues.md', mangledText);

      final result = _run(['--known-issues', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('P9'));
    });
  });

  group('A3 — every P0/P1 known-issues.md row exists, same severity, in '
      'blockers.md — the §6.1 valódi-sértés próba', () {
    test('a P1 known-issues row whose id is NOT in blockers.md is a non-zero '
        'exit naming it (real-violation probe, run against a temp fixture — '
        'the shipped known-issues.md is never mutated by this test)', () {
      final issuesText = File(_knownIssues).readAsStringSync();
      const insertAfter = '<!-- known-issues:begin -->';
      expect(issuesText, contains(insertAfter));
      const injectedRow =
          '\n| `K-FAKE-01` | `P1` | fabricated P1 not in blockers.md | some '
          'impact | some workaround |';
      final mangled = issuesText.replaceFirst(
        insertAfter,
        '$insertAfter$injectedRow',
      );
      expect(mangled, isNot(issuesText));
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'known-issues.md', mangled);

      final result = _run(['--known-issues', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('K-FAKE-01'));
      expect(result.stderr.toString(), contains('blockers.md'));
    });

    test('a P0/P1 known-issues row whose severity disagrees with its '
        'blockers.md severity is a non-zero exit', () {
      final issuesText = File(_knownIssues).readAsStringSync();
      const original = '| `R-VER-01` | `P1` |';
      const mangled = '| `R-VER-01` | `P0` |';
      expect(issuesText, contains(original));
      final mangledText = issuesText.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'known-issues.md', mangledText);

      final result = _run(['--known-issues', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('R-VER-01'));
    });

    test('a known-issues.md row DOWNGRADED below its blockers.md severity '
        '(P1 -> P2) is a non-zero exit naming it (MAJOR-2 regression — a '
        'severity mismatch used to be checked only when the known-issues.md '
        'row was itself P0/P1, so a P1 -> P2 downgrade went undetected)', () {
      final issuesText = File(_knownIssues).readAsStringSync();
      const original = '| `R-VER-01` | `P1` |';
      const mangled = '| `R-VER-01` | `P2` |';
      expect(issuesText, contains(original));
      final mangledText = issuesText.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'known-issues.md', mangledText);

      final result = _run(['--known-issues', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('R-VER-01'));
      expect(result.stderr.toString(), contains('blockers.md'));
    });

    test('the shipped known-issues.md has no P0/P1 row outside blockers.md '
        '(sanity, tool-independent)', () {
      final issuesText = File(_knownIssues).readAsStringSync();
      final blockersText = File(_blockers).readAsStringSync();
      final blockerIds =
          RegExp(
            r'^\| (R-[A-Z0-9-]+) \| (P[0-4]) \|',
            multiLine: true,
          ).allMatches(blockersText).fold<Map<String, String>>({}, (map, m) {
            map[m.group(1)!] = m.group(2)!;
            return map;
          });
      final issueRows = RegExp(
        r'^\| `([^`]+)` \| `(P[0-3])` \|',
        multiLine: true,
      ).allMatches(issuesText);
      for (final row in issueRows) {
        final id = row.group(1)!;
        final severity = row.group(2)!;
        if (severity == 'P0' || severity == 'P1') {
          expect(
            blockerIds[id],
            severity,
            reason:
                '$id is $severity in known-issues.md but blockers.md has '
                '${blockerIds[id]}',
          );
        }
      }
    });
  });

  group('A4 — CHANGELOG.md release-header matches the measured pubspec.yaml '
      '+ manifest-generator sources', () {
    test('a mismatched version is a non-zero exit', () {
      final changelogText = File(_changelog).readAsStringSync();
      const original = 'version: 1.0.0\n';
      const mangled = 'version: 9.9.9\n';
      expect(changelogText, contains(original));
      final mangledText = changelogText.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'CHANGELOG.md', mangledText);

      final result = _run(['--changelog', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('9.9.9'));
    });

    test('a mismatched build is a non-zero exit', () {
      final changelogText = File(_changelog).readAsStringSync();
      const original = 'build: 1\n';
      const mangled = 'build: 42\n';
      expect(changelogText, contains(original));
      final mangledText = changelogText.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'CHANGELOG.md', mangledText);

      final result = _run(['--changelog', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('42'));
    });

    test('a mismatched schema_version is a non-zero exit', () {
      final changelogText = File(_changelog).readAsStringSync();
      const original = 'schema_version: 1\n';
      const mangled = 'schema_version: 7\n';
      expect(changelogText, contains(original));
      final mangledText = changelogText.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'CHANGELOG.md', mangledText);

      final result = _run(['--changelog', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('7'));
    });
  });

  group('A7 — all three marker-block parsers are fail-closed '
      '(L566/L571/L573/L575)', () {
    group('feature-freeze.md (freeze-classes block)', () {
      test('a missing marker block is exit 2', () {
        final text = File(_featureFreeze).readAsStringSync();
        final mangled = text
            .replaceFirst('<!-- freeze-classes:begin -->', '')
            .replaceFirst('<!-- freeze-classes:end -->', '');
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'feature-freeze.md', mangled);

        final result = _run(['--feature-freeze', file.path]);
        expect(result.exitCode, 2);
      });

      test('a malformed row (broken backtick shape) is exit 2', () {
        final text = File(_featureFreeze).readAsStringSync();
        const original = '| `blocker-fix` | `*` | `yes` |';
        const mangled = '| blocker-fix | `*` | `yes` |';
        expect(text, contains(original));
        final mangledText = text.replaceFirst(original, mangled);
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'feature-freeze.md', mangledText);

        final result = _run(['--feature-freeze', file.path]);
        expect(result.exitCode, 2);
        expect(
          result.stderr.toString(),
          contains('does not match the expected shape'),
        );
      });

      test('an empty freeze-classes block is exit 2', () {
        final text = File(_featureFreeze).readAsStringSync();
        final beginIndex = text.indexOf('<!-- freeze-classes:begin -->');
        final endIndex = text.indexOf('<!-- freeze-classes:end -->');
        expect(beginIndex, greaterThan(-1));
        expect(endIndex, greaterThan(beginIndex));
        final mangled = text.replaceRange(
          beginIndex + '<!-- freeze-classes:begin -->'.length,
          endIndex,
          '\n',
        );
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'feature-freeze.md', mangled);

        final result = _run(['--feature-freeze', file.path]);
        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('empty'));
      });

      test('an empty freeze-base block is exit 2', () {
        final text = File(_featureFreeze).readAsStringSync();
        final beginIndex = text.indexOf('<!-- freeze-base:begin -->');
        final endIndex = text.indexOf('<!-- freeze-base:end -->');
        expect(beginIndex, greaterThan(-1));
        expect(endIndex, greaterThan(beginIndex));
        final mangled = text.replaceRange(
          beginIndex + '<!-- freeze-base:begin -->'.length,
          endIndex,
          '\n',
        );
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'feature-freeze.md', mangled);

        final result = _run(['--feature-freeze', file.path]);
        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('empty'));
      });
    });

    group('known-issues.md', () {
      test('a missing marker block is exit 2', () {
        final text = File(_knownIssues).readAsStringSync();
        final mangled = text
            .replaceFirst('<!-- known-issues:begin -->', '')
            .replaceFirst('<!-- known-issues:end -->', '');
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'known-issues.md', mangled);

        final result = _run(['--known-issues', file.path]);
        expect(result.exitCode, 2);
      });

      test('a malformed row (missing a column) is exit 2', () {
        final text = File(_knownIssues).readAsStringSync();
        const original = '| `R-SIGN-01` | `P0` |';
        const mangled = '| `R-SIGN-01` |';
        expect(text, contains(original));
        final lineStart = text.indexOf(original);
        final lineEnd = text.indexOf('\n', lineStart);
        final originalLine = text.substring(lineStart, lineEnd);
        final mangledLine = originalLine.replaceFirst(original, mangled);
        expect(mangledLine, isNot(originalLine));
        final mangledText = text.replaceFirst(originalLine, mangledLine);
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'known-issues.md', mangledText);

        final result = _run(['--known-issues', file.path]);
        expect(result.exitCode, 2);
        expect(
          result.stderr.toString(),
          contains('does not match the expected shape'),
        );
      });

      test('an empty known-issues block is exit 2', () {
        final text = File(_knownIssues).readAsStringSync();
        final beginIndex = text.indexOf('<!-- known-issues:begin -->');
        final endIndex = text.indexOf('<!-- known-issues:end -->');
        expect(beginIndex, greaterThan(-1));
        expect(endIndex, greaterThan(beginIndex));
        final mangled = text.replaceRange(
          beginIndex + '<!-- known-issues:begin -->'.length,
          endIndex,
          '\n',
        );
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'known-issues.md', mangled);

        final result = _run(['--known-issues', file.path]);
        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('empty'));
      });
    });

    group('CHANGELOG.md (release-header block)', () {
      test('a missing marker block is exit 2', () {
        final text = File(_changelog).readAsStringSync();
        final mangled = text
            .replaceFirst('<!-- release-header:begin -->', '')
            .replaceFirst('<!-- release-header:end -->', '');
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'CHANGELOG.md', mangled);

        final result = _run(['--changelog', file.path]);
        expect(result.exitCode, 2);
      });

      test('a malformed line (missing the colon) is exit 2', () {
        final text = File(_changelog).readAsStringSync();
        const original = 'version: 1.0.0\n';
        const mangled = 'version 1.0.0\n';
        expect(text, contains(original));
        final mangledText = text.replaceFirst(original, mangled);
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'CHANGELOG.md', mangledText);

        final result = _run(['--changelog', file.path]);
        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('version: X.Y.Z'));
      });

      test('an empty release-header block is exit 2', () {
        final text = File(_changelog).readAsStringSync();
        final beginIndex = text.indexOf('<!-- release-header:begin -->');
        final endIndex = text.indexOf('<!-- release-header:end -->');
        expect(beginIndex, greaterThan(-1));
        expect(endIndex, greaterThan(beginIndex));
        final mangled = text.replaceRange(
          beginIndex + '<!-- release-header:begin -->'.length,
          endIndex,
          '\n',
        );
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'CHANGELOG.md', mangled);

        final result = _run(['--changelog', file.path]);
        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('empty'));
      });
    });
  });

  group('usage errors (exit 2) — missing files', () {
    test('a missing --feature-freeze path is exit 2', () {
      final result = _run([
        '--feature-freeze',
        'docs/release/this-file-does-not-exist.md',
      ]);
      expect(result.exitCode, 2);
    });

    test('a missing --known-issues path is exit 2', () {
      final result = _run([
        '--known-issues',
        'docs/release/this-file-does-not-exist.md',
      ]);
      expect(result.exitCode, 2);
    });

    test('a missing --changelog path is exit 2', () {
      final result = _run(['--changelog', 'this-file-does-not-exist.md']);
      expect(result.exitCode, 2);
    });
  });
}
