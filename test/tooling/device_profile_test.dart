// E16-R04 (ADR 0503 D5, R6) — the device-profile secret boundary is GÉPI,
// not a documented promise. `test/tooling/check_secrets_test.dart` builds
// temp repos to prove the SCANNER works; it never touches the live tree
// (its own comment says so, 181-190. sor). This file is the guard that
// actually reads `device_build.example.json` and
// `docs/operations/device-backend-runbook.md` from the REAL repository
// (`Directory.current`, matching `test/tooling/data_inventory_test.dart` /
// `deprecation_audit_test.dart`'s pattern), reusing the SAME secret rules
// `tool/ci/check_secrets.dart` ships (not a re-implementation) so a real
// finding in the example profile fails this cell exactly the way it would
// fail the `secrets` gate step.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/check_secrets.dart';

const String _exampleProfilePath = 'device_build.example.json';
const String _runbookPath = 'docs/operations/device-backend-runbook.md';

const List<String> _existingRunbookHeadings = <String>[
  '## 1. Start the backend, bound to the LAN, not just localhost',
  "## 2. Find the laptop's LAN IP",
  '## 3. Make sure the phone can actually reach it',
  "## 4. Point the Flutter build at it via `STRUMSIGHT_API_URL`",
  '## 5. Verify end-to-end',
  '## 6. What must be enabled to see the full Community surface',
  '## 7. Known, pre-existing client↔server gaps (measured, not fixed by '
      'this round)',
];

void main() {
  final Directory repository = Directory.current;

  Map<String, dynamic> readExampleProfile() {
    final file = File('${repository.path}/$_exampleProfilePath');
    expect(
      file.existsSync(),
      isTrue,
      reason: '$_exampleProfilePath must exist at the repository root',
    );
    final decoded = jsonDecode(file.readAsStringSync());
    expect(decoded, isA<Map<String, dynamic>>());
    return decoded as Map<String, dynamic>;
  }

  String readRunbook() {
    final file = File('${repository.path}/$_runbookPath');
    expect(file.existsSync(), isTrue, reason: '$_runbookPath must exist');
    return file.readAsStringSync();
  }

  group('A3 — device_build.example.json is schema-valid and secret-free', () {
    test('is valid JSON with every value a plain dart-define string', () {
      final profile = readExampleProfile();
      expect(profile, isNotEmpty);
      for (final entry in profile.entries) {
        expect(
          entry.value,
          isA<String>(),
          reason:
              '${entry.key}: --dart-define-from-file values must be strings',
        );
      }
    });

    test('declares the required build-target keys with plausible shapes', () {
      final profile = readExampleProfile();

      expect(profile, contains('STRUMSIGHT_ENV'));
      expect(
        profile['STRUMSIGHT_ENV'],
        anyOf('development', 'lab', 'production'),
        reason:
            'must be one of AppEnvironment.values.name (app_environment.dart)',
      );

      expect(profile, contains('STRUMSIGHT_API_URL'));
      final apiUrl = Uri.tryParse(profile['STRUMSIGHT_API_URL'] as String);
      expect(
        apiUrl,
        isNotNull,
        reason: 'STRUMSIGHT_API_URL must be a valid URI',
      );
      expect(apiUrl!.hasScheme, isTrue);
      expect(apiUrl.scheme, anyOf('http', 'https'));
      expect(apiUrl.host, isNotEmpty);

      expect(profile, contains('STRUMSIGHT_ACCOUNT'));
      expect(profile['STRUMSIGHT_ACCOUNT'], anyOf('true', 'false'));

      for (final communityFlag in profile.keys.where(
        (key) => key.startsWith('STRUMSIGHT_COMMUNITY'),
      )) {
        expect(
          profile[communityFlag],
          anyOf('true', 'false'),
          reason: '$communityFlag must be a boolean-shaped dart-define value',
        );
      }
    });

    test('the live tree has no committed secret in the example profile '
        '(reuses tool/ci/check_secrets.dart against Directory.current)', () {
      // Not a temp repo (that is check_secrets_test.dart's job, R6) — this
      // scans the ACTUAL working tree the round committed to. checkSecrets
      // only looks at `git ls-files` output, so the round must `git add`
      // the profile before this cell can prove anything about it.
      final report = checkSecrets(projectRoot: repository);
      final profileIssues = report.issues.where(
        (issue) => issue.path == _exampleProfilePath,
      );
      expect(
        profileIssues,
        isEmpty,
        reason:
            '$_exampleProfilePath must contain only placeholder values:\n'
            '${report.format()}',
      );
    });

    test('the .gitignore rule actually excludes a real device_build.json '
        '(measured via `git check-ignore`, not text-matching the rule)', () {
      final realProfile = Process.runSync('git', const [
        'check-ignore',
        '-q',
        'device_build.json',
      ], workingDirectory: repository.path);
      expect(
        realProfile.exitCode,
        0,
        reason: 'device_build.json must be gitignored (ADR 0503 D5)',
      );

      final variantProfile = Process.runSync('git', const [
        'check-ignore',
        '-q',
        'device_build.local.json',
      ], workingDirectory: repository.path);
      expect(
        variantProfile.exitCode,
        0,
        reason: 'device_build.*.json must be gitignored too',
      );
    });
  });

  group(
    'A4 — the runbook keeps §1-§7 and documents the profile/smoke step',
    () {
      test('every existing §1-§7 heading is still present verbatim', () {
        final runbook = readRunbook();
        for (final heading in _existingRunbookHeadings) {
          expect(
            runbook,
            contains(heading),
            reason:
                'existing runbook heading must not be deleted or reworded: '
                '$heading',
          );
        }
      });

      test(
        'documents building device_build.json from the example template',
        () {
          final runbook = readRunbook();
          expect(runbook, contains('device_build.example.json'));
          expect(runbook, contains('device_build.json'));
          expect(runbook, contains('--dart-define-from-file'));
        },
      );

      test(
        'documents running the live bring-up smoke with a verify command',
        () {
          final runbook = readRunbook();
          expect(runbook, contains('tool/release/live_backend_smoke.py'));
          expect(runbook, contains('--base-url'));
        },
      );
    },
  );
}
