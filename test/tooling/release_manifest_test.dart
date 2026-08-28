// Release manifest / SBOM / provenance gate (E12-R06, ADR 0447).
//
// Follows the `test/tooling/ml_asset_manifest_test.dart` (ADR 0063) and
// `test/tooling/repository_policy_test.dart` (ADR 0444) pattern: a single
// gate test file that both imports the Dart generator as a plain library
// (no `flutter test` process-spawn needed for the pure parts) and, for the
// two Python tools, shells out to `python3` on fixture input — the ONLY
// external binary this file is allowed to invoke (ADR 0447 D5, L110). The
// restricted-subset GitHub Actions YAML parser (group "A5") lives directly
// in this file rather than a separate `tool/*.dart` library, the same
// choice `repository_policy_test.dart` documents for ADR 0444 D6: the
// round's allowed-files list does not grant a second Dart file for it.
//
// Fixtures for A2/A3 are written to `Directory.systemTemp` at test run time
// and torn down in `addTearDown` (E12-R06 brief §0.0.A R5) — the
// allowed-files list does not include `test/fixtures/**`, so no fixture is
// committed.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_release_manifest.dart';

void main() {
  group(
    'A1 — deterministic, timestamp-free release manifest (ADR 0447 D1)',
    () {
      Map<String, Object?> fixtureMlManifest() => <String, Object?>{
        'schema_version': 1,
        'models': [
          {'filename': 'a.bin'},
          {'filename': 'b.bin'},
        ],
      };

      Map<String, Object?> fixtureKnowledgeManifest() => <String, Object?>{
        'schemaVersion': 1,
        'documents': [
          {'id': 'doc-1'},
        ],
      };

      List<int> fixtureBytes(Map<String, Object?> value) =>
          utf8.encode(jsonEncode(value));

      Map<String, Object?> buildFixtureManifest() {
        final mlManifest = fixtureMlManifest();
        final knowledgeManifest = fixtureKnowledgeManifest();
        return buildReleaseManifest(
          appVersion: '1.2.3',
          appBuildNumber: 7,
          shortSha: 'abcdef1',
          channel: 'production',
          mlManifest: mlManifest,
          mlManifestBytes: fixtureBytes(mlManifest),
          knowledgeManifest: knowledgeManifest,
          knowledgeManifestBytes: fixtureBytes(knowledgeManifest),
        );
      }

      test('canonicalJsonBytes sorts object keys ascending at every nesting '
          'level — the exact property the required mutation probe (removing '
          'the key sort) must break (§10)', () {
        final bytes = canonicalJsonBytes(<String, Object?>{
          'z': 1,
          'a': <String, Object?>{'y': 2, 'b': 3},
          'm': [
            <String, Object?>{'z': 1, 'a': 2},
          ],
        });
        expect(
          utf8.decode(bytes),
          '{"a":{"b":3,"y":2},"m":[{"a":2,"z":1}],"z":1}\n',
        );
      });

      test('two runs against identical inputs are byte-identical', () {
        final first = canonicalJsonBytes(buildFixtureManifest());
        final second = canonicalJsonBytes(buildFixtureManifest());
        expect(first, second);
      });

      test('the fixture manifest text has no ISO-8601-shaped timestamp '
          'anywhere', () {
        final text = utf8.decode(canonicalJsonBytes(buildFixtureManifest()));
        expect(text, isNot(matches(_iso8601Pattern)));
      });

      test('self-check: the ISO-8601 regex used above actually detects a '
          'timestamp (guards against a vacuous checker)', () {
        expect('2026-08-28T10:00:00Z', matches(_iso8601Pattern));
      });

      test('no key anywhere in the fixture manifest names a time/date/'
          'generation concept', () {
        _expectNoTimestampLikeKeys(buildFixtureManifest());
      });

      test('self-check: the timestamp-key-name scanner used above actually '
          'flags a key named "generatedAt"', () {
        expect(
          () => _expectNoTimestampLikeKeys(<String, Object?>{
            'generatedAt': '2026-08-28',
          }),
          throwsA(isA<TestFailure>()),
        );
      });

      test('the generator source never calls DateTime.now() (source '
          'introspection safety net, matrix row: injected timestamp)', () {
        final source = File(
          'tool/generate_release_manifest.dart',
        ).readAsStringSync();
        expect(source, isNot(contains('DateTime.now')));
      });

      test('keys are sorted ascending, recursively, in the REAL release '
          'manifest built from the real ML + tutor knowledge manifests', () {
        final manifest = _buildRealManifest();
        final decoded =
            jsonDecode(utf8.decode(canonicalJsonBytes(manifest)))
                as Map<String, Object?>;
        _expectSortedKeys(decoded);
      });
    },
  );

  group('A2 — missing license fails closed (ADR 0447 D3)', () {
    test('a hosted Dart package with no pub-cache LICENSE and no curated '
        'registry entry blocks the SBOM with a non-zero exit naming it', () {
      final fixtureRoot = Directory.systemTemp.createTempSync(
        'strumsight_sbom_missing_license_',
      );
      addTearDown(() => fixtureRoot.deleteSync(recursive: true));

      final pubCache = Directory('${fixtureRoot.path}/pubcache')
        ..createSync(recursive: true);
      // `known_pkg` resolves via the pub cache; `mystery_pkg` has neither a
      // pub cache LICENSE nor a _CURATED_LICENSES entry.
      final knownPkgDir = Directory(
        '${pubCache.path}/hosted/pub.dev/known_pkg-1.0.0',
      )..createSync(recursive: true);
      File('${knownPkgDir.path}/LICENSE').writeAsStringSync('MIT License\n');

      final pubspecLock = File('${fixtureRoot.path}/pubspec.lock')
        ..writeAsStringSync('''
# Generated by pub
packages:
  known_pkg:
    dependency: "direct main"
    description:
      name: known_pkg
      sha256: "deadbeef"
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  mystery_pkg:
    dependency: transitive
    description:
      name: mystery_pkg
      sha256: "deadbeef"
      url: "https://pub.dev"
    source: hosted
    version: "2.0.0"
''');
      final requirements = File('${fixtureRoot.path}/requirements.txt')
        ..writeAsStringSync('');
      final outputSbom = '${fixtureRoot.path}/sbom.json';
      final outputNotices = '${fixtureRoot.path}/NOTICES.md';

      final result = Process.runSync('python3', [
        'tool/release/generate_sbom.py',
        '--pubspec-lock',
        pubspecLock.path,
        '--pub-cache',
        pubCache.path,
        '--requirements',
        requirements.path,
        '--output-sbom',
        outputSbom,
        '--output-notices',
        outputNotices,
      ]);

      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('mystery_pkg'));
      expect(File(outputSbom).existsSync(), isFalse);
      expect(File(outputNotices).existsSync(), isFalse);
    });

    test('the SBOM and notices carry no absolute filesystem path — measured '
        'against a fixture pub cache under systemTemp (not \$HOME); the '
        'pre-fix implementation embedded the full resolved cache path here '
        'and this cell would have caught it (F1, docs/reviews/e12-r06-'
        'review.md)', () {
      final fixtureRoot = Directory.systemTemp.createTempSync(
        'strumsight_sbom_relative_license_path_',
      );
      addTearDown(() => fixtureRoot.deleteSync(recursive: true));

      final pubCache = Directory('${fixtureRoot.path}/pubcache')
        ..createSync(recursive: true);
      final knownPkgDir = Directory(
        '${pubCache.path}/hosted/pub.dev/known_pkg-1.0.0',
      )..createSync(recursive: true);
      File('${knownPkgDir.path}/LICENSE').writeAsStringSync('MIT License\n');

      final pubspecLock = File('${fixtureRoot.path}/pubspec.lock')
        ..writeAsStringSync('''
# Generated by pub
packages:
  known_pkg:
    dependency: "direct main"
    description:
      name: known_pkg
      sha256: "deadbeef"
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');
      final requirements = File('${fixtureRoot.path}/requirements.txt')
        ..writeAsStringSync('');
      final outputSbom = '${fixtureRoot.path}/sbom.json';
      final outputNotices = '${fixtureRoot.path}/NOTICES.md';

      final result = Process.runSync('python3', [
        'tool/release/generate_sbom.py',
        '--pubspec-lock',
        pubspecLock.path,
        '--pub-cache',
        pubCache.path,
        '--requirements',
        requirements.path,
        '--output-sbom',
        outputSbom,
        '--output-notices',
        outputNotices,
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final sbomText = File(outputSbom).readAsStringSync();
      final noticesText = File(outputNotices).readAsStringSync();
      final decoded = jsonDecode(sbomText) as Map<String, Object?>;

      _expectNoAbsoluteFilesystemPathValues(decoded, source: 'fixture SBOM');
      _expectTextHasNoAbsoluteFilesystemPath(sbomText, source: 'fixture SBOM');
      _expectTextHasNoAbsoluteFilesystemPath(
        noticesText,
        source: 'fixture notices',
      );
      expect(
        noticesText,
        contains('hosted/pub.dev/known_pkg-1.0.0/LICENSE'),
        reason:
            'the relative licensePath must still be present, just without '
            'the resolved pub cache root prefix (${pubCache.path})',
      );
    });

    test('the committed THIRD_PARTY_NOTICES.md carries no absolute '
        'filesystem path (F1, docs/reviews/e12-r06-review.md)', () {
      final noticesText = File('THIRD_PARTY_NOTICES.md').readAsStringSync();
      _expectTextHasNoAbsoluteFilesystemPath(
        noticesText,
        source: 'THIRD_PARTY_NOTICES.md',
      );
    });

    test('when every package resolves, the SBOM never writes "unknown", '
        'null, or an empty license value', () {
      final fixtureRoot = Directory.systemTemp.createTempSync(
        'strumsight_sbom_resolved_',
      );
      addTearDown(() => fixtureRoot.deleteSync(recursive: true));

      final pubCache = Directory('${fixtureRoot.path}/pubcache')
        ..createSync(recursive: true);
      final knownPkgDir = Directory(
        '${pubCache.path}/hosted/pub.dev/known_pkg-1.0.0',
      )..createSync(recursive: true);
      File('${knownPkgDir.path}/LICENSE').writeAsStringSync('MIT License\n');

      final pubspecLock = File('${fixtureRoot.path}/pubspec.lock')
        ..writeAsStringSync('''
# Generated by pub
packages:
  known_pkg:
    dependency: "direct main"
    description:
      name: known_pkg
      sha256: "deadbeef"
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');
      final requirements = File('${fixtureRoot.path}/requirements.txt')
        ..writeAsStringSync('fastapi>=0.115,<0.116\n');
      final outputSbom = '${fixtureRoot.path}/sbom.json';
      final outputNotices = '${fixtureRoot.path}/NOTICES.md';

      final result = Process.runSync('python3', [
        'tool/release/generate_sbom.py',
        '--pubspec-lock',
        pubspecLock.path,
        '--pub-cache',
        pubCache.path,
        '--requirements',
        requirements.path,
        '--output-sbom',
        outputSbom,
        '--output-notices',
        outputNotices,
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final sbomText = File(outputSbom).readAsStringSync();
      final decoded = jsonDecode(sbomText) as Map<String, Object?>;
      expect(decoded['componentCount'], 2);
      _expectNoUnknownLicenseValues(decoded);
    });
  });

  group('A3 — strictly monotonic build number (ADR 0447 D2)', () {
    String writeManifest(Directory root, String name, int buildNumber) {
      final file = File('${root.path}/$name.json');
      file.writeAsStringSync(
        jsonEncode({
          'app': {'buildNumber': buildNumber},
          'artifacts': <Object?>[],
        }),
      );
      return file.path;
    }

    late Directory fixtureRoot;
    late String previousManifest;

    setUp(() {
      fixtureRoot = Directory.systemTemp.createTempSync(
        'strumsight_verify_artifacts_',
      );
      previousManifest = writeManifest(fixtureRoot, 'previous', 42);
    });
    tearDown(() => fixtureRoot.deleteSync(recursive: true));

    test(
      'threshold cell: below the baseline (41 vs 42) is a non-zero exit',
      () {
        final newManifest = writeManifest(fixtureRoot, 'new_41', 41);
        final result = Process.runSync('python3', [
          'tool/release/verify_artifacts.py',
          '--manifest',
          newManifest,
          '--previous',
          previousManifest,
        ]);
        expect(result.exitCode, isNot(0));
      },
    );

    test('threshold cell: exactly on the baseline (42 vs 42) is a non-zero '
        'exit — the equality case matrix row', () {
      final newManifest = writeManifest(fixtureRoot, 'new_42', 42);
      final result = Process.runSync('python3', [
        'tool/release/verify_artifacts.py',
        '--manifest',
        newManifest,
        '--previous',
        previousManifest,
      ]);
      expect(result.exitCode, isNot(0));
    });

    test('threshold cell: above the baseline (43 vs 42) is a zero exit', () {
      final newManifest = writeManifest(fixtureRoot, 'new_43', 43);
      final result = Process.runSync('python3', [
        'tool/release/verify_artifacts.py',
        '--manifest',
        newManifest,
        '--previous',
        previousManifest,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test('without --previous, monotonicity is not silently skipped — the '
        'tool states "baseline: none" and exits zero (matrix row)', () {
      final newManifest = writeManifest(fixtureRoot, 'no_baseline', 1);
      final result = Process.runSync('python3', [
        'tool/release/verify_artifacts.py',
        '--manifest',
        newManifest,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('baseline: none'));
    });

    test('a missing or checksum-mismatched artifact is a non-zero exit', () {
      final artifactPath = '${fixtureRoot.path}/app.apk';
      File(artifactPath).writeAsStringSync('apk-bytes');
      final manifestFile = File('${fixtureRoot.path}/with_artifact.json')
        ..writeAsStringSync(
          jsonEncode({
            'app': {'buildNumber': 43},
            'artifacts': [
              {
                'name': 'app.apk',
                'path': artifactPath,
                'sha256': '0' * 64, // deliberately wrong
              },
            ],
          }),
        );
      final result = Process.runSync('python3', [
        'tool/release/verify_artifacts.py',
        '--manifest',
        manifestFile.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('app.apk'));
    });
  });

  group('A4 — ML + tutor knowledge package references, no invented '
      '"package version" (ADR 0447 D6)', () {
    test('the real release manifest names the shipping model count (4, the '
        'expectedModelCount pin L164 keeps this) and document count (10) '
        'via measured schema version + manifest sha256 only', () {
      final manifest = _buildRealManifest();

      final modelPackage = manifest['modelPackage'] as Map<String, Object?>;
      expect(modelPackage.keys.toSet(), {
        'schemaVersion',
        'manifestSha256',
        'modelCount',
      });
      expect(modelPackage['schemaVersion'], 1);
      expect(modelPackage['modelCount'], 4);
      expect(
        modelPackage['manifestSha256'],
        sha256
            .convert(File('assets/ml/model_manifest.json').readAsBytesSync())
            .toString(),
      );

      final knowledgePackage =
          manifest['knowledgePackage'] as Map<String, Object?>;
      expect(knowledgePackage.keys.toSet(), {
        'schemaVersion',
        'manifestSha256',
        'documentCount',
      });
      expect(knowledgePackage['schemaVersion'], 1);
      expect(knowledgePackage['documentCount'], 10);
      expect(
        knowledgePackage['manifestSha256'],
        sha256
            .convert(
              File('assets/tutor_knowledge/manifest.json').readAsBytesSync(),
            )
            .toString(),
      );
    });

    test('matrix row: a model manifest missing "models" is refused rather '
        'than silently producing a package reference', () {
      expect(
        () => buildReleaseManifest(
          appVersion: '1.0.0',
          appBuildNumber: 1,
          shortSha: 'abcdef1',
          channel: 'dev',
          mlManifest: const <String, Object?>{'schema_version': 1},
          mlManifestBytes: const [1, 2, 3],
          knowledgeManifest: const <String, Object?>{
            'schemaVersion': 1,
            'documents': <Object?>[],
          },
          knowledgeManifestBytes: const [4, 5, 6],
        ),
        throwsA(isA<ReleaseManifestException>()),
      );
    });
  });

  group('A5 — provenance proposal YAML validity (ADR 0447 D4/D5)', () {
    test('parses a minimal well-formed steps fragment', () {
      const fixture = '''
steps:
  - name: Generate release manifest
    run: |
      dart run tool/generate_release_manifest.dart --output dist/m.json
  - name: Upload release manifest
    uses: actions/upload-artifact@v4
    with:
      name: release-manifest
      path: dist/m.json
''';
      final steps = parseWorkflowSteps(fixture, sourceLabel: 'fixture');
      expect(steps, hasLength(2));
      expect(steps[0].name, 'Generate release manifest');
      expect(steps[0].run, contains('generate_release_manifest.dart'));
      expect(steps[1].uses, 'actions/upload-artifact@v4');
      expect(steps[1].withArgs['path'], 'dist/m.json');
    });

    test('matrix row: a "run:" that is not a literal block scalar ("|") is '
        'rejected (syntactically broken fragment)', () {
      const fixture = '''
steps:
  - name: X
    run: echo hi
''';
      expect(
        () => parseWorkflowSteps(fixture, sourceLabel: 'fixture'),
        throwsFormatException,
      );
    });

    test('matrix row: an unsupported step key is rejected', () {
      const fixture = '''
steps:
  - name: X
    env:
      FOO: bar
''';
      expect(
        () => parseWorkflowSteps(fixture, sourceLabel: 'fixture'),
        throwsFormatException,
      );
    });

    test('matrix row: a fragment missing the notices upload is flagged, '
        'not silently accepted', () {
      const fixture = '''
steps:
  - name: Generate release manifest
    run: |
      dart run tool/generate_release_manifest.dart --output dist/release-manifest.json
  - name: Generate SBOM and third-party notices
    run: |
      python3 tool/release/generate_sbom.py --output-sbom dist/sbom.json
  - name: Upload release manifest
    uses: actions/upload-artifact@v4
    with:
      name: release-manifest
      path: dist/release-manifest.json
  - name: Upload SBOM
    uses: actions/upload-artifact@v4
    with:
      name: sbom
      path: dist/sbom.json
''';
      final steps = parseWorkflowSteps(fixture, sourceLabel: 'fixture');
      expect(findMissingArtifactUploads(steps), ['THIRD_PARTY_NOTICES.md']);
    });

    test('the real proposal doc: YAML fragment parses, generates + uploads '
        'all three artifacts, and names an existing release-apk.yml step '
        'as the insertion point', () {
      const docPath =
          'docs/release/workflows/release-apk-provenance.proposal.md';
      final markdown = File(docPath).readAsStringSync();
      final yamlFragment = extractYamlFence(markdown, sourceLabel: docPath);
      final steps = parseWorkflowSteps(yamlFragment, sourceLabel: docPath);

      expect(steps, isNotEmpty);
      expect(
        steps.any(
          (step) => (step.run ?? '').contains('generate_release_manifest.dart'),
        ),
        isTrue,
        reason: 'must generate the release manifest',
      );
      expect(
        steps.any((step) => (step.run ?? '').contains('generate_sbom.py')),
        isTrue,
        reason: 'must generate the SBOM + notices',
      );
      expect(findMissingArtifactUploads(steps), isEmpty);

      const insertionPointStepName = 'Read APK metadata from pubspec';
      expect(markdown, contains(insertionPointStepName));
      final realWorkflow = File(
        '.github/workflows/release-apk.yml',
      ).readAsStringSync();
      expect(
        realWorkflow,
        contains('- name: $insertionPointStepName'),
        reason:
            'the named insertion-point step must exist in the real '
            'workflow',
      );
    });
  });

  // No skip path anywhere in this file, including groups A2/A3 above that
  // spawn python3 (generate_sbom.py / verify_artifacts.py): if python3 is
  // missing, `Process.runSync` throws ProcessException the first time a
  // test calls it, which fails that test — exactly the "PIROS, not skip"
  // contract this group measures directly below.
  group(
    'A7 — this gate never relies on an unguaranteed binary (ADR 0447 D5, L110)',
    () {
      test('this file does not import the transitive-only YAML package', () {
        final source = File(
          'test/tooling/release_manifest_test.dart',
        ).readAsStringSync();
        expect(
          RegExp(r"^import\s+'package:yaml", multiLine: true).hasMatch(source),
          isFalse,
        );
      });

      test('every external process this file spawns targets python3 only '
          '— never rg/grep/jq/gh', () {
        final source = File(
          'test/tooling/release_manifest_test.dart',
        ).readAsStringSync();
        final executables = _processCallExecutable
            .allMatches(source)
            .map((match) => match.group(1)!)
            .toSet();
        expect(executables, isNotEmpty, reason: 'this file must call python3');
        expect(executables, {'python3'});
      });

      test('self-check: python3 is on PATH in this environment — if it is '
          'not, the calls above throw ProcessException and this whole '
          'file turns red, never a silent skip', () {
        final result = Process.runSync('python3', ['--version']);
        expect(result.exitCode, 0);
      });
    },
  );
}

final _iso8601Pattern = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');

final _timestampKeyPattern = RegExp(
  r'time|date|generated|created',
  caseSensitive: false,
);

void _expectNoTimestampLikeKeys(Object? value) {
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      expect(
        _timestampKeyPattern.hasMatch(entry.key),
        isFalse,
        reason:
            '"${entry.key}" looks like a timestamp field — ADR 0447 D1 '
            'forbids any generation timestamp in the manifest',
      );
      _expectNoTimestampLikeKeys(entry.value);
    }
  } else if (value is List) {
    for (final item in value) {
      _expectNoTimestampLikeKeys(item);
    }
  }
}

void _expectSortedKeys(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList();
    final sortedKeys = [...keys]..sort();
    expect(keys, sortedKeys, reason: 'object keys must be sorted ascending');
    for (final nested in value.values) {
      _expectSortedKeys(nested);
    }
  } else if (value is List) {
    for (final item in value) {
      _expectSortedKeys(item);
    }
  }
}

void _expectNoUnknownLicenseValues(Object? value) {
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      if (entry.key.toLowerCase().contains('license') || entry.key == 'spdx') {
        expect(entry.value, isNot(isNull));
        if (entry.value is String) {
          expect(
            (entry.value as String).trim().toLowerCase(),
            isNot('unknown'),
          );
          expect((entry.value as String).trim(), isNotEmpty);
        }
      }
      _expectNoUnknownLicenseValues(entry.value);
    }
  } else if (value is List) {
    for (final item in value) {
      _expectNoUnknownLicenseValues(item);
    }
  }
}

/// Walks a decoded SBOM document and fails on any `licensePath` value that
/// is an absolute filesystem path (F1, docs/reviews/e12-r06-review.md):
/// `_resolve_dart_license` must record the path relative to the pub cache
/// root, never the resolved absolute cache path, or the committed notices
/// bundle differs per machine/CI runner for an identical commit.
void _expectNoAbsoluteFilesystemPathValues(
  Object? value, {
  required String source,
}) {
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      if (entry.key == 'licensePath' && entry.value is String) {
        expect(
          (entry.value as String).startsWith('/'),
          isFalse,
          reason:
              '$source: "licensePath" must be relative to the pub cache '
              'root, not an absolute filesystem path — got: ${entry.value}',
        );
      }
      _expectNoAbsoluteFilesystemPathValues(entry.value, source: source);
    }
  } else if (value is List) {
    for (final item in value) {
      _expectNoAbsoluteFilesystemPathValues(item, source: source);
    }
  }
}

/// Scans raw generated text (SBOM JSON or notices markdown) for any of the
/// machine-specific absolute path shapes forbidden by F1: a `License text:`
/// line whose value starts with `/`, or an embedded `/home/`, `/Users/` or
/// `C:\` fragment anywhere in the text.
void _expectTextHasNoAbsoluteFilesystemPath(
  String text, {
  required String source,
}) {
  expect(
    text,
    isNot(contains('/home/')),
    reason: '$source must not embed a machine-specific /home/ path',
  );
  expect(
    text,
    isNot(contains('/Users/')),
    reason: '$source must not embed a machine-specific /Users/ path',
  );
  expect(
    text,
    isNot(contains(r'C:\')),
    reason: '$source must not embed a machine-specific C:\\ path',
  );
  final licenseTextLine = RegExp(r'^- License text: (\S+)$', multiLine: true);
  for (final match in licenseTextLine.allMatches(text)) {
    final pathValue = match.group(1)!;
    expect(
      pathValue.startsWith('/'),
      isFalse,
      reason:
          '$source: "License text:" value must be relative to the pub '
          'cache root, not an absolute filesystem path — got: $pathValue',
    );
  }
}

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

// Built via adjacent string-literal concatenation so this constant's own
// definition text never spells out the executable-call pattern it searches
// for as one contiguous run of characters — otherwise the A7 self-scan
// below would match its own regex source, exactly the self-matching trap
// `repository_policy_test.dart`'s A8 group avoids.
final _processCallExecutable = RegExp(
  'Process'
  r'''\.(?:run|runSync|start)\(\s*['"]([^'"\n]+)['"]''',
);

// ---------------------------------------------------------------------------
// Restricted GitHub Actions "steps:" YAML subset (ADR 0447 D5, ADR 0444 D3
// precedent).
// ---------------------------------------------------------------------------

/// One parsed `- name: ...` element of a restricted-subset `steps:` list.
final class WorkflowStep {
  const WorkflowStep({
    required this.name,
    this.run,
    this.uses,
    this.withArgs = const {},
  });

  final String name;
  final String? run;
  final String? uses;
  final Map<String, String> withArgs;
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
/// the release-provenance proposal uses.
///
/// `package:yaml` is only a transitive dependency on this tree
/// (`pubspec.lock:1261`) and importing it here would turn `flutter
/// analyze` red via the `depend_on_referenced_packages` lint, the same
/// measurement `repository_policy_test.dart` documents for ADR 0444 D3.
/// This parser therefore restricts the proposal's YAML fragment to a
/// subset a small, indentation-exact, line-based parser can read without
/// ambiguity:
///
///  - a single top-level key `steps:` (empty value) starting a 2-space
///    indented block list;
///  - each list element begins `  - name: <value>`;
///  - inside an element (exactly 4-space indent): `run:` (must be a
///    literal block scalar, `run: |`, followed by 6-space-indented shell
///    lines), `uses: <value>`, or `with:` (empty value, followed by a
///    6-space-indented flat scalar map);
///
/// A container key (`steps:`, `with:`) written with an inline value, a
/// `run:` that is not a `|` block scalar, or any step key other than
/// run/uses/with fails with a `FormatException` naming the exact line —
/// not silently misread. A fragment needing anything richer is not a
/// parser gap to route around; it needs rewriting into this subset.
List<WorkflowStep> parseWorkflowSteps(
  String contents, {
  required String sourceLabel,
}) {
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

    String? run;
    String? uses;
    final withArgs = <String, String>{};

    while (i < lines.length && _fourSpaceKeyLine.hasMatch(lines[i])) {
      final match = _fourSpaceKeyLine.firstMatch(lines[i])!;
      final key = match.group(1)!;
      final rest = match.group(2)!.trim();
      final lineNumber = i + 1;
      i++;
      switch (key) {
        case 'run':
          if (rest != '|') {
            throw FormatException(
              '$sourceLabel:$lineNumber: "run:" must be a literal block '
              'scalar ("run: |"), got: "$rest"',
            );
          }
          final blockLines = <String>[];
          while (i < lines.length &&
              (lines[i].startsWith('      ') || lines[i].trim().isEmpty)) {
            blockLines.add(lines[i].isEmpty ? '' : lines[i].substring(6));
            i++;
          }
          run = blockLines.join('\n');
        case 'uses':
          uses = _unquote(rest);
        case 'with':
          if (rest.isNotEmpty) {
            throw FormatException(
              '$sourceLabel:$lineNumber: "with:" must start a block '
              'mapping, not an inline value: "$rest"',
            );
          }
          while (i < lines.length && _sixSpaceKeyLine.hasMatch(lines[i])) {
            final withMatch = _sixSpaceKeyLine.firstMatch(lines[i])!;
            withArgs[withMatch.group(1)!] = _unquote(withMatch.group(2)!);
            i++;
          }
        default:
          throw FormatException(
            '$sourceLabel:$lineNumber: unsupported step key "$key" — only '
            'run/uses/with are supported',
          );
      }
    }

    steps.add(
      WorkflowStep(name: name, run: run, uses: uses, withArgs: withArgs),
    );
  }
  return steps;
}

/// Substrings that must each appear in some `actions/upload-artifact` step's
/// `with.path` — the release manifest, the SBOM, and the notices bundle.
const List<String> requiredProvenanceArtifactPathFragments = [
  'release-manifest',
  'sbom',
  'THIRD_PARTY_NOTICES.md',
];

/// Returns the subset of [requiredProvenanceArtifactPathFragments] that no
/// `actions/upload-artifact` step in [steps] uploads — empty when all three
/// generated artifacts are covered.
List<String> findMissingArtifactUploads(List<WorkflowStep> steps) {
  final uploadPaths = <String>[
    for (final step in steps)
      if ((step.uses ?? '').startsWith('actions/upload-artifact'))
        step.withArgs['path'] ?? '',
  ];
  return [
    for (final fragment in requiredProvenanceArtifactPathFragments)
      if (!uploadPaths.any((path) => path.contains(fragment))) fragment,
  ];
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
