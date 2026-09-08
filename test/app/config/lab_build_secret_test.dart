import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';

// Audit H6 — `lab_build.json` shipped a LIVE diagnostics token. AGENTS.md §5
// forbids a secret in a commit, and a `--dart-define-from-file` bundle IS a
// commit. The token must come from the CI secret (or a local
// `--dart-define`), never from this tracked file, and an empty token must
// read as "diagnostics disabled" rather than an empty `X-Diag-Token` header.

Map<String, Object?> _labBuild() {
  final file = File('lab_build.json');
  expect(file.existsSync(), isTrue, reason: 'lab_build.json must exist');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

AppConfig _labConfig(String diagnosticsToken) => AppConfig.resolve(
  environment: AppEnvironment.lab,
  apiBaseUrl: 'https://lab.example.com',
  flags: FeatureFlags.forEnvironment(AppEnvironment.lab, accountEnabled: false),
  diagnosticsToken: diagnosticsToken,
  buildMode: 'release',
  appVersion: '1.0.0+1',
);

void main() {
  test('lab_build.json ships an EMPTY diagnostics token', () {
    final config = _labBuild();

    expect(config.containsKey(AppConfig.diagTokenDefine), isTrue);
    expect(config[AppConfig.diagTokenDefine], '');
  });

  test('lab_build.json carries no lab QC credential in any value', () {
    for (final entry in _labBuild().entries) {
      final value = entry.value;
      if (value is! String) continue;
      expect(
        value.startsWith('lab-qc-'),
        isFalse,
        reason: '${entry.key} still carries a committed credential',
      );
    }
  });

  test('an empty token means diagnostics are unusable, not open', () {
    final config = _labConfig('');

    // The Lab build still ENABLES diagnostics; without a token they simply
    // cannot be used — no request goes out with an empty header.
    expect(config.flags.diagnosticsEnabled, isTrue);
    expect(config.diagnosticsUsable, isFalse);
  });

  test('a blank-but-present token is treated as empty', () {
    expect(_labConfig('   ').diagnosticsUsable, isFalse);
  });

  test('an injected token makes diagnostics usable again', () {
    expect(_labConfig('from-ci-secret').diagnosticsUsable, isTrue);
  });
}
