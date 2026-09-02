// GA-scope consistency gate (E12-R28, ADR 0489). Follows the
// `test/tooling/beta_profile_test.dart` / `test/tooling/rc_assembly_test.dart`
// pattern: a Dart gate test that shells out to `python3
// tool/release/verify_ga_scope.py` against both the real tree and synthetic
// fixtures built from temp-dir copies (never committed).
//
// A1 = D1 (closed capability set, exactly one classification each), A2 = D4
// (disabled <=> false in every cohort — the brief §6.1 "valódi-sértés próba"
// lives in this group), A3 = D5 (a core-path-required capability must be
// `ga`), A4 = D6 (every frozen contract carries a named, non-banned
// resolution condition), A5 = D7 (an open P0/P1 blocker forces an explicit
// NOT-READY header).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _tool = 'tool/release/verify_ga_scope.py';
const _scope = 'docs/release/ga-scope.md';
const _profile = 'docs/beta/cohort-profiles.yaml';
const _contractFreeze = 'docs/release/contract-freeze.md';
const _blockers = 'docs/release/blockers.md';

ProcessResult _run(List<String> args) =>
    Process.runSync('python3', [_tool, ...args]);

/// Writes [contents] to a fresh file inside a fresh temp dir and returns
/// both so callers can `addTearDown` the directory.
({Directory dir, File file}) _tempCopy(String name, String contents) {
  final dir = Directory.systemTemp.createTempSync('strumsight_ga_scope_');
  final file = File('${dir.path}/$name')..writeAsStringSync(contents);
  return (dir: dir, file: file);
}

void main() {
  group('self-check — python3 is on PATH', () {
    test('a missing python3 would turn every cell below red, not skip it', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });
  });

  group('sanity — the shipped documents validate against the real tree', () {
    test('exit 0 on the real tree', () {
      final result = _run(['--scope', _scope, '--profile', _profile]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout.toString(), contains('ok'));
    });

    test('the shipped ga-scope.md classifies exactly the 16 cohort-profile '
        'flag keys, no more, no fewer', () {
      final scopeText = File(_scope).readAsStringSync();
      final rows = RegExp(
        r'^\| `[a-zA-Z0-9]+` \| `(ga|preview|disabled|postponed)` \|',
        multiLine: true,
      ).allMatches(scopeText).length;
      expect(rows, 16);
    });
  });

  group('A1 — the closed capability set (D1): every cohort-profile flag key '
      'gets exactly one classification', () {
    test('a duplicated classification row is a non-zero exit naming the key '
        '(§6.1: a capability gets two classifications)', () {
      final scopeText = File(_scope).readAsStringSync();
      const marker =
          '| `accountEnabled` | `disabled` | `false` | '
          '`lib/core/feature_flags/feature_flag_registry.dart` |';
      expect(scopeText, contains(marker));
      final duplicateLineEnd = scopeText.indexOf(
        '\n',
        scopeText.indexOf(marker),
      );
      final duplicatedLine = scopeText.substring(
        scopeText.indexOf(marker),
        duplicateLineEnd,
      );
      final mangled = scopeText.replaceFirst(
        '$duplicatedLine\n',
        '$duplicatedLine\n$duplicatedLine\n',
      );
      final fixture = _tempCopy('ga-scope.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final result = _run([
        '--scope',
        fixture.file.path,
        '--profile',
        _profile,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('accountEnabled'));
      expect(result.stderr.toString(), contains('more than once'));
    });

    test('a missing classification row is a non-zero exit naming the key '
        '(§6.1: a capability stays without a classification)', () {
      final scopeText = File(_scope).readAsStringSync();
      final lines = scopeText.split('\n');
      final withoutAdaptiveShell = lines
          .where((line) => !line.contains('`adaptiveShellEnabled`'))
          .join('\n');
      expect(withoutAdaptiveShell, isNot(contains('adaptiveShellEnabled')));

      final fixture = _tempCopy('ga-scope.md', withoutAdaptiveShell);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final result = _run([
        '--scope',
        fixture.file.path,
        '--profile',
        _profile,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('adaptiveShellEnabled'));
      expect(result.stderr.toString(), contains('no classification row'));
    });

    test(
      'an unknown classification value is a non-zero exit (D2 closed set)',
      () {
        final scopeText = File(_scope).readAsStringSync();
        final mangled = scopeText.replaceFirst(
          '| `accountEnabled` | `disabled` |',
          '| `accountEnabled` | `retired` |',
        );
        final fixture = _tempCopy('ga-scope.md', mangled);
        addTearDown(() => fixture.dir.deleteSync(recursive: true));

        final result = _run([
          '--scope',
          fixture.file.path,
          '--profile',
          _profile,
        ]);
        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains('retired'));
      },
    );

    test('a dangling evidence path is a non-zero exit (D3)', () {
      final scopeText = File(_scope).readAsStringSync();
      final mangled = scopeText.replaceFirst(
        '`lib/core/feature_flags/feature_flag_registry.dart` | High-risk '
            'optional account layer',
        '`docs/release/this-file-does-not-exist.md` | High-risk optional '
            'account layer',
      );
      expect(mangled, isNot(scopeText));
      final fixture = _tempCopy('ga-scope.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final result = _run([
        '--scope',
        fixture.file.path,
        '--profile',
        _profile,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('this-file-does-not-exist.md'));
    });
  });

  group('A2 — disabled <=> false in every cohort (D4) — the §6.1 '
      'valódi-sértés próba', () {
    test('flipping a disabled capability\'s flag to true in one cohort is a '
        'non-zero exit naming the flag', () {
      final profileText = File(_profile).readAsStringSync();
      // The FIRST occurrence is the `internal` cohort's `accountEnabled`
      // line (accountEnabled is classified `disabled` in ga-scope.md, and
      // D4 requires false in EVERY cohort — flipping just one is enough to
      // violate it).
      final mangled = profileText.replaceFirst(
        'accountEnabled: false',
        'accountEnabled: true',
      );
      expect(mangled, isNot(profileText));
      final fixture = _tempCopy('cohort-profiles.yaml', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final result = _run(['--scope', _scope, '--profile', fixture.file.path]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('accountEnabled'));
      expect(result.stderr.toString(), contains('disabled'));
    });

    test('the shipped profile keeps every `disabled`-classified flag false '
        'in every cohort today (sanity, tool-independent)', () {
      final scopeText = File(_scope).readAsStringSync();
      final profileText = File(_profile).readAsStringSync();
      final disabledKeys = RegExp(
        r'^\| `([a-zA-Z0-9]+)` \| `disabled` \|',
        multiLine: true,
      ).allMatches(scopeText).map((m) => m.group(1)!).toList();
      expect(disabledKeys, isNotEmpty);
      for (final key in disabledKeys) {
        expect(
          RegExp(
            '^\\s*$key\\s*:\\s*true\\s*\$',
            multiLine: true,
          ).hasMatch(profileText),
          isFalse,
          reason:
              '$key is classified disabled but is true somewhere in '
              '$_profile',
        );
      }
    });
  });

  group('A3 — a core-path-required capability must be classified ga (D5)', () {
    test('pointing a core-path step at a `preview`-classified capability is '
        'a non-zero exit naming it', () {
      final scopeText = File(_scope).readAsStringSync();
      const marker =
          '| Fresh install → onboarding (Skip) → Quick Start → offline '
          'practice session → history persists | `practiceEngineV2Enabled` '
          '| `test/e2e/first_practice_offline_test.dart` |';
      expect(scopeText, contains(marker));
      final mangled = scopeText.replaceFirst(
        '`practiceEngineV2Enabled` | `test/e2e/first_practice_offline_test.dart`',
        '`labModeAvailable` | `test/e2e/first_practice_offline_test.dart`',
      );
      final fixture = _tempCopy('ga-scope.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final result = _run([
        '--scope',
        fixture.file.path,
        '--profile',
        _profile,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('labModeAvailable'));
      expect(result.stderr.toString(), contains('preview'));
    });

    test(
      'a core-path step naming `none` never requires a classification '
      '(sanity — the tool does not over-constrain flag-independent steps)',
      () {
        final result = _run(['--scope', _scope, '--profile', _profile]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
      },
    );
  });

  group('MAJOR-1 fix (E12-R28 1. javító kör) — a core-path row must fully '
      'match its shape; a malformed row is a hard failure, never a '
      'silently-dropped row (review P7)', () {
    test('a core-path row with no space after the leading `|` and a '
        'backtick-first step cell — a `preview` capability disguised as '
        "the core path's required element, exactly the D5/A3 guard is "
        'meant to catch — is a non-zero exit, not a silent no-op', () {
      final scopeText = File(_scope).readAsStringSync();
      const originalRow =
          '| Returning user survives an app restart on the same store | '
          '`none` | `test/e2e/returning_user_restart_test.dart` |';
      expect(scopeText, contains(originalRow));
      const poisonedRow =
          '|`LabMode` overlay is required to finish onboarding | '
          '`labModeAvailable` | `test/e2e/returning_user_restart_test.dart` |';
      final mangled = scopeText.replaceFirst(originalRow, poisonedRow);
      expect(mangled, isNot(scopeText));
      final fixture = _tempCopy('ga-scope.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final result = _run([
        '--scope',
        fixture.file.path,
        '--profile',
        _profile,
      ]);
      // Before the fix: exit 0 — the row missed only the looser
      // `_CORE_PATH_ROW_START` pre-filter (no space after `|`, a
      // backtick-first step cell), so `_parse_table` silently `continue`d
      // past it; the reported core-path-step count quietly dropped from 4
      // to 3 and the D5 guard never saw the `preview`-classified
      // `labModeAvailable` row it was supposed to reject. After the fix:
      // every non-header, non-separator row is a required data row, so a
      // shape mismatch is a `VerifyError` naming the line.
      expect(result.exitCode, isNot(0));
      expect(
        result.stderr.toString(),
        contains('does not match the expected shape'),
      );
    });
  });

  group(
    'MAJOR-2 fix (E12-R28 1. javító kör) — production_default is '
    'documented AND cross-checked against the measured '
    'FeatureFlags.forEnvironment default (lib/app/config/feature_flags.dart)',
    () {
      test('a documented production_default that disagrees with the measured '
          'FeatureFlags.forEnvironment default is a non-zero exit naming the '
          'capability', () {
        final scopeText = File(_scope).readAsStringSync();
        const marker =
            '| `practiceEngineV2Enabled` | `ga` | `false` | '
            '`lib/app/routing/app_router.dart` |';
        expect(scopeText, contains(marker));
        final mangled = scopeText.replaceFirst(
          '| `practiceEngineV2Enabled` | `ga` | `false` |',
          '| `practiceEngineV2Enabled` | `ga` | `true` |',
        );
        expect(mangled, isNot(scopeText));
        final fixture = _tempCopy('ga-scope.md', mangled);
        addTearDown(() => fixture.dir.deleteSync(recursive: true));

        final result = _run([
          '--scope',
          fixture.file.path,
          '--profile',
          _profile,
        ]);
        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains('practiceEngineV2Enabled'));
        expect(result.stderr.toString(), contains('production_default'));
      });

      test('a `ga`-classified capability with production_default false but no '
          "named 'Production unlock:' condition in its note is a non-zero "
          'exit', () {
        final scopeText = File(_scope).readAsStringSync();
        const conditionSentence =
            "Production unlock: a future round flips this field's "
            '`forEnvironment` production branch to `true` (or adds a '
            "dart-define override), and this row's `production_default` "
            'updates to `true` in the same commit.';
        expect(scopeText, contains(conditionSentence));
        final mangled = scopeText.replaceFirst(conditionSentence, '');
        expect(mangled, isNot(scopeText));
        final fixture = _tempCopy('ga-scope.md', mangled);
        addTearDown(() => fixture.dir.deleteSync(recursive: true));

        final result = _run([
          '--scope',
          fixture.file.path,
          '--profile',
          _profile,
        ]);
        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains('practiceEngineV2Enabled'));
        expect(result.stderr.toString(), contains('Production unlock'));
      });

      test('the shipped ga-scope.md production_default column matches the '
          'measured FeatureFlags.forEnvironment default for every capability '
          'this tool verifies against feature_flags.dart (sanity)', () {
        final result = _run(['--scope', _scope, '--profile', _profile]);
        expect(result.exitCode, 0, reason: result.stderr.toString());
      });
    },
  );

  group('A4 — every frozen contract carries a named, non-banned resolution '
      'condition (D6)', () {
    test('an empty resolution condition is a non-zero exit', () {
      final freezeText = File(_contractFreeze).readAsStringSync();
      // Blank the ENTIRE condition cell of the last row (leaving one space
      // so the row still has 4 pipe-delimited cells) — replacing only part
      // of the sentence would leave a non-empty (if truncated) condition,
      // which the tool correctly does NOT flag.
      final mangled = freezeText.replaceFirst(
        'A `test/tooling/ga_scope_test.dart` vagy a '
            '`test/tooling/beta_profile_test.dart` egy jövőbeli körben explicit '
            'új cellát kap egy negyedik kilépő-kódhoz — enélkül a három kód '
            'jelentése fagyott.',
        ' ',
      );
      expect(mangled, isNot(freezeText));
      final fixture = _tempCopy('contract-freeze.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final result = _run([
        '--scope',
        _scope,
        '--profile',
        _profile,
        '--contract-freeze',
        fixture.file.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('empty resolution condition'));
    });

    test('a banned non-event phrase is a non-zero exit (D6 "NEM elfogadható '
        'gyengítés")', () {
      final freezeText = File(_contractFreeze).readAsStringSync();
      final mangled = freezeText.replaceFirst(
        'Egy jövőbeli kör explicit ADR-t ír egy eltérő hibakezelési '
            'szerződésre (pl. fail-fast bevezetése egy nevesített migrációs '
            'lépésnél) — enélkül a jelenlegi never-throws szerződés fagyott.',
        'Szükség esetén módosítható.',
      );
      expect(mangled, isNot(freezeText));
      final fixture = _tempCopy('contract-freeze.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final result = _run([
        '--scope',
        _scope,
        '--profile',
        _profile,
        '--contract-freeze',
        fixture.file.path,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('banned non-event'));
    });

    test('the shipped contract-freeze.md has no empty and no banned-phrase '
        'resolution condition (sanity)', () {
      final result = _run(['--scope', _scope, '--profile', _profile]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    });
  });

  group('A5 — an open P0/P1 blocker forces an explicit NOT-READY header '
      '(D7)', () {
    test('removing the NOT-READY marker while a P0/P1 blocker stays open is '
        'a non-zero exit', () {
      final scopeText = File(_scope).readAsStringSync();
      final mangled = scopeText.replaceFirst(
        '**Állapot: NEM KÉSZ (NOT READY)**',
        '**Állapot rendben.**',
      );
      expect(mangled, isNot(scopeText));
      final fixture = _tempCopy('ga-scope.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final result = _run([
        '--scope',
        fixture.file.path,
        '--profile',
        _profile,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('NOT-READY'));
    });

    test('claiming "GA-kész" in the header while a P0/P1 blocker stays open '
        'is a non-zero exit', () {
      final scopeText = File(_scope).readAsStringSync();
      final mangled = scopeText.replaceFirst(
        '**Állapot: NEM KÉSZ (NOT READY)**',
        '**Állapot: NEM KÉSZ (NOT READY), de a build GA-kész.**',
      );
      expect(mangled, isNot(scopeText));
      final fixture = _tempCopy('ga-scope.md', mangled);
      addTearDown(() => fixture.dir.deleteSync(recursive: true));

      final result = _run([
        '--scope',
        fixture.file.path,
        '--profile',
        _profile,
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('GA-kész'));
    });

    test('the real blockers.md carries at least one open P0/P1 today '
        '(sanity — this is what makes the NOT-READY header correct, not a '
        'gap)', () {
      final blockersText = File(_blockers).readAsStringSync();
      final severities = RegExp(
        r'^\| R-[A-Z0-9-]+ \| (P[0-4]) \|',
        multiLine: true,
      ).allMatches(blockersText).map((m) => m.group(1)!).toList();
      expect(severities, isNotEmpty);
      expect(
        severities.any((s) => s == 'P0' || s == 'P1'),
        isTrue,
        reason:
            'no open P0/P1 blocker found — the NOT-READY header claim '
            'would then need re-justifying',
      );
    });
  });

  group('usage errors (exit 2) — missing files', () {
    test('a missing --scope path is exit 2', () {
      final result = _run([
        '--scope',
        'docs/release/this-file-does-not-exist.md',
        '--profile',
        _profile,
      ]);
      expect(result.exitCode, 2);
    });

    test('a missing --profile path is exit 2', () {
      final result = _run([
        '--scope',
        _scope,
        '--profile',
        'docs/beta/this-file-does-not-exist.yaml',
      ]);
      expect(result.exitCode, 2);
    });
  });
}
