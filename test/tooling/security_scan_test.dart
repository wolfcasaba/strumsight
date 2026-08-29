// strumsight:allow-secret-file — this file's whole purpose is proving the
// `security_scan.py` `secrets` branch flags a synthetic, known-bad literal
// (A1); every token below is intentionally shaped like a secret so the
// detection is provable, exactly like `check_secrets_test.dart` does for
// `tool/ci/check_secrets.dart` itself.
//
// Release security scan gate (E12-R18, ADR 0481). Follows the
// `test/tooling/signing_policy_test.dart` pattern: a Dart gate test that
// shells out to `python3 tool/release/security_scan.py` against both
// synthetic fixtures and the real tree. `security_scan.py` DELEGATES its
// `secrets` branch to `tool/ci/check_secrets.dart` (ADR 0481 D3) rather
// than declaring a second regex set — A1/A2 measure that delegation, not a
// re-implementation of secret detection.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _tool = 'tool/release/security_scan.py';
const _realCheckSecrets = 'tool/ci/check_secrets.dart';

class _ScanResult {
  _ScanResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

_ScanResult _run(List<String> args) {
  final result = Process.runSync('python3', [_tool, ...args]);
  return _ScanResult(
    result.exitCode,
    result.stdout.toString(),
    result.stderr.toString(),
  );
}

void _write(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

String _guardBlock({
  required String id,
  String component = 'diagnostics-upload',
  String threat = 'tampering',
  bool releaseGate = true,
  required String path,
  String? test,
}) {
  final testLine = test == null ? '' : '\n  test: $test';
  return '''
```yaml
id: $id
component: $component
threat: $threat
release_gate: $releaseGate
guard:
  path: $path$testLine
```
''';
}

const String _emptyExceptions = '''
exceptions: []
''';

void main() {
  late Directory fixtureRoot;

  setUp(() {
    fixtureRoot = Directory.systemTemp.createTempSync(
      'strumsight_security_scan_',
    );
  });

  tearDown(() => fixtureRoot.deleteSync(recursive: true));

  group('A1 — secrets branch delegates to check_secrets.dart', () {
    test('a synthetic provider-token literal is a critical finding', () {
      final secretsRoot = Directory.systemTemp.createTempSync(
        'strumsight_secrets_fixture_',
      );
      addTearDown(() => secretsRoot.deleteSync(recursive: true));

      Process.runSync('git', const [
        'init',
        '-q',
      ], workingDirectory: secretsRoot.path);
      Process.runSync('git', const [
        'config',
        'user.email',
        'gate@example.invalid',
      ], workingDirectory: secretsRoot.path);
      Process.runSync('git', const [
        'config',
        'user.name',
        'Gate Test',
      ], workingDirectory: secretsRoot.path);

      _write(
        secretsRoot,
        _realCheckSecrets,
        File(_realCheckSecrets).readAsStringSync(),
      );
      // Matches the check_secrets provider-token rule (`sk-` prefix) and is
      // NOT on the placeholder list — the exact shape L220 requires so the
      // red path is proven, not assumed.
      _write(
        secretsRoot,
        'lib/leaked.dart',
        "const key = 'sk-abcdefghijklmnopqrstuvwxyz0123';\n",
      );
      Process.runSync('git', const [
        'add',
        '-f',
        'lib/leaked.dart',
        'tool/ci/check_secrets.dart',
      ], workingDirectory: secretsRoot.path);

      final result = _run(['--root', secretsRoot.path, '--only', 'secrets']);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('secrets.delegate-failed'));
      // Proves this is the INJECTED secret being detected, not a
      // coincidental non-zero exit: the delegate's own location + rule
      // name must surface.
      expect(result.stdout, contains('lib/leaked.dart'));
      expect(result.stdout, contains('provider token'));
      // The location may appear, the secret VALUE never may.
      expect(
        result.stdout,
        isNot(contains('sk-abcdefghijklmnopqrstuvwxyz0123')),
      );
    });
  });

  group('A2 — secrets branch fails closed when the delegate cannot run', () {
    test('an unrunnable --secrets-cmd is a critical finding, not skipped', () {
      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'secrets',
        '--secrets-cmd',
        'a-command-that-does-not-exist-anywhere-xyz',
      ]);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('secrets.delegate-unavailable'));
      expect(result.stdout, isNot(contains('skipped')));
    });

    test(
      'a non-zero-exit --secrets-cmd is a critical finding, not skipped',
      () {
        final result = _run([
          '--root',
          fixtureRoot.path,
          '--only',
          'secrets',
          '--secrets-cmd',
          '/bin/false',
        ]);

        expect(result.exitCode, 1, reason: result.stdout + result.stderr);
        expect(result.stdout, contains('secrets.delegate-failed'));
        expect(result.stdout, isNot(contains('skipped')));
      },
    );
  });

  group('A3 — exception expiry threshold is inclusive', () {
    _ScanResult runWithExpiry(String expires, String today) {
      _write(fixtureRoot, 'exceptions.yaml', '''
exceptions:
  - finding: SOME-FINDING
    owner: gate@example.invalid
    expires: "$expires"
    reason: fixture for the A3 threshold triple
''');
      return _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'exceptions',
        '--exceptions',
        'exceptions.yaml',
        '--today',
        today,
      ]);
    }

    test(
      'below the threshold (expired yesterday) is a critical finding, exit 1',
      () {
        final result = runWithExpiry('2026-08-28', '2026-08-29');
        expect(result.exitCode, 1, reason: result.stdout + result.stderr);
        expect(result.stdout, contains('exceptions.expired'));
      },
    );

    test('exactly on the threshold (expires today) is still live, exit 0', () {
      final result = runWithExpiry('2026-08-29', '2026-08-29');
      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    });

    test('above the threshold (expires tomorrow) is live, exit 0', () {
      final result = runWithExpiry('2026-08-30', '2026-08-29');
      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    });
  });

  group(
    'A4 — an exception entry without owner/expires is a critical finding',
    () {
      test('missing owner', () {
        _write(fixtureRoot, 'exceptions.yaml', '''
exceptions:
  - finding: SOME-FINDING
    expires: "2099-01-01"
    reason: fixture missing owner
''');

        final result = _run([
          '--root',
          fixtureRoot.path,
          '--only',
          'exceptions',
          '--exceptions',
          'exceptions.yaml',
        ]);

        expect(result.exitCode, 1, reason: result.stdout + result.stderr);
        expect(result.stdout, contains('exceptions.missing-field'));
      });

      test('missing expires', () {
        _write(fixtureRoot, 'exceptions.yaml', '''
exceptions:
  - finding: SOME-FINDING
    owner: gate@example.invalid
    reason: fixture missing expires
''');

        final result = _run([
          '--root',
          fixtureRoot.path,
          '--only',
          'exceptions',
          '--exceptions',
          'exceptions.yaml',
        ]);

        expect(result.exitCode, 1, reason: result.stdout + result.stderr);
        expect(result.stdout, contains('exceptions.missing-field'));
      });
    },
  );

  group('A5 — the guards branch checks both guard.path AND guard.test', () {
    test('a guard.path that does not exist is a critical finding', () {
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(id: 'T-FIXTURE-01', path: 'no/such/file.py'),
      );

      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'guards',
        '--threat-model',
        'threat-model.md',
      ]);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('T-FIXTURE-01'));
      expect(result.stdout, contains('does not exist'));
    });

    test('a guard.test name absent from guard.path is a critical finding', () {
      _write(
        fixtureRoot,
        'guarded.py',
        'def test_something_else():\n    pass\n',
      );
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-02',
          path: 'guarded.py',
          test: 'test_the_real_thing',
        ),
      );

      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'guards',
        '--threat-model',
        'threat-model.md',
      ]);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('T-FIXTURE-02'));
      expect(result.stdout, contains('not found in'));
    });

    test('a guard whose path and test both resolve passes', () {
      _write(
        fixtureRoot,
        'guarded.py',
        'def test_the_real_thing():\n    pass\n',
      );
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-03',
          path: 'guarded.py',
          test: 'test_the_real_thing',
        ),
      );

      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'guards',
        '--threat-model',
        'threat-model.md',
      ]);

      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    });
  });

  group('A6 — dependency bound and advisory checks', () {
    test('a dependency line without an upper bound is a critical finding', () {
      _write(fixtureRoot, 'exceptions.yaml', _emptyExceptions);
      _write(fixtureRoot, 'requirements.txt', 'somepackage>=1.0\n');

      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'dependencies',
        '--requirements',
        'requirements.txt',
        '--exceptions',
        'exceptions.yaml',
      ]);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('no-upper-bound'));
    });

    test('a version matching a documented advisory is a critical finding', () {
      _write(fixtureRoot, 'exceptions.yaml', _emptyExceptions);
      _write(fixtureRoot, 'requirements.txt', 'PyJWT>=2.0,<2.4.0\n');

      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'dependencies',
        '--requirements',
        'requirements.txt',
        '--exceptions',
        'exceptions.yaml',
      ]);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('CVE-2022-29217'));
    });

    test('a live exception naming the advisory id exempts the finding', () {
      _write(fixtureRoot, 'requirements.txt', 'PyJWT>=2.0,<2.4.0\n');
      _write(fixtureRoot, 'exceptions.yaml', '''
exceptions:
  - finding: CVE-2022-29217
    owner: gate@example.invalid
    expires: "2099-01-01"
    reason: fixture — proves live-exception suppression (A6)
''');

      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'dependencies',
        '--requirements',
        'requirements.txt',
        '--exceptions',
        'exceptions.yaml',
      ]);

      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    });
  });

  group('A7 — missing or malformed inputs fail closed with exit 2', () {
    test('a missing threat model file exits 2, not 0', () {
      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'guards',
        '--threat-model',
        'no-such-threat-model.md',
      ]);

      expect(result.exitCode, 2, reason: result.stdout + result.stderr);
    });

    test('a guard block with unparsable YAML exits 2, not 0', () {
      _write(fixtureRoot, 'threat-model.md', '''
```yaml
id: [this is not, valid: yaml: at: all
```
''');

      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'guards',
        '--threat-model',
        'threat-model.md',
      ]);

      expect(result.exitCode, 2, reason: result.stdout + result.stderr);
    });

    test('a missing exceptions file exits 2, not 0', () {
      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'exceptions',
        '--exceptions',
        'no-such-exceptions.yaml',
      ]);

      expect(result.exitCode, 2, reason: result.stdout + result.stderr);
    });

    test('a missing requirements file exits 2, not 0', () {
      _write(fixtureRoot, 'exceptions.yaml', _emptyExceptions);
      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'dependencies',
        '--requirements',
        'no-such-requirements.txt',
        '--exceptions',
        'exceptions.yaml',
      ]);

      expect(result.exitCode, 2, reason: result.stdout + result.stderr);
    });

    test('--only dependencies still fails closed when the exceptions registry '
        'it consults for suppression is missing', () {
      _write(fixtureRoot, 'requirements.txt', 'somepackage>=1.0,<2.0\n');
      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'dependencies',
        '--requirements',
        'requirements.txt',
        '--exceptions',
        'no-such-exceptions.yaml',
      ]);

      expect(result.exitCode, 2, reason: result.stdout + result.stderr);
    });
  });

  group('A8 — the shipped threat model resolves on the real tree', () {
    const realThreatModel = 'docs/security/threat-model.md';

    test('guards branch passes exit 0 against the real threat-model.md', () {
      final result = _run(['--only', 'guards']);

      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    });

    test(
      'every component in the real threat model has at least one guard id',
      () {
        final text = File(realThreatModel).readAsStringSync();
        const components = [
          'client-storage',
          'backend-api',
          'diagnostics-upload',
          'community-media-upload',
          'model-package',
          'community',
          'release-chain',
        ];
        for (final component in components) {
          expect(
            text,
            contains('component: $component'),
            reason: '$component has no guard block in $realThreatModel',
          );
        }
      },
    );
  });

  group('--format json is machine-readable', () {
    test('emits a findings[] array with id/severity/branch/message', () {
      final result = _run([
        '--root',
        fixtureRoot.path,
        '--only',
        'secrets',
        '--secrets-cmd',
        '/bin/false',
        '--format',
        'json',
      ]);

      final decoded = jsonDecode(result.stdout) as Map<String, dynamic>;
      final findings = decoded['findings'] as List<dynamic>;
      expect(findings, isNotEmpty);
      final first = findings.first as Map<String, dynamic>;
      expect(
        first.keys,
        containsAll(<String>['id', 'severity', 'branch', 'message']),
      );
    });
  });
}
