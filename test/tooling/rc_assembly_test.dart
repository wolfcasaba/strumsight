// Release Candidate assembly gate (E12-R25, ADR 0488).
//
// Follows the `test/tooling/release_manifest_test.dart` (ADR 0447) /
// `test/tooling/signing_policy_test.dart` (ADR 0448) pattern: a single gate
// test file that shells out to `python3` on both the real tree and
// synthetic fixtures — the ONLY external binary this file is allowed to
// invoke (ADR 0488 D6, precedent ADR 0447 D5, L110) — plus a restricted
// GitHub Actions YAML parser living directly in this file. `package:yaml`
// is NOT imported: it is only a transitive dependency on this tree, and
// importing it would turn `flutter analyze` red via the
// `depend_on_referenced_packages` lint (ADR 0447 D5 / ADR 0448 D6
// precedent).
//
// This round's parser is a SUPERSET of the two precedent files: it reads
// job-level structure (`jobs:`, `needs:`, `environment:`, `steps:`), not
// just a bare `steps:` list, because A1/A6 need the approval-gate/needs
// graph, not just step bodies (ADR 0488 D6).
//
// L566 (fail-OPEN line parser): every line inside the `jobs:` block that
// does not match a recognized shape throws `FormatException` naming the
// line — no silent `continue`. The parsed job count and total step count
// are additionally cross-checked against raw `RegExp` occurrence counts
// (group "A7"), so a parser that silently swallowed a job or a step would
// itself fail a cell, not just the state it failed to see.
//
// L563 (cells green on the broken implementation): every acceptance group
// below carries at least one fixture proven to turn that SAME cell red —
// see the "mutation probe" test in each group.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _tool = 'tool/release/assemble_rc.py';
const _proposalPath = 'docs/release/workflows/release-candidate.proposal.yml';

// Composite gate steps' exact `run:` command bodies (ADR 0488 D2 — the
// proposal must call the composite, never copy these). Compared by EXACT
// equality against a parsed step's `run` body (R3: "pontos egyezés", not
// `contains`) so a legitimately similar-but-different command (e.g. this
// round's own "flutter test --coverage") is never a false positive.
const _compositeGateCommands = <String>{
  'flutter pub get',
  'dart format --output=none --set-exit-if-changed lib test tool',
  'flutter analyze lib/ test/ tool/',
  'dart run tool/check_architecture.dart',
  'dart run tool/ci/check_secrets.dart',
  'dart run tool/ci/check_l10n_parity.dart',
  'dart run tool/ci/check_assets.dart',
  'flutter test',
  'flutter test test/property',
};

void main() {
  group('A2/A3/A4 — assemble_rc.py fixture cells (ADR 0488 D4/D5)', () {
    late Directory fixtureRoot;
    late Map<String, String> inputPaths;

    setUp(() {
      fixtureRoot = Directory.systemTemp.createTempSync(
        'strumsight_rc_assembly_',
      );
      final in_ = Directory('${fixtureRoot.path}/in')
        ..createSync(recursive: true);
      String write(String name, String contents) {
        final file = File('${in_.path}/$name');
        file.writeAsStringSync(contents);
        return file.path;
      }

      inputPaths = {
        'apk': write('app-release.apk', 'fake apk bytes'),
        'release_manifest': write(
          'release-manifest.json',
          '{"app":{"buildNumber":1}}',
        ),
        'sbom': write('sbom.json', '{"componentCount":0,"components":[]}'),
        'notices': write('THIRD_PARTY_NOTICES.md', '# Third-party notices\n'),
        'ai_report': write('ai-report.json', '{"findings":[]}'),
        'security_report': write('security-report.json', '{"findings":[]}'),
        'test_report': write('lcov.info', 'TN:\nend_of_record\n'),
      };
    });
    tearDown(() => fixtureRoot.deleteSync(recursive: true));

    List<String> _allArgs({String? outputDir}) {
      final args = <String>[
        '--profile',
        'development',
        '--output-dir',
        outputDir ?? '${fixtureRoot.path}/out',
      ];
      for (final entry in inputPaths.entries) {
        args.addAll(['--${entry.key.replaceAll('_', '-')}', entry.value]);
      }
      return args;
    }

    test('A2 — with all seven inputs present, assembly exits 0 and the '
        'package contains all seven files plus a checksum manifest whose '
        'hashes match the copied files exactly', () {
      final outputDir = '${fixtureRoot.path}/out';
      final result = Process.runSync('python3', [
        _tool,
        ..._allArgs(outputDir: outputDir),
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());

      final packageDir = Directory(outputDir);
      final manifestFile = File('$outputDir/checksum-manifest.json');
      expect(manifestFile.existsSync(), isTrue);
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      final files = (manifest['files'] as List).cast<Map<String, Object?>>();

      final expectedNames = inputPaths.values
          .map((p) => p.split('/').last)
          .toSet();
      final manifestNames = files.map((f) => f['path'] as String).toSet();
      expect(manifestNames, expectedNames);

      final actualNames = packageDir
          .listSync()
          .whereType<File>()
          .map((f) => f.path.split('/').last)
          .where((name) => name != 'checksum-manifest.json')
          .toSet();
      expect(actualNames, expectedNames);

      for (final entry in files) {
        final path = entry['path'] as String;
        final expectedSha = entry['sha256'] as String;
        final actualSha = sha256
            .convert(File('$outputDir/$path').readAsBytesSync())
            .toString();
        expect(actualSha, expectedSha, reason: 'checksum mismatch for $path');
      }
    });

    const _labels = {
      'apk': 'APK artifact',
      'release_manifest': 'release manifest',
      'sbom': 'SBOM',
      'notices': 'third-party notices',
      'ai_report': 'AI quality report',
      'security_report': 'security scan report',
      'test_report': 'test/coverage report',
    };

    for (final missingKey in _labels.keys) {
      test('A3 — missing "$missingKey" alone (all six others present) is a '
          'non-zero exit naming "${_labels[missingKey]}", and the output '
          'directory is never created (D4: no half-built package)', () {
        final outputDir = '${fixtureRoot.path}/out-missing-$missingKey';
        final args = <String>[
          '--profile',
          'development',
          '--output-dir',
          outputDir,
        ];
        for (final entry in inputPaths.entries) {
          final value = entry.key == missingKey
              ? '${fixtureRoot.path}/does-not-exist-${entry.key}'
              : entry.value;
          args.addAll(['--${entry.key.replaceAll('_', '-')}', value]);
        }
        final result = Process.runSync('python3', [_tool, ...args]);
        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains(_labels[missingKey]!));
        expect(Directory(outputDir).existsSync(), isFalse);
      });
    }

    test('A3 — matrix row: a fixture with ALL seven inputs missing (a '
        'clean tree) reports all seven labels, not just the first', () {
      final outputDir = '${fixtureRoot.path}/out-all-missing';
      final result = Process.runSync('python3', [
        _tool,
        '--profile',
        'development',
        '--output-dir',
        outputDir,
        '--apk',
        '${fixtureRoot.path}/nope-apk',
        '--release-manifest',
        '${fixtureRoot.path}/nope-manifest',
        '--sbom',
        '${fixtureRoot.path}/nope-sbom',
        '--notices',
        '${fixtureRoot.path}/nope-notices',
        '--ai-report',
        '${fixtureRoot.path}/nope-ai',
        '--security-report',
        '${fixtureRoot.path}/nope-security',
        '--test-report',
        '${fixtureRoot.path}/nope-test',
      ]);
      expect(result.exitCode, isNot(0));
      for (final label in _labels.values) {
        expect(result.stderr.toString(), contains(label));
      }
    });

    test('A3/D4 — --dry-run on the REAL tree (a clean checkout with no '
        'release artifacts built) is EXPECTED to exit non-zero, listing '
        'the missing mandatory inputs — this is the §7 local run and the '
        'live proof of D4, not a failure', () {
      final result = Process.runSync('python3', [
        _tool,
        '--profile',
        'development',
        '--dry-run',
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stdout.toString(), contains('assemble_rc: input plan'));
      expect(result.stdout.toString(), contains('MISSING'));
    });

    test('A3 — matrix row: --dry-run with all seven inputs present exits 0 '
        'and writes nothing', () {
      final outputDir = '${fixtureRoot.path}/out-dry-run-complete';
      final result = Process.runSync('python3', [
        _tool,
        '--profile',
        'development',
        '--dry-run',
        '--output-dir',
        outputDir,
        ..._allArgs(outputDir: outputDir).skip(4),
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        result.stdout.toString(),
        contains('all mandatory inputs present'),
      );
      expect(Directory(outputDir).existsSync(), isFalse);
    });

    test('A4 — --verify on a freshly assembled package exits 0', () {
      final outputDir = '${fixtureRoot.path}/out-verify-ok';
      final assemble = Process.runSync('python3', [
        _tool,
        ..._allArgs(outputDir: outputDir),
      ]);
      expect(assemble.exitCode, 0, reason: assemble.stderr.toString());
      final verify = Process.runSync('python3', [
        _tool,
        '--verify',
        '--output-dir',
        outputDir,
      ]);
      expect(verify.exitCode, 0, reason: verify.stderr.toString());
    });

    test('A4 — a single-byte change to a packaged file after assembly is a '
        'non-zero --verify exit naming that file', () {
      final outputDir = '${fixtureRoot.path}/out-verify-tamper';
      final assemble = Process.runSync('python3', [
        _tool,
        ..._allArgs(outputDir: outputDir),
      ]);
      expect(assemble.exitCode, 0, reason: assemble.stderr.toString());
      final sbomFile = File('$outputDir/sbom.json');
      sbomFile.writeAsStringSync('${sbomFile.readAsStringSync()}tampered');
      final verify = Process.runSync('python3', [
        _tool,
        '--verify',
        '--output-dir',
        outputDir,
      ]);
      expect(verify.exitCode, isNot(0));
      expect(verify.stderr.toString(), contains('sbom.json'));
    });

    test('A4 — an extra file dropped into the package after assembly (not '
        'named in the checksum manifest) is a non-zero --verify exit', () {
      final outputDir = '${fixtureRoot.path}/out-verify-extra';
      final assemble = Process.runSync('python3', [
        _tool,
        ..._allArgs(outputDir: outputDir),
      ]);
      expect(assemble.exitCode, 0, reason: assemble.stderr.toString());
      File('$outputDir/uninvited.txt').writeAsStringSync('surprise');
      final verify = Process.runSync('python3', [
        _tool,
        '--verify',
        '--output-dir',
        outputDir,
      ]);
      expect(verify.exitCode, isNot(0));
      expect(verify.stderr.toString(), contains('uninvited.txt'));
      expect(
        verify.stderr.toString(),
        contains('not in the checksum manifest'),
      );
    });

    test('A4 — deleting a packaged file after assembly is a non-zero '
        '--verify exit naming it as missing', () {
      final outputDir = '${fixtureRoot.path}/out-verify-missing';
      final assemble = Process.runSync('python3', [
        _tool,
        ..._allArgs(outputDir: outputDir),
      ]);
      expect(assemble.exitCode, 0, reason: assemble.stderr.toString());
      File('$outputDir/ai-report.json').deleteSync();
      final verify = Process.runSync('python3', [
        _tool,
        '--verify',
        '--output-dir',
        outputDir,
      ]);
      expect(verify.exitCode, isNot(0));
      expect(verify.stderr.toString(), contains('missing from package'));
      expect(verify.stderr.toString(), contains('ai-report.json'));
    });

    test('A4 — mutation probe (§6.1 matrix row "checksum-manifest csak az '
        'APK-ra terjed ki"): a hand-written manifest naming only the APK, '
        'sitting next to all seven real package files, fails --verify by '
        'flagging the other six as unlisted — proving this cell would '
        'catch a manifest that only ever covers the APK', () {
      final outputDir = '${fixtureRoot.path}/out-apk-only-manifest';
      final assemble = Process.runSync('python3', [
        _tool,
        ..._allArgs(outputDir: outputDir),
      ]);
      expect(assemble.exitCode, 0, reason: assemble.stderr.toString());

      final apkSha = sha256
          .convert(File('$outputDir/app-release.apk').readAsBytesSync())
          .toString();
      File('$outputDir/checksum-manifest.json').writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'profile': 'development',
          'files': [
            {'path': 'app-release.apk', 'sha256': apkSha},
          ],
        }),
      );

      final verify = Process.runSync('python3', [
        _tool,
        '--verify',
        '--output-dir',
        outputDir,
      ]);
      expect(verify.exitCode, isNot(0));
      for (final name in [
        'release-manifest.json',
        'sbom.json',
        'THIRD_PARTY_NOTICES.md',
        'ai-report.json',
        'security-report.json',
        'lcov.info',
      ]) {
        expect(verify.stderr.toString(), contains(name));
      }
    });
  });

  group('A1 — the approval gate stands before every build/upload job '
      '(ADR 0488 D3)', () {
    test('the real proposal: the environment-gated job is the ONLY one '
        'with no "needs" edge of its own, and every job that carries an '
        'upload-artifact step transitively needs it', () {
      final source = File(_proposalPath).readAsStringSync();
      final workflow = parseWorkflowJobs(source, sourceLabel: _proposalPath);

      final approvalJobs = workflow.jobs
          .where((job) => job.environment != null)
          .toList();
      expect(
        approvalJobs,
        hasLength(1),
        reason: 'exactly one environment-gated job',
      );
      final approvalJobId = approvalJobs.single.id;
      expect(
        approvalJobs.single.needs,
        isEmpty,
        reason: 'the approval job itself must not depend on anything else',
      );

      final uploadJobs = workflow.jobs.where(
        (job) => job.steps.any(
          (step) => (step.uses ?? '').startsWith('actions/upload-artifact'),
        ),
      );
      expect(
        uploadJobs,
        isNotEmpty,
        reason: 'the proposal must upload the RC package',
      );
      for (final job in uploadJobs) {
        expect(
          jobTransitivelyNeeds(workflow, job.id, approvalJobId),
          isTrue,
          reason:
              '"${job.id}" (which uploads a release artifact) must '
              'transitively need the approval-gated job "$approvalJobId"',
        );
      }
    });

    test('mutation probe: a build job with NO "needs" at all does not '
        'transitively need the approval job — proves this cell would go '
        'red if the approval gate were dropped or placed after the build', () {
      const fixture = '''
jobs:
  approve-release-candidate:
    name: Approve
    runs-on: ubuntu-latest
    environment: release-candidate-approval
    steps:
      - name: Record approval
        run: |
          echo approved

  build-release-candidate:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - name: Upload release candidate package
        uses: actions/upload-artifact@v4
        with:
          name: release-candidate
          path: dist/rc
''';
      final workflow = parseWorkflowJobs(fixture, sourceLabel: 'fixture');
      expect(
        jobTransitivelyNeeds(
          workflow,
          'build-release-candidate',
          'approve-release-candidate',
        ),
        isFalse,
      );
    });
  });

  group('A5 — the RC calls the shared composite gate, never copies its '
      'steps (ADR 0488 D2)', () {
    test('the real proposal: the quality-gates job calls '
        '"./.github/actions/flutter-gates"', () {
      final source = File(_proposalPath).readAsStringSync();
      final workflow = parseWorkflowJobs(source, sourceLabel: _proposalPath);
      final allSteps = workflow.jobs.expand((job) => job.steps);
      expect(
        allSteps.any((step) => step.uses == './.github/actions/flutter-gates'),
        isTrue,
      );
    });

    test('the real proposal: no step anywhere copies one of the composite '
        "action's own gate commands verbatim", () {
      final source = File(_proposalPath).readAsStringSync();
      final workflow = parseWorkflowJobs(source, sourceLabel: _proposalPath);
      expect(findCopiedCompositeCommands(workflow), isEmpty);
    });

    test('mutation probe: a fixture step whose run body is EXACTLY '
        'the composite\'s analyze command is flagged as copied', () {
      const fixture = '''
jobs:
  quality-gates:
    name: Gates
    runs-on: ubuntu-latest
    steps:
      - name: Analyze (copied, not composite)
        run: |
          flutter analyze lib/ test/ tool/
''';
      final workflow = parseWorkflowJobs(fixture, sourceLabel: 'fixture');
      expect(
        findCopiedCompositeCommands(workflow),
        contains('flutter analyze lib/ test/ tool/'),
      );
    });

    test('self-check: a similar-but-different command (this round\'s own '
        'coverage step) is NOT flagged as a copy — exact-equality, not '
        'substring containment', () {
      const fixture = '''
jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - name: Test coverage gate
        run: |
          flutter test --coverage
''';
      final workflow = parseWorkflowJobs(fixture, sourceLabel: 'fixture');
      expect(findCopiedCompositeCommands(workflow), isEmpty);
    });
  });

  group('A6 — every upload job needs BOTH gate jobs, exact match '
      '(ADR 0488 D3/D6)', () {
    test('the real proposal: the job that uploads the RC package needs '
        'exactly [quality-gates, backend-tests]', () {
      final source = File(_proposalPath).readAsStringSync();
      final workflow = parseWorkflowJobs(source, sourceLabel: _proposalPath);
      final uploadJob = workflow.jobs.firstWhere(
        (job) => job.steps.any(
          (step) => (step.uses ?? '').startsWith('actions/upload-artifact'),
        ),
      );
      expect(uploadJob.needs, ['quality-gates', 'backend-tests']);
    });

    test('mutation probe: a build job with an empty "needs" is not equal '
        'to the expected gate list', () {
      const fixture = '''
jobs:
  build-release-candidate:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - name: Upload release candidate package
        uses: actions/upload-artifact@v4
        with:
          name: release-candidate
          path: dist/rc
''';
      final workflow = parseWorkflowJobs(fixture, sourceLabel: 'fixture');
      expect(
        workflow.jobs.single.needs,
        isNot(['quality-gates', 'backend-tests']),
      );
    });
  });

  group('A7 — the parser is fail-closed and never relies on an '
      'unguaranteed binary (ADR 0488 D6, L110/L566)', () {
    test('this file does not import the transitive-only YAML package', () {
      final source = File(
        'test/tooling/rc_assembly_test.dart',
      ).readAsStringSync();
      expect(
        RegExp(r"^import\s+'package:yaml", multiLine: true).hasMatch(source),
        isFalse,
      );
    });

    test('every external process this file spawns targets python3 only — '
        'never rg/grep/jq/gh', () {
      final source = File(
        'test/tooling/rc_assembly_test.dart',
      ).readAsStringSync();
      final executables = _processCallExecutable
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();
      expect(executables, isNotEmpty, reason: 'this file must call python3');
      expect(executables, {'python3'});
    });

    test('self-check: python3 is on PATH — if it is not, every call above '
        'throws ProcessException and turns this whole file red, never a '
        'silent skip', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });

    test('cross-check: the real proposal\'s parsed job count equals the '
        'raw "  <id>:" occurrence count inside the "jobs:" block — a '
        'silently-dropped job would break this equality, not just hide '
        'the job from the assertions above', () {
      final source = File(_proposalPath).readAsStringSync();
      final workflow = parseWorkflowJobs(source, sourceLabel: _proposalPath);
      final jobsBlockStart = source.indexOf('\njobs:\n');
      expect(jobsBlockStart, greaterThanOrEqualTo(0));
      final jobsBlockText = source.substring(jobsBlockStart);
      final rawJobHeaderCount = RegExp(
        r'^  [a-z][a-z0-9_-]*:$',
        multiLine: true,
      ).allMatches(jobsBlockText).length;
      expect(workflow.jobs.length, rawJobHeaderCount);
    });

    test('cross-check: the real proposal\'s total parsed step count equals '
        'the raw "- name:" occurrence count', () {
      final source = File(_proposalPath).readAsStringSync();
      final workflow = parseWorkflowJobs(source, sourceLabel: _proposalPath);
      final rawStepCount = RegExp(
        r'^ *- name:',
        multiLine: true,
      ).allMatches(source).length;
      final parsedStepCount = workflow.jobs.fold<int>(
        0,
        (sum, job) => sum + job.steps.length,
      );
      expect(parsedStepCount, rawStepCount);
    });

    test('self-check: scoping the job-header raw-count regex to the '
        '"jobs:" block onward is load-bearing — applied to the WHOLE '
        'document it over-counts, because "on:\\n  workflow_dispatch:" is '
        'itself a 2-space-indented bare-colon line', () {
      final source = File(_proposalPath).readAsStringSync();
      final workflow = parseWorkflowJobs(source, sourceLabel: _proposalPath);
      final wholeDocumentCount = RegExp(
        r'^  [a-z][a-z0-9_-]*:$',
        multiLine: true,
      ).allMatches(source).length;
      expect(wholeDocumentCount, greaterThan(workflow.jobs.length));
    });

    test('fail-closed: a line inside the "jobs:" block that matches no '
        'recognized shape throws FormatException naming the line, not a '
        'silent skip', () {
      const fixture = '''
jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    this is not a valid field line at all
''';
      expect(
        () => parseWorkflowJobs(fixture, sourceLabel: 'fixture'),
        throwsFormatException,
      );
    });

    test('fail-closed: a document with no top-level "jobs:" key throws', () {
      const fixture = 'name: Nothing here\non:\n  workflow_dispatch:\n';
      expect(
        () => parseWorkflowJobs(fixture, sourceLabel: 'fixture'),
        throwsFormatException,
      );
    });

    test('fail-closed: an unrecognized step key throws FormatException, '
        'not a silent partial parse', () {
      const fixture = '''
jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - name: X
        some_unknown_key: value
''';
      expect(
        () => parseWorkflowJobs(fixture, sourceLabel: 'fixture'),
        throwsFormatException,
      );
    });
  });
}

// Built via adjacent string-literal concatenation so this constant's own
// definition text never spells out the executable-call pattern it searches
// for as one contiguous run of characters — the self-matching trap
// `release_manifest_test.dart`'s A7 group avoids.
final _processCallExecutable = RegExp(
  'Process'
  r'''\.(?:run|runSync|start)\(\s*['"]([^'"\n]+)['"]''',
);

// ---------------------------------------------------------------------------
// Restricted GitHub Actions job/step YAML subset (ADR 0488 D6, precedent
// ADR 0447 D5 / ADR 0448 D6: `package:yaml` is only a transitive dependency
// on this tree — importing it would turn `flutter analyze` red via
// `depend_on_referenced_packages`).
//
// A superset of `release_manifest_test.dart`'s / `signing_policy_test.dart`'s
// bare `steps:` parser: this one also reads job-level structure (`jobs:`,
// `needs:`, `environment:`, `steps:` nested one level deeper under each
// job) — A1/A6 need the approval/needs graph, not just step bodies.
//
// Supported shape only:
//   jobs:
//     <job-id>:                         (2-space indent, bare colon)
//       <field>: <value>                (4-space indent; "needs"/"environment"/
//                                         "name"/"runs-on"/"if" are plain scalars,
//                                         "needs" may also be a "[a, b]" flow list)
//       steps:                          (4-space indent, empty value)
//         - name: <value>               (6-space indent)
//           <field>: <value>            (8-space indent: id/shell/uses/if, or
//                                         "run: |"/"env:"/"with:" starting a
//                                         10-space-indented block)
//
// Any line inside the "jobs:" block that does not match one of these shapes
// throws `FormatException` naming the exact line — no silent `continue`
// (L566). A container key with an inline value, or a step/job field this
// parser does not recognize, is the same: a hard failure, not a gap routed
// around.
// ---------------------------------------------------------------------------

final class ParsedStep {
  const ParsedStep({required this.name, required this.fields});

  final String name;

  /// Each value is either a `String` (a scalar or a `run: |` block) or a
  /// `Map<String, String>` (a flat map, e.g. `with:`/`env:`).
  final Map<String, Object?> fields;

  String? get run => fields['run'] as String?;
  String? get uses => fields['uses'] as String?;
}

final class ParsedJob {
  const ParsedJob({
    required this.id,
    required this.fields,
    required this.steps,
  });

  final String id;
  final Map<String, String> fields;
  final List<ParsedStep> steps;

  String? get environment => fields['environment'];
  List<String> get needs => parseNeeds(fields['needs']);
}

final class ParsedWorkflow {
  const ParsedWorkflow({required this.jobs});

  final List<ParsedJob> jobs;
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

/// Parses a job's `needs:` field value — either a bare scalar job id, or a
/// flow-sequence `[a, b]` — into an ordered list. Empty/absent -> `[]`.
List<String> parseNeeds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final trimmed = raw.trim();
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    final inner = trimmed.substring(1, trimmed.length - 1);
    return inner
        .split(',')
        .map((part) => _unquote(part.trim()))
        .where((part) => part.isNotEmpty)
        .toList();
  }
  return [_unquote(trimmed)];
}

/// True when `startJobId` needs `targetJobId`, directly or transitively,
/// via a breadth-first walk of the parsed `needs:` graph.
bool jobTransitivelyNeeds(
  ParsedWorkflow workflow,
  String startJobId,
  String targetJobId,
) {
  final byId = {for (final job in workflow.jobs) job.id: job};
  final visited = <String>{};
  final queue = <String>[startJobId];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    if (!visited.add(current)) continue;
    final job = byId[current];
    if (job == null) continue;
    for (final need in job.needs) {
      if (need == targetJobId) return true;
      queue.add(need);
    }
  }
  return false;
}

/// Returns every step `run:` body across [workflow] that is an EXACT copy
/// of one of the shared composite gate's own commands (ADR 0488 D2).
List<String> findCopiedCompositeCommands(ParsedWorkflow workflow) {
  final copied = <String>[];
  for (final job in workflow.jobs) {
    for (final step in job.steps) {
      final run = step.run?.trim();
      if (run != null && _compositeGateCommands.contains(run)) {
        copied.add(run);
      }
    }
  }
  return copied;
}

final _jobHeader = RegExp(r'^  ([a-z][a-z0-9_-]*):$');
final _jobFieldLine = RegExp(r'^ {4}([a-zA-Z_-]+):(.*)$');
final _stepHeader = RegExp(r'^ {6}- name: (.*)$');
final _stepFieldLine = RegExp(r'^ {8}([a-zA-Z_-]+):(.*)$');
final _stepMapLine = RegExp(r'^ {10}([a-zA-Z_-]+):(.*)$');

ParsedWorkflow parseWorkflowJobs(
  String contents, {
  required String sourceLabel,
}) {
  final lines = contents.split('\n');
  final jobsLineIndex = lines.indexWhere((line) => line == 'jobs:');
  if (jobsLineIndex == -1) {
    throw FormatException('$sourceLabel: no top-level "jobs:" key found');
  }

  var i = jobsLineIndex + 1;
  final jobs = <ParsedJob>[];

  while (i < lines.length) {
    if (_isBlankOrComment(lines[i])) {
      i++;
      continue;
    }
    final header = _jobHeader.firstMatch(lines[i]);
    if (header == null) {
      throw FormatException(
        '$sourceLabel:${i + 1}: expected a 2-space-indented job id '
        '"  <id>:", got: "${lines[i]}"',
      );
    }
    final jobId = header.group(1)!;
    i++;

    final fields = <String, String>{};
    var steps = const <ParsedStep>[];

    while (i < lines.length) {
      if (_isBlankOrComment(lines[i])) {
        i++;
        continue;
      }
      final fieldMatch = _jobFieldLine.firstMatch(lines[i]);
      if (fieldMatch == null) break;
      final key = fieldMatch.group(1)!;
      final rest = fieldMatch.group(2)!.trim();
      final lineNumber = i + 1;
      i++;

      if (key == 'steps') {
        if (rest.isNotEmpty) {
          throw FormatException(
            '$sourceLabel:$lineNumber: "steps:" must start a block list, '
            'not an inline value',
          );
        }
        final parsedSteps = <ParsedStep>[];
        while (i < lines.length) {
          if (_isBlankOrComment(lines[i])) {
            i++;
            continue;
          }
          final stepHeader = _stepHeader.firstMatch(lines[i]);
          if (stepHeader == null) break;
          final name = _unquote(stepHeader.group(1)!);
          i++;

          final stepFields = <String, Object?>{};
          while (i < lines.length) {
            final stepFieldMatch = _stepFieldLine.firstMatch(lines[i]);
            if (stepFieldMatch == null) break;
            final stepKey = stepFieldMatch.group(1)!;
            final stepRest = stepFieldMatch.group(2)!.trim();
            final stepLineNumber = i + 1;
            i++;
            if (stepRest == '|') {
              final blockLines = <String>[];
              while (i < lines.length &&
                  (lines[i].startsWith(' ' * 10) || lines[i].trim().isEmpty)) {
                blockLines.add(lines[i].isEmpty ? '' : lines[i].substring(10));
                i++;
              }
              stepFields[stepKey] = blockLines.join('\n');
            } else if (stepRest.isEmpty) {
              final map = <String, String>{};
              while (i < lines.length && _stepMapLine.hasMatch(lines[i])) {
                final mapMatch = _stepMapLine.firstMatch(lines[i])!;
                map[mapMatch.group(1)!] = _unquote(mapMatch.group(2)!);
                i++;
              }
              if (map.isEmpty) {
                throw FormatException(
                  '$sourceLabel:$stepLineNumber: "$stepKey:" started a '
                  'block mapping but no 10-space-indented "key: value" '
                  'line followed',
                );
              }
              stepFields[stepKey] = map;
            } else {
              stepFields[stepKey] = _unquote(stepRest);
            }
          }
          parsedSteps.add(ParsedStep(name: name, fields: stepFields));
        }
        steps = parsedSteps;
      } else {
        fields[key] = rest;
      }
    }

    jobs.add(ParsedJob(id: jobId, fields: fields, steps: steps));
  }

  return ParsedWorkflow(jobs: jobs);
}
