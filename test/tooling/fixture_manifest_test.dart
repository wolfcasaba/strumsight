// Release fixture-corpus manifest gate (E12-R12, ADR 0473).
//
// Follows the `check_assets_test.dart` / `ml_asset_manifest_test.dart`
// pattern: imports `tool/check_fixture_manifest.dart` as a plain library and
// exercises `checkFixtureManifest(projectRoot: ...)` against BOTH synthetic
// temp-directory fixtures (fast, isolated mutation cells) and the real
// repository tree (the A1/A7/A8 cells that must hold for the fixture corpus
// actually shipping). No fixture under `test/fixtures/**` is ever modified —
// mutation cells (A2) write into a `Directory.systemTemp` copy and tear it
// down in `addTearDown`.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_fixture_manifest.dart';

void main() {
  group('A1 — the corpus is defined by the file tree, not the manifest '
      '(ADR 0473 D1/D2)', () {
    test('the real test/fixtures/ tree has exactly 52 data files, and the '
        'real manifest is clean against it (E12-R23 §0.0/R2: 48 -> 51, three '
        'new upgrade-migration fixtures registered; ADR 0112 self-heal of '
        'E16-R02/H3: 51 -> 52, the E15-R13 completion-report reachability '
        'baseline registered, L613)', () {
      final projectRoot = _findProjectRoot();
      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isTrue, reason: report.format());
      expect(report.entries, hasLength(52));
    });

    test('a fixture file on disk with no manifest entry is flagged — a '
        'checker that only reads the manifest list would miss this', () {
      final projectRoot = _newFixtureProject();
      _writeFixtureFile(projectRoot, 'test/fixtures/untracked.json', '{}');
      _writeManifest(projectRoot, const []);

      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isFalse);
      expect(
        report.issues.map((issue) => issue.kind),
        contains(FixtureManifestIssueKind.fixtureMissingManifestEntry),
      );
      expect(
        report.issues
            .map((issue) => issue.path)
            .contains('test/fixtures/untracked.json'),
        isTrue,
      );
    });

    test('a manifest entry with no backing file on disk is flagged', () {
      final projectRoot = _newFixtureProject();
      _writeManifest(projectRoot, [
        _entry(
          path: 'test/fixtures/ghost.json',
          bytes: 2,
          sha256Hex: _sha256Of('{}'),
        ),
      ]);

      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isFalse);
      expect(
        report.issues.map((issue) => issue.kind),
        contains(FixtureManifestIssueKind.entryMissingFromDisk),
      );
    });

    test('*.dart fixture sources and README.md files require no manifest '
        'entry (ADR 0473 D2 exclusion) — a well-formed manifest naming only '
        'the data file stays clean', () {
      final projectRoot = _newFixtureProject();
      _writeFixtureFile(
        projectRoot,
        'test/fixtures/builder/some_fixtures.dart',
        'const fixtures = [];\n',
      );
      _writeFixtureFile(
        projectRoot,
        'test/fixtures/builder/README.md',
        '# fixtures\n',
      );
      const contents = '{"a":1}';
      _writeFixtureFile(projectRoot, 'test/fixtures/data.json', contents);
      _writeManifest(projectRoot, [
        _entry(
          path: 'test/fixtures/data.json',
          bytes: contents.length,
          sha256Hex: _sha256Of(contents),
        ),
      ]);

      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isTrue, reason: report.format());
      expect(report.entries, hasLength(1));
    });

    test('the manifest itself requires no manifest entry (self-reference '
        'would be a checksum fixed point)', () {
      final projectRoot = _newFixtureProject();
      const contents = '{"a":1}';
      _writeFixtureFile(projectRoot, 'test/fixtures/data.json', contents);
      _writeManifest(projectRoot, [
        _entry(
          path: 'test/fixtures/data.json',
          bytes: contents.length,
          sha256Hex: _sha256Of(contents),
        ),
      ]);

      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isTrue, reason: report.format());
      expect(
        report.entries.map((entry) => entry.path),
        isNot(contains('test/fixtures/manifest.json')),
      );
    });
  });

  group('A2 — the checksum is of the CONTENT, and a byte mutation turns the '
      'checker red (ADR 0473 D3, §6.1 matrix row)', () {
    test('real-corruption probe: a single mutated byte in a COPY of a real '
        'fixture is caught, and the original fixture on disk is never '
        'touched', () {
      final realProjectRoot = _findProjectRoot();
      const relativePath = 'test/fixtures/song_trainer/midi/format0.mid';
      final originalFile = File('${realProjectRoot.path}/$relativePath');
      final originalBytes = originalFile.readAsBytesSync();

      final tempProject = Directory.systemTemp.createTempSync(
        'strumsight_fixture_manifest_corruption_',
      );
      addTearDown(() => tempProject.deleteSync(recursive: true));

      final mutatedBytes = _copyWithFlippedFirstByte(originalBytes);
      _writeFixtureBytes(tempProject, relativePath, mutatedBytes);
      _writeManifest(tempProject, [
        _entry(
          path: relativePath,
          bytes: originalBytes.length,
          sha256Hex: sha256.convert(originalBytes).toString(),
        ),
      ]);

      final report = checkFixtureManifest(projectRoot: tempProject);

      expect(report.isClean, isFalse);
      expect(
        report.issues.map((issue) => issue.kind),
        contains(FixtureManifestIssueKind.checksumMismatch),
      );
      // The real fixture on disk must be byte-identical to what it was
      // before this test ran — only the temp copy was mutated.
      expect(originalFile.readAsBytesSync(), originalBytes);
    });

    test('matrix row: size-only agreement with a content mutation still '
        'turns the checker red (rules out a size-only implementation)', () {
      final projectRoot = _newFixtureProject();
      const original = '{"a":1}';
      const mutated = '{"a":2}'; // same length, different content
      expect(mutated.length, original.length);

      _writeFixtureFile(projectRoot, 'test/fixtures/data.json', mutated);
      _writeManifest(projectRoot, [
        _entry(
          path: 'test/fixtures/data.json',
          bytes: original.length,
          sha256Hex: _sha256Of(original),
        ),
      ]);

      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isFalse);
      expect(
        report.issues.map((issue) => issue.kind),
        contains(FixtureManifestIssueKind.checksumMismatch),
      );
    });
  });

  group('A3 — an unknown/missing license is a hard failure, never '
      '"unknown" (ADR 0473 D4)', () {
    test('an empty license string is flagged', () {
      final projectRoot = _newFixtureProject();
      const contents = '{"a":1}';
      _writeFixtureFile(projectRoot, 'test/fixtures/data.json', contents);
      _writeManifest(projectRoot, [
        _entry(
          path: 'test/fixtures/data.json',
          bytes: contents.length,
          sha256Hex: _sha256Of(contents),
          license: '',
        ),
      ]);

      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isFalse);
      expect(
        report.issues.map((issue) => issue.kind),
        contains(FixtureManifestIssueKind.missingLicense),
      );
    });

    test('the literal string "unknown" is a hard failure, not a valid '
        'license — a placeholder must not pass as real provenance (D4)', () {
      final projectRoot = _newFixtureProject();
      const contents = '{"a":1}';
      _writeFixtureFile(projectRoot, 'test/fixtures/data.json', contents);
      _writeManifest(projectRoot, [
        _entry(
          path: 'test/fixtures/data.json',
          bytes: contents.length,
          sha256Hex: _sha256Of(contents),
          license: 'unknown',
        ),
      ]);

      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isFalse, reason: report.format());
      expect(
        report.issues.map((issue) => issue.kind),
        contains(FixtureManifestIssueKind.placeholderProvenance),
      );
    });

    test('the literal string "n/a" is a hard failure as a source, not a '
        'valid provenance value (D4)', () {
      final projectRoot = _newFixtureProject();
      const contents = '{"a":1}';
      _writeFixtureFile(projectRoot, 'test/fixtures/data.json', contents);
      _writeManifest(projectRoot, [
        _entry(
          path: 'test/fixtures/data.json',
          bytes: contents.length,
          sha256Hex: _sha256Of(contents),
          source: 'n/a',
        ),
      ]);

      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isFalse, reason: report.format());
      expect(
        report.issues.map((issue) => issue.kind),
        contains(FixtureManifestIssueKind.placeholderProvenance),
      );
    });

    test('every placeholder in placeholderProvenanceValues is rejected as a '
        'license, in original and mixed case', () {
      for (final placeholder in placeholderProvenanceValues) {
        for (final value in {placeholder, _shout(placeholder)}) {
          final projectRoot = _newFixtureProject();
          const contents = '{"a":1}';
          _writeFixtureFile(projectRoot, 'test/fixtures/data.json', contents);
          _writeManifest(projectRoot, [
            _entry(
              path: 'test/fixtures/data.json',
              bytes: contents.length,
              sha256Hex: _sha256Of(contents),
              license: value,
            ),
          ]);

          final report = checkFixtureManifest(projectRoot: projectRoot);

          expect(
            report.isClean,
            isFalse,
            reason: 'license "$value" should be rejected: ${report.format()}',
          );
          expect(
            report.issues.map((issue) => issue.kind),
            contains(FixtureManifestIssueKind.placeholderProvenance),
            reason: 'license "$value" should be rejected',
          );
        }
      }
    });

    test('a missing source/provenance field is flagged independently of '
        'license', () {
      final projectRoot = _newFixtureProject();
      const contents = '{"a":1}';
      _writeFixtureFile(projectRoot, 'test/fixtures/data.json', contents);
      _writeManifest(projectRoot, [
        _entry(
          path: 'test/fixtures/data.json',
          bytes: contents.length,
          sha256Hex: _sha256Of(contents),
          source: '',
        ),
      ]);

      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isFalse);
      expect(
        report.issues.map((issue) => issue.kind),
        contains(FixtureManifestIssueKind.missingSource),
      );
    });

    test('the real manifest names no fixture "unknown" — a documentation, '
        'not-mechanical, license-quality guard for the shipping corpus', () {
      final projectRoot = _findProjectRoot();
      final manifestFile = File(
        '${projectRoot.path}/test/fixtures/manifest.json',
      );
      final decoded =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      final fixtures = (decoded['fixtures']! as List<Object?>)
          .cast<Map<String, Object?>>();

      for (final fixture in fixtures) {
        final license = (fixture['license'] as String).trim().toLowerCase();
        final source = (fixture['source'] as String).trim().toLowerCase();
        expect(license, isNot('unknown'), reason: fixture['path'] as String);
        expect(source, isNot('unknown'), reason: fixture['path'] as String);
      }
    });
  });

  group(
    'A4 — the UI golden tree is excluded from the corpus (ADR 0473 D5)',
    () {
      test('a manifest entry pointing outside test/fixtures/ (e.g. a UI '
          'golden path) is rejected, never silently accepted', () {
        final projectRoot = _newFixtureProject();
        _writeManifest(projectRoot, [
          _entry(
            path: 'test/ui/goldens/some_screen.png',
            bytes: 4,
            sha256Hex: _sha256Of('png!'),
          ),
        ]);

        final report = checkFixtureManifest(projectRoot: projectRoot);

        expect(report.isClean, isFalse);
        expect(
          report.issues.map((issue) => issue.kind),
          contains(FixtureManifestIssueKind.pathOutsideFixtureTree),
        );
      });

      test('the real manifest names no path under test/ui/goldens/', () {
        final projectRoot = _findProjectRoot();
        final manifestText = File(
          '${projectRoot.path}/test/fixtures/manifest.json',
        ).readAsStringSync();

        expect(manifestText, isNot(contains('test/ui/goldens')));
      });
    },
  );

  group(
    'A5 — explicit containsUserData, fail-closed on true (ADR 0473 D8)',
    () {
      test('containsUserData: true is a hard failure — release fixtures must '
          'never carry user data', () {
        final projectRoot = _newFixtureProject();
        const contents = '{"a":1}';
        _writeFixtureFile(projectRoot, 'test/fixtures/data.json', contents);
        _writeManifest(projectRoot, [
          _entry(
            path: 'test/fixtures/data.json',
            bytes: contents.length,
            sha256Hex: _sha256Of(contents),
            containsUserData: true,
          ),
        ]);

        final report = checkFixtureManifest(projectRoot: projectRoot);

        expect(report.isClean, isFalse);
        expect(
          report.issues.map((issue) => issue.kind),
          contains(FixtureManifestIssueKind.containsUserData),
        );
      });

      test('an omitted containsUserData field is rejected — D8 requires an '
          'explicit boolean, never a defaulted one', () {
        final projectRoot = _newFixtureProject();
        const contents = '{"a":1}';
        _writeFixtureFile(projectRoot, 'test/fixtures/data.json', contents);
        final entry = _entry(
          path: 'test/fixtures/data.json',
          bytes: contents.length,
          sha256Hex: _sha256Of(contents),
        )..remove('containsUserData');
        _writeManifest(projectRoot, [entry]);

        final report = checkFixtureManifest(projectRoot: projectRoot);

        expect(report.isClean, isFalse);
      });

      test('the real manifest declares containsUserData=false for every '
          'fixture — this round ships no fixture with user data', () {
        final projectRoot = _findProjectRoot();
        final manifestFile = File(
          '${projectRoot.path}/test/fixtures/manifest.json',
        );
        final decoded =
            jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
        final fixtures = (decoded['fixtures']! as List<Object?>)
            .cast<Map<String, Object?>>();

        for (final fixture in fixtures) {
          expect(
            fixture['containsUserData'],
            isFalse,
            reason: fixture['path'] as String,
          );
        }
      });
    },
  );

  // A6 (the existing check_assets_test.dart stays green) has no cell here:
  // it is evidence about a DIFFERENT, untouched test file, and the §7 gate
  // command runs it directly alongside this one.

  group('A7 — cross-match with the protected song_trainer checksum source '
      '(ADR 0473 D6)', () {
    test('every song_trainer manifest entry sha256 also appears verbatim in '
        'tool/ci/check_song_fixture_licenses.dart — the two independent '
        'checksum sources for the same 30 files must agree', () {
      final projectRoot = _findProjectRoot();
      final manifestFile = File(
        '${projectRoot.path}/test/fixtures/manifest.json',
      );
      final decoded =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      final fixtures = (decoded['fixtures']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final songTrainerFixtures = fixtures.where(
        (fixture) => (fixture['path'] as String).startsWith(
          'test/fixtures/song_trainer/',
        ),
      );

      final checkerSource = File(
        '${projectRoot.path}/tool/ci/check_song_fixture_licenses.dart',
      ).readAsStringSync();

      expect(songTrainerFixtures, hasLength(30));
      for (final fixture in songTrainerFixtures) {
        final sha = fixture['sha256'] as String;
        expect(
          checkerSource,
          contains(sha),
          reason:
              '${fixture['path']}: manifest sha256 $sha must also be present '
              'in the protected song_trainer checksum source',
        );
      }
    });

    test('matrix row: a manifest sha256 that drifts from the protected '
        "checker's value is provably distinguishable — the real manifest's "
        'hash for a known file equals the checker constant exactly (not '
        'merely "some hash appears somewhere")', () {
      final projectRoot = _findProjectRoot();
      final manifestFile = File(
        '${projectRoot.path}/test/fixtures/manifest.json',
      );
      final decoded =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      final fixtures = (decoded['fixtures']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final entry = fixtures.singleWhere(
        (fixture) =>
            fixture['path'] == 'test/fixtures/song_trainer/midi/format0.mid',
      );

      expect(
        entry['sha256'],
        'c1b7c74fd988bc25e434dd80c6a1b570464c5d28c0d96a6468f4dbbed6b91f93',
      );
    });
  });

  group('A8 — no machine-specific absolute path in the manifest (ADR 0473 '
      'D7, L530)', () {
    test('a manifest whose source text embeds an absolute /home/ path is '
        'rejected', () {
      final projectRoot = _newFixtureProject();
      const contents = '{"a":1}';
      _writeFixtureFile(projectRoot, 'test/fixtures/data.json', contents);
      _writeManifest(projectRoot, [
        _entry(
          path: 'test/fixtures/data.json',
          bytes: contents.length,
          sha256Hex: _sha256Of(contents),
          source: 'Generated at /home/ubuntu/cache/fixture_export',
        ),
      ]);

      final report = checkFixtureManifest(projectRoot: projectRoot);

      expect(report.isClean, isFalse);
      expect(
        report.issues.map((issue) => issue.kind),
        contains(FixtureManifestIssueKind.machinePath),
      );
    });

    test('self-check: the machinePathFragments list actually contains '
        '/home/, /Users/ and C:\\', () {
      expect(
        machinePathFragments,
        containsAll(<String>['/home/', '/Users/', r'C:\']),
      );
    });

    test('the real committed manifest carries no /home/, /Users/ or C:\\ '
        'fragment anywhere in its text', () {
      final projectRoot = _findProjectRoot();
      final manifestText = File(
        '${projectRoot.path}/test/fixtures/manifest.json',
      ).readAsStringSync();

      for (final fragment in machinePathFragments) {
        expect(manifestText, isNot(contains(fragment)));
      }
    });
  });
}

Directory _findProjectRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (_isRegularFile('${candidate.path}/pubspec.yaml') &&
        _isRegularFile('${candidate.path}/AGENTS.md')) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not find the StrumSight repository root.');
    }
    candidate = parent;
  }
}

bool _isRegularFile(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) ==
    FileSystemEntityType.file;

Directory _newFixtureProject() {
  final projectRoot = Directory.systemTemp.createTempSync(
    'strumsight_fixture_manifest_',
  );
  return projectRoot;
}

void _writeFixtureFile(Directory projectRoot, String path, String contents) {
  final file = File('${projectRoot.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void _writeFixtureBytes(Directory projectRoot, String path, List<int> bytes) {
  final file = File('${projectRoot.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

void _writeManifest(
  Directory projectRoot,
  List<Map<String, Object?>> fixtures,
) {
  _writeFixtureFile(
    projectRoot,
    'test/fixtures/manifest.json',
    jsonEncode(<String, Object?>{
      'schemaVersion': fixtureManifestSchemaVersion,
      'fixtures': fixtures,
    }),
  );
}

Map<String, Object?> _entry({
  required String path,
  required int bytes,
  required String sha256Hex,
  String license = 'Project-authored synthetic test fixture.',
  String source = 'Project-authored fixture for this round.',
  bool containsUserData = false,
}) {
  return <String, Object?>{
    'path': path,
    'bytes': bytes,
    'sha256': sha256Hex,
    'license': license,
    'source': source,
    'containsUserData': containsUserData,
  };
}

String _sha256Of(String contents) =>
    sha256.convert(utf8.encode(contents)).toString();

/// Mixed-case variant of [value] (e.g. `unknown` -> `Unknown`) to prove the
/// placeholder check normalizes case, not just the exact stored spelling.
String _shout(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

List<int> _copyWithFlippedFirstByte(List<int> bytes) {
  final mutated = List<int>.from(bytes);
  mutated[0] = mutated[0] ^ 0xff;
  return mutated;
}
