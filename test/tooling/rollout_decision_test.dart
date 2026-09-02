// Staged rollout decision-packet gate (E12-R32). Follows the
// `test/tooling/freeze_policy_test.dart` pattern: a Dart gate test that
// shells out to `python3 tool/release/verify_rollout_decision.py` against
// both the real tree and synthetic TEMP fixtures (never committed) — the
// shipped `docs/release/rollout-decision.md` /
// `docs/release/staged-rollout-log.md` are never mutated by any cell here.
//
// A1 = a missing mandatory cell (window/mutató/döntéshozó) is a non-zero
// exit. A2 = an `approved` decision while `blockers.md` has an open P0/P1
// row is a non-zero exit — read against the REAL `blockers.md` (round brief
// §6.1 valódi-sértés próba). A3 = every observation row carries a
// `machine`/`manual` source tag. A4 = the shipped log skeleton carries all
// three steps with a rollback_target column (document sanity, no tool
// invocation). A5 = the schema states the percentage is a human operation.
// A6 (the sibling `freeze_policy_test.dart` staying green) is asserted by
// the round's own `tools/round-gate.sh` invocation, not by a cell here. A7 =
// the `cohort` cell carries exactly one dimension — a two-dimension
// (intersection) cell is a non-zero exit. A8 = the bare call (no flags)
// against the shipped tree is exit 0 and evaluates every rule. A9 = all
// four marker-block parsers (human-gate, rollout-steps, rollout-decisions,
// rollout-observations) are fail-closed (L566/L571/L573/L575). The
// `23`/`24`/`25` threshold triple proves the `min_observation_hours` bound
// is inclusive, not a strict `>`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _tool = 'tool/release/verify_rollout_decision.py';
const _decisionDoc = 'docs/release/rollout-decision.md';
const _logDoc = 'docs/release/staged-rollout-log.md';

ProcessResult _run(List<String> args) =>
    Process.runSync('python3', [_tool, ...args]);

Directory _tempDir() =>
    Directory.systemTemp.createTempSync('strumsight_rollout_decision_');

File _writeIn(Directory dir, String name, String contents) =>
    File('${dir.path}/$name')..writeAsStringSync(contents);

const _cleanBlockers =
    '| ID | Severity | Cím |\n'
    '|---|---|---|\n'
    '| R-TEST-01 | P2 | fixture-only, no open P0/P1 |\n';

String _decisionsBlock(String stage1Row) =>
    '<!-- rollout-decisions:begin -->\n'
    '| step | window_start | window_end | observed_hours | decision | decision_maker | rollback_target |\n'
    '|---|---|---|---|---|---|---|\n'
    '$stage1Row\n'
    '| `stage-5` | TBD | TBD | TBD | `pending` | TBD | TBD |\n'
    '| `stage-20` | TBD | TBD | TBD | `pending` | TBD | TBD |\n'
    '<!-- rollout-decisions:end -->\n';

String _observationRow(String step, String cohort, String verdict) =>
    '| `$step` | `chord_detection_latency_p95` | `$cohort` | `manual` | `$verdict` | ${verdict == 'unknown' ? 'n/a' : '1200ms'} |\n'
    '| `$step` | `tuner_pitch_accuracy` | `$cohort` | `manual` | `$verdict` | ${verdict == 'unknown' ? 'n/a' : '99%'} |\n'
    '| `$step` | `offline_egress_free` | `$cohort` | `manual` | `$verdict` | ${verdict == 'unknown' ? 'n/a' : '100%'} |\n'
    '| `$step` | `crash_free_sessions` | `$cohort` | `manual` | `$verdict` | ${verdict == 'unknown' ? 'n/a' : '99.8%'} |\n'
    '| `$step` | `tutor_turn_success_rate` | `$cohort` | `manual` | `$verdict` | ${verdict == 'unknown' ? 'n/a' : '97%'} |\n';

String _observationsBlock({
  String stage1Cohort = 'all',
  String stage1Verdict = 'unknown',
}) =>
    '<!-- rollout-observations:begin -->\n'
    '| step | metric | cohort | source | verdict | measured_value |\n'
    '|---|---|---|---|---|---|\n'
    '${_observationRow('stage-1', stage1Cohort, stage1Verdict)}'
    '${_observationRow('stage-5', 'all', 'unknown')}'
    '${_observationRow('stage-20', 'all', 'unknown')}'
    '<!-- rollout-observations:end -->\n';

/// A clean, self-contained fixture pair (decision.md + log.md) with a
/// `stage-1` row the caller controls — used by cells that need an
/// `approved`/threshold scenario isolated from the shipped tree's own
/// `pending`-only skeleton.
({File decision, File log}) _cleanFixture(
  Directory dir, {
  required String stage1DecisionRow,
  String stage1Cohort = 'all',
  String stage1Verdict = 'success',
}) {
  final decision = _writeIn(dir, 'rollout-decision.md', '''
<!-- human-gate:begin -->
A rollout-százalék állítása EMBERI művelet.
<!-- human-gate:end -->

<!-- rollout-steps:begin -->
| step | rollout_percent | min_observation_hours |
|---|---|---|
| `stage-1` | 1 | 24 |
| `stage-5` | 5 | 48 |
| `stage-20` | 20 | 72 |
<!-- rollout-steps:end -->
''');
  final log = _writeIn(
    dir,
    'staged-rollout-log.md',
    '${_decisionsBlock(stage1DecisionRow)}\n'
        '${_observationsBlock(stage1Cohort: stage1Cohort, stage1Verdict: stage1Verdict)}',
  );
  return (decision: decision, log: log);
}

void main() {
  group('self-check — python3 is on PATH', () {
    test('a missing python3 would turn every cell below red, not skip it', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });
  });

  group('sanity — the shipped documents validate against the real tree', () {
    test('bare call (no flags) on the shipped tree is exit 0 (A8)', () {
      final result = _run([]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('ok'));
      expect(result.stdout.toString(), contains('3 decision row(s)'));
      expect(result.stdout.toString(), contains('15 observation row(s)'));
    });

    test('--log pointed at the shipped log explicitly still validates '
        'against the real decision/blockers/slo defaults (A8 — the bare '
        'call does not silently skip a rule)', () {
      final result = _run(['--log', _logDoc]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });
  });

  group('A4 — the shipped log skeleton carries all three steps with a '
      'rollback_target column', () {
    test('sanity, tool-independent', () {
      final text = File(_logDoc).readAsStringSync();
      expect(text, contains('rollback_target'));
      expect(text, contains('`stage-1`'));
      expect(text, contains('`stage-5`'));
      expect(text, contains('`stage-20`'));
    });
  });

  group('A5 — the schema states the percentage is a human operation', () {
    test('the shipped human-gate block carries the literal sentence '
        '(sanity, tool-independent)', () {
      final text = File(_decisionDoc).readAsStringSync();
      expect(text, contains('A rollout-százalék állítása EMBERI művelet.'));
    });

    test('a human-gate block missing the literal sentence is a non-zero '
        'exit', () {
      final text = File(_decisionDoc).readAsStringSync();
      const original = 'A rollout-százalék állítása EMBERI művelet.';
      const mangled = 'A rollout-százalék állítását bárki állíthatja.';
      expect(text, contains(original));
      final mangledText = text.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'rollout-decision.md', mangledText);

      final result = _run(['--decision', file.path]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('EMBERI'));
    });
  });

  group('A1 — a missing mandatory cell is a non-zero exit', () {
    test('an empty decision_maker cell in an otherwise-valid row is a '
        'non-zero exit', () {
      final text = File(_logDoc).readAsStringSync();
      const original =
          '| `stage-1` | TBD | TBD | TBD | `pending` | TBD | TBD |';
      const mangled = '| `stage-1` | TBD | TBD | TBD | `pending` |  | TBD |';
      expect(text, contains(original));
      final mangledText = text.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'staged-rollout-log.md', mangledText);

      final result = _run(['--log', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('empty cell'));
    });

    test('an empty metric cell in an observation row is a non-zero exit', () {
      final text = File(_logDoc).readAsStringSync();
      const original =
          '| `stage-1` | `chord_detection_latency_p95` | `all` | `manual` | `unknown` | n/a |';
      const mangled = '| `stage-1` |  | `all` | `manual` | `unknown` | n/a |';
      expect(text, contains(original));
      final mangledText = text.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'staged-rollout-log.md', mangledText);

      final result = _run(['--log', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains('empty cell'));
    });
  });

  group('A2 — an approved decision while blockers.md has an open P0/P1 row '
      'is a non-zero exit (§6.1 valódi-sértés próba: read against the REAL '
      'blockers.md, never a fixture copy, in this group)', () {
    test('a clean, otherwise-valid approved stage-1 row is rejected because '
        'the REAL blockers.md has open P0/P1 rows today', () {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final fixture = _cleanFixture(
        dir,
        stage1DecisionRow:
            '| `stage-1` | 2026-09-01T00:00Z | 2026-09-02T00:00Z | 30 | '
            '`approved` | Alice | build-42 |',
      );

      // --blockers is NOT overridden — this run reads the real
      // docs/release/blockers.md, which today carries R-SIGN-01 (P0) and
      // five P1 rows (docs/release/blockers.md "Miért pont ezek").
      final result = _run([
        '--decision',
        fixture.decision.path,
        '--log',
        fixture.log.path,
      ]);
      expect(result.exitCode, 1, reason: result.stderr.toString());
      expect(result.stderr.toString(), contains('open P0/P1'));
    });

    test('the same fixture with a clean (no open P0/P1) --blockers override '
        'is accepted (isolates R5 from the other approved-decision rules)', () {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final fixture = _cleanFixture(
        dir,
        stage1DecisionRow:
            '| `stage-1` | 2026-09-01T00:00Z | 2026-09-02T00:00Z | 30 | '
            '`approved` | Alice | build-42 |',
      );
      final blockers = _writeIn(dir, 'blockers.md', _cleanBlockers);

      final result = _run([
        '--decision',
        fixture.decision.path,
        '--log',
        fixture.log.path,
        '--blockers',
        blockers.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });
  });

  group('A3 — every observation row carries a machine/manual source tag', () {
    test('a source value outside {machine, manual} is a non-zero exit', () {
      final text = File(_logDoc).readAsStringSync();
      const original =
          '| `stage-1` | `chord_detection_latency_p95` | `all` | `manual` | `unknown` | n/a |';
      const mangled =
          '| `stage-1` | `chord_detection_latency_p95` | `all` | `cloud` | `unknown` | n/a |';
      expect(text, contains(original));
      final mangledText = text.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'staged-rollout-log.md', mangledText);

      final result = _run(['--log', file.path]);
      expect(result.exitCode, 1);
      expect(result.stderr.toString(), contains("'cloud'"));
    });
  });

  group('A7 — the cohort cell carries exactly one dimension (§0.0.1 P7)', () {
    test('a two-dimension (intersection) cohort cell is a non-zero exit', () {
      final text = File(_logDoc).readAsStringSync();
      const original =
          '| `stage-1` | `chord_detection_latency_p95` | `all` | `manual` | `unknown` | n/a |';
      const mangled =
          '| `stage-1` | `chord_detection_latency_p95` | `platform:android,build_mode:release` | `manual` | `unknown` | n/a |';
      expect(text, contains(original));
      final mangledText = text.replaceFirst(original, mangled);
      final fixture = _tempDir();
      addTearDown(() => fixture.deleteSync(recursive: true));
      final file = _writeIn(fixture, 'staged-rollout-log.md', mangledText);

      final result = _run(['--log', file.path]);
      expect(result.exitCode, 1);
      expect(
        result.stderr.toString(),
        contains('not exactly one known dimension'),
      );
    });

    test('a single, valid dimension cohort (platform:android) is accepted '
        '(isolates R4 from the other approved-decision rules)', () {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final fixture = _cleanFixture(
        dir,
        stage1DecisionRow:
            '| `stage-1` | TBD | TBD | TBD | `pending` | TBD | TBD |',
        stage1Cohort: 'platform:android',
        stage1Verdict: 'unknown',
      );
      final blockers = _writeIn(dir, 'blockers.md', _cleanBlockers);

      final result = _run([
        '--decision',
        fixture.decision.path,
        '--log',
        fixture.log.path,
        '--blockers',
        blockers.path,
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });
  });

  group('threshold triple — min_observation_hours is an INCLUSIVE bound, '
      'not a strict ">" (round brief §6, stage-1 W = 24)', () {
    ProcessResult runWithHours(String observedHours) {
      final dir = _tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final fixture = _cleanFixture(
        dir,
        stage1DecisionRow:
            '| `stage-1` | 2026-09-01T00:00Z | 2026-09-02T00:00Z | '
            '$observedHours | `approved` | Alice | build-42 |',
      );
      final blockers = _writeIn(dir, 'blockers.md', _cleanBlockers);
      return _run([
        '--decision',
        fixture.decision.path,
        '--log',
        fixture.log.path,
        '--blockers',
        blockers.path,
      ]);
    }

    test('23h (below the 24h threshold) is a non-zero exit naming the step '
        'and the 24h threshold', () {
      final result = runWithHours('23');
      expect(result.exitCode, 1, reason: result.stderr.toString());
      expect(result.stderr.toString(), contains('stage-1'));
      expect(result.stderr.toString(), contains('24'));
    });

    test('24h (exactly on the threshold) is exit 0 — the inclusive bound', () {
      final result = runWithHours('24');
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test('25h (above the threshold) is exit 0', () {
      final result = runWithHours('25');
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });
  });

  group('A9 — all four marker-block parsers are fail-closed '
      '(L566/L571/L573/L575)', () {
    group('rollout-decision.md', () {
      test('a missing human-gate marker block is exit 2', () {
        final text = File(_decisionDoc).readAsStringSync();
        final mangled = text
            .replaceFirst('<!-- human-gate:begin -->', '')
            .replaceFirst('<!-- human-gate:end -->', '');
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'rollout-decision.md', mangled);

        final result = _run(['--decision', file.path]);
        expect(result.exitCode, 2);
      });

      test('an empty rollout-steps block is exit 2', () {
        final text = File(_decisionDoc).readAsStringSync();
        final beginIndex = text.indexOf('<!-- rollout-steps:begin -->');
        final endIndex = text.indexOf('<!-- rollout-steps:end -->');
        expect(beginIndex, greaterThan(-1));
        expect(endIndex, greaterThan(beginIndex));
        final mangled = text.replaceRange(
          beginIndex + '<!-- rollout-steps:begin -->'.length,
          endIndex,
          '\n',
        );
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'rollout-decision.md', mangled);

        final result = _run(['--decision', file.path]);
        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('empty'));
      });

      test('a malformed rollout-steps row (broken backtick shape) is exit '
          '2', () {
        final text = File(_decisionDoc).readAsStringSync();
        const original = '| `stage-1` | 1 | 24 |';
        const mangled = '| stage-1 | 1 | 24 |';
        expect(text, contains(original));
        final mangledText = text.replaceFirst(original, mangled);
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'rollout-decision.md', mangledText);

        final result = _run(['--decision', file.path]);
        expect(result.exitCode, 2);
        expect(
          result.stderr.toString(),
          contains('does not match the expected shape'),
        );
      });

      test('a rollout-steps table missing a declared step is exit 2', () {
        final text = File(_decisionDoc).readAsStringSync();
        const original = '| `stage-20` | 20 | 72 |\n';
        expect(text, contains(original));
        final mangledText = text.replaceFirst(original, '');
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'rollout-decision.md', mangledText);

        final result = _run(['--decision', file.path]);
        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('stage-20'));
      });
    });

    group('staged-rollout-log.md', () {
      test('a missing rollout-decisions marker block is exit 2', () {
        final text = File(_logDoc).readAsStringSync();
        final mangled = text
            .replaceFirst('<!-- rollout-decisions:begin -->', '')
            .replaceFirst('<!-- rollout-decisions:end -->', '');
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'staged-rollout-log.md', mangled);

        final result = _run(['--log', file.path]);
        expect(result.exitCode, 2);
      });

      test('an empty rollout-observations block is exit 2', () {
        final text = File(_logDoc).readAsStringSync();
        final beginIndex = text.indexOf('<!-- rollout-observations:begin -->');
        final endIndex = text.indexOf('<!-- rollout-observations:end -->');
        expect(beginIndex, greaterThan(-1));
        expect(endIndex, greaterThan(beginIndex));
        final mangled = text.replaceRange(
          beginIndex + '<!-- rollout-observations:begin -->'.length,
          endIndex,
          '\n',
        );
        expect(mangled, isNot(text));
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'staged-rollout-log.md', mangled);

        final result = _run(['--log', file.path]);
        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('empty'));
      });

      test('a malformed decisions row (missing a column) is exit 2', () {
        final text = File(_logDoc).readAsStringSync();
        const original =
            '| `stage-1` | TBD | TBD | TBD | `pending` | TBD | TBD |';
        const mangled = '| `stage-1` | TBD | TBD | TBD | `pending` | TBD |';
        expect(text, contains(original));
        final mangledText = text.replaceFirst(original, mangled);
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'staged-rollout-log.md', mangledText);

        final result = _run(['--log', file.path]);
        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('expected 7 columns'));
      });

      test('a malformed observations row (extra column) is exit 2', () {
        final text = File(_logDoc).readAsStringSync();
        const original =
            '| `stage-1` | `chord_detection_latency_p95` | `all` | `manual` | `unknown` | n/a |';
        const mangled =
            '| `stage-1` | `chord_detection_latency_p95` | `all` | `manual` | `unknown` | n/a | extra |';
        expect(text, contains(original));
        final mangledText = text.replaceFirst(original, mangled);
        final fixture = _tempDir();
        addTearDown(() => fixture.deleteSync(recursive: true));
        final file = _writeIn(fixture, 'staged-rollout-log.md', mangledText);

        final result = _run(['--log', file.path]);
        expect(result.exitCode, 2);
        expect(result.stderr.toString(), contains('expected 6 columns'));
      });
    });
  });

  group('usage errors (exit 2) — missing files', () {
    test('a missing --decision path is exit 2', () {
      final result = _run([
        '--decision',
        'docs/release/this-file-does-not-exist.md',
      ]);
      expect(result.exitCode, 2);
    });

    test('a missing --log path is exit 2', () {
      final result = _run([
        '--log',
        'docs/release/this-file-does-not-exist.md',
      ]);
      expect(result.exitCode, 2);
    });

    test('a missing --blockers path is exit 2', () {
      final result = _run([
        '--blockers',
        'docs/release/this-file-does-not-exist.md',
      ]);
      expect(result.exitCode, 2);
    });

    test('a missing --slo path is exit 2', () {
      final result = _run([
        '--slo',
        'docs/operations/this-file-does-not-exist.yaml',
      ]);
      expect(result.exitCode, 2);
    });
  });
}
