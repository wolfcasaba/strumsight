// Production/internal-cohort readiness gate (E12-R31, round brief §0.0.1
// P1-P6). Follows the `test/tooling/beta_profile_test.dart` /
// `rc_assembly_test.dart` pattern: a Dart gate test that shells out to
// `python3 tool/release/production_smoke.py` against real and synthetic
// fixtures (temp dirs, never committed), plus direct cells on
// `lib/app/config/app_config.dart` (A3) and the two new release documents
// (A5/A6) — the same "the cell measures the document, not the other way
// round" split `beta_profile_test.dart`'s A5/A6 groups use.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';

const _tool = 'tool/release/production_smoke.py';
const _checklistDoc = 'docs/release/internal-production-checklist.md';
const _rolloutTemplate = 'docs/release/rollout-packet-template.md';

// A port on loopback that refuses connections immediately — fast, offline,
// deterministic "the server is unreachable" outcome for the checks that
// don't matter to a given sub-test (fingerprint/model-manifest cells only
// care about their own `[PASS]`/`[FAIL]` line, not the others).
const _unreachableBaseUrl = 'http://127.0.0.1:1';

ProcessResult _run(
  List<String> args, {
  Map<String, String>? environment,
  bool includeParentEnvironment = true,
}) => Process.runSync(
  'python3',
  [_tool, ...args],
  environment: environment,
  includeParentEnvironment: includeParentEnvironment,
);

/// A local stub backend (round brief MAJOR-2 fix) that answers `POST
/// /auth/login` with 200 + `bearerToken`, so `production_smoke.py`'s
/// success branch — `check_auth`'s `login_result`/token assignment, the
/// ONLY place a password or bearer token could ever reach a print
/// statement — actually executes. The unreachable-port cells elsewhere in
/// this file (`_unreachableBaseUrl`) never reach that branch at all, so
/// they cannot prove a leak there is caught; this stub is what makes the
/// sentinel-absence assertion below meaningful (measured mutation-kill: see
/// the round brief §10 transcript).
///
/// MEASURED environment constraint: a socket bound directly in *this* Dart
/// test process (`HttpServer.bind`) is unreachable from the `python3`
/// subprocess `_run` launches on this box (probed directly — a `curl`/
/// `python3` child of a `dart run` process times out against a socket the
/// parent Dart process itself bound, even with the tool sandbox disabled).
/// A `python3` SUBPROCESS-to-`python3`-SUBPROCESS loopback connection (two
/// siblings, both spawned via `dart:io Process`, same as `_run` spawns the
/// smoke tool) works fine — so the stub itself is a spawned `python3`
/// process too, not a Dart-bound `HttpServer`.
class _StubServer {
  _StubServer(this._process, this.port);
  final Process _process;
  final int port;

  void stop() => _process.kill();
}

Future<_StubServer> _startStubServer({required String bearerToken}) async {
  final script =
      '''
import http.server
import json

BEARER_TOKEN = ${jsonEncode(bearerToken)}


class Handler(http.server.BaseHTTPRequestHandler):
    def _reply(self, status, body):
        payload = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/health/ready":
            self._reply(200, {"status": "ready"})
        elif self.path == "/auth/me":
            self._reply(200, {"email": "smoke@strumsight.app"})
        elif self.path == "/settings":
            self._reply(200, {})
        else:
            self._reply(404, {"detail": "Not Found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        self.rfile.read(length)
        if self.path == "/auth/login":
            self._reply(200, {"access_token": BEARER_TOKEN, "token_type": "bearer"})
        else:
            self._reply(404, {"detail": "Not Found"})

    def log_message(self, *args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
print("PORT", server.server_port, flush=True)
server.serve_forever()
''';

  final process = await Process.start('python3', ['-c', script]);
  final portLine = await process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .firstWhere((line) => line.startsWith('PORT '));
  final port = int.parse(portLine.substring('PORT '.length).trim());
  return _StubServer(process, port);
}

void main() {
  group('self-check — python3 is on PATH', () {
    test('a missing python3 would turn every cell below red, not skip it', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });
  });

  group('A1 — the smoke package never takes a credential as a CLI argument, '
      'and never prints one', () {
    test('the source defines --password-env, never a --password flag', () {
      final text = File(_tool).readAsStringSync();
      expect(text, contains('--password-env'));
      expect(RegExp('[\'"]--password[\'"]').hasMatch(text), isFalse);
    });

    test('a missing/empty password env var exits non-zero without a network '
        'attempt', () {
      final result = _run(
        [
          '--base-url',
          _unreachableBaseUrl,
          '--email',
          'smoke@strumsight.app',
          '--password-env',
          'STRUMSIGHT_SMOKE_TEST_UNSET_VAR',
          '--signing-certificate',
          'does/not/matter.json',
          '--expected-fingerprint',
          'AA:BB',
        ],
        includeParentEnvironment: false,
        environment: {'PATH': Platform.environment['PATH'] ?? ''},
      );
      expect(result.exitCode, isNot(0));
      expect(
        result.stderr.toString(),
        contains('STRUMSIGHT_SMOKE_TEST_UNSET_VAR'),
      );
    });

    test('a distinctive password value never appears in stdout or stderr '
        'when the target is unreachable — this is an offline sanity check '
        '(the tool never even gets to attempt a login), NOT proof that a '
        'successful login cannot leak the password/token; that proof is the '
        "MAJOR-2 stub-server probe below", () {
      const sentinel = 'sentinel-password-must-never-leak-9f3c';
      final result = _run(
        [
          '--base-url',
          _unreachableBaseUrl,
          '--allow-insecure-http',
          '--email',
          'smoke@strumsight.app',
          '--password-env',
          'STRUMSIGHT_SMOKE_TEST_PW',
          '--signing-certificate',
          'does/not/matter.json',
          '--expected-fingerprint',
          'AA:BB',
        ],
        environment: {'STRUMSIGHT_SMOKE_TEST_PW': sentinel},
      );

      expect(result.exitCode, isNot(0)); // unreachable base-url
      expect(result.stdout.toString(), isNot(contains(sentinel)));
      expect(result.stderr.toString(), isNot(contains(sentinel)));
    });
  });

  group('A3 — the client production profile still fails closed on the dev '
      'sentinel values (besides test/app/app_config_test.dart)', () {
    test('production + the default dev host + the default dev token throws '
        'for BOTH reasons at once', () {
      List<String> problems = const [];
      try {
        AppConfig.resolve(
          environment: AppEnvironment.production,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: const FeatureFlags(
            accountEnabled: true,
            diagnosticsEnabled: true,
            labModeAvailable: false,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'release',
          appVersion: '1.0.0+1',
        );
        fail('expected ConfigurationException');
      } on ConfigurationException catch (e) {
        problems = e.problems;
      }
      expect(
        problems.any((p) => p.contains('development host')),
        isTrue,
        reason: 'the dev host sentinel must still be rejected: $problems',
      );
      expect(
        problems.any((p) => p.contains('development token')),
        isTrue,
        reason: 'the dev token sentinel must still be rejected: $problems',
      );
    });
  });

  group('A4 — the fingerprint check compares the sidecar to '
      '--expected-fingerprint and fails closed (§0.0.1 P2)', () {
    const fingerprint =
        'AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:'
        '00:11:22:33:44:55:66:77:88';

    late Directory tempDir;
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync(
        'strumsight_production_smoke_fingerprint_',
      );
    });
    tearDown(() => tempDir.deleteSync(recursive: true));

    String fingerprintLine(ProcessResult result) {
      final line = result.stdout
          .toString()
          .split('\n')
          .firstWhere((l) => l.contains('] fingerprint:'), orElse: () => '');
      expect(line, isNotEmpty, reason: 'no fingerprint line in stdout');
      return line;
    }

    ProcessResult runWithCert(String certJson) {
      final cert = File('${tempDir.path}/signing-certificate.json');
      cert.writeAsStringSync(certJson);
      return _run(
        [
          '--base-url',
          _unreachableBaseUrl,
          '--allow-insecure-http',
          '--email',
          'smoke@strumsight.app',
          '--password-env',
          'STRUMSIGHT_SMOKE_TEST_PW',
          '--signing-certificate',
          cert.path,
          '--expected-fingerprint',
          fingerprint,
        ],
        environment: {'STRUMSIGHT_SMOKE_TEST_PW': 'irrelevant-for-this-cell'},
      );
    }

    test('a matching sidecar PASSes', () {
      final result = runWithCert(
        '{"keyAlias": "release", "sha256Fingerprint": "$fingerprint"}',
      );
      expect(fingerprintLine(result), startsWith('[PASS]'));
    });

    test('a mismatched sidecar FAILs with "mismatch" in the detail', () {
      final result = runWithCert(
        '{"keyAlias": "release", "sha256Fingerprint": "00:11:22:33"}',
      );
      final line = fingerprintLine(result);
      expect(line, startsWith('[FAIL]'));
      expect(line, contains('mismatch'));
      expect(result.exitCode, isNot(0));
    });

    test('a sidecar with no "sha256Fingerprint" key FAILs — fail-CLOSED, '
        'never a 0-exit pass (round brief §6.1)', () {
      final result = runWithCert('{"keyAlias": "release"}');
      final line = fingerprintLine(result);
      expect(line, startsWith('[FAIL]'));
      expect(line, contains('sha256Fingerprint'));
      expect(
        result.exitCode,
        isNot(0),
        reason:
            'a missing key must be a non-zero exit — a fail-OPEN '
            'implementation that exits 0 here is a BUKOTT implementation',
      );
    });

    test('an unparsable sidecar FAILs', () {
      final result = runWithCert('{not json');
      final line = fingerprintLine(result);
      expect(line, startsWith('[FAIL]'));
      expect(result.exitCode, isNot(0));
    });
  });

  group('A5 — every checklist item carries a GÉPI or EMBERI label', () {
    final tagPattern = RegExp(
      r'^- \[ \] \*\*\[(GÉPI|EMBERI)\]\*\*',
      multiLine: true,
    );
    final bulletPattern = RegExp(r'^- \[ \] ', multiLine: true);

    test('the real checklist has no unlabeled bullet', () {
      final text = File(_checklistDoc).readAsStringSync();
      final bulletCount = bulletPattern.allMatches(text).length;
      final taggedCount = tagPattern.allMatches(text).length;
      expect(
        taggedCount,
        bulletCount,
        reason:
            '$bulletCount checklist bullet(s) but only $taggedCount carry a '
            'GÉPI/EMBERI label',
      );
    });

    test('sanity: the checklist has non-trivial coverage (>= 10 items) and '
        'BOTH labels are used at least once', () {
      final text = File(_checklistDoc).readAsStringSync();
      expect(bulletPattern.allMatches(text).length, greaterThanOrEqualTo(10));
      expect(text, contains('**[GÉPI]**'));
      expect(text, contains('**[EMBERI]**'));
    });

    test('mutation probe: an unlabeled bullet is flagged', () {
      const fixture = '''
## Checklist

- [ ] This line has no GÉPI/EMBERI label.
''';
      final bulletCount = bulletPattern.allMatches(fixture).length;
      final taggedCount = tagPattern.allMatches(fixture).length;
      expect(taggedCount, isNot(bulletCount));
    });

    test('mutation probe: a labeled bullet is NOT flagged', () {
      const fixture = '''
## Checklist

- [ ] **[GÉPI]** This line has a label.
- [ ] **[EMBERI]** So does this one.
''';
      final bulletCount = bulletPattern.allMatches(fixture).length;
      final taggedCount = tagPattern.allMatches(fixture).length;
      expect(taggedCount, bulletCount);
    });
  });

  group(
    'A6 — the rollout packet template carries all nine SDD §26.1 elements',
    () {
      // Exact order from docs/sdd/12-release-roadmap-final-integration.md
      // §26.1.
      const requiredSections = [
        'Build és commit',
        'Active flags',
        'Migration version',
        'Model version',
        'Known issues',
        'Dashboard snapshot',
        'Support readiness',
        'Rollback target',
        'Döntéshozó',
      ];

      test('the real template has all nine section headers, in order', () {
        final text = File(_rolloutTemplate).readAsStringSync();
        final headers = RegExp(
          r'^## \d+\. (.+)$',
          multiLine: true,
        ).allMatches(text).map((m) => m.group(1)!.trim()).toList();
        expect(headers, requiredSections);
      });

      test('the rollback target and decision-maker sections are non-empty '
          'placeholders, not silently dropped', () {
        final text = File(_rolloutTemplate).readAsStringSync();
        final rollbackIndex = text.indexOf('## 8. Rollback target');
        final decisionIndex = text.indexOf('## 9. Döntéshozó');
        expect(rollbackIndex, isNot(-1));
        expect(decisionIndex, isNot(-1));
        final rollbackBody = text.substring(rollbackIndex, decisionIndex);
        expect(rollbackBody.toLowerCase(), contains('rollback'));
        final decisionBody = text.substring(decisionIndex);
        expect(decisionBody.trim(), isNotEmpty);
      });

      test('mutation probe: a template missing one section is flagged', () {
        const fixture = '''
## 1. Build és commit
## 2. Active flags
## 3. Migration version
## 4. Model version
## 5. Known issues
## 6. Dashboard snapshot
## 7. Support readiness
## 9. Döntéshozó
''';
        final headers = RegExp(
          r'^## \d+\. (.+)$',
          multiLine: true,
        ).allMatches(fixture).map((m) => m.group(1)!.trim()).toList();
        expect(headers, isNot(requiredSections));
      });
    },
  );

  group('MAJOR-2 (review E12-R31) — the password/token sentinel probe must '
      'actually reach the login success branch', () {
    test('a distinctive password AND a distinctive bearer token never '
        'appear in stdout or stderr of a run that ACTUALLY logs in '
        'against a local stub server', () async {
      const passwordSentinel = 'sentinel-password-must-never-leak-9f3c';
      const tokenSentinel = 'sentinel-bearer-token-must-never-leak-7a1d';

      final server = await _startStubServer(bearerToken: tokenSentinel);
      addTearDown(server.stop);

      final tempDir = Directory.systemTemp.createTempSync(
        'strumsight_production_smoke_breach_probe_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));
      Directory('${tempDir.path}/assets/ml').createSync(recursive: true);
      File(
        '${tempDir.path}/assets/ml/model_manifest.json',
      ).writeAsStringSync('{"models": []}');
      final cert = File('${tempDir.path}/signing-certificate.json');
      cert.writeAsStringSync(
        '{"keyAlias": "release", "sha256Fingerprint": "AA:BB"}',
      );

      final result = _run(
        [
          '--base-url',
          'http://127.0.0.1:${server.port}',
          '--allow-insecure-http',
          '--email',
          'smoke@strumsight.app',
          '--password-env',
          'STRUMSIGHT_SMOKE_TEST_PW',
          '--signing-certificate',
          cert.path,
          '--expected-fingerprint',
          'AA:BB',
          '--asset-root',
          tempDir.path,
        ],
        environment: {'STRUMSIGHT_SMOKE_TEST_PW': passwordSentinel},
      );

      // Sanity: the success branch this probe targets actually ran — this
      // is what makes the sentinel-absence assertions below a meaningful
      // measurement rather than a vacuous one (unlike the unreachable-URL
      // cells above, which never reach this branch at all).
      expect(result.stdout.toString(), contains('[PASS] auth_login:'));
      expect(result.stdout.toString(), contains('[PASS] auth_me:'));

      expect(result.stdout.toString(), isNot(contains(passwordSentinel)));
      expect(result.stderr.toString(), isNot(contains(passwordSentinel)));
      expect(result.stdout.toString(), isNot(contains(tokenSentinel)));
      expect(result.stderr.toString(), isNot(contains(tokenSentinel)));
    });
  });

  group('MAJOR-3 (review E12-R31) — the CLI refuses a non-https --base-url '
      'without an explicit opt-out', () {
    test('a plain http:// --base-url exits 2 with a structured message and '
        'never attempts a network call', () {
      const sentinel = 'sentinel-password-must-never-leak-9f3c';
      final result = _run(
        [
          '--base-url',
          _unreachableBaseUrl,
          '--email',
          'smoke@strumsight.app',
          '--password-env',
          'STRUMSIGHT_SMOKE_TEST_PW',
          '--signing-certificate',
          'does/not/matter.json',
          '--expected-fingerprint',
          'AA:BB',
        ],
        environment: {'STRUMSIGHT_SMOKE_TEST_PW': sentinel},
      );

      expect(result.exitCode, 2);
      expect(result.stderr.toString(), contains('https'));
      // No check line printed — the scheme is rejected before run_checks().
      expect(result.stdout.toString(), isEmpty);
    });

    test('--allow-insecure-http lets a plain http:// target proceed past '
        'the usage-error stage (network failure now, exit 1, not exit 2)', () {
      final result = _run(
        [
          '--base-url',
          _unreachableBaseUrl,
          '--allow-insecure-http',
          '--email',
          'smoke@strumsight.app',
          '--password-env',
          'STRUMSIGHT_SMOKE_TEST_PW',
          '--signing-certificate',
          'does/not/matter.json',
          '--expected-fingerprint',
          'AA:BB',
        ],
        environment: {'STRUMSIGHT_SMOKE_TEST_PW': 'irrelevant-for-this-cell'},
      );

      expect(result.exitCode, isNot(2));
    });

    test('an https:// --base-url needs no opt-out flag', () {
      final result = _run(
        [
          '--base-url',
          'https://127.0.0.1:1',
          '--email',
          'smoke@strumsight.app',
          '--password-env',
          'STRUMSIGHT_SMOKE_TEST_PW',
          '--signing-certificate',
          'does/not/matter.json',
          '--expected-fingerprint',
          'AA:BB',
        ],
        environment: {'STRUMSIGHT_SMOKE_TEST_PW': 'irrelevant-for-this-cell'},
      );

      expect(result.exitCode, isNot(2));
    });
  });
}
