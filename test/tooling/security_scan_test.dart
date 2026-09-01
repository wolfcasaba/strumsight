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
    branch: dependencies
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
    branch: dependencies
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

  group('MAJOR-1 — an exceptions entry can never suppress the secrets branch, '
      'and only ever suppresses the SAME branch + finding it names', () {
    test('an exception naming a secrets finding id does not suppress a '
        'failing --secrets-cmd on the default (full) run', () {
      _write(
        fixtureRoot,
        'guarded.py',
        'def test_the_real_thing():\n    pass\n',
      );
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-MAJOR1A',
          path: 'guarded.py',
          test: 'test_the_real_thing',
        ),
      );
      _write(fixtureRoot, 'requirements.txt', 'somepackage<2.0\n');
      // Exactly the review's repro: owner + future expires, naming both
      // fixed secrets-branch finding ids. Before the fix this silenced
      // the WHOLE secrets branch — any future real commited secret
      // included.
      _write(fixtureRoot, 'exceptions.yaml', '''
exceptions:
  - finding: secrets.delegate-failed
    branch: guards
    owner: gate@example.invalid
    expires: "2099-01-01"
    reason: fixture — MAJOR-1, must never reach the secrets branch
  - finding: secrets.delegate-unavailable
    branch: guards
    owner: gate@example.invalid
    expires: "2099-01-01"
    reason: fixture — MAJOR-1, must never reach the secrets branch
''');

      final result = _run([
        '--root',
        fixtureRoot.path,
        '--threat-model',
        'threat-model.md',
        '--requirements',
        'requirements.txt',
        '--exceptions',
        'exceptions.yaml',
        '--secrets-cmd',
        '/bin/false',
      ]);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('secrets.delegate-failed'));
    });

    test('an exception entry without a branch field is a critical finding', () {
      _write(fixtureRoot, 'exceptions.yaml', '''
exceptions:
  - finding: SOME-FINDING
    owner: gate@example.invalid
    expires: "2099-01-01"
    reason: fixture missing branch
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

    test('an exception entry whose branch is not "guards"/"dependencies" '
        '(e.g. "secrets") is a critical finding', () {
      _write(fixtureRoot, 'exceptions.yaml', '''
exceptions:
  - finding: SOME-FINDING
    branch: secrets
    owner: gate@example.invalid
    expires: "2099-01-01"
    reason: fixture — secrets is not an exceptable branch
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
      expect(result.stdout, contains('exceptions.invalid-branch'));
    });

    test('a dependencies-branch exception does not suppress a guards-branch '
        'finding of the same id', () {
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(id: 'CROSS-BRANCH-01', path: 'no/such/file.py'),
      );
      _write(fixtureRoot, 'requirements.txt', 'somepackage<2.0\n');
      _write(fixtureRoot, 'exceptions.yaml', '''
exceptions:
  - finding: CROSS-BRANCH-01
    branch: dependencies
    owner: gate@example.invalid
    expires: "2099-01-01"
    reason: fixture — a dependencies-scoped exception must not reach guards
''');

      final result = _run([
        '--root',
        fixtureRoot.path,
        '--threat-model',
        'threat-model.md',
        '--requirements',
        'requirements.txt',
        '--exceptions',
        'exceptions.yaml',
        '--secrets-cmd',
        'true',
      ]);

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('CROSS-BRANCH-01'));
    });

    test('a guards-branch exception with the matching branch still '
        'suppresses the matching guard finding (D4 stays usable)', () {
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(id: 'CROSS-BRANCH-02', path: 'no/such/file.py'),
      );
      _write(fixtureRoot, 'requirements.txt', 'somepackage<2.0\n');
      _write(fixtureRoot, 'exceptions.yaml', '''
exceptions:
  - finding: CROSS-BRANCH-02
    branch: guards
    owner: gate@example.invalid
    expires: "2099-01-01"
    reason: fixture — correctly-scoped exception must still suppress
''');

      final result = _run([
        '--root',
        fixtureRoot.path,
        '--threat-model',
        'threat-model.md',
        '--requirements',
        'requirements.txt',
        '--exceptions',
        'exceptions.yaml',
        '--secrets-cmd',
        'true',
      ]);

      expect(result.exitCode, 0, reason: result.stdout + result.stderr);
    });
  });

  group('MAJOR-2 — guard.test resolution rejects disabled or comment-only '
      'protections, not just missing ones', () {
    test('a guard.test that exists but is skip-marked is a critical '
        'finding, not a pass', () {
      _write(fixtureRoot, 'guarded.py', '''
@pytest.mark.skip(reason='flaky, TODO')
def test_the_real_thing():
    pass
''');
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-04',
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
      expect(result.stdout, contains('T-FIXTURE-04'));
    });

    test('a Dart guard.test whose test( call is commented out is a '
        'critical finding, not a pass', () {
      _write(fixtureRoot, 'guarded_test.dart', '''
void main() {
  // test('the real thing', () {
  //   expect(1, 1);
  // });
}
''');
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-05',
          path: 'guarded_test.dart',
          test: 'the real thing',
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
      expect(result.stdout, contains('T-FIXTURE-05'));
    });

    test('a python guard.test renamed with a suffix does not slip past an '
        'unclosed needle', () {
      _write(fixtureRoot, 'guarded.py', '''
def test_the_real_thing_v2():
    pass
''');
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-06',
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
      expect(result.stdout, contains('T-FIXTURE-06'));
    });

    test('a Dart guard.test with a skip: argument is a critical finding, '
        'not a pass', () {
      _write(fixtureRoot, 'guarded_test.dart', '''
void main() {
  test('the real thing', () {
    expect(1, 1);
  }, skip: true);
}
''');
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-07',
          path: 'guarded_test.dart',
          test: 'the real thing',
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
    });

    test(
      'a Dart guard.test name split across two adjacent string literals '
      '(the shipped consent guards\' own shape) still resolves when live',
      () {
        _write(fixtureRoot, 'guarded_test.dart', '''
void main() {
  test('first part of the name '
      'second part of the name', () {
    expect(1, 1);
  });
}
''');
        _write(
          fixtureRoot,
          'threat-model.md',
          _guardBlock(
            id: 'T-FIXTURE-08',
            path: 'guarded_test.dart',
            test: 'first part of the name second part of the name',
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
      },
    );
  });

  group(
    'MAJOR-2 cross-check — Dart guards resolve independently of the '
    'python scan (the --collect-only analog for Dart, A9\'s counterpart)',
    () {
      test(
        'every dart release_gate guard.test name is a live, unskipped '
        'test( call — measured directly in Dart, not via the python parser',
        () {
          final text = File('docs/security/threat-model.md').readAsStringSync();
          final blockPattern = RegExp(r'```yaml\n(.*?)\n```', dotAll: true);
          var dartGuardCount = 0;
          for (final block in blockPattern.allMatches(text)) {
            final body = block.group(1)!;
            if (!RegExp(
              r'^release_gate:\s*true$',
              multiLine: true,
            ).hasMatch(body)) {
              continue;
            }
            final pathMatch = RegExp(
              r'^\s*path:\s*(\S+)$',
              multiLine: true,
            ).firstMatch(body);
            final testMatch = RegExp(
              r'^\s*test:\s*(.+)$',
              multiLine: true,
            ).firstMatch(body);
            if (pathMatch == null || testMatch == null) continue;
            final path = pathMatch.group(1)!.trim();
            if (!path.endsWith('.dart')) continue;
            dartGuardCount++;
            final name = testMatch.group(1)!.trim();
            final stripped = _withoutDartComments(
              File(path).readAsStringSync(),
            );
            expect(
              _dartTestNames(stripped),
              contains(name),
              reason:
                  "$path has no live test('$name', ...) call (Dart "
                  'cross-check, independent of the python scan)',
            );
          }
          expect(dartGuardCount, greaterThanOrEqualTo(6));
        },
      );
    },
  );

  group('S8 — file/group-level elnémítás is a critical finding, not a pass '
      '(ADR 0481 D2, the docstring\'s "present, uncommented, not '
      'skip/xfail-marked" claim extended to file-wide silencers)', () {
    test('a module-level `pytestmark = pytest.mark.skip(...)` silences the '
        'whole python file even though the test itself carries no marker', () {
      _write(fixtureRoot, 'guarded.py', '''
pytestmark = pytest.mark.skip(reason='whole file disabled')


def test_the_real_thing():
    pass
''');
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-13',
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
      expect(result.stdout, contains('T-FIXTURE-13'));
    });

    test('a module-level `pytestmark = [pytest.mark.skip(...)]` list form '
        'silences the whole python file too', () {
      _write(fixtureRoot, 'guarded.py', '''
pytestmark = [
    pytest.mark.skip(reason='whole file disabled'),
]


def test_the_real_thing():
    pass
''');
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-14',
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
      expect(result.stdout, contains('T-FIXTURE-14'));
    });

    test('a Dart library-level `@Skip(...)` above `library;` silences the '
        'whole file even though the test itself carries no marker', () {
      _write(fixtureRoot, 'guarded_test.dart', '''
@Skip('whole file disabled')
library;

void main() {
  test('the real thing', () {
    expect(1, 1);
  });
}
''');
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-15',
          path: 'guarded_test.dart',
          test: 'the real thing',
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
      expect(result.stdout, contains('T-FIXTURE-15'));
    });

    test('a Dart `group(..., skip: true)` wrapping the guard.test silences it '
        'even though the test\'s own call carries no marker', () {
      _write(fixtureRoot, 'guarded_test.dart', '''
void main() {
  group('disabled', skip: true, () {
    test('the real thing', () {
      expect(1, 1);
    });
  });
}
''');
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(
          id: 'T-FIXTURE-16',
          path: 'guarded_test.dart',
          test: 'the real thing',
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
      expect(result.stdout, contains('T-FIXTURE-16'));
    });
  });

  group('MINOR-1 — guard.path cannot escape the repo root', () {
    test('an absolute guard.path is a critical finding, not a pass', () {
      _write(
        fixtureRoot,
        'threat-model.md',
        _guardBlock(id: 'T-ESCAPE-01', path: '/etc/hostname'),
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
      expect(result.stdout, contains('T-ESCAPE-01'));
    });

    test(
      'a `..`-relative guard.path escaping the root is a critical finding',
      () {
        _write(
          fixtureRoot,
          'threat-model.md',
          _guardBlock(id: 'T-ESCAPE-02', path: '../../../../etc/hosts'),
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
        expect(result.stdout, contains('T-ESCAPE-02'));
      },
    );
  });

  group('MINOR-2 — every known guard id in the shipped model has its OWN '
      'release_gate: true block, not just a component substring', () {
    const knownGuardIds = [
      'T-CLIENT-01',
      'T-API-01',
      'T-API-02',
      'T-DIAG-01',
      'T-DIAG-02',
      'T-DIAG-03',
      'T-MEDIA-01',
      'T-MEDIA-02',
      'T-MEDIA-03',
      'T-MODEL-01',
      'T-MODEL-02',
      'T-COMM-01',
      'T-COMM-02',
      'T-RELEASE-01',
      'T-RELEASE-02',
      'T-RELEASE-03',
      'T-EGRESS-01',
      'T-EGRESS-02',
    ];

    test('each known id resolves to id + release_gate: true, in order', () {
      final text = File('docs/security/threat-model.md').readAsStringSync();
      for (final id in knownGuardIds) {
        final pattern = RegExp(
          'id: ${RegExp.escape(id)}\\n'
          r'component: [^\n]+\n'
          r'threat: [^\n]+\n'
          r'release_gate: true\n',
        );
        expect(
          pattern.hasMatch(text),
          isTrue,
          reason:
              '$id is missing, or not release_gate: true, in the shipped '
              'threat model',
        );
      }
    });

    // S9 — pins the SHIPPED `guard.path`/`guard.test` pair too, not just
    // the id + release_gate: true. Retargeting a delivered guard back to a
    // weaker path/test (the review's measured T-CLIENT-01 regression: a
    // silent swap from `test/features/auth/token_store_test.dart` /
    // "round-trips a token under the documented secure key" back to the
    // pre-fix `test/core/storage/secure_store_test.dart` / "round-trips a
    // secret") left the old cell green — this cell catches it.
    const knownGuardTargets = {
      'T-CLIENT-01': (
        path: 'test/features/auth/token_store_test.dart',
        test: 'round-trips a token under the documented secure key',
      ),
      'T-API-01': (
        path: 'backend/tests/test_auth.py',
        test:
            'test_unknown_email_and_wrong_password_responses_are_byte_identical',
      ),
      'T-API-02': (
        path: 'backend/tests/test_hardening.py',
        test: 'test_login_brute_force_gets_429_with_retry_after',
      ),
      'T-DIAG-01': (
        path: 'backend/tests/test_diagnostics.py',
        test: 'test_diagnostics_session_id_cannot_escape_data_dir',
      ),
      'T-DIAG-02': (
        path: 'backend/tests/test_diagnostics.py',
        test: 'test_diagnostics_oversize_endpoint_returns_413',
      ),
      'T-DIAG-03': (
        path: 'backend/tests/test_diagnostics.py',
        test: 'test_diagnostics_rejects_bad_token',
      ),
      'T-MEDIA-01': (
        path: 'backend/tests/community/test_media_upload.py',
        test: 'test_a2_finalize_rejects_expired_signed_url',
      ),
      'T-MEDIA-02': (
        path: 'backend/tests/community/test_media_upload.py',
        test: 'test_a3_finalize_rejects_bucket_mime_mismatch',
      ),
      'T-MEDIA-03': (
        path: 'backend/tests/community/test_media_upload.py',
        test: 'test_a4_finalize_rejects_oversize_bucket_object',
      ),
      'T-MODEL-01': (
        path: 'test/tooling/vision_model_integrity_test.dart',
        test: 'bad checksum fails the integrity gate',
      ),
      'T-MODEL-02': (
        path: 'test/tooling/ml_asset_manifest_test.dart',
        test: 'shipping manifest covers four valid declared ML binaries',
      ),
      'T-COMM-01': (
        path: 'backend/tests/community/test_challenge_verification.py',
        test: 'test_a1_replay_same_source_event_id_lands_one_row',
      ),
      'T-COMM-02': (
        path: 'backend/tests/community/test_access_policy.py',
        test: 'test_a2_blocked_public_profile_returns_summary',
      ),
      'T-RELEASE-01': (
        path: 'test/tooling/signing_policy_test.dart',
        test: 'the real workflow passes with exit 0',
      ),
      'T-RELEASE-02': (
        path: 'test/tooling/check_secrets_test.dart',
        test: 'flags provider token literals by their own prefix',
      ),
      'T-RELEASE-03': (
        path: 'test/tooling/security_scan_test.dart',
        test: 'a dependency line without an upper bound is a critical finding',
      ),
      'T-EGRESS-01': (
        path: 'test/privacy/consent_enforcement_test.dart',
        test: 'upload() with consent false never touches the wire adapter',
      ),
      'T-EGRESS-02': (
        path: 'test/privacy/consent_enforcement_test.dart',
        test:
            'a profile update sent while signed in reaches the wire; the '
            'same call after logout does not — same container, no restart '
            '(A6)',
      ),
    };

    test('each known id resolves to its OWN shipped guard.path + guard.test — '
        'a silent retarget to a weaker guard is a critical finding, not a '
        'pass (S9)', () {
      final text = File('docs/security/threat-model.md').readAsStringSync();
      for (final id in knownGuardIds) {
        final target = knownGuardTargets[id]!;
        final pattern = RegExp(
          'id: ${RegExp.escape(id)}\\n'
          r'component: [^\n]+\n'
          r'threat: [^\n]+\n'
          r'release_gate: true\n'
          'guard:\\n'
          '  path: ${RegExp.escape(target.path)}\\n'
          '  test: ${RegExp.escape(target.test)}\\n',
        );
        expect(
          pattern.hasMatch(text),
          isTrue,
          reason:
              '$id no longer resolves to its shipped guard.path '
              '(${target.path}) + guard.test (${target.test}) in the '
              'threat model',
        );
      }
    });
  });

  group('MINOR-3 — a threat model with zero release_gate: true blocks is a '
      'critical finding, not a clean scan', () {
    test('all guard blocks demoted to a non-```yaml``` fence exits 1', () {
      _write(fixtureRoot, 'threat-model.md', '''
```text
id: T-FIXTURE-09
component: diagnostics-upload
threat: tampering
release_gate: true
guard:
  path: guarded.py
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

      expect(result.exitCode, 1, reason: result.stdout + result.stderr);
      expect(result.stdout, contains('no-release-gate-entries'));
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
          'client-egress',
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

// ---------------------------------------------------------------------------
// MAJOR-2 cross-check helpers — an INDEPENDENT (Dart, not python) re-parse of
// `test('<name>', ...)` calls, used only to verify the shipped Dart guards
// resolve, mirroring `test/core/architecture_dependency_test.dart:1227`
// `_withoutTrivia`'s comment-stripping convention without importing it (this
// file does not re-implement any PROTECTION — it re-checks the scan's OWN
// guard-resolution claim from a second angle, the same role
// `backend/tests/test_security_release.py`'s `--collect-only` plays for the
// backend guards).
// ---------------------------------------------------------------------------

String _withoutDartComments(String source) {
  final buffer = StringBuffer();
  var index = 0;
  while (index < source.length) {
    if (source.startsWith('//', index)) {
      final newline = source.indexOf('\n', index);
      index = newline == -1 ? source.length : newline;
      continue;
    }
    if (source.startsWith('/*', index)) {
      var depth = 1;
      index += 2;
      while (index < source.length && depth > 0) {
        if (source.startsWith('/*', index)) {
          depth++;
          index += 2;
        } else if (source.startsWith('*/', index)) {
          depth--;
          index += 2;
        } else {
          index++;
        }
      }
      continue;
    }
    final char = source[index];
    if (char == "'" || char == '"') {
      final start = index;
      final triple = source.startsWith('$char$char$char', index);
      final delimiter = triple ? '$char$char$char' : char;
      index += delimiter.length;
      while (index < source.length && !source.startsWith(delimiter, index)) {
        index += (source[index] == r'\' && index + 1 < source.length) ? 2 : 1;
      }
      index = (index + delimiter.length).clamp(0, source.length);
      buffer.write(source.substring(start, index));
      continue;
    }
    buffer.write(char);
    index++;
  }
  return buffer.toString();
}

Set<String> _dartTestNames(String strippedSource) {
  final names = <String>{};
  final callPattern = RegExp(r'\btest\(');
  for (final match in callPattern.allMatches(strippedSource)) {
    var index = match.end;
    while (index < strippedSource.length &&
        strippedSource[index].trim().isEmpty) {
      index++;
    }
    final parts = <String>[];
    while (index < strippedSource.length &&
        (strippedSource[index] == "'" || strippedSource[index] == '"')) {
      final quote = strippedSource[index];
      final triple = strippedSource.startsWith('$quote$quote$quote', index);
      final delimiter = triple ? '$quote$quote$quote' : quote;
      index += delimiter.length;
      final start = index;
      while (index < strippedSource.length &&
          !strippedSource.startsWith(delimiter, index)) {
        index +=
            (strippedSource[index] == r'\' && index + 1 < strippedSource.length)
            ? 2
            : 1;
      }
      parts.add(strippedSource.substring(start, index));
      index += delimiter.length;
      while (index < strippedSource.length &&
          strippedSource[index].trim().isEmpty) {
        index++;
      }
    }
    if (parts.isNotEmpty) names.add(parts.join());
  }
  return names;
}
