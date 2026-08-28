// Production signing policy + secret hardening gate (E12-R07, ADR 0448).
//
// Follows the `test/tooling/release_manifest_test.dart` (ADR 0447) pattern:
// a single gate test file that shells out to `python3` on both the REAL
// tree and synthetic fixtures — the ONLY external binary this file is
// allowed to invoke (ADR 0448 D6, precedent ADR 0447 D5, L110) — plus a
// restricted-subset GitHub Actions YAML parser living directly in this file
// (group "A5"), the same choice that file documents for ADR 0444 D6: the
// round's allowed-files list does not grant a second Dart file for it.
//
// ADR 0448 D6 requires the audit to measure in BOTH directions: the real
// `android/app/build.gradle.kts` / `.github/workflows/release-apk.yml` must
// pass, AND a synthetic fixture missing the rejecting branch (or assigning
// the debug alias to the production branch) must fail with the violated
// rule's name — a cell that only ever checks the real file green would hide
// the absence of measurement (the `check_secrets_test.dart` L220 failure
// class).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _tool = 'tool/release/verify_signing_policy.py';
const _realGradle = 'android/app/build.gradle.kts';
const _realWorkflow = '.github/workflows/release-apk.yml';

class _AuditResult {
  _AuditResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

_AuditResult _runAudit({String? gradlePath, String? workflowPath}) {
  final result = Process.runSync('python3', [
    _tool,
    '--strict',
    '--gradle',
    gradlePath ?? _realGradle,
    '--workflow',
    workflowPath ?? _realWorkflow,
  ]);
  return _AuditResult(
    result.exitCode,
    result.stdout.toString(),
    result.stderr.toString(),
  );
}

void main() {
  late Directory fixtureRoot;

  setUp(() {
    fixtureRoot = Directory.systemTemp.createTempSync(
      'strumsight_signing_policy_',
    );
  });
  tearDown(() => fixtureRoot.deleteSync(recursive: true));

  String writeFixture(String name, String contents) {
    final file = File('${fixtureRoot.path}/$name');
    file.writeAsStringSync(contents);
    return file.path;
  }

  group('A1/A3 — Gradle debug-signing rejection audit (ADR 0448 D2/D3/D6)', () {
    test('the real android/app/build.gradle.kts + release-apk.yml pass with '
        'exit 0 — this is the FIRST required direction of the D6 dual-'
        'direction measurement', () {
      final result = _runAudit();
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, contains('all rules satisfied'));
    });

    test('a fixture missing the rejecting branch entirely fails with both '
        'debug-keystore-rejected and debug-alias-rejected — the SECOND '
        'required direction (matrix row: "figyelmeztetést ír, de nem dob" '
        'class, here entirely absent)', () {
      final fixture = writeFixture('missing_rejection.kts', '''
val releaseSigningRequired = true
val releaseSigningValues = mapOf(
    "storeFile" to "/tmp/keystore.jks",
    "keyAlias" to "release_key",
)
android {
    buildTypes {
        release {
            signingConfig = if (releaseSigningValues == null) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
        }
    }
}
''');
      final result = _runAudit(gradlePath: fixture);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('debug-keystore-rejected'));
      expect(result.stderr, contains('debug-alias-rejected'));
    });

    test('a fixture that assigns the debug key alias to the production '
        'signing branch (with no rejecting comparison at all) fails with '
        'debug-alias-rejected — R4/R5\'s second required fixture shape', () {
      final fixture = writeFixture('debug_alias_on_production.kts', '''
val releaseSigningRequired = true
val releaseSigningValues = mapOf(
    "storeFile" to "/tmp/keystore.jks",
    "keyAlias" to "androiddebugkey",
)
android {
    signingConfigs {
        create("release") {
            keyAlias = "androiddebugkey"
            storeFile = File("/tmp/keystore.jks")
        }
    }
    buildTypes {
        release {
            signingConfig = if (releaseSigningValues == null) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
        }
    }
}
''');
      final result = _runAudit(gradlePath: fixture);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('debug-alias-rejected'));
    });

    test('a fixture that only warns (println) instead of throwing fails '
        'with debug-keystore-rejected — matrix row: "figyelmeztetést ír, '
        'de nem dob"', () {
      final fixture = writeFixture('warn_only.kts', '''
val releaseSigningRequired = true
val releaseSigningValues = mapOf(
    "storeFile" to "/tmp/keystore.jks",
    "keyAlias" to "release_key",
)
val releaseStoreFile = File(releaseSigningValues.getValue("storeFile"))
if (releaseSigningRequired && releaseSigningValues != null) {
    val storeFileName = releaseStoreFile.name
    if (storeFileName.equals("debug.keystore", ignoreCase = true)) {
        println("WARNING: release signing looks like the debug keystore.")
    }
    val keyAlias = releaseSigningValues.getValue("keyAlias")
    if (keyAlias.equals("androiddebugkey", ignoreCase = true)) {
        println("WARNING: release signing looks like the debug key alias.")
    }
}
android {
    buildTypes {
        release {
            signingConfig = if (releaseSigningValues == null) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
        }
    }
}
''');
      final result = _runAudit(gradlePath: fixture);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('debug-keystore-rejected'));
      expect(result.stderr, contains('only warns'));
    });

    test('a minimal, hand-written COMPLIANT fixture (not the real file) '
        'also passes with exit 0 — proves the rule is not coincidentally '
        'matching only the real file\'s exact text', () {
      final fixture = writeFixture('compliant.kts', '''
val releaseSigningRequired = true
val defaultDebugKeystorePath = "/home/test/.android/debug.keystore"
val releaseSigningValues = mapOf(
    "storeFile" to "/tmp/keystore.jks",
    "keyAlias" to "release_key",
)
val releaseStoreFile = File(releaseSigningValues.getValue("storeFile"))
if (releaseSigningRequired && releaseSigningValues != null) {
    val storeFileName = releaseStoreFile.name
    val storeFileAbsolutePath = releaseStoreFile.absolutePath
    if (storeFileName.equals("debug.keystore", ignoreCase = true) ||
        storeFileAbsolutePath.equals(defaultDebugKeystorePath, ignoreCase = true)
    ) {
        throw GradleException(
            "Production release signing must not use the debug keystore: " +
                storeFileAbsolutePath,
        )
    }
    val keyAlias = releaseSigningValues.getValue("keyAlias")
    if (keyAlias.equals("androiddebugkey", ignoreCase = true)) {
        throw GradleException(
            "Production release signing must not use the debug key alias: " +
                keyAlias,
        )
    }
}
android {
    buildTypes {
        release {
            signingConfig = if (releaseSigningValues == null) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
        }
    }
}
''');
      final result = _runAudit(gradlePath: fixture);
      expect(result.exitCode, 0, reason: result.stderr);
    });

    test('a fixture that removes the Lab/dev debug fallback entirely fails '
        'with lab-fallback-preserved — matrix row: "a tiltás a buildType-'
        'tól függetlenül él → a Lab ág is elhasal" (A3)', () {
      final fixture = writeFixture('no_lab_fallback.kts', '''
val releaseSigningRequired = true
val defaultDebugKeystorePath = "/home/test/.android/debug.keystore"
val releaseSigningValues = mapOf(
    "storeFile" to "/tmp/keystore.jks",
    "keyAlias" to "release_key",
)
val releaseStoreFile = File(releaseSigningValues.getValue("storeFile"))
if (releaseSigningRequired && releaseSigningValues != null) {
    val storeFileName = releaseStoreFile.name
    val storeFileAbsolutePath = releaseStoreFile.absolutePath
    if (storeFileName.equals("debug.keystore", ignoreCase = true) ||
        storeFileAbsolutePath.equals(defaultDebugKeystorePath, ignoreCase = true)
    ) {
        throw GradleException("must not use the debug keystore")
    }
    val keyAlias = releaseSigningValues.getValue("keyAlias")
    if (keyAlias.equals("androiddebugkey", ignoreCase = true)) {
        throw GradleException("must not use the debug key alias")
    }
}
android {
    buildTypes {
        release {
            // BUG: the release buildType always resolves to the production
            // signing config, regardless of releaseSigningRequired — the
            // Lab/dev build (no signing env) would fail to build.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
''');
      final result = _runAudit(gradlePath: fixture);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('lab-fallback-preserved'));
    });
  });

  group('A4 — release-apk.yml regression guard (ADR 0448 D5, R3: already '
      'fail-closed — this is a regression guard, not new behaviour)', () {
    test('the real workflow passes with exit 0', () {
      final result = _runAudit();
      expect(result.exitCode, 0, reason: result.stderr);
    });

    test('a fixture workflow that echoes the store password fails with '
        'keystore-not-echoed', () {
      final fixture = writeFixture('echoing_workflow.yml', r'''
name: Production Android APK
jobs:
  release-apk:
    needs: signing-prerequisites
    steps:
      - name: Debug print password
        env:
          ANDROID_STORE_PASSWORD: some-value
        run: |
          echo "$ANDROID_STORE_PASSWORD"
      - name: Remove production keystore
        if: always()
        run: |
          rm -f -- "$KEYSTORE_PATH"
''');
      final result = _runAudit(workflowPath: fixture);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('keystore-not-echoed'));
    });

    test('a fixture workflow with "set -x" fails with keystore-not-echoed', () {
      final fixture = writeFixture('set_x_workflow.yml', r'''
name: Production Android APK
jobs:
  release-apk:
    needs: signing-prerequisites
    steps:
      - name: Build
        run: |
          set -x
          echo building
      - name: Remove production keystore
        if: always()
        run: |
          rm -f -- "$KEYSTORE_PATH"
''');
      final result = _runAudit(workflowPath: fixture);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('keystore-not-echoed'));
    });

    test('a fixture workflow missing the signing-prerequisites dependency '
        'fails with secrets-checked-before-build', () {
      final fixture = writeFixture('no_prereq_workflow.yml', r'''
name: Production Android APK
jobs:
  release-apk:
    steps:
      - name: Build
        run: echo building
      - name: Remove production keystore
        if: always()
        run: |
          rm -f -- "$KEYSTORE_PATH"
''');
      final result = _runAudit(workflowPath: fixture);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('secrets-checked-before-build'));
    });

    test('a fixture workflow missing the always()-gated cleanup step fails '
        'with keystore-cleanup-present', () {
      final fixture = writeFixture('no_cleanup_workflow.yml', '''
name: Production Android APK
jobs:
  release-apk:
    needs: signing-prerequisites
    steps:
      - name: Build
        run: echo building
''');
      final result = _runAudit(workflowPath: fixture);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('keystore-cleanup-present'));
    });

    test('F1 (review) — the fingerprint proposal fragment '
        '(docs/release/workflows/release-apk-fingerprint.proposal.md), '
        'spliced into an otherwise-compliant workflow, passes with exit 0 — '
        'the required "::add-mask::" idiom must not itself be flagged as a '
        'leak', () {
      final fixture = writeFixture('fingerprint_proposal_spliced.yml', r'''
name: Production Android APK
jobs:
  release-apk:
    needs: signing-prerequisites
    steps:
      - name: Capture production signing certificate fingerprint
        id: fingerprint
        shell: bash
        env:
          STRUMSIGHT_RELEASE_STORE_PASSWORD: ${{ secrets.ANDROID_STORE_PASSWORD }}
          STRUMSIGHT_RELEASE_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
          KEYSTORE_PATH: ${{ steps.keystore.outputs.path }}
        run: |
          set -euo pipefail
          echo "::add-mask::$STRUMSIGHT_RELEASE_STORE_PASSWORD"
          fingerprint_line="$(
            keytool -list -v \
              -keystore "$KEYSTORE_PATH" \
              -alias "$STRUMSIGHT_RELEASE_KEY_ALIAS" \
              -storepass:env STRUMSIGHT_RELEASE_STORE_PASSWORD |
              grep 'SHA256:'
          )"
          fingerprint="$(printf '%s' "$fingerprint_line" | sed -E 's/^.*SHA256: *//')"
      - name: Remove production keystore
        if: always()
        run: |
          rm -f -- "$KEYSTORE_PATH"
''');
      final result = _runAudit(workflowPath: fixture);
      expect(result.exitCode, 0, reason: result.stderr);
    });

    test('F1 (review) — the SAME fixture with the "::add-mask::" prefix '
        'stripped (a plain echo of the password) still fails with '
        'keystore-not-echoed — the exclusion is not wider than the exact '
        'masking idiom', () {
      final fixture = writeFixture('fingerprint_proposal_unmasked.yml', r'''
name: Production Android APK
jobs:
  release-apk:
    needs: signing-prerequisites
    steps:
      - name: Capture production signing certificate fingerprint
        id: fingerprint
        shell: bash
        env:
          STRUMSIGHT_RELEASE_STORE_PASSWORD: ${{ secrets.ANDROID_STORE_PASSWORD }}
          KEYSTORE_PATH: ${{ steps.keystore.outputs.path }}
        run: |
          set -euo pipefail
          echo "$STRUMSIGHT_RELEASE_STORE_PASSWORD"
      - name: Remove production keystore
        if: always()
        run: |
          rm -f -- "$KEYSTORE_PATH"
''');
      final result = _runAudit(workflowPath: fixture);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('keystore-not-echoed'));
    });

    test('F2 (review) — a fixture workflow that echoes the canonical GitHub '
        'Actions secrets-interpolation form (dollar-brace-brace secrets.NAME) '
        'fails with keystore-not-echoed', () {
      final fixture = writeFixture('leak_interpolation_workflow.yml', r'''
name: Production Android APK
jobs:
  release-apk:
    needs: signing-prerequisites
    steps:
      - name: Leak
        run: |
          echo "${{ secrets.ANDROID_STORE_PASSWORD }}"
      - name: Remove production keystore
        if: always()
        run: |
          rm -f -- "$KEYSTORE_PATH"
''');
      final result = _runAudit(workflowPath: fixture);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('keystore-not-echoed'));
    });

    test('F2 (review) — the real release-apk.yml stays exit 0: its legitimate '
        'secrets.ANDROID_KEYSTORE_BASE64 interpolation piped into '
        'base64 --decode is not a password name and must not be flagged', () {
      final result = _runAudit();
      expect(result.exitCode, 0, reason: result.stderr);
    });
  });

  group(
    'A5 — fingerprint proposal YAML validity + masking (ADR 0448 D4/D5)',
    () {
      const docPath =
          'docs/release/workflows/release-apk-fingerprint.proposal.md';

      test('the proposal YAML fragment parses under the restricted subset '
          'parser', () {
        final markdown = File(docPath).readAsStringSync();
        final fragment = extractYamlFence(markdown, sourceLabel: docPath);
        final steps = parseSteps(fragment, sourceLabel: docPath);
        expect(steps, hasLength(2));
        expect(
          steps[0].name,
          'Capture production signing certificate fingerprint',
        );
        expect(steps[1].name, 'Upload signing certificate');
      });

      test('the fingerprint step never passes the store password as a '
          'literal CLI argument — only -storepass:env', () {
        final markdown = File(docPath).readAsStringSync();
        final fragment = extractYamlFence(markdown, sourceLabel: docPath);
        final steps = parseSteps(fragment, sourceLabel: docPath);
        final run = steps[0].fields['run'] as String;
        expect(run, contains('-storepass:env'));
        expect(run, isNot(contains('-storepass "')));
        expect(run, isNot(contains("-storepass '")));
      });

      test('the fingerprint step masks the store password before using it '
          '(ADR 0448 D5)', () {
        final markdown = File(docPath).readAsStringSync();
        final fragment = extractYamlFence(markdown, sourceLabel: docPath);
        final steps = parseSteps(fragment, sourceLabel: docPath);
        final run = steps[0].fields['run'] as String;
        final maskIndex = run.indexOf('::add-mask::');
        final keytoolIndex = run.indexOf('keytool');
        expect(maskIndex, greaterThanOrEqualTo(0));
        expect(
          maskIndex,
          lessThan(keytoolIndex),
          reason: 'the mask must run BEFORE the password is used by keytool',
        );
      });

      test('the fingerprint step never echoes/cats the raw keytool output '
          'and never sets "set -x"', () {
        final markdown = File(docPath).readAsStringSync();
        final fragment = extractYamlFence(markdown, sourceLabel: docPath);
        final steps = parseSteps(fragment, sourceLabel: docPath);
        final run = steps[0].fields['run'] as String;
        expect(run, isNot(contains(r'echo "$fingerprint_line"')));
        expect(run, isNot(matches(RegExp(r'\bcat\b'))));
        expect(run, isNot(contains('set -x')));
      });

      test('the sidecar JSON the step writes carries only keyAlias and '
          'sha256Fingerprint — never a password- or key-shaped field name', () {
        final markdown = File(docPath).readAsStringSync();
        final fragment = extractYamlFence(markdown, sourceLabel: docPath);
        final steps = parseSteps(fragment, sourceLabel: docPath);
        final run = steps[0].fields['run'] as String;
        expect(run, contains('"keyAlias"'));
        expect(run, contains('"sha256Fingerprint"'));
        expect(run, isNot(contains('"password"')));
        expect(run, isNot(contains('"storePassword"')));
        expect(run, isNot(contains('"keyPassword"')));
        expect(run, isNot(contains('"privateKey"')));
      });

      test('the upload step targets the sidecar path, with '
          'if-no-files-found: error', () {
        final markdown = File(docPath).readAsStringSync();
        final fragment = extractYamlFence(markdown, sourceLabel: docPath);
        final steps = parseSteps(fragment, sourceLabel: docPath);
        final withArgs = steps[1].fields['with'] as Map<String, String>;
        expect(withArgs['path'], 'dist/signing-certificate.json');
        expect(withArgs['if-no-files-found'], 'error');
      });

      test('the doc documents the --artifact sidecar-binding mechanism '
          '(ADR 0448 D4 — no new release-manifest field)', () {
        final markdown = File(docPath).readAsStringSync();
        expect(markdown, contains('--artifact dist/signing-certificate.json'));
      });

      test('the insertion-point step names exist in the REAL '
          'release-apk.yml (regression anchor, precedent: '
          'release_manifest_test.dart)', () {
        final markdown = File(docPath).readAsStringSync();
        final realWorkflow = File(_realWorkflow).readAsStringSync();
        for (final stepName in [
          'Materialize production keystore',
          'Build production APK',
        ]) {
          expect(markdown, contains(stepName));
          expect(realWorkflow, contains('- name: $stepName'));
        }
      });
    },
  );

  group('A6 — signing-key runbook covers backup/rotation/access/loss with '
      'an owner (ADR 0448)', () {
    test('docs/security/signing-key-runbook.md exists and names all four '
        'required sections plus a responsible party', () {
      final text = File(
        'docs/security/signing-key-runbook.md',
      ).readAsStringSync();
      expect(text, contains('Backup'));
      expect(text, contains('Rotáció'));
      expect(text, contains('Hozzáférés'));
      expect(text, contains('elvesztés'));
      expect(text, contains('Felelős'));
    });
  });

  // No skip path anywhere in this file: if python3 is missing,
  // `Process.runSync` throws ProcessException the first time a test calls
  // it, which fails that test loudly — never a silent skip (ADR 0448 D6).
  group('A7 — this gate never relies on an unguaranteed binary (ADR 0448 '
      'D6, L110)', () {
    test('this file does not import the transitive-only YAML package', () {
      final source = File(
        'test/tooling/signing_policy_test.dart',
      ).readAsStringSync();
      expect(
        RegExp(r"^import\s+'package:yaml", multiLine: true).hasMatch(source),
        isFalse,
      );
    });

    test('every external process this file spawns targets python3 only — '
        'never rg/grep/jq/gh', () {
      final source = File(
        'test/tooling/signing_policy_test.dart',
      ).readAsStringSync();
      final executables = _processCallExecutable
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toSet();
      expect(executables, isNotEmpty, reason: 'this file must call python3');
      expect(executables, {'python3'});
    });

    test('self-check: python3 is on PATH in this environment — if it is '
        'not, the calls above throw ProcessException and this whole file '
        'turns red, never a silent skip', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });
  });
}

// Built via adjacent string-literal concatenation so this constant's own
// definition text never spells out the executable-call pattern it searches
// for as one contiguous run of characters (same self-matching trap
// `release_manifest_test.dart`'s A7 group avoids).
final _processCallExecutable = RegExp(
  'Process'
  r'''\.(?:run|runSync|start)\(\s*['"]([^'"\n]+)['"]''',
);

// ---------------------------------------------------------------------------
// Restricted GitHub Actions "steps:" YAML subset (ADR 0448 D6, precedent
// ADR 0447 D5 / ADR 0444 D3: `package:yaml` is only a transitive dependency
// on this tree, importing it here would turn `flutter analyze` red via the
// `depend_on_referenced_packages` lint).
//
// A superset of `release_manifest_test.dart`'s parser: this proposal's
// fragment also uses `id:`, `shell:` and `env:` (a flat 6-space-indented
// map, same shape as `with:`), so this parser treats every 4-space-indented
// step key generically rather than whitelisting run/uses/with specifically.
// A container key (`steps:`, or a step field with a block-map/list value
// written inline) fails with a `FormatException` naming the exact line —
// not silently misread.
// ---------------------------------------------------------------------------

final class WorkflowStep {
  const WorkflowStep({required this.name, required this.fields});

  final String name;

  /// Each value is either a `String` (a scalar or a `run: |` block) or a
  /// `Map<String, String>` (a flat map, e.g. `with:`/`env:`).
  final Map<String, Object?> fields;
}

bool _isBlankOrComment(String line) {
  final trimmed = line.trim();
  return trimmed.isEmpty || trimmed.startsWith('#');
}

String _unquote(String raw) {
  final trimmed = raw.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

final _topLevelKeyLine = RegExp(r'^([a-zA-Z_]+):(.*)$');
final _stepHeader = RegExp(r'^ {2}- name: (.*)$');
final _fourSpaceKeyLine = RegExp(r'^ {4}([a-zA-Z_-]+):(.*)$');
final _sixSpaceKeyLine = RegExp(r'^ {6}([a-zA-Z_-]+):(.*)$');

/// Parses the deliberately RESTRICTED GitHub Actions "steps:" YAML subset
/// this round's fingerprint proposal uses. See the file-level doc comment
/// above for the exact supported shape.
List<WorkflowStep> parseSteps(String contents, {required String sourceLabel}) {
  final lines = contents.split('\n');
  var i = 0;
  while (i < lines.length && _isBlankOrComment(lines[i])) {
    i++;
  }
  if (i >= lines.length) {
    throw FormatException(
      '$sourceLabel: empty document, expected a top-level "steps:" key',
    );
  }
  final topMatch = _topLevelKeyLine.firstMatch(lines[i]);
  if (topMatch == null || topMatch.group(1) != 'steps') {
    throw FormatException(
      '$sourceLabel:${i + 1}: expected a top-level "steps:" key, got: '
      '"${lines[i]}"',
    );
  }
  if (topMatch.group(2)!.trim().isNotEmpty) {
    throw FormatException(
      '$sourceLabel:${i + 1}: "steps:" must start a block list, not an '
      'inline value',
    );
  }
  i++;

  final steps = <WorkflowStep>[];
  while (i < lines.length) {
    if (_isBlankOrComment(lines[i])) {
      i++;
      continue;
    }
    final header = _stepHeader.firstMatch(lines[i]);
    if (header == null) {
      throw FormatException(
        '$sourceLabel:${i + 1}: expected a step "  - name: <value>", got: '
        '"${lines[i]}"',
      );
    }
    final name = _unquote(header.group(1)!);
    i++;

    final fields = <String, Object?>{};
    while (i < lines.length && _fourSpaceKeyLine.hasMatch(lines[i])) {
      final match = _fourSpaceKeyLine.firstMatch(lines[i])!;
      final key = match.group(1)!;
      final rest = match.group(2)!.trim();
      final lineNumber = i + 1;
      i++;
      if (rest == '|') {
        final blockLines = <String>[];
        while (i < lines.length &&
            (lines[i].startsWith('      ') || lines[i].trim().isEmpty)) {
          blockLines.add(lines[i].isEmpty ? '' : lines[i].substring(6));
          i++;
        }
        fields[key] = blockLines.join('\n');
      } else if (rest.isEmpty) {
        final map = <String, String>{};
        while (i < lines.length && _sixSpaceKeyLine.hasMatch(lines[i])) {
          final mapMatch = _sixSpaceKeyLine.firstMatch(lines[i])!;
          map[mapMatch.group(1)!] = _unquote(mapMatch.group(2)!);
          i++;
        }
        if (map.isEmpty) {
          throw FormatException(
            '$sourceLabel:$lineNumber: "$key:" started a block mapping but '
            'no 6-space-indented "key: value" line followed',
          );
        }
        fields[key] = map;
      } else {
        fields[key] = _unquote(rest);
      }
    }

    steps.add(WorkflowStep(name: name, fields: fields));
  }
  return steps;
}

/// Extracts the contents of the first ` ```yaml ` fenced code block in
/// [markdown]. Plain string search — not YAML parsing.
String extractYamlFence(String markdown, {required String sourceLabel}) {
  final match = RegExp(r'```yaml\n([\s\S]*?)\n```').firstMatch(markdown);
  if (match == null) {
    throw FormatException('$sourceLabel: no ```yaml fenced block found');
  }
  return match.group(1)!;
}
