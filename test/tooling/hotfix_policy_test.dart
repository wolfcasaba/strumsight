// Hotfix path policy gate (E12-R34, ADR 0490).
//
// Follows the `test/tooling/release_manifest_test.dart` (ADR 0447) /
// `test/tooling/signing_policy_test.dart` (ADR 0448) / `rc_assembly_test.dart`
// (ADR 0488) precedent: `python3` is the ONLY external binary this file is
// allowed to invoke (ADR 0490 D7, precedent L110), and A1/A2/A3 delegate to
// `tool/release/verify_hotfix.py` — both its static (`--workflow`) and
// request (`--incident-id`) modes — against BOTH the real tree and synthetic
// fixtures, so a cell is proven red on a broken fixture, not just green on
// the real file (L563).
//
// A6/A7 additionally carry their OWN restricted GitHub Actions job/step YAML
// parser, independent of `verify_hotfix.py`'s internal one, so a bug shared
// between the two would not silently pass both. `package:yaml` is NOT
// imported here (only a transitive dependency on this tree — the
// `depend_on_referenced_packages` lint would turn `flutter analyze` red,
// ADR 0447 D5 / ADR 0448 D6 / ADR 0488 D6 precedent). L566 (fail-OPEN line
// parser): a line inside the `jobs:` block that matches no recognized shape
// throws `FormatException` naming the line — no silent `continue`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _verifyHotfixTool = 'tool/release/verify_hotfix.py';
const _proposalPath = 'docs/release/workflows/hotfix.proposal.yml';
const _runbookPath = 'docs/operations/hotfix-runbook.md';
const _day7Path = 'docs/release/post-launch-day7.md';
const _day14Path = 'docs/release/post-launch-day14.md';

// The shared composite gate's own `run:` command bodies (ADR 0490 D7 — the
// proposal must call the composite, never copy these). Mirrors
// `.github/actions/flutter-gates/action.yml` exactly, same set
// `rc_assembly_test.dart` uses for the RC proposal (both proposals share the
// one composite action).
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

// A5 — mandatory post-launch report fields (round brief §6/§6.1, ADR 0490
// D8): crash, migration, battery, audio, support, checked on BOTH the day7
// and day14 documents.
const _mandatoryReportFields = <String>[
  'crash',
  'migration',
  'battery',
  'audio',
  'support',
];

bool _reportHasMandatoryFields(String text) {
  final lower = text.toLowerCase();
  return _mandatoryReportFields.every((field) => lower.contains(field));
}

// A4 — the runbook must require a regression test alongside every fix: RED
// before the fix, GREEN after (ADR 0490 D4). All four markers must be
// present, case-insensitively, or the requirement reads as optional.
bool _runbookRequiresRegressionCell(String text) {
  final lower = text.toLowerCase();
  return lower.contains('regression') &&
      lower.contains('mandatory') &&
      lower.contains('red') &&
      lower.contains('green');
}

void main() {
  group('A1 — incident_id is a required input, and the empty/missing case '
      'is a non-zero exit in both modes (ADR 0490 D2)', () {
    test('the real proposal: static mode exits 0', () {
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        _proposalPath,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test('request mode: a non-empty incident id with an incrementing '
        'version exits 0', () {
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--incident-id',
        'INC-2026-0001',
        '--previous-version',
        '1.2.3',
        '--version',
        '1.2.4',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test('mutation probe (request mode): an empty --incident-id is a '
        'non-zero exit naming the missing incident id — proves this cell '
        'would catch a verify_hotfix.py that let an empty id through', () {
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--incident-id',
        '',
        '--previous-version',
        '1.2.3',
        '--version',
        '1.2.4',
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('incident-id-required'));
    });

    test('mutation probe (static mode): a fixture whose incident_id input '
        'has no "required: true" is a non-zero exit naming the input', () {
      final fixture = _writeFixture('''
on:
  workflow_dispatch:
    inputs:
      incident_id:
        description: x
        type: string
jobs:
  approve-hotfix:
    name: Approve
    runs-on: ubuntu-latest
    environment: hotfix-approval
    steps:
      - name: Release security scan
        run: |
          echo scan
  build:
    name: Build
    needs: approve-hotfix
    runs-on: ubuntu-latest
    steps:
      - name: Build and sign production APK
        run: |
          echo build
''');
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        fixture.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('incident-id-required'));
      fixture.parent.deleteSync(recursive: true);
    });
  });

  group('A2 — the security-scan and production-signing steps are both '
      'present and unconditional (ADR 0490 D1)', () {
    test('the real proposal: static mode exits 0 (already proven in A1, '
        'restated here for the A2 group)', () {
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        _proposalPath,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test(
      'mutation probe: a fixture where the security-scan step carries '
      '"if: inputs.skip_scan != true" is a non-zero exit naming the step',
      () {
        final fixture = _writeFixture('''
on:
  workflow_dispatch:
    inputs:
      incident_id:
        description: x
        required: true
        type: string
jobs:
  approve-hotfix:
    name: Approve
    runs-on: ubuntu-latest
    environment: hotfix-approval
    steps:
      - name: Record approval
        run: |
          echo approved
  build:
    name: Build
    needs: approve-hotfix
    runs-on: ubuntu-latest
    steps:
      - name: Release security scan
        if: inputs.skip_scan != true
        run: |
          echo scan
      - name: Build and sign production APK
        run: |
          echo build
''');
        final result = Process.runSync('python3', [
          _verifyHotfixTool,
          '--workflow',
          fixture.path,
        ]);
        expect(result.exitCode, isNot(0));
        expect(
          result.stderr.toString(),
          contains('security-scan-unconditional'),
        );
        fixture.parent.deleteSync(recursive: true);
      },
    );

    test('mutation probe: a fixture with no security-scan step at all is a '
        'non-zero exit', () {
      final fixture = _writeFixture('''
on:
  workflow_dispatch:
    inputs:
      incident_id:
        description: x
        required: true
        type: string
jobs:
  approve-hotfix:
    name: Approve
    runs-on: ubuntu-latest
    environment: hotfix-approval
    steps:
      - name: Record approval
        run: |
          echo approved
  build:
    name: Build
    needs: approve-hotfix
    runs-on: ubuntu-latest
    steps:
      - name: Build and sign production APK
        run: |
          echo build
''');
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        fixture.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('security-scan-required'));
      fixture.parent.deleteSync(recursive: true);
    });

    test('mutation probe: a fixture where the production-signing step '
        'carries "continue-on-error: true" is a non-zero exit', () {
      final fixture = _writeFixture('''
on:
  workflow_dispatch:
    inputs:
      incident_id:
        description: x
        required: true
        type: string
jobs:
  approve-hotfix:
    name: Approve
    runs-on: ubuntu-latest
    environment: hotfix-approval
    steps:
      - name: Release security scan
        run: |
          echo scan
  build:
    name: Build
    needs: approve-hotfix
    runs-on: ubuntu-latest
    steps:
      - name: Build and sign production APK
        continue-on-error: true
        run: |
          echo build
''');
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        fixture.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(
        result.stderr.toString(),
        contains('production-signing-unconditional'),
      );
      fixture.parent.deleteSync(recursive: true);
    });

    test('mutation probe: a fixture with no production-signing step at all '
        'is a non-zero exit', () {
      final fixture = _writeFixture('''
on:
  workflow_dispatch:
    inputs:
      incident_id:
        description: x
        required: true
        type: string
jobs:
  approve-hotfix:
    name: Approve
    runs-on: ubuntu-latest
    environment: hotfix-approval
    steps:
      - name: Release security scan
        run: |
          echo scan
  build:
    name: Build
    needs: approve-hotfix
    runs-on: ubuntu-latest
    steps:
      - name: Build the APK
        run: |
          echo build
''');
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        fixture.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('production-signing-required'));
      fixture.parent.deleteSync(recursive: true);
    });

    test('mutation probe: a "skip_scan" workflow_dispatch input is itself a '
        'non-zero exit, even if unused by any step (ADR 0490 D1: no such '
        'switch may exist at all)', () {
      final fixture = _writeFixture('''
on:
  workflow_dispatch:
    inputs:
      incident_id:
        description: x
        required: true
        type: string
      skip_scan:
        description: y
        required: false
        type: boolean
jobs:
  approve-hotfix:
    name: Approve
    runs-on: ubuntu-latest
    environment: hotfix-approval
    steps:
      - name: Release security scan
        run: |
          echo scan
  build:
    name: Build
    needs: approve-hotfix
    runs-on: ubuntu-latest
    steps:
      - name: Build and sign production APK
        run: |
          echo build
''');
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        fixture.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('gate-not-skippable'));
      fixture.parent.deleteSync(recursive: true);
    });

    // Javító kör #1 / MAJOR-1: the same gate-not-skippable, one indent level
    // up. Review kör #1 reproduced this on the REAL proposal (not a minimal
    // synthetic fixture) — a `continue-on-error: true` on the JOB header
    // that CONTAINS the security-scan step slipped past the old step-only
    // check. Mirror that reproduction here so the cell proves the real
    // fixture, not a hand-shrunk stand-in.
    test('mutation probe (job-level, real proposal): "continue-on-error: '
        'true" on the security-scan JOB header (not the step) is a '
        'non-zero exit', () {
      final fixture = _fixtureFromRealProposal(
        '  security-scan:\n'
            '    name: Release security scan\n'
            '    needs: approve-hotfix\n',
        '  security-scan:\n'
            '    name: Release security scan\n'
            '    needs: approve-hotfix\n'
            '    continue-on-error: true\n',
      );
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        fixture.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('security-scan-unconditional'));
      fixture.parent.deleteSync(recursive: true);
    });

    // Javító kör #1 / MAJOR-1: a job-level "if:" using a neutral input name
    // ("fast_track") that does NOT match the skip|emergency name pattern —
    // the old code only inspected step.if_condition, so this slipped past
    // both the name-pattern check (D1's "no skip switch" rule targets input
    // NAMES) and the unconditional check (which never looked at the job).
    test('mutation probe (job-level, real proposal): "if: '
        'inputs.fast_track != true" on the security-scan JOB header, with a '
        'neutrally-named "fast_track" input, is a non-zero exit', () {
      final withInput = _replaceOnce(
        File(_proposalPath).readAsStringSync(),
        '      summary:\n'
            '        description: One-line human summary of the hotfix, for '
            'the approval record.\n'
            '        required: true\n'
            '        type: string\n',
        '      summary:\n'
            '        description: One-line human summary of the hotfix, for '
            'the approval record.\n'
            '        required: true\n'
            '        type: string\n'
            '      fast_track:\n'
            '        description: y\n'
            '        required: false\n'
            '        type: boolean\n',
      );
      final mutated = _replaceOnce(
        withInput,
        '  security-scan:\n'
            '    name: Release security scan\n'
            '    needs: approve-hotfix\n',
        '  security-scan:\n'
            '    name: Release security scan\n'
            '    needs: approve-hotfix\n'
            '    if: inputs.fast_track != true\n',
      );
      final fixture = _writeFixture(mutated);
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        fixture.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('security-scan-unconditional'));
      fixture.parent.deleteSync(recursive: true);
    });

    // Javító kör #1 / MAJOR-2: the step keeps its gate-shaped NAME
    // ("Release security scan") but its "run:" body no longer calls
    // security_scan.py at all — the old code matched on name only, so a
    // decoy body satisfied the whole D1 scan requirement.
    test('mutation probe (real proposal): the security-scan step keeps its '
        'name but its "run:" body is replaced with a decoy echo — non-zero '
        'exit naming the missing content assertion', () {
      final fixture = _fixtureFromRealProposal(
        '          python3 tool/release/security_scan.py --format json > '
            'hotfix-security-report.json\n',
        "          echo 'skipping scan for speed' > "
            'hotfix-security-report.json\n',
      );
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        fixture.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('security-scan-content'));
      fixture.parent.deleteSync(recursive: true);
    });
  });

  group('A3 — version increment is enforced, strictly (ADR 0490 D5, §6.3 '
      'the "rajta" cell)', () {
    test('cell "alatta": previous 1.2.3, version 1.2.2 -> exit 1', () {
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--incident-id',
        'INC-2026-0001',
        '--previous-version',
        '1.2.3',
        '--version',
        '1.2.2',
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('version-strictly-greater'));
    });

    test('cell "rajta": previous 1.2.3, version 1.2.3 -> exit 1 (a >= '
        'implementation would wrongly exit 0 here)', () {
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--incident-id',
        'INC-2026-0001',
        '--previous-version',
        '1.2.3',
        '--version',
        '1.2.3',
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('version-strictly-greater'));
    });

    test('cell "fölötte": previous 1.2.3, version 1.2.4 -> exit 0', () {
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--incident-id',
        'INC-2026-0001',
        '--previous-version',
        '1.2.3',
        '--version',
        '1.2.4',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    // Javító kör #1 / MINOR-1: unequal dotted-integer lengths compared as
    // tuples made "1.2" < "1.2.0" TRUE, so a same-semantic "increment"
    // wrongly passed. The fix pads both tuples to equal length with
    // trailing zeros before comparing.
    test('mutation probe: previous 1.2, version 1.2.0 -> exit 1 (same '
        'semantic version, zero-padded to equal length before comparison)', () {
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--incident-id',
        'INC-2026-0001',
        '--previous-version',
        '1.2',
        '--version',
        '1.2.0',
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('version-strictly-greater'));
    });
  });

  group('A4 — the runbook requires a regression test alongside every fix '
      '(ADR 0490 D4)', () {
    test('the real runbook requires it', () {
      final text = File(_runbookPath).readAsStringSync();
      expect(_runbookRequiresRegressionCell(text), isTrue);
    });

    test('mutation probe: a runbook fixture with no mention of a mandatory '
        'RED/GREEN regression cell fails this check', () {
      const fixture =
          '# Hotfix runbook\n\n'
          'Deploy the fix, then move on to the next incident.\n';
      expect(_runbookRequiresRegressionCell(fixture), isFalse);
    });
  });

  group('A5 — the post-launch reports define the mandatory fields (ADR '
      '0490 D8): crash, migration, battery, audio, support', () {
    test('the real day7 report has all five', () {
      final text = File(_day7Path).readAsStringSync();
      expect(_reportHasMandatoryFields(text), isTrue);
    });

    test('the real day14 report has all five', () {
      final text = File(_day14Path).readAsStringSync();
      expect(_reportHasMandatoryFields(text), isTrue);
    });

    for (final missingField in _mandatoryReportFields) {
      test('mutation probe: a report fixture missing "$missingField" alone '
          'fails this check', () {
        final present = _mandatoryReportFields.where((f) => f != missingField);
        final fixture =
            '# Report\n\n${present.map((f) => '- $f: TBD').join('\n')}\n';
        expect(_reportHasMandatoryFields(fixture), isFalse);
      });
    }
  });

  group('A6 — the approval job stands before every build/sign/upload job '
      '(ADR 0490 D3)', () {
    test('the real proposal: exactly one environment-gated job, and every '
        'job that uploads a release artifact transitively needs it', () {
      final source = File(_proposalPath).readAsStringSync();
      final workflow = parseWorkflowJobs(source, sourceLabel: _proposalPath);

      final approvalJobs = workflow.jobs
          .where((job) => job.environment != null)
          .toList();
      expect(approvalJobs, hasLength(1));
      final approvalJobId = approvalJobs.single.id;
      expect(approvalJobs.single.needs, isEmpty);

      final uploadJobs = workflow.jobs.where(
        (job) => job.steps.any(
          (step) => (step.uses ?? '').startsWith('actions/upload-artifact'),
        ),
      );
      expect(uploadJobs, isNotEmpty);
      for (final job in uploadJobs) {
        expect(
          jobTransitivelyNeeds(workflow, job.id, approvalJobId),
          isTrue,
          reason: '"${job.id}" must transitively need "$approvalJobId"',
        );
      }
    });

    test('mutation probe: a build job with NO "needs" at all does not '
        'transitively need the approval job', () {
      const fixture = '''
jobs:
  approve-hotfix:
    name: Approve
    runs-on: ubuntu-latest
    environment: hotfix-approval
    steps:
      - name: Record approval
        run: |
          echo approved

  build-hotfix:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - name: Upload hotfix package
        uses: actions/upload-artifact@v4
        with:
          name: hotfix
          path: build/hotfix-package
''';
      final workflow = parseWorkflowJobs(fixture, sourceLabel: 'fixture');
      expect(
        jobTransitivelyNeeds(workflow, 'build-hotfix', 'approve-hotfix'),
        isFalse,
      );
    });

    test('mutation probe: two jobs each carrying "environment:" is not '
        'exactly one approval gate', () {
      const fixture = '''
jobs:
  approve-hotfix:
    name: Approve
    runs-on: ubuntu-latest
    environment: hotfix-approval
    steps:
      - name: Record approval
        run: |
          echo approved

  also-gated:
    name: Also gated
    runs-on: ubuntu-latest
    environment: another-environment
    steps:
      - name: Noop
        run: |
          echo noop
''';
      final workflow = parseWorkflowJobs(fixture, sourceLabel: 'fixture');
      final approvalJobs = workflow.jobs.where(
        (job) => job.environment != null,
      );
      expect(approvalJobs, hasLength(2));
      expect(approvalJobs, isNot(hasLength(1)));
    });

    // Javító kör #1 / MAJOR-3: the D3 check used to be a DENYLIST keyed on
    // step-name/`uses:` verbs (build|sign|assembl|upload) — a job whose
    // step names/uses fall outside those four words was silently skipped,
    // "needs:" or not. `verify_hotfix.py` now requires EVERY job other than
    // the approval gate to transitively need it, fail-closed. Reproduced on
    // the real proposal plus a `publish-hotfix` job with a "Publish to Play
    // Store" step and no "needs:" at all — the denylist words never match
    // "publish", so the old check let this straight through.
    test('mutation probe (real proposal, fail-closed): a "publish-hotfix" job '
        'with no "needs:" and a "Publish to Play Store" step is a non-zero '
        'exit even though its step name matches none of the old '
        'build/sign/assemble/upload denylist words', () {
      final mutated =
          '${File(_proposalPath).readAsStringSync()}\n'
          '  publish-hotfix:\n'
          '    name: Publish hotfix\n'
          '    runs-on: ubuntu-latest\n'
          '    steps:\n'
          '      - name: Publish to Play Store\n'
          '        run: |\n'
          '          echo publish\n';
      final fixture = _writeFixture(mutated);
      final result = Process.runSync('python3', [
        _verifyHotfixTool,
        '--workflow',
        fixture.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('approval-gate-transitive'));
      fixture.parent.deleteSync(recursive: true);
    });
  });

  group('A8 — no workflow_dispatch input is interpolated into a "run:" '
      'shell body (ADR 0490 D1/D3 context, GHA script-injection, MAJOR-4)', () {
    test('the real proposal: no step\'s "run:" body contains a literal '
        '"\${{ inputs." — every input reaches the shell only via an "env:" '
        'binding, referenced as a quoted shell variable', () {
      final source = File(_proposalPath).readAsStringSync();
      final workflow = parseWorkflowJobs(source, sourceLabel: _proposalPath);
      final offendingSteps = <String>[];
      for (final job in workflow.jobs) {
        for (final step in job.steps) {
          final run = step.run;
          if (run != null && run.contains(r'${{ inputs.')) {
            offendingSteps.add('${job.id}/${step.name}');
          }
        }
      }
      expect(
        offendingSteps,
        isEmpty,
        reason:
            'GitHub Actions substitutes \${{ }} textually into the shell '
            'script before execution — an input containing a quote and a '
            ';" breaks out of the string. Offending steps: $offendingSteps',
      );
    });

    test('mutation probe: a fixture step whose "run:" body interpolates '
        '"\${{ inputs.version }}" unquoted is caught by the same assertion '
        'this A8 check makes', () {
      const fixture = '''
jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - name: Build and sign production APK
        run: |
          flutter build apk --release --build-name=\${{ inputs.version }}
''';
      final workflow = parseWorkflowJobs(fixture, sourceLabel: 'fixture');
      final run = workflow.jobs.single.steps.single.run!;
      expect(run.contains(r'${{ inputs.'), isTrue);
    });
  });

  group('A7 — the proposal calls the shared composite gate, never copies '
      'its steps (ADR 0490 D7)', () {
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

    test('mutation probe: a fixture step whose run body is EXACTLY the '
        "composite's own analyze command is flagged as copied", () {
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

    test('self-check: a similar-but-different command is NOT flagged — '
        'exact equality, not substring containment', () {
      const fixture = '''
jobs:
  build:
    name: Build
    runs-on: ubuntu-latest
    steps:
      - name: Stage hotfix package
        run: |
          mkdir -p build/hotfix-package
''';
      final workflow = parseWorkflowJobs(fixture, sourceLabel: 'fixture');
      expect(findCopiedCompositeCommands(workflow), isEmpty);
    });
  });

  group('meta — D7 fail-closed guarantees (precedent L110/L566)', () {
    test('this file does not import the transitive-only YAML package', () {
      final source = File(
        'test/tooling/hotfix_policy_test.dart',
      ).readAsStringSync();
      expect(
        RegExp(r"^import\s+'package:yaml", multiLine: true).hasMatch(source),
        isFalse,
      );
    });

    test('every external process this file spawns targets python3 only', () {
      final source = File(
        'test/tooling/hotfix_policy_test.dart',
      ).readAsStringSync();
      final executables = _processCallExecutable
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();
      expect(executables, isNotEmpty);
      expect(executables, {'python3'});
    });

    test('self-check: python3 is on PATH — if not, every call above throws '
        'ProcessException and turns this whole file red, never a silent '
        'skip', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });

    test('fail-closed: a line inside the "jobs:" block that matches no '
        'recognized shape throws FormatException naming the line', () {
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
  });
}

File _writeFixture(String contents) {
  final directory = Directory.systemTemp.createTempSync(
    'strumsight_hotfix_policy_',
  );
  final file = File('${directory.path}/hotfix-fixture.yml');
  file.writeAsStringSync(contents);
  return file;
}

// Javító kör #1 helpers: several MAJOR-1/-2/-3 mutation probes reproduce
// their fixture the same way the review did — take the REAL proposal
// document and apply exactly one textual mutation, rather than a hand-built
// minimal fixture that might not exercise the same job/step structure.
String _replaceOnce(String source, String find, String replace) {
  final index = source.indexOf(find);
  if (index == -1) {
    throw StateError(
      'fixture anchor text not found in the real proposal document — the '
      'proposal changed shape, update this mutation probe: $find',
    );
  }
  return source.replaceRange(index, index + find.length, replace);
}

File _fixtureFromRealProposal(String find, String replace) {
  final source = File(_proposalPath).readAsStringSync();
  return _writeFixture(_replaceOnce(source, find, replace));
}

// Built via adjacent string-literal concatenation so this constant's own
// definition text never spells out the executable-call pattern it searches
// for as one contiguous run of characters (precedent: rc_assembly_test.dart).
final _processCallExecutable = RegExp(
  'Process'
  r'''\.(?:run|runSync|start)\(\s*['"]([^'"\n]+)['"]''',
);

// ---------------------------------------------------------------------------
// Restricted GitHub Actions job/step YAML subset (ADR 0490 D7, precedent
// ADR 0488 D6's `parseWorkflowJobs`). Independent of the parser living
// inside `tool/release/verify_hotfix.py` — a bug shared between the two
// would not silently pass both A6/A7 here and the A1/A2 static checks
// there.
//
// Supported shape only:
//   jobs:
//     <job-id>:                         (2-space indent, bare colon)
//       <field>: <value>                (4-space indent; "needs" may also
//                                         be a "[a, b]" flow list)
//       steps:                          (4-space indent, empty value)
//         - name: <value>               (6-space indent)
//           <field>: <value>            (8-space indent: id/shell/uses/if,
//                                         or "run: |"/"env:"/"with:"
//                                         starting a 10-space-indented block)
//
// Any line inside the "jobs:" block that does not match one of these shapes
// throws `FormatException` naming the exact line — no silent `continue`
// (L566).
// ---------------------------------------------------------------------------

final class ParsedStep {
  const ParsedStep({required this.name, required this.fields});

  final String name;
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
final _stepMapLine = RegExp(r'^ {10}([a-zA-Z0-9_-]+):(.*)$');

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
