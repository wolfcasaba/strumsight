// Closed Beta profile gate (E12-R27, round brief §0.0.1 P2-P6). Follows the
// `test/tooling/rc_assembly_test.dart` / `test/tooling/security_scan_test.dart`
// pattern: a Dart gate test that shells out to `python3
// tool/release/verify_beta_profile.py` against both the real tree and
// synthetic fixtures built in a temp directory (never committed — precedent
// `rc_assembly_test.dart:60-84`).
//
// A5/A6 read `docs/beta/closed-beta-launch.md` directly in Dart (no python
// involved) — the same "the cell measures the document, not the other way
// round" split `rollback_policy_test.dart` uses for
// `disaster-recovery-drill.md`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _tool = 'tool/release/verify_beta_profile.py';
const _profile = 'docs/beta/cohort-profiles.yaml';
const _registry = 'lib/core/feature_flags/feature_flag_registry.dart';
const _launchDoc = 'docs/beta/closed-beta-launch.md';

const _knownHighRiskFlags = [
  'accountEnabled',
  'diagnosticsEnabled',
  'aiTutorCloudEnabled',
  'visionLabCaptureEnabled',
  'communityEnabled',
  'communityWritesEnabled',
  'communityMediaEnabled',
];

ProcessResult _run(List<String> args) =>
    Process.runSync('python3', [_tool, ...args]);

void main() {
  group('self-check — python3 is on PATH', () {
    test('a missing python3 would turn every cell below red, not skip it', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });
  });

  group('A1 — the shipped profile validates against the real registry', () {
    test('exit 0 on the real tree', () {
      final result = _run(['--profile', _profile]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('ok'));
    });

    test('fail-closed: a registry copy truncated to 5 entries is a non-zero '
        'exit naming the expected minimum (§0.0.1 P2)', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'strumsight_beta_registry_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final fullText = File(_registry).readAsStringSync();
      final entryStarts = RegExp(
        r'  FeatureFlagDefinition\(',
      ).allMatches(fullText).toList();
      expect(
        entryStarts.length,
        greaterThanOrEqualTo(40),
        reason: 'sanity: the real registry must have >= 40 entries',
      );
      final cutIndex = entryStarts[5].start;
      final truncated = '${fullText.substring(0, cutIndex)}];\n';
      final registryCopy = File('${tempDir.path}/truncated_registry.dart');
      registryCopy.writeAsStringSync(truncated);

      final result = _run([
        '--profile',
        _profile,
        '--registry',
        registryCopy.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('expected >= 40'));
    });
  });

  group('A2 — an unknown flag name is a non-zero exit', () {
    test('a typo\'d flag key in a temp profile copy fails validation', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'strumsight_beta_profile_a2_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final mangled = File(_profile).readAsStringSync().replaceFirst(
        'accountEnabled: false',
        'accountEnabldTypo: false',
      );
      final profileCopy = File('${tempDir.path}/cohort-profiles.yaml');
      profileCopy.writeAsStringSync(mangled);

      final result = _run(['--profile', profileCopy.path]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('accountEnabldTypo'));
    });
  });

  group(
    'A3 — a high-risk flag defaulting to true in the profile is a '
    'non-zero exit, and the shipped profile keeps all 7 high-risk flags off',
    () {
      test('a temp profile with communityWritesEnabled: true fails', () {
        final tempDir = Directory.systemTemp.createTempSync(
          'strumsight_beta_profile_a3_',
        );
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final mangled = File(_profile).readAsStringSync().replaceFirst(
          'communityWritesEnabled: false',
          'communityWritesEnabled: true',
        );
        final profileCopy = File('${tempDir.path}/cohort-profiles.yaml');
        profileCopy.writeAsStringSync(mangled);

        final result = _run(['--profile', profileCopy.path]);
        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains('communityWritesEnabled'));
      });

      // Secondary backstop only — the primary measurement of "the shipped
      // profile is valid" is the A1 "exit 0 on the real tree" cell above,
      // which runs the tool (i.e. measures PyYAML-parsed truth, not this
      // regex's idea of YAML). This cell is a cheap, tool-independent
      // second signal, so its pattern tolerates whitespace on both sides
      // of the colon (`flag : true` is valid YAML the PyYAML parser would
      // accept, even though the shipped profile doesn't use that style).
      test('the shipped profile never sets any of the 7 known high-risk '
          'flags to true', () {
        final text = File(_profile).readAsStringSync();
        for (final flag in _knownHighRiskFlags) {
          expect(
            RegExp(
              '^\\s*$flag\\s*:\\s*true\\s*\$',
              multiLine: true,
            ).hasMatch(text),
            isFalse,
            reason: '$flag must default to false in every cohort',
          );
        }
      });
    },
  );

  group('A4 — the kill-switch dry-run is read-only, toggles exactly one '
      'flag, and matches the launch doc byte-for-byte', () {
    test('read-only: a temp profile copy is byte-identical after the run, '
        'and no new file is created in its directory', () {
      final tempDir = Directory.systemTemp.createTempSync(
        'strumsight_beta_profile_a4_',
      );
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final originalBytes = File(_profile).readAsBytesSync();
      final profileCopy = File('${tempDir.path}/cohort-profiles.yaml');
      profileCopy.writeAsBytesSync(originalBytes);
      final beforeListing = tempDir.listSync().map((e) => e.path).toSet();

      final result = _run([
        '--profile',
        profileCopy.path,
        '--kill-switch',
        'labModeAvailable',
        '--cohort',
        'closed_beta',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());

      expect(profileCopy.readAsBytesSync(), originalBytes);
      final afterListing = tempDir.listSync().map((e) => e.path).toSet();
      expect(afterListing, beforeListing);
    });

    test('exactly one flag line differs between the before/after blocks', () {
      final result = _run([
        '--profile',
        _profile,
        '--kill-switch',
        'labModeAvailable',
        '--cohort',
        'closed_beta',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final blocks = _extractBeforeAfter(result.stdout.toString());
      final beforeLines = blocks.before.split('\n');
      final afterLines = blocks.after.split('\n');
      expect(afterLines.length, beforeLines.length);
      var diffCount = 0;
      for (var i = 0; i < beforeLines.length; i++) {
        if (beforeLines[i] != afterLines[i]) diffCount++;
      }
      expect(diffCount, 1);
      expect(blocks.before, contains('labModeAvailable: true'));
      expect(blocks.after, contains('labModeAvailable: false'));
    });

    test('unknown --cohort / --kill-switch flag is a non-zero exit', () {
      final badCohort = _run([
        '--profile',
        _profile,
        '--kill-switch',
        'labModeAvailable',
        '--cohort',
        'no_such_cohort',
      ]);
      expect(badCohort.exitCode, isNot(0));

      final badFlag = _run([
        '--profile',
        _profile,
        '--kill-switch',
        'noSuchFlag',
        '--cohort',
        'closed_beta',
      ]);
      expect(badFlag.exitCode, isNot(0));
    });

    test('the launch doc\'s embedded dry-run block is byte-identical (mod '
        'surrounding whitespace) to a fresh run of the tool on the shipped '
        'profile', () {
      final freshRun = _run([
        '--profile',
        _profile,
        '--kill-switch',
        'labModeAvailable',
        '--cohort',
        'closed_beta',
      ]);
      expect(freshRun.exitCode, 0, reason: freshRun.stderr.toString());

      final docText = File(_launchDoc).readAsStringSync();
      final embedded = _extractFencedBlock(
        docText,
        beginMarker: '<!-- beta-kill-switch-dry-run:begin -->',
        endMarker: '<!-- beta-kill-switch-dry-run:end -->',
      );
      expect(embedded.trim(), freshRun.stdout.toString().trim());
    });
  });

  group('A5 — every launch-checklist line carries a reference, and every '
      'repo-relative path referenced actually exists', () {
    test('the real document has no unreferenced or dangling-reference '
        'checklist lines', () {
      final text = File(_launchDoc).readAsStringSync();
      final problems = findChecklistReferenceProblems(text);
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('sanity: the checklist has non-trivial coverage (>= 8 items)', () {
      final text = File(_launchDoc).readAsStringSync();
      final items = RegExp(
        r'^- \[ \] ',
        multiLine: true,
      ).allMatches(text).length;
      expect(items, greaterThanOrEqualTo(8));
    });

    test('mutation probe: a checklist line with no backtick reference and '
        'no URL is flagged', () {
      const fixture = '''
## Checklist

- [ ] This line has no reference at all.
''';
      final problems = findChecklistReferenceProblems(fixture);
      expect(problems, isNotEmpty);
    });

    test('mutation probe: a checklist line referencing a non-existent '
        'repo-relative path is flagged', () {
      const fixture = '''
## Checklist

- [ ] See `docs/beta/this-file-does-not-exist.md` for details.
''';
      final problems = findChecklistReferenceProblems(fixture);
      expect(problems, isNotEmpty);
    });

    test('mutation probe: a checklist line referencing a real path is NOT '
        'flagged', () {
      final fixture =
          '''
## Checklist

- [ ] See `$_profile` for details.
''';
      final problems = findChecklistReferenceProblems(fixture);
      expect(problems, isEmpty);
    });

    test('mutation probe: a CHECKED (- [x]) line referencing a '
        'non-existent repo-relative path is flagged (fail-open guard, '
        'L566)', () {
      const fixture = '''
## Checklist

- [x] See `docs/beta/NOPE-does-not-exist.md` for details.
''';
      final problems = findChecklistReferenceProblems(fixture);
      expect(problems, isNotEmpty);
    });

    test('mutation probe: a CHECKED (- [x]) line referencing a real path '
        'is NOT flagged', () {
      final fixture =
          '''
## Checklist

- [x] See `$_profile` for details.
''';
      final problems = findChecklistReferenceProblems(fixture);
      expect(problems, isEmpty);
    });
  });

  group('A6 — the document states the beta has NOT launched and launching '
      'is a human decision', () {
    test('the real document carries the required framing and no past-tense '
        'launch claim', () {
      final text = File(_launchDoc).readAsStringSync();
      final lower = text.toLowerCase();

      expect(lower, contains('has not launched'));
      expect(lower, contains('human decision'));

      const bannedPhrases = [
        'the beta has launched',
        'beta launched',
        'testers invited',
        'testers have been invited',
        'cohort opened',
        'cohort has been opened',
        'a béta elindult',
        'tesztelők meghívva',
      ];
      for (final phrase in bannedPhrases) {
        expect(
          lower,
          isNot(contains(phrase)),
          reason: 'past-tense launch claim found: "$phrase"',
        );
      }
    });
  });
}

// ---------------------------------------------------------------------------
// A4 helper — extracts the "before:"/"after:" flag blocks from the tool's
// own stdout shape (see verify_beta_profile.py's run_kill_switch()).
// ---------------------------------------------------------------------------

class _BeforeAfter {
  const _BeforeAfter(this.before, this.after);
  final String before;
  final String after;
}

_BeforeAfter _extractBeforeAfter(String stdout) {
  final beforeIndex = stdout.indexOf('before:\n');
  final afterIndex = stdout.indexOf('after:\n');
  if (beforeIndex == -1 || afterIndex == -1 || afterIndex < beforeIndex) {
    throw FormatException('stdout has no recognizable before:/after: blocks');
  }
  final before = stdout
      .substring(beforeIndex + 'before:\n'.length, afterIndex)
      .trim();
  final after = stdout.substring(afterIndex + 'after:\n'.length).trim();
  return _BeforeAfter(before, after);
}

// ---------------------------------------------------------------------------
// A4 helper — extracts the text between two exact marker lines, then the
// fenced ```text ... ``` block inside it.
// ---------------------------------------------------------------------------

String _extractFencedBlock(
  String text, {
  required String beginMarker,
  required String endMarker,
}) {
  final beginIndex = text.indexOf(beginMarker);
  final endIndex = text.indexOf(endMarker);
  if (beginIndex == -1 || endIndex == -1 || endIndex < beginIndex) {
    throw FormatException('markers $beginMarker / $endMarker not found');
  }
  final between = text.substring(beginIndex + beginMarker.length, endIndex);
  final fenceMatch = RegExp(
    r'```text\n(.*?)\n```',
    dotAll: true,
  ).firstMatch(between);
  if (fenceMatch == null) {
    throw FormatException('no ```text fenced block between the markers');
  }
  return fenceMatch.group(1)!;
}

// ---------------------------------------------------------------------------
// A5 helper — every "- [ ] ..." OR "- [x] ..." checklist item must carry a
// recognized reference: a backtick-quoted repo-relative path that exists, or
// a bare http(s) URL. A backtick span containing whitespace (a command
// example, e.g. `python3 tool/... --flag`) is not treated as a path
// candidate and is not checked for existence, but also does not count as
// the item's reference on its own. Fail-closed (L566): an item with none of
// the above is a problem, never a silently-accepted gap — including a
// CHECKED item, which is exactly when the guard matters most (a human just
// ticked the box, trusting the reference behind it still resolves).
//
// An item may wrap across multiple physical lines — a bullet line followed
// by 6-space-indented continuation lines (this doc's own wrapping style,
// aligned under "- [ ] " / "- [x] ") — so the item is first reassembled
// into one logical string before reference extraction runs.
// ---------------------------------------------------------------------------

List<String> _splitChecklistItems(String text) {
  final bulletStart = RegExp(r'^- \[[ xX]\] (.*)$');
  final items = <String>[];
  StringBuffer? current;

  for (final line in text.split('\n')) {
    final bulletMatch = bulletStart.firstMatch(line);
    if (bulletMatch != null) {
      if (current != null) items.add(current.toString());
      current = StringBuffer(bulletMatch.group(1)!);
      continue;
    }
    if (current != null &&
        line.startsWith('      ') &&
        line.trim().isNotEmpty) {
      current.write(' ${line.trim()}');
      continue;
    }
    if (current != null) {
      items.add(current.toString());
      current = null;
    }
  }
  if (current != null) items.add(current.toString());
  return items;
}

List<String> findChecklistReferenceProblems(String text) {
  final problems = <String>[];
  final backtick = RegExp(r'`([^`]+)`');
  final url = RegExp(r'https?://\S+');

  for (final item in _splitChecklistItems(text)) {
    var hasReference = false;
    var hasDanglingPath = false;

    for (final span in backtick.allMatches(item)) {
      final candidate = span.group(1)!;
      final looksLikePath =
          !candidate.contains(' ') &&
          !candidate.startsWith('--') &&
          candidate.contains('/');
      if (!looksLikePath) continue;
      final exists =
          File(candidate).existsSync() || Directory(candidate).existsSync();
      if (exists) {
        hasReference = true;
      } else {
        hasDanglingPath = true;
      }
    }
    if (url.hasMatch(item)) hasReference = true;

    if (hasDanglingPath) {
      problems.add('dangling path reference: $item');
    } else if (!hasReference) {
      problems.add('no recognized reference: $item');
    }
  }
  return problems;
}
