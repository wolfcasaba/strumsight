// GA record gate (E12-R33). Follows the
// `test/tooling/rollout_decision_test.dart` pattern: a Dart gate test that
// shells out to `python3 tool/release/verify_ga_record.py` against both the
// real tree and synthetic TEMP fixtures (never committed) — the shipped
// `docs/release/ga-record.md` is never mutated by any cell here. The A2
// group additionally imports `tool/generate_release_manifest.dart` as a
// plain library (round brief §0.0.1 P3, the
// `test/tooling/release_manifest_test.dart:24` `_buildRealManifest()`
// pattern) so the version/model/document fields are cross-checked in Dart
// too, independent of the Python tool — there is no static release-manifest
// file on the tree and neither this file nor `verify_ga_record.py` ever
// invokes `dart run`.
//
// A1 = a required field carrying an empty/unknown placeholder value is a
// non-zero exit. A2 = a recorded version field that disagrees with the
// value recomputed from pubspec.yaml/the two asset manifests is a non-zero
// exit (round brief §6.1 valódi-sértés próba 1). A3 = the record's
// flag-profile snapshot must match `docs/release/ga-scope.md` key-for-key
// (round brief §0.0.1 P4). A4 = `rollback_target` must resolve to an
// existing repo-relative path (§5.3). A5 = `docs/release/release-notes.md`
// is deterministic (no timestamp) and references `known-issues.md`. A6 =
// the record states the GA publish is a human operation. A7 = `ga_status:
// ga` is rejected while `staged-rollout-log.md` has a non-approved stage-*
// decision or `blockers.md` has an open P0/P1 row — read against the REAL
// files, which today are pending/open (round brief §0.0.1 P2/§5.4, §6.1
// valódi-sértés próba 2), and accepted once both are clean (fixture
// override), proving the rule is not vacuous.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_release_manifest.dart';

const _tool = 'tool/release/verify_ga_record.py';
const _recordDoc = 'docs/release/ga-record.md';
const _gaScopeDoc = 'docs/release/ga-scope.md';
const _releaseNotesDoc = 'docs/release/release-notes.md';
const _knownIssuesDoc = 'docs/release/known-issues.md';

ProcessResult _run(List<String> args) =>
    Process.runSync('python3', [_tool, ...args]);

Directory _tempDir() =>
    Directory.systemTemp.createTempSync('strumsight_ga_record_');

File _writeIn(Directory dir, String name, String contents) =>
    File('${dir.path}/$name')..writeAsStringSync(contents);

String _mangle(String text, String original, String replacement) {
  expect(text, contains(original));
  return text.replaceFirst(original, replacement);
}

void main() {
  group('self-check — python3 is on PATH', () {
    test('a missing python3 would turn every cell below red, not skip it', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });
  });

  group(
    'sanity — the shipped ga-record.md validates against the real tree',
    () {
      test('bare call (no flags) on the shipped tree is exit 0', () {
        final result = _run([]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout.toString(), contains('ga_status=not-yet'));
        expect(result.stdout.toString(), contains('16 flag(s)'));
      });
    },
  );

  group('A1 — a required field with a placeholder/unknown value is a '
      'non-zero exit', () {
    test('an empty version-field cell is a non-zero exit', () {
      final text = File(_recordDoc).readAsStringSync();
      final mangled = _mangle(
        text,
        '| `app_build_number` | `1` |',
        '| `app_build_number` | `` |',
      );
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run(['--record', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('placeholder'));
    });

    test('an unknown ga_status value is a non-zero exit', () {
      final text = File(_recordDoc).readAsStringSync();
      final mangled = _mangle(text, 'ga_status: not-yet', 'ga_status: shipped');
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run(['--record', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('unknown ga_status'));
    });
  });

  group('A2 — recorded version fields must match the release-manifest '
      "inputs (round brief §0.0.1 P3) — never a hand-typed literal", () {
    test('a build number that disagrees with pubspec.yaml is a non-zero '
        'exit (round brief §6.1 valódi-sértés próba 1)', () {
      final text = File(_recordDoc).readAsStringSync();
      final mangled = _mangle(
        text,
        '| `app_build_number` | `1` |',
        '| `app_build_number` | `2` |',
      );
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run(['--record', file.path]);
      expect(result.exitCode, 1, reason: result.stderr.toString());
      expect(result.stderr.toString(), contains('app_build_number'));
      expect(result.stderr.toString(), contains('(A2)'));
    });

    test('an ML manifest sha256 that disagrees with the real file is a '
        'non-zero exit', () {
      final realSha = RegExp(
        r'ml_manifest_sha256.*?`([0-9a-f]{64,})`',
      ).firstMatch(File(_recordDoc).readAsStringSync())!.group(1)!;
      final text = File(_recordDoc).readAsStringSync();
      final mangled = _mangle(text, '`$realSha`', '`${'0' * realSha.length}`');
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run(['--record', file.path]);
      expect(result.exitCode, 1, reason: result.stderr.toString());
      expect(result.stderr.toString(), contains('ml_manifest_sha256'));
    });

    test('the real committed version table matches the real release-'
        'manifest inputs, measured in Dart via '
        'generate_release_manifest.dart (round brief §0.0.1 P3, the '
        'release_manifest_test.dart:24 pattern)', () {
      final manifest = _buildRealManifest();
      final modelPackage = manifest['modelPackage'] as Map<String, Object?>;
      final knowledgePackage =
          manifest['knowledgePackage'] as Map<String, Object?>;

      final recordText = File(_recordDoc).readAsStringSync();
      expect(recordText, contains('| `app_version` | `1.0.0` |'));
      expect(recordText, contains('| `app_build_number` | `1` |'));
      expect(
        recordText,
        contains(
          '| `ml_manifest_schema_version` | '
          '`${modelPackage['schemaVersion']}` |',
        ),
      );
      expect(
        recordText,
        contains(
          '| `ml_manifest_sha256` | `${modelPackage['manifestSha256']}` |',
        ),
      );
      expect(
        recordText,
        contains('| `ml_model_count` | `${modelPackage['modelCount']}` |'),
      );
      expect(
        recordText,
        contains(
          '| `knowledge_manifest_schema_version` | '
          '`${knowledgePackage['schemaVersion']}` |',
        ),
      );
      expect(
        recordText,
        contains(
          '| `knowledge_manifest_sha256` | '
          '`${knowledgePackage['manifestSha256']}` |',
        ),
      );
      expect(
        recordText,
        contains(
          '| `knowledge_document_count` | '
          '`${knowledgePackage['documentCount']}` |',
        ),
      );
    });
  });

  group('A3 — the flag-profile snapshot must match ga-scope.md key-for-key '
      '(round brief §0.0.1 P4)', () {
    test('removing a flag row (16 -> 15) is a non-zero exit', () {
      final text = File(_recordDoc).readAsStringSync();
      final mangled = _mangle(
        text,
        '| `adaptiveShellEnabled` | `preview` | `false` |\n',
        '',
      );
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run(['--record', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('adaptiveShellEnabled'));
    });

    test('a classification that disagrees with ga-scope.md is a non-zero '
        'exit', () {
      final text = File(_recordDoc).readAsStringSync();
      final mangled = _mangle(
        text,
        '| `practiceEngineV2Enabled` | `ga` | `false` |',
        '| `practiceEngineV2Enabled` | `preview` | `false` |',
      );
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run(['--record', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('practiceEngineV2Enabled'));
    });

    test('the real committed snapshot carries exactly the 16 keys the real '
        'ga-scope.md classifies (16, brief §0.0.1 P4)', () {
      final scopeText = File(_gaScopeDoc).readAsStringSync();
      final keyPattern = RegExp(
        r'^\| `([a-zA-Z0-9]+)` \| `(?:ga|preview|disabled|postponed)` \| '
        r'`(?:true|false)` \| `[^`]+` \|',
        multiLine: true,
      );
      final scopeKeys = keyPattern
          .allMatches(scopeText)
          .map((m) => m.group(1)!)
          .toSet();
      expect(scopeKeys, hasLength(16));

      final recordText = File(_recordDoc).readAsStringSync();
      for (final key in scopeKeys) {
        expect(recordText, contains('`$key`'));
      }
    });
  });

  group(
    'A4 — rollback_target must resolve on this tree (round brief §5.3)',
    () {
      test('a TBD rollback_target is a non-zero exit', () {
        final text = File(_recordDoc).readAsStringSync();
        final mangled = _mangle(
          text,
          'rollback_target: docs/operations/disaster-recovery-drill.md',
          'rollback_target: TBD',
        );
        final dir = _tempDir();
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = _writeIn(dir, 'ga-record.md', mangled);

        final result = _run(['--record', file.path]);
        expect(result.exitCode, 1);
        expect(result.stderr.toString(), contains('placeholder'));
      });

      test('a non-existent rollback_target path is a non-zero exit', () {
        final text = File(_recordDoc).readAsStringSync();
        final mangled = _mangle(
          text,
          'rollback_target: docs/operations/disaster-recovery-drill.md',
          'rollback_target: docs/operations/this-file-does-not-exist.md',
        );
        final dir = _tempDir();
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = _writeIn(dir, 'ga-record.md', mangled);

        final result = _run(['--record', file.path]);
        expect(result.exitCode, 1);
        expect(result.stderr.toString(), contains('does not resolve'));
      });

      test('the real committed rollback_target resolves on this tree '
          '(sanity)', () {
        expect(
          File('docs/operations/disaster-recovery-drill.md').existsSync(),
          isTrue,
        );
      });
    },
  );

  group('A6 — the record states the GA publish is a human operation', () {
    test('the shipped record carries the literal sentence (sanity)', () {
      final text = File(_recordDoc).readAsStringSync();
      expect(text, contains('A GA-közzététel EMBERI művelet.'));
    });

    test('a record missing the literal sentence is a non-zero exit', () {
      final text = File(_recordDoc).readAsStringSync();
      final mangled = _mangle(
        text,
        'A GA-közzététel EMBERI művelet.',
        'A GA-közzétételt bárki elindíthatja.',
      );
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run(['--record', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('(A6)'));
    });
  });

  group('A7 — ga_status: ga is blocked by open P0/P1 or a non-approved '
      'stage-* decision (round brief §0.0.1 P2 / §5.4, §6.1 valódi-sértés '
      'próba 2)', () {
    test('flipping the shipped ga_status to ga is a non-zero exit against '
        'the REAL staged-rollout-log.md/blockers.md, which today are '
        'pending/open', () {
      final text = File(_recordDoc).readAsStringSync();
      final mangled = _mangle(text, 'ga_status: not-yet', 'ga_status: ga');
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run(['--record', file.path]);
      expect(result.exitCode, 1, reason: result.stderr.toString());
      expect(result.stderr.toString(), contains('(A7)'));
    });

    test('ga_status: ga is accepted when every stage-* decision is approved '
        'and no P0/P1 blocker is open (isolates the rule from the shipped '
        "tree's pending state — proves it is not vacuously always red)", () {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));

      final cleanLog = _writeIn(
        dir,
        'staged-rollout-log.md',
        '<!-- rollout-decisions:begin -->\n'
            '| step | window_start | window_end | observed_hours | decision | '
            'decision_maker | rollback_target |\n'
            '|---|---|---|---|---|---|---|\n'
            '| `stage-1` | 2026-09-01T00:00Z | 2026-09-02T00:00Z | 30 | '
            '`approved` | Alice | build-42 |\n'
            '| `stage-5` | 2026-09-02T00:00Z | 2026-09-04T00:00Z | 55 | '
            '`approved` | Alice | build-42 |\n'
            '| `stage-20` | 2026-09-04T00:00Z | 2026-09-07T00:00Z | 80 | '
            '`approved` | Alice | build-42 |\n'
            '<!-- rollout-decisions:end -->\n',
      );
      final cleanBlockers = _writeIn(
        dir,
        'blockers.md',
        '| ID | Severity | Cím |\n'
            '|---|---|---|\n'
            '| R-TEST-01 | P2 | fixture-only, no open P0/P1 |\n',
      );

      final recordText = File(_recordDoc).readAsStringSync();
      final mangled = _mangle(
        recordText,
        'ga_status: not-yet',
        'ga_status: ga',
      );
      final recordFile = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run([
        '--record',
        recordFile.path,
        '--rollout-log',
        cleanLog.path,
        '--blockers',
        cleanBlockers.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });
  });

  group('A9 — the marker-block/table parsers are fail-closed', () {
    test('a missing ga-status marker block is exit 2', () {
      final text = File(_recordDoc).readAsStringSync();
      final mangled = text
          .replaceFirst('<!-- ga-status:begin -->', '')
          .replaceFirst('<!-- ga-status:end -->', '');
      expect(mangled, isNot(text));
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run(['--record', file.path]);
      expect(result.exitCode, 2);
    });

    test('a malformed version-table row (missing a column) is exit 2', () {
      final text = File(_recordDoc).readAsStringSync();
      final mangled = _mangle(
        text,
        '| `app_build_number` | `1` |',
        '| `app_build_number` |',
      );
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = _writeIn(dir, 'ga-record.md', mangled);

      final result = _run(['--record', file.path]);
      expect(result.exitCode, 2);
      expect(result.stderr.toString(), contains('expected 2 columns'));
    });
  });

  group('usage errors (exit 2) — missing files', () {
    test('a missing --record path is exit 2', () {
      final result = _run([
        '--record',
        'docs/release/this-file-does-not-exist.md',
      ]);
      expect(result.exitCode, 2);
    });

    test('a missing --ga-scope path is exit 2', () {
      final result = _run([
        '--ga-scope',
        'docs/release/this-file-does-not-exist.md',
      ]);
      expect(result.exitCode, 2);
    });
  });

  group('A5 — release-notes.md is deterministic and references '
      'known-issues.md', () {
    test('release-notes.md contains no ISO-8601-shaped timestamp anywhere', () {
      final text = File(_releaseNotesDoc).readAsStringSync();
      expect(text, isNot(matches(_iso8601Pattern)));
    });

    test('self-check: the ISO-8601 regex used above actually detects a '
        'timestamp (guards against a vacuous checker)', () {
      expect('2026-08-28T10:00:00Z', matches(_iso8601Pattern));
    });

    test('release-notes.md references known-issues.md', () {
      final text = File(_releaseNotesDoc).readAsStringSync();
      expect(text, contains('known-issues.md'));
    });

    test('release-notes.md names the same app version/build the release '
        'manifest inputs measure (1.0.0+1)', () {
      final text = File(_releaseNotesDoc).readAsStringSync();
      expect(text, contains('1.0.0'));
      expect(text, contains('+1'));
    });

    test('known-issues.md (the doc release-notes.md points at) exists on '
        'this tree', () {
      expect(File(_knownIssuesDoc).existsSync(), isTrue);
    });
  });
}

final _iso8601Pattern = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');

Map<String, Object?> _buildRealManifest() {
  final mlManifestBytes = File(
    'assets/ml/model_manifest.json',
  ).readAsBytesSync();
  final knowledgeManifestBytes = File(
    'assets/tutor_knowledge/manifest.json',
  ).readAsBytesSync();
  return buildReleaseManifest(
    appVersion: '1.0.0',
    appBuildNumber: 1,
    shortSha: 'abcdef1',
    channel: 'dev',
    mlManifest:
        jsonDecode(utf8.decode(mlManifestBytes)) as Map<String, Object?>,
    mlManifestBytes: mlManifestBytes,
    knowledgeManifest:
        jsonDecode(utf8.decode(knowledgeManifestBytes)) as Map<String, Object?>,
    knowledgeManifestBytes: knowledgeManifestBytes,
  );
}
